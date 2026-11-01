class_name LLMConfig
extends RefCounted
## LLM settings (M12): shipped defaults (content/core/llm/defaults.json) with the
## user's overrides (user://llm_config.json) merged on top, field by field.
##
## Keys never live in res://, saves, transcripts or logs. Lookup order for a
## profile's key: the env var named by `api_key_env`, then user://llm/keys.cfg
## (written by the settings panel). `masked()` is the only form ever displayed.

const DEFAULTS := "res://content/core/llm/defaults.json"
## The shared build (export feature "share") ships this instead: cloud only, Anthropic.
const SHARE_DEFAULTS := "res://content/core/llm/defaults_share.json"
const USER_PATH := "user://llm_config.json"
const KEYS_PATH := "user://llm/keys.cfg"

var data: Dictionary = {}
var user_path := USER_PATH
var keys_path := KEYS_PATH


static func default_path() -> String:
	return SHARE_DEFAULTS if OS.has_feature("share") and FileAccess.file_exists(SHARE_DEFAULTS) else DEFAULTS


func load_all(defaults_path: String = "") -> LLMConfig:
	data = _read(defaults_path if defaults_path != "" else default_path())
	var user := _read(user_path)
	data = merge(data, user)
	# Issue #328: a stored key picks its provider, unless the player set one by hand.
	var hand: Dictionary = user.get("profiles", {}).get("cloud", {})
	if not hand.has("type") and not hand.has("base_url"):
		apply_key_preset("cloud", api_key("cloud"), hand)
	return self


## Issue #328: AI characters on or off (off on a fresh install). Off, no model is
## called and no sidecar starts: everyone talks from their canned lines.
func ai_enabled() -> bool:
	return bool(data.get("ai_enabled", false))


func set_ai_enabled(on: bool) -> void:
	data["ai_enabled"] = on


## Issue #328: the first launch asks once whether to turn AI characters on.
func first_run_asked() -> bool:
	return bool(data.get("first_run_asked", false))


func set_first_run_asked() -> void:
	data["first_run_asked"] = true


## Issue #328: the preset ("key_presets" in the defaults) a key's prefix names, or {}.
func key_preset(key: String) -> Dictionary:
	var presets: Dictionary = data.get("key_presets", {})
	for prefix in presets:
		if presets[prefix] is Dictionary and key.begins_with(str(prefix)):
			return presets[prefix]
	return {}


## Set profile `id` to the provider its key belongs to (but not the fields in
## `keep`, set by hand). Returns true if it changed.
func apply_key_preset(id: String, key: String, keep: Dictionary = {}) -> bool:
	var pre := key_preset(key)
	if pre.is_empty() or profile(id).is_empty():
		return false
	var changed := false
	for k in pre:
		if not keep.has(k) and str(profile(id).get(k, "")) != str(pre[k]):
			set_value("profiles/%s/%s" % [id, k], pre[k])
			changed = true
	return changed


## Issue #328: the stored key belongs to another provider than the profile points
## at (an Anthropic key sent to OpenRouter): "" if it fits or nothing says.
func key_mismatch(id: String) -> String:
	var pre := key_preset(api_key(id))
	if pre.is_empty():
		return ""
	var p := profile(id)
	if str(p.get("type", "openai_compat")) != str(pre.get("type", "")) \
			or str(p.get("base_url", "")).trim_suffix("/") != str(pre.get("base_url", "")).trim_suffix("/"):
		return "the key is for %s but the profile points at %s" % [_host(str(pre.get("base_url", ""))), _host(str(p.get("base_url", "")))]
	return ""


static func _host(url: String) -> String:
	var rest := url.trim_prefix("https://").trim_prefix("http://")
	return rest.substr(0, rest.find("/")) if rest.find("/") >= 0 else rest


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


## Issue #328: how long a player waits for a first word before canned lines.
func give_up_ms() -> int:
	return int(gen().get("give_up_ms", 9000))


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
func save_user(defaults_path: String = "") -> bool:
	var base := _read(defaults_path if defaults_path != "" else default_path())
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
