extends RefCounted
## Core content data layer (M0).
##
## Loads every entry under res://content/core at runtime and exposes them by
## string id. NOTHING that is IP-neutral (names, factions, weapon labels,
## dialogue, prompts) is hardcoded anywhere outside content/core. This class is
## the only place that knows a name means a thing; code elsewhere asks by id.
##
## A private "skin" layer added later can point this loader at a different
## directory and the game requires zero code changes.

const ROOT := "res://content/core"

var manifest: Dictionary = {}
var npcs: Dictionary = {}
var weapons: Dictionary = {}
var factions: Dictionary = {}
var dialogues: Dictionary = {}   # list-id -> Array of Dictionary
var persona_prompts: Dictionary = {}  # npc-id -> String
var _loaded := false


func load_from(root: String = ROOT) -> bool:
	manifest = {}
	npcs = {}
	weapons = {}
	factions = {}
	dialogues = {}
	persona_prompts = {}

	manifest = _read_json_at(root_path(root, "manifest.json"))
	if manifest.is_empty():
		push_warning("CoreContent: manifest.json missing, continuing")
		return false

	var npc_ids: Array = manifest.get("npcs", [])
	var weapon_ids: Array = manifest.get("weapons", [])
	var faction_ids: Array = manifest.get("factions", [])

	for npc_id in npc_ids:
		var d: Dictionary = _read_dir_entry(root, "npcs", npc_id)
		if d.is_empty():
			push_warning("CoreContent: npc entry missing: ", npc_id)
			continue
		npcs[npc_id] = d
		_load_dialogue_refs(root, npc_id, d)
		if d.get("kind", "") == "llm" and d.has("persona_prompt_file"):
			persona_prompts[npc_id] = _read_text(root, "dialogue", str(d["persona_prompt_file"]).replace("dialogue/", ""))

	for weapon_id in weapon_ids:
		weapons[weapon_id] = _read_dir_entry(root, "weapons", weapon_id)
	for faction_id in faction_ids:
		factions[faction_id] = _read_dir_entry(root, "factions", faction_id)

	_loaded = true
	return true


## Resolve every dialogue reference on an npc entry into dialogues[list-id] and
## attach the parsed lines back onto the npc dictionary under "lines".
func _load_dialogue_refs(root: String, npc_id: String, npc: Dictionary) -> void:
	var refs: Array = npc.get("dialogue", [])
	for ref in refs:
		var ref_str: String = str(ref)
		# refs look like "dialogue/fixer_lines"; take the filename without ".json".
		var parts: Array = ref_str.split("/")
		var list_id: String = (parts[parts.size() - 1]).replace(".json", "")
		var lines: Array = _read_json_at_array(root, "dialogue", list_id + ".json")
		dialogues[list_id] = lines
		npc["_lines_" + list_id] = lines


func all_npcs() -> Array:
	return npcs.values()


func get_npc(id: String) -> Dictionary:
	return npcs.get(id, {})


func get_weapon(id: String) -> Dictionary:
	return weapons.get(id, {})


func get_faction(id: String) -> Dictionary:
	return factions.get(id, {})


func get_persona(npc_id: String) -> String:
	return persona_prompts.get(npc_id, "")


func get_dialogue(list_id: String) -> Array:
	return dialogues.get(list_id, [])


# ---- IO helpers -----------------------------------------------------------

func _read_dir_entry(root: String, dir: String, id: String) -> Dictionary:
	return _read_json(root, dir, id + ".json")


func _read_json(root: String, dir: String, name: String) -> Dictionary:
	return _read_json_at(root_path(root, dir + "/" + name))


func _read_json_at(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("CoreContent: missing ", path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("CoreContent: cannot open ", path)
		return {}
	var raw: String = file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(raw)
	if parsed is Dictionary:
		return parsed
	push_warning("CoreContent: not a JSON object: ", path)
	return {}


func _read_text(root: String, dir: String, name: String) -> String:
	var path: String = root + "/" + dir + "/" + name
	if not FileAccess.file_exists(path):
		push_warning("CoreContent: missing text ", path)
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


func root_path(root: String, sub: String) -> String:
	return root + "/" + sub


func _read_json_at_array(root: String, dir: String, name: String) -> Array:
	var parsed: Variant = _parse_at(root_path(root, dir + "/" + name))
	if parsed is Array:
		return parsed
	if parsed is Dictionary and parsed.has("lines"):
		return parsed["lines"]
	push_warning("CoreContent: dialogue not an array: ", name)
	return []


func _parse_at(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_warning("CoreContent: missing ", path)
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("CoreContent: cannot open ", path)
		return null
	var raw: String = file.get_as_text()
	file.close()
	return JSON.parse_string(raw)
