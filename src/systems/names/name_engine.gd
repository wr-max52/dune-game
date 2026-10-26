class_name NameEngine
extends RefCounted
## The sci-fi name generator (issue #15). One engine names everything -- people,
## pilots' callsigns, ships, equipment, towns, planets -- from a library of terms
## and a small template grammar, all in content/core/names/. No LLM, no network:
## the same seed and key always give the same name, on every machine.
##
## A "kind" (people, a town, a planet...) is a weighted list of templates. A
## template is text with tokens in braces:
##
##   {list}            a term from a word list            {remnant_given}
##   {@rule}           another template (shared rules)    {@clan}
##   {~tongue}         a made-up word from a phonology    {~astral}
##   {#lo-hi}          a number                           {#2-9}
##   ...:mod           modifiers after a colon            {~dune:cap}  {#1-7:roman}
##   [p|text]          optional text, kept with chance p  [0.3| "{nickname}"]
##   %(key)            a context value, substituted first {product_%(class)}
##
## Modifiers: cap (first letter up), title (every word), upper, lower, first (the
## first letter only), roman (a number as I, II, IV...), plural.
##
## Words from a tongue are built syllable by syllable (onset + nucleus + coda,
## each a weighted pick), so a handful of sounds per culture gives names that
## feel like they belong together, without a fixed list to run out of.
##
## Uniqueness across the game is NameBook's job; this class only generates.

const MAX_DEPTH := 8

var lists: Dictionary = {}     ## list name -> Array of terms
var rules: Dictionary = {}     ## rule name -> template or [[template, weight], ...]
var tongues: Dictionary = {}   ## tongue name -> phonology
var kinds: Dictionary = {}     ## kind name -> { patterns, max_len, min_len, ... }
var deny: Array = []           ## lower-case fragments a name may never contain
var deny_words: Array = []     ## whole words a name may never be or contain
var config: Dictionary = {}

var _rng := RandomNumberGenerator.new()


## Build from the name banks (content/core/names/*.json, by id). Each bank may hold
## any of: lists, rules, tongues, kinds, deny, config.
func setup(banks: Dictionary, ip_terms: Array = [], ip_name_terms: Array = []) -> void:
	lists = {}
	rules = {}
	tongues = {}
	kinds = {}
	deny = []
	deny_words = []
	config = {}
	var ids := banks.keys()
	ids.sort()                                  # merge order never depends on the file system
	for id in ids:
		var b: Dictionary = banks[id]
		_merge(lists, b.get("lists", {}))
		_merge(rules, b.get("rules", {}))
		_merge(tongues, b.get("tongues", {}))
		_merge(kinds, b.get("kinds", {}))
		_merge(config, b.get("config", {}))
		for d in b.get("deny", []):
			deny.append(str(d).to_lower())
		for d in b.get("deny_words", []):
			deny_words.append(str(d).to_lower())
	for t in ip_terms:
		deny.append(str(t).to_lower())
	for t in ip_name_terms:
		deny_words.append(str(t).to_lower())


func _merge(into: Dictionary, from: Dictionary) -> void:
	for k in from:
		if into.has(k) and into[k] is Array and from[k] is Array:
			into[k] = into[k] + from[k]           # two banks may add to one list
		else:
			into[k] = from[k]


## Every term the library holds (for tests and the size check).
func term_count() -> int:
	var n := 0
	for k in lists:
		n += (lists[k] as Array).size()
	return n


# ------------------------------------------------------------------ generation

## One candidate name of `kind` for `seed`. Deterministic: the same kind, seed and
## context always give the same text. Returns "" if the kind is unknown or every
## try was rejected (too long, too short, a denied word).
func generate(kind: String, seed: int, ctx: Dictionary = {}) -> String:
	var k: Dictionary = kinds.get(kind, {})
	if k.is_empty():
		push_warning("NameEngine: unknown kind " + kind)
		return ""
	_rng.seed = seed
	var tries := int(k.get("tries", 12))
	for i in tries:
		var text := _finish(expand(_pick_weighted(k.get("patterns", [])), ctx, 0), k)
		if text != "" and acceptable(text, k):
			return text
	return ""


