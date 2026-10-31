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
var locations: Dictionary = {}    # location-id -> Dictionary (outpost, etc.)
var missions: Dictionary = {}      # mission-id -> Dictionary (crate_retrieval, etc.)
var ships: Dictionary = {}         # ship-id -> Dictionary (interceptor, etc.) (M10)
var pilots: Dictionary = {}        # pilot-id -> Dictionary (AI flying profiles) (M10)
var soldiers: Dictionary = {}      # soldier-id -> Dictionary (ground AI profiles: body, senses, pathing)
var encounters: Dictionary = {}    # encounter-id -> Dictionary (dogfight setups) (M10)
var items: Dictionary = {}         # item-id -> Dictionary (jetpack, etc.) (M13)
var vendors: Dictionary = {}       # vendor-id -> Dictionary (who buys and sells items) (M13)
var pickups: Dictionary = {}       # location-id -> Dictionary (items lying in that place) (M13)
var worlds: Dictionary = {}        # world-id -> Dictionary (terrain, landmarks, atmosphere) (M14)
var planets: Dictionary = {}       # planet-id -> Dictionary (a planet's config: type, town size, style) (issue #45)
var names: Dictionary = {}         # bank-id -> Dictionary (the name library: lists, tongues, kinds) (issue #15)
var towns: Dictionary = {}         # layout-id -> Dictionary (a saved town layout at its size: port_square) (issue #237)
var _loaded := false


func load_from(root: String = ROOT) -> bool:
	manifest = {}
	npcs = {}
	weapons = {}
	factions = {}
	dialogues = {}
	persona_prompts = {}
	locations = {}
	missions = {}
	ships = {}
	pilots = {}
	soldiers = {}
	encounters = {}
	items = {}
	vendors = {}
	pickups = {}
	worlds = {}
	names = {}
	planets = {}
	towns = {}

	manifest = _read_json_at(root_path(root, "manifest.json"))
	if manifest.is_empty():
		push_warning("CoreContent: manifest.json missing, continuing")
		return false

	var npc_ids: Array = manifest.get("npcs", [])
	var weapon_ids: Array = manifest.get("weapons", [])
	var faction_ids: Array = manifest.get("factions", [])
	var location_ids: Array = manifest.get("locations", [])
	var mission_ids: Array = manifest.get("missions", [])

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
	for location_id in location_ids:
		var ld: Dictionary = _read_dir_entry(root, "locations", location_id)
		if not ld.is_empty():
			locations[location_id] = ld
	for mission_id in mission_ids:
		var md: Dictionary = _read_dir_entry(root, "missions", mission_id)
		if not md.is_empty():
			missions[mission_id] = md
	# M10: flight categories use the same generic path; a new ship, pilot or encounter
	# is a JSON file plus a manifest entry, with no code change.
	_load_category(root, "ships", ships)
	_load_category(root, "pilots", pilots)
	# Ground AI profiles, the on-foot twin of the pilot profiles.
	_load_category(root, "soldiers", soldiers)
	_load_category(root, "encounters", encounters)
	# M13: gear and trade, same generic path.
	_load_category(root, "items", items)
	_load_category(root, "vendors", vendors)
	_load_category(root, "pickups", pickups)
	# M14: the world around a town (terrain, landmarks, where space starts).
	_load_category(root, "worlds", worlds)
	# Issue #15: the name library (NameBook also reads it straight from disk).
	_load_category(root, "names", names)
	# Issue #45: planets (the generator turns each into a town and a world).
	_load_category(root, "planets", planets)
	# Issue #237: saved town layouts. A planet names its town (the place: port_town)
	# and the layout it is built to; that town is also a location, so get_location
	# ("port_town") is the planet's chosen layout.
	_load_category(root, "towns", towns)
	for pid in planets:
		var town_id := str(planets[pid].get("town", ""))
		var layout := str(planets[pid].get("town_layout", ""))
		if town_id != "" and layout != "" and not locations.has(town_id):
			var t := town_from_layout(layout, town_id)
			if not t.is_empty():
				locations[town_id] = t

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


func get_location(id: String) -> Dictionary:
	return locations.get(id, {})


## Issue #237: a saved town layout as the town `town_id` (a deep copy: its id is
## the town's, its layout the layout's id). Empty when there is no such layout.
func town_from_layout(layout: String, town_id: String) -> Dictionary:
	var src: Dictionary = towns.get(layout, {})
	if src.is_empty():
		push_warning("CoreContent: no town layout " + layout)
		return {}
	var t: Dictionary = src.duplicate(true)
	t["id"] = town_id
	t["layout"] = layout
	return t


