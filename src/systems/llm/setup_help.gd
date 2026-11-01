class_name LLMSetupHelp
extends RefCounted
## Settings > AI brain: a Link and a Prompt button for Ollama, the local server and the
## cloud. Pure; the links and prompts live in content/core/llm/setup_help.json.
##   link(id)    -- the page to install it from
##   prompt(id)  -- set-up text for a coding agent (the Prompt button copies it)
##   intro()     -- what to do with the prompt

const PATH := "res://content/core/llm/setup_help.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f != null:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_data = d
	return _data


static func provider(id: String) -> Dictionary:
	return data().get("providers", {}).get(id, {})


static func link(id: String) -> String:
	return str(provider(id).get("link", ""))


static func intro() -> String:
	return str(data().get("prompt_intro", ""))


## The prompt is stored as an array of lines in the JSON so it stays readable.
static func prompt(id: String) -> String:
	var p = provider(id).get("prompt", "")
	return "\n".join(PackedStringArray(p)) if p is Array else str(p)
