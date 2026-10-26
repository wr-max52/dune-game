class_name ReplyParser
extends RefCounted
## Reads the bartender's reply (M12). Pure.
##
## The reply is one JSON object with "say" first, so while it streams we can pull
## the characters of the say string out of the raw text (decoding escapes) and
## type them on screen before the actions arrive. At the end, parse() reads the
## whole object, repairing the usual small-model mistakes (code fences, chatter
## around the JSON, a plain-text answer with no JSON at all).


## The say text so far from a partial (or complete) raw reply. "" until the
## "say" string has started.
static func say_partial(raw: String) -> String:
	var k := raw.find("\"say\"")
	if k < 0:
		if not raw.strip_edges().begins_with("{") and not raw.strip_edges().begins_with("`") and raw.strip_edges() != "":
			return raw.strip_edges()     # a plain-text reply: the whole thing is speech
		return ""
	var i := k + 5
	var n := raw.length()
	while i < n and (raw[i] == " " or raw[i] == ":" or raw[i] == "\n" or raw[i] == "\t" or raw[i] == "\r"):
		i += 1
	if i >= n or raw[i] != "\"":
		return ""
	i += 1
	var out := ""
	while i < n:
		var ch := raw[i]
		if ch == "\\":
			if i + 1 >= n:
				break                      # escape cut by the stream: wait for more
			var e := raw[i + 1]
			match e:
				"n":
					out += "\n"
				"t":
					out += " "
				"\"", "\\", "/":
					out += e
				"u":
					if i + 5 >= n:
						break
					out += char(raw.substr(i + 2, 4).hex_to_int())
					i += 4
				_:
					out += e
			i += 2
			continue
		if ch == "\"":
			break
		out += ch
		i += 1
	return out


## JSON.parse_string() logs an engine error on bad input; a cut-off reply is
## normal here, so parse quietly.
static func _quiet_parse(text: String) -> Variant:
	var j := JSON.new()
	if j.parse(text) != OK:
		return null
	return j.data


## The whole reply -> { say, mood, actions, ok, repaired }.
static func parse(raw: String) -> Dictionary:
	var text := raw.strip_edges()
	var d = _quiet_parse(text)
	var repaired := false
	if not (d is Dictionary):
		var s := text.replace("```json", "").replace("```", "")
		var a := s.find("{")
		var b := s.rfind("}")
		if a >= 0 and b > a:
			d = _quiet_parse(s.substr(a, b - a + 1))
			repaired = true
	if d is Dictionary and d.get("say") is String:
		var acts = d.get("actions", [])
		return {
			"say": str(d.say), "mood": str(d.get("mood", "")),
			"actions": acts if acts is Array else [], "ok": true, "repaired": repaired,
		}
	var say := say_partial(text)
	return { "say": say, "mood": "", "actions": [], "ok": say != "", "repaired": true }
