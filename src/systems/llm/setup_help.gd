class_name LLMSetupHelp
extends RefCounted
## Settings > AI brain: a Link and a Prompt button for Ollama, the local server and the
## cloud. Pure; the links and prompts live in content/core/llm/setup_help.json.
##   link(id)    -- the page to install it from
##   prompt(id)  -- text to give a coding agent, with this machine's real paths filled in
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


## `paths` can replace game_dir, user_dir and config_file (tests do).
static func prompt(id: String, paths: Dictionary = {}) -> String:
	var text := str(provider(id).get("prompt", ""))
	var fill := {
		"game_dir": ProjectSettings.globalize_path("res://").trim_suffix("/"),
		"user_dir": ProjectSettings.globalize_path("user://").trim_suffix("/"),
		"config_file": ProjectSettings.globalize_path(LLMConfig.USER_PATH),
	}
	fill.merge(paths, true)
	for k in fill:
		text = text.replace("{%s}" % k, str(fill[k]))
	return text