## Expand one template.
func expand(template: String, ctx: Dictionary = {}, depth: int = 0) -> String:
	if depth > MAX_DEPTH:
		return ""
	var t := _substitute(template, ctx)
	var out := ""
	var i := 0
	while i < t.length():
		var c := t[i]
		if c == "{":
			var j := _close(t, i, "{", "}")
			out += _token(t.substr(i + 1, j - i - 1), ctx, depth)
			i = j + 1
		elif c == "[":
			var j := _close(t, i, "[", "]")
			var inner := t.substr(i + 1, j - i - 1)
			var bar := inner.find("|")
			var p := float(inner.substr(0, bar)) if bar > 0 else 0.5
			var body := inner.substr(bar + 1) if bar > 0 else inner
			if _rng.randf() < p:
				out += expand(body, ctx, depth + 1)
			i = j + 1
		else:
			out += c
			i += 1
	return out


## %(key) -> the context's value (or nothing).
func _substitute(t: String, ctx: Dictionary) -> String:
	var at := t.find("%(")
	while at >= 0:
		var end := t.find(")", at)
		if end < 0:
			break
		var key := t.substr(at + 2, end - at - 2)
		t = t.substr(0, at) + str(ctx.get(key, "")) + t.substr(end + 1)
		at = t.find("%(")
	return t


## Index of the bracket closing the one at `from` (nesting aware).
func _close(t: String, from: int, open: String, close: String) -> int:
	var depth := 0
	for i in range(from, t.length()):
		if t[i] == open:
			depth += 1
		elif t[i] == close:
			depth -= 1
			if depth == 0:
				return i
	return t.length() - 1


func _token(body: String, ctx: Dictionary, depth: int) -> String:
	var parts := body.split(":")
	var head := parts[0]
	var v := ""
	if head.begins_with("@"):
		var r = rules.get(head.substr(1), "")
		v = expand(_pick_weighted(r) if r is Array else str(r), ctx, depth + 1)
	elif head.begins_with("~"):
		v = word(head.substr(1))
	elif head.begins_with("#"):
		var span := head.substr(1).split("-")
		var lo := int(span[0])
		var hi := int(span[1]) if span.size() > 1 else lo
		v = str(_rng.randi_range(lo, hi))
	else:
		var l: Array = lists.get(head, [])
		if l.is_empty():
			push_warning("NameEngine: empty or unknown list " + head)
			return ""
		v = expand(str(l[_rng.randi_range(0, l.size() - 1)]), ctx, depth + 1)
	for m in parts.slice(1):
		v = modify(v, m)
	return v


static func modify(v: String, m: String) -> String:
	match m:
		"cap":
			return v.substr(0, 1).to_upper() + v.substr(1) if v != "" else v
		"title":
			var words := v.split(" ")
			for i in words.size():
				words[i] = modify(words[i], "cap")
			return " ".join(words)
		"upper":
			return v.to_upper()
		"lower":
			return v.to_lower()
		"first":
			return v.substr(0, 1).to_upper()
		"roman":
			return roman(int(v))
		"plural":
			if v.ends_with("s") or v.ends_with("x") or v.ends_with("sh"):
				return v + "es"
			return v + "s"
	return v


