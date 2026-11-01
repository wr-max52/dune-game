extends RefCounted
## Ship loadout (M10). Pure: turns a ship's "hardpoints" list into working guns. Each
## hardpoint owns its own M2 Weapon state machine (ammo, fire rate, reload), so ship
## guns follow the same rules as the hand blasters. Weapons are grouped by their
## data "fire_group": "primary" (cannons) and "secondary" (seekers).
##
## A weapon with "reload_each" (seconds) never reloads the whole mag at once: it
## gets one round back every reload_each seconds while it is short (the seeker
## rack), so you can fire the rack off in a salvo and it trickles back.
##
## fire() returns projectile spawns; it never creates nodes. The dogfight director
## feeds them to the projectile field, and the scene draws them. A new weapon is a
## weapons/*.json entry plus a hardpoint line, with no code change.

const Weapon := preload("res://src/systems/combat/weapon.gd")

var hardpoints: Array = []   ## each: { weapon_id, cfg, weapon, mount: Vector3, group, refill }
var convergence := 300.0     ## metres ahead where fixed guns cross
var power := 1.0             ## the ship's "blaster_power": every bolt's damage times this


func _init(ship_cfg: Dictionary = {}, content = null) -> void:
	convergence = float(ship_cfg.get("convergence", convergence))
	power = float(ship_cfg.get("blaster_power", 1.0))
	for hp in ship_cfg.get("hardpoints", []):
		var wid := str(hp.get("weapon", ""))
		var wcfg: Dictionary = content.get_weapon(wid) if content != null else {}
		if wcfg.is_empty():
			push_warning("ShipLoadout: unknown weapon id: ", wid)
			continue
		var m: Array = hp.get("mount", [0, 0, 0])
		hardpoints.append({
			"weapon_id": wid,
			"cfg": wcfg,
			"weapon": Weapon.new(wcfg),
			"mount": Vector3(float(m[0]), float(m[1]), float(m[2])),
			"group": str(wcfg.get("fire_group", "primary")),
			"refill": 0.0,           ## seconds toward the next round (reload_each weapons)
		})


func has_group(group: String) -> bool:
	for h in hardpoints:
		if h.group == group:
			return true
	return false


## The first weapon config in a group (used for lead speed and lock tuning).
func group_config(group: String) -> Dictionary:
	for h in hardpoints:
		if h.group == group:
			return h.cfg
	return {}


## Rounds left across a group, for the HUD.
func group_ammo(group: String) -> int:
	var n := 0
	for h in hardpoints:
		if h.group == group:
			n += int(h.weapon.ammo)
	return n


func group_reloading(group: String) -> bool:
	for h in hardpoints:
		if h.group == group and h.weapon.is_reloading():
			return true
	return false


## Tick every weapon and return the projectiles fired this frame.
##   xform        -- the ship's world transform (mount points are local to it)
##   ship_vel     -- the ship's velocity; projectiles inherit it
##   primary      -- trigger for the primary group
##   secondary    -- trigger for the secondary group (seekers launch with or without a lock)
##   target_id    -- what a homing projectile should chase (-1 for none: it flies
##                   straight off the nose, like a bolt)
func fire(dt: float, xform: Transform3D, ship_vel: Vector3, primary: bool, secondary: bool,
		target_id: int = -1) -> Array:
	var out: Array = []
	var fwd := -xform.basis.z
	var aim_point := xform.origin + fwd * convergence
	var fired_secondary := false
	for h in hardpoints:
		var w = h.weapon
		var pull := primary if h.group == "primary" else (secondary and not fired_secondary)
		var each := float(h.cfg.get("reload_each", 0.0))
		if each > 0.0:
			_trickle(h, dt, each)
			pull = pull and w.ammo > 0
		var result: int = w.start_firing(dt, pull)
		# Ship weapons recharge on their own once empty (heat / rack reload).
		if each <= 0.0 and w.ammo <= 0 and not w.is_reloading():
			w.start_reloading()
		if result != Weapon.Result.SHOT:
			continue
		var origin: Vector3 = xform * (h.mount as Vector3)
		var homing := bool(h.cfg.get("homing", false))
		var dir: Vector3 = fwd if homing else (aim_point - origin).normalized()
		var spd := float(h.cfg.get("bolt_speed", 200.0))
		out.append({
			"weapon_id": h.weapon_id,
			"kind": "missile" if homing else "bolt",
			"origin": origin,
			"velocity": dir * spd + ship_vel,
			"speed": spd,
			"damage": float(h.cfg.get("damage", 10.0)) * power,
			"personnel_damage": float(h.cfg.get("personnel_damage", 0.0)) * power,
			"range": float(h.cfg.get("range", 800.0)),
			"homing": homing,
			"turn_rate": float(h.cfg.get("turn_rate", 0.0)),
			"target_id": target_id if homing else -1,
			"splash_radius": float(h.cfg.get("splash_radius", 0.0)),
			"splash_damage": float(h.cfg.get("splash_damage", 0.0)) * power,
			"blast_size": float(h.cfg.get("blast_size", 0.0)),
		})
		if h.group == "secondary":
			fired_secondary = true
	return out


## A group's rounds and refill clocks, one entry per hardpoint: the seeker rack the
## air and a space fight share (ShipPilot hands it across both ways).
func rack(group: String) -> Array:
	var out: Array = []
	for h in hardpoints:
		if h.group == group:
			out.append({ "ammo": int(h.weapon.ammo), "refill": float(h.refill) })
	return out


func set_rack(group: String, r: Array) -> void:
	var i := 0
	for h in hardpoints:
		if h.group != group or i >= r.size():
			continue
		h.weapon.ammo = mini(int(h.weapon.config.get("mag", 10)), int(r[i].ammo))
		h.refill = float(r[i].refill)
		i += 1


## One round back into a reload_each weapon every `each` seconds it is short.
func _trickle(h: Dictionary, dt: float, each: float) -> void:
	var w = h.weapon
	var mag := int(w.config.get("mag", 10))
	if w.ammo >= mag:
		h.refill = 0.0
		return
	h.refill += dt
	if h.refill >= each:
		h.refill -= each
		w.ammo = mini(mag, w.ammo + 1)
