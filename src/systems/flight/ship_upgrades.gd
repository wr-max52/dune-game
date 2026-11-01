class_name ShipUpgrades
extends RefCounted
## Ship upgrades T-89 fits (issue #207): boosted shields, reinforced hull, booster
## speed. Pure and static; what is fitted lives in WorldState.ship_fits (saved):
## ship id -> [upgrade id, ...], each one-time per ship.
##
## Each upgrade is data in content/core/npcs/t89.json "upgrades": { label, short,
## price, mult: { "<path>": factor } }, a path being a key in the ship's data
## ("hull", "shield.max", "atmosphere.boost_speed"). apply() puts them on a copy of
## a ship's data wherever the player's ship is set up (ShipPilot in the air,
## Dogfight in space); every other ship of that model stays as it is.
## An upgrade can also repaint a ship: see look().

const CFG_PATH := "res://content/core/npcs/t89.json"
const SHIP_DIR := "res://content/core/ships"

static var _cfg: Dictionary = {}
static var _looks: Dictionary = {}


static func all() -> Dictionary:
	if _cfg.is_empty():
		var f := FileAccess.open(CFG_PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f != null else null
		_cfg = d.get("upgrades", {}) if d is Dictionary else {}
	return _cfg


static func ids() -> Array:
	return all().keys()


static func label(id: String) -> String:
	return str(all().get(id, {}).get("label", id))


static func price(id: String) -> int:
	return int(all().get(id, {}).get("price", 0))


static func fitted(ship_id: String) -> Array:
	return WorldState.ship_fits.get(ship_id, [])


static func has(ship_id: String, id: String) -> bool:
	return fitted(ship_id).has(id)


## Fit one (the money is the shop's business). Returns false when it is unknown or already on.
static func fit(ship_id: String, id: String) -> bool:
	if not all().has(id) or has(ship_id, id):
		return false
	WorldState.ship_fits[ship_id] = fitted(ship_id) + [id]
	return true


## The ships the player owns, by id (each kind once): the wreck T-89 rebuilt, the
## one he sold you, and issue #368's stolen ones Skrugs cleaned up (Fleet).
static func owned() -> Array:
	var out: Array = []
	for e in Fleet.owned():
		if not out.has(str(e.ship)):
			out.append(str(e.ship))
	return out


## A copy of `cfg` (ship `ship_id`'s data) with its upgrades on.
static func apply(cfg: Dictionary, ship_id: String) -> Dictionary:
	var fits := fitted(ship_id)
	if fits.is_empty():
		return cfg
	var out := cfg.duplicate(true)
	for id in fits:
		var mult: Dictionary = all().get(id, {}).get("mult", {})
		for path in mult:
			var keys := str(path).split(".")
			var d: Dictionary = out
			for k in keys.slice(0, keys.size() - 1):
				d = d.get(k, {})
			var last := keys[keys.size() - 1]
			if d.has(last):
				d[last] = float(d[last]) * float(mult[path])
	if out.has("look"):
		out["look"] = look(ship_id, str(out.look))
	return out


## The look ship `ship_id` shows with its upgrades on. An upgrade with a paint job for
## this look ("<look>_<upgrade id>" in content/look/ships.json: the frigate's three,
## the same model recoloured by tools/look/prep_vehicle.gd) repaints it; with several,
## the last one fitted wins. Otherwise `look_id` as it is.
static func look(ship_id: String, look_id: String) -> String:
	if _looks.is_empty():
		_looks = ShipKit._read_json(ShipKit.LOOKS_PATH).get("looks", {})
	var fits := fitted(ship_id)
	for k in range(fits.size() - 1, -1, -1):
		var painted := "%s_%s" % [look_id, fits[k]]
		if _looks.has(painted):
			return painted
	return look_id


## "Shields+  Hull+" for the board prompt, "" with none.
static func short(ship_id: String) -> String:
	return "  ".join(PackedStringArray(fitted(ship_id).map(func(id): return str(all().get(id, {}).get("short", id)))))


## "Kaldor VX-88 Kestrel: boosted shields, booster speed" per owned ship (the log, F1).
static func owned_lines() -> Array:
	var out: Array = []
	for sid in owned():
		var names: Array = fitted(sid).map(func(id): return label(id).to_lower())
		out.append("%s: %s" % [ship_label(sid), ", ".join(PackedStringArray(names)) if not names.is_empty() else "stock"])
	return out


static func ship_label(ship_id: String) -> String:
	var f := FileAccess.open("%s/%s.json" % [SHIP_DIR, ship_id], FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f != null else null
	return str(d.get("label", ship_id)) if d is Dictionary else ship_id