func get_mission(id: String) -> Dictionary:
	return missions.get(id, {})


func get_ship(id: String) -> Dictionary:
	return ships.get(id, {})


func get_pilot(id: String) -> Dictionary:
	return pilots.get(id, {})


## A soldier profile. One with "base" starts from that profile and overrides it
## block by block (a tower sentry is a gate guard with longer eyes), so shared
## numbers live in one file.
func get_soldier(id: String) -> Dictionary:
	var d: Dictionary = soldiers.get(id, {})
	var base := str(d.get("base", ""))
	if base == "" or base == id or not soldiers.has(base):
		return d
	return _merge(get_soldier(base), d)


static func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate(true)
	for k in b:
		if out.get(k) is Dictionary and b[k] is Dictionary:
			out[k] = _merge(out[k], b[k])
		else:
			out[k] = b[k]
	return out


func get_encounter(id: String) -> Dictionary:
	return encounters.get(id, {})


func get_item(id: String) -> Dictionary:
	return items.get(id, {})


func get_vendor(id: String) -> Dictionary:
	return vendors.get(id, {})


## Pickups placed in a location (an empty list when there are none). Issue #237:
## in a town built to `layout`, an entry's "layouts": { <layout>: {...} } block
## (where it lies in that layout: marker, offset) is laid over it. Same id and
## taken flag in every layout, so a pickup taken stays taken.
func get_pickups(location_id: String, layout: String = "") -> Array:
	var list: Array = pickups.get(location_id, {}).get("pickups", [])
	if layout == "":
		return list
	var out: Array = []
	for e in list:
		var over: Dictionary = e.get("layouts", {}).get(layout, {})
		if over.is_empty():
			out.append(e)
			continue
		var d: Dictionary = e.duplicate(true)
		d.merge(over, true)
		out.append(d)
	return out


## Wreck field: the supply crates out on the wrecks the place's planet holds
## ({ id, site, site_point }), and the prizes they roll from.
func get_site_crates(location_id: String) -> Array:
	return pickups.get(location_id, {}).get("site_crates", [])


func get_crate_prizes(location_id: String) -> Array:
	return pickups.get(location_id, {}).get("crate_prizes", [])


func get_world(id: String) -> Dictionary:
	return worlds.get(id, {})


## The world a town sits in (an empty dictionary when none names it), its
## landmarks where they stand in a town built to `layout` (issue #295; "" = the
## layout the town's planet names).
func world_for_town(town_id: String, layout: String = "") -> Dictionary:
	for id in worlds:
		if str(worlds[id].get("town", "")) == town_id:
			return resolve_layout(worlds[id], layout if layout != "" else layout_of(town_id))
	return {}


## Issue #295: the saved layout the planet holding `town_id` is built to ("" if none).
func layout_of(town_id: String) -> String:
	for pid in planets:
		if str(planets[pid].get("town", "")) == town_id:
			return str(planets[pid].get("town_layout", ""))
	return ""


## Issue #295: a copy of `world` with each landmark where it stands in a town built
## to `layout`: its "layouts": { <layout>: { at, yaw_deg, location } } block is laid
## over it and dropped, so every reader (the ground, SpeederPost, the tests) sees
## one landmark in one place. A layout it has no block for keeps its own fields.
static func resolve_layout(world: Dictionary, layout: String) -> Dictionary:
	var out: Dictionary = world.duplicate(true)
	for lm in out.get("landmarks", []):
		var over: Dictionary = lm.get("layouts", {}).get(layout, {})
		lm.erase("layouts")
		lm.merge(over, true)
	return out


## Vendors whose stall is in a location.
func vendors_in(location_id: String) -> Array:
	var out: Array = []
	for id in vendors:
		if str(vendors[id].get("location", "")) == location_id:
			out.append(vendors[id])
	return out


func get_persona(npc_id: String) -> String:
	return persona_prompts.get(npc_id, "")


func get_dialogue(list_id: String) -> Array:
	return dialogues.get(list_id, [])


# ---- IO helpers -----------------------------------------------------------

## Load every id the manifest lists under `category` from the folder of the same
## name. Missing entries are skipped with a warning, never a crash.
func _load_category(root: String, category: String, into: Dictionary) -> void:
	for id in manifest.get(category, []):
		var d: Dictionary = _read_dir_entry(root, category, str(id))
		if d.is_empty():
			push_warning("CoreContent: %s entry missing: %s" % [category, id])
			continue
		into[str(id)] = d


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