static func roman(n: int) -> String:
	if n <= 0 or n > 3999:
		return str(n)
	var vals := [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
	var syms := ["M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"]
	var out := ""
	for i in vals.size():
		while n >= vals[i]:
			out += syms[i]
			n -= vals[i]
	return out


## A weighted pick. Accepts "text", ["a", "b"], or [["a", 3], ["b", 1]].
func _pick_weighted(options) -> String:
	if options is String:
		return options
	if not options is Array or options.is_empty():
		return ""
	var total := 0.0
	for o in options:
		total += float(o[1]) if o is Array else 1.0
	var r := _rng.randf() * total
	for o in options:
		var w := float(o[1]) if o is Array else 1.0
		if r < w:
			return str(o[0]) if o is Array else str(o)
		r -= w
	var last = options.back()
	return str(last[0]) if last is Array else str(last)


# ------------------------------------------------------------------ tongues

## A made-up word from a tongue's sounds: syllables of onset + nucleus + coda.
## Rejects (and retries) words with a banned cluster or a letter three times in a
## row, so the sounds stay in the culture's mouth.
func word(tongue: String) -> String:
	var t: Dictionary = tongues.get(tongue, {})
	if t.is_empty():
		push_warning("NameEngine: unknown tongue " + tongue)
		return ""
	var bad: Array = t.get("bad", [])
	var min_len := int(t.get("min_len", 3))
	var max_len := int(t.get("max_len", 9))
	for attempt in 16:
		var n := int(_pick_weighted(t.get("syllables", [["2", 1]])))
		var w := ""
		for s in n:
			var onset := _pick_weighted(t.get("onsets", [""]))
			if s == 0 and _rng.randf() < float(t.get("vowel_start", 0.0)):
				onset = ""
			if s > 0 and w != "" and _rng.randf() < float(t.get("apostrophe", 0.0)):
				w += "'"
			w += onset + _pick_weighted(t.get("nuclei", ["a"]))
			var last := s == n - 1
			if _rng.randf() < float(t.get("coda_end" if last else "coda_mid", 0.3)):
				w += _pick_weighted(t.get("codas", [""]))
		if t.has("endings") and _rng.randf() < float(t.get("ending_chance", 0.0)):
			w += _pick_weighted(t.endings)
		w = w.to_lower()
		if w.length() < min_len or w.length() > max_len or _triple(w) or w.ends_with("'") \
				or _vowel_run(w) > int(t.get("max_vowel_run", 2)):
			continue
		var ok := true
		for b in bad:
			if w.contains(str(b)):
				ok = false
				break
		if ok:
			return w
	return ""


## The longest run of vowels in a word ("Eoxeooki" has 3: unpronounceable).
static func _vowel_run(w: String) -> int:
	var best := 0
	var run := 0
	for ch in w:
		if "aeiouy".contains(ch):
			run += 1
			best = maxi(best, run)
		else:
			run = 0
	return best


static func _triple(w: String) -> bool:
	for i in range(2, w.length()):
		if w[i] == w[i - 1] and w[i] == w[i - 2]:
			return true
	return false


# ------------------------------------------------------------------ checks

func _finish(text: String, k: Dictionary) -> String:
	var t := text.strip_edges()
	while t.contains("  "):
		t = t.replace("  ", " ")
	t = t.replace(" ,", ",").replace("\" \"", "\"\"").replace("\"\"", "")
	return t.strip_edges()


## Too short, too long, or containing a denied fragment or word: not a name.
func acceptable(text: String, k: Dictionary = {}) -> bool:
	if text.length() < int(k.get("min_len", 3)) or text.length() > int(k.get("max_len", 32)):
		return false
	var low := text.to_lower()
	var squashed := normalize(text)
	for d in deny:
		if low.contains(d) or squashed.contains(normalize(d)):
			return false
	var words := PackedStringArray()
	for w in low.replace("-", " ").replace("'", " ").replace("\"", " ").replace(".", " ").split(" ", false):
		words.append(w)
	for d in deny_words:
		if words.has(d) or low == d or squashed == normalize(d):
			return false
	return true


## The form names are compared in: lower case, letters and digits only. "Kael
## Dorn" and "kael-dorn" are the same name.
static func normalize(text: String) -> String:
	var out := ""
	for ch in text.to_lower():
		var c := ch.unicode_at(0)
		if (c >= 97 and c <= 122) or (c >= 48 and c <= 57):
			out += ch
	return out


## A stable 32-bit hash (FNV-1a) of any text: the same on every machine and
## every Godot version, unlike String.hash().
static func fnv(text: String) -> int:
	var h := 2166136261
	for b in text.to_utf8_buffer():
		h = h ^ b
		h = (h * 16777619) & 0xFFFFFFFF
	return h
