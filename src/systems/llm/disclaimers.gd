class_name Disclaimers
extends RefCounted
## Issue #29: the reminders that AI characters are not real people. Pure; the
## texts and trigger words live in content/core/llm/disclaimers.json.
##   launch()          -- { title, text, button } for the notice at game start
##   talk_text(name)   -- pinned at the top of every conversation
##   triggered(text)   -- does the player's message call for the reminder again?
##   repeat_text(name) -- that reminder

const PATH := "res://content/core/llm/disclaimers.json"
const ENDINGS := "(s|es|d|ed|ing|er|ers)?"

static var _data: Dictionary = {}
static var _patterns: Array = []     ## RegEx, one per trigger
static var launch_shown := false     ## once per run of the game, not per scene load


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f != null:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_data = d
		if _data.is_empty():
			push_warning("Disclaimers: could not read ", PATH)
	return _data


static func launch() -> Dictionary:
	return data().get("launch", {})


static func talk_text(npc_name: String) -> String:
	return _fill(str(data().get("talk", "")), npc_name)


static func repeat_text(npc_name: String) -> String:
	return _fill(str(data().get("repeat", "")), npc_name)


## True when `text` contains a trigger as a whole word (or phrase).
static func triggered(text: String) -> bool:
	return not matches(text).is_empty()


## The triggers found in `text` (for tests and the debug overlay).
static func matches(text: String) -> Array:
	if _patterns.is_empty():
		for t in data().get("triggers", []):
			var words := str(t).to_lower().strip_edges().split(" ", false)
			var esc: PackedStringArray = []
			for w in words:
				esc.append(_escape(w))
			var re := RegEx.new()
			re.compile("(?<![a-z'])" + "\\s+".join(esc) + ENDINGS + "(?![a-z'])")
			_patterns.append({ "word": str(t), "re": re })
	var low := text.to_lower().replace("’", "'")
	var out: Array = []
	for p in _patterns:
		if (p.re as RegEx).search(low) != null:
			out.append(p.word)
	return out


static func _fill(t: String, npc_name: String) -> String:
	return t % npc_name if t.contains("%s") else t


static func _escape(w: String) -> String:
	var out := ""
	for c in w:
		out += ("\\" + c) if "\\.^$|?*+()[]{}".contains(c) else c
	return out
