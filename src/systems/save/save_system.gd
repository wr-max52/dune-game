extends RefCounted
## Save system (M5). Pure, headless-testable, no Node3D (so it works in CI and in
## the editor). It serialises and restores the four things the spec names:
##   - player position (Vector3)
##   - credits (int)
##   - mission state (from a Mission's to_save())
##   - cantina owner memory (a Dictionary of remembered facts)
##
## It writes one JSON file. A future skin can swap the path or add fields without
## other code changes. A deterministic stub path is fine for CI because this is a
## file round-trip, not LLM inference.
##
## v2 (M12) adds "world" (WorldState: standing, flags, jobs, credits) and
## "relationships" (npc id -> Relationship). A v1 file migrates on load: its loose
## npc_memory becomes facts the cantina owner remembers.

const VERSION := 2

var save_path := "user://save.json"
var data: Dictionary = {}


func new_game() -> void:
	data = {
		"player_position": [0.0, 0.0, 0.0],
		"credits": 0,
		"mission": {},
		"npc_memory": {},
		"world": {},
		"relationships": {},
		"version": VERSION,
	}


func set_player_position(p: Vector3) -> void:
	data["player_position"] = [p.x, p.y, p.z]


func get_player_position() -> Vector3:
	var v: Array = data.get("player_position", [0.0, 0.0, 0.0])
	return Vector3(v[0], v[1], v[2])


func add_credits(amount: int) -> void:
	data["credits"] = int(data.get("credits", 0)) + amount


func get_credits() -> int:
	return int(data.get("credits", 0))


func set_mission(mission_state: Dictionary) -> void:
	data["mission"] = mission_state


func get_mission() -> Dictionary:
	return data.get("mission", {})


func remember_in_cantina_owner(key: String, value: Variant) -> void:
	data["npc_memory"][key] = value


func get_npc_memory() -> Dictionary:
	return data.get("npc_memory", {})


func set_world(w: Dictionary) -> void:
	data["world"] = w


func get_world() -> Dictionary:
	return data.get("world", {})


func set_relationship(npc_id: String, r: Dictionary) -> void:
	if not data.has("relationships"):
		data["relationships"] = {}
	data["relationships"][npc_id] = r


func get_relationship(npc_id: String) -> Dictionary:
	return data.get("relationships", {}).get(npc_id, {})


## Bring an older save up to VERSION. Idempotent.
static func migrate(d: Dictionary) -> Dictionary:
	var v := int(d.get("version", 1))
	if v < 2:
		d["world"] = d.get("world", {})
		var rel := { "facts": [] }
		var mem: Dictionary = d.get("npc_memory", {})
		for k in mem:
			rel.facts.append("%s: %s" % [str(k).replace("_", " "), str(mem[k])])
		d["relationships"] = { "cantina_owner": rel }
		d["version"] = 2
	return d


func save_to(path: String = save_path) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("SaveSystem: cannot open ", path)
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true


func load_from(path: String = save_path) -> bool:
	if not FileAccess.file_exists(path):
		push_warning("SaveSystem: no save at ", path)
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var raw: String = f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(raw)
	if parsed != null and parsed is Dictionary:
		data = migrate(parsed)
		return true
	return false