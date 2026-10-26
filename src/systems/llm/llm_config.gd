class_name LLMConfig
extends RefCounted
## LLM settings (M12): shipped defaults (content/core/llm/defaults.json) with the
## user's overrides (user://llm_config.json) merged on top, field by field.
##
## Keys never live in res://, saves, transcripts or logs. Lookup order for a
## profile's key: the env var named by `api_key_env`, then user://llm/keys.cfg
## (written by the settings panel). `masked()` is the only form ever displayed.

const DEFAULTS := "res://content/core/llm/defaults.json"
const USER_PATH := "user://llm_config.json"
const KEYS_PATH := "user://llm/keys.cfg"

var data: Dictionary = {}
var user_path := USER_PATH
var keys_path := KEYS_PATH


func load_all(defaults_path: String = DEFAULTS) -> LLMConfig:
	data = _read(defaults_path)
	var user := _read(user_path)
	data = merge(data, user)
	return self


## Deep merge: dictionaries merge key by key, everything else replaces.
static func merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for k in over:
		if out.has(k) and out[k] is Dictionary and over[k] is Dictionary:
			out[k] = merge(out[k], over[k])
		else:
			out[k] = over[k] if not (over[k] is Dictionary or over[k] is Array) else over[k].duplicate(true)
	return out


func chain() -> Array:
	return data.get("chain", [])


func profile(id: String) -> Dictionary:
	return data.get("profiles", {}).get(id, {})


func gen() -> Dictionary:
	return data.get("gen", {})


func first_token_timeout_ms(id: String) -> int:
	var t: Dictionary = gen().get("first_token_timeout_ms", {})
	return int(t.get(id, t.get("cloud", 4000) if id.begins_with("cloud") else 2500))


## A profile is usable if it is not switched off and, when it needs a key, has one.
func usable(id: String) -> bool:
	var p := profile(id)
	if p.is_empty() or not bool(p.get("enabled", true)):
		return false
	if p.has("api_key_env") or str(p.get("type", "")) == "anthropic":
		return api_key(id) != ""
	return true


func api_key(id: String) -> String:
	var p := profile(id)
	var env := str(p.get("api_key_env", ""))
	if env != "" and OS.has_environment(env) and OS.get_environment(env) != "":
		return OS.get_environment(env)
	var cf := ConfigFile.new()
	if cf.load(keys_path) == OK:
		return str(cf.get_value("keys", id, ""))
	return ""


func set_api_key(id: String, key: String) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(keys_path.get_base_dir()))
	var cf := ConfigFile.new()
	cf.load(keys_path)
	cf.set_value("keys", id, key)
	return cf.save(keys_path) == OK


static func masked(key: String) -> String:
	if key == "":
		return "(none)"
	if key.length() <= 8:
		return "****"
	return key.substr(0, 3) + "..." + key.substr(key.length() - 4)


## Save only what differs from the defaults, so shipped changes still flow in.
func save_user(defaults_path: String = DEFAULTS) -> bool:
	var base := _read(defaults_path)
	var diff := _diff(base, data)
	var f := FileAccess.open(user_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(diff, "\t"))
	return true


func set_value(path: String, value) -> void:
	var parts := path.split("/")
	var d: Dictionary = data
	for i in parts.size() - 1:
		if not d.has(parts[i]) or not (d[parts[i]] is Dictionary):
			d[parts[i]] = {}
		d = d[parts[i]]
	d[parts[parts.size() - 1]] = value


static func _diff(base: Dictionary, cur: Dictionary) -> Dictionary:
	var out := {}
	for k in cur:
		if not base.has(k):
			out[k] = cur[k]
		elif cur[k] is Dictionary and base[k] is Dictionary:
			var sub := _diff(base[k], cur[k])
			if not sub.is_empty():
				out[k] = sub
		elif str(cur[k]) != str(base[k]):
			out[k] = cur[k]
	return out


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}
