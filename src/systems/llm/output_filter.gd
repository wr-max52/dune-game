class_name OutputFilter
extends RefCounted
## Last line of defense on what the bartender says (M12). Pure.
##
## - Franchise terms (the shared IP blocklist) are rewritten as outlander talk.
## - Admitting to being an AI / model / program, or talking about prompts and
##   instructions, swaps the whole line for an in-character deflection.
## - Anything that looks like it is reciting her own hidden card is swapped too.
## - Roleplay asterisks go, and the line is capped at three sentences.
## Also screens what the player says, for hostility (the validator uses it to
## decide whether "call_guards" is even allowed).

const BLOCKLIST := "res://content/core/llm/ip_blocklist.json"

const META := [
	"as an ai", "an ai language", "language model", "i am an ai", "i'm an ai", "im an ai",
	"i am a bot", "i'm a bot", "chatbot", "artificial intelligence", "my programming",
	"system prompt", "my instructions", "my prompt", "openai", "anthropic", "large language",
	"i'm just a program", "i am a program", "as a character", "in this roleplay", "role-play",
]

var terms: Array = []
var deflections: Array = []
var hostile_words: Array = []
var guard_phrases: Array = []    ## distinctive strings from the card that must never be recited
var _rx: Array = []


func _init(card: Dictionary = {}) -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(BLOCKLIST)) if FileAccess.file_exists(BLOCKLIST) else null
	terms = d.get("terms", []) if d is Dictionary else []
	for t in terms:
		var rx := RegEx.new()
		rx.compile("(?i)\\b" + _escape(str(t)) + "\\b")
		_rx.append(rx)
	deflections = card.get("meta_deflections", ["You've had enough, friend."])
	hostile_words = card.get("hostile_words", [])
	for r in card.get("rules", []):
		guard_phrases.append(str(r).substr(0, 48).to_lower())
	guard_phrases.append(str(card.get("identity", "")).substr(0, 60).to_lower())


static func _escape(s: String) -> String:
	var out := ""
	for ch in s:
		out += ("\\" + ch) if "\\^$.|?*+()[]{}".contains(ch) else ch
	return out


## Rewrite franchise terms. Cheap enough to run on every streamed delta.
func scrub_terms(text: String) -> String:
	for rx in _rx:
		text = (rx as RegEx).sub(text, "that outlander nonsense", true)
	return text


func has_meta_talk(text: String) -> bool:
	var low := text.to_lower()
	for m in META:
		if low.contains(m):
			return true
	return false


func leaks_card(text: String) -> bool:
	var low := text.to_lower()
	for g in guard_phrases:
		if g.length() >= 24 and low.contains(g.substr(0, 40)):
			return true
	return false


## The full filter for a finished line -> { say, flags: [..] }.
func clean(say: String, seed: int = 0) -> Dictionary:
	var flags: Array = []
	var s := say.replace("*", "").strip_edges()
	var scrubbed := scrub_terms(s)
	if scrubbed != s:
		flags.append("ip_term")
	s = scrubbed
	if has_meta_talk(s):
		flags.append("meta")
		s = str(deflections[abs(seed) % deflections.size()]) if not deflections.is_empty() else "Drink?"
	elif leaks_card(s):
		flags.append("leak")
		s = str(deflections[abs(seed) % deflections.size()]) if not deflections.is_empty() else "Drink?"
	var capped := cap_sentences(s, 3)
	if capped != s:
		flags.append("capped")
	if capped.strip_edges() == "":
		flags.append("empty")
	return { "say": capped, "flags": flags }


static func cap_sentences(s: String, n: int) -> String:
	var count := 0
	for i in s.length():
		var ch := s[i]
		if ch == "." or ch == "!" or ch == "?":
			var next_is_space := i + 1 >= s.length() or s[i + 1] == " " or s[i + 1] == "\n"
			if next_is_space and not (i + 1 < s.length() and (s[i + 1] == "." )):
				count += 1
				if count >= n:
					return s.substr(0, i + 1)
	return s


## Player-side screen: was that a threat or an insult?
func is_hostile(player_text: String) -> bool:
	var low := player_text.to_lower()
	for w in hostile_words:
		if low.contains(str(w)):
			return true
	return false
