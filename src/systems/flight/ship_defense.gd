extends RefCounted
## Ship defense (M10). Pure: a regenerating shield in front of the M2 Health hull.
## Damage drains the shield first and spills the rest into the hull. The shield
## starts recharging `delay` seconds after the last hit. A ship with max shield 0
## (the unshielded remnant fighter) takes every hit on the hull.
##
## Tuning comes from the ship's "hull" and "shield" fields.

const Health := preload("res://src/systems/combat/health.gd")

var hull
var shield_max := 0.0
var shield := 0.0
var regen := 0.0
var delay := 0.0
var _since_hit := 1000.0


func _init(ship_cfg: Dictionary = {}) -> void:
	hull = Health.new(int(ship_cfg.get("hull", 100)))
	var s: Dictionary = ship_cfg.get("shield", {})
	shield_max = float(s.get("max", 0.0))
	shield = shield_max
	regen = float(s.get("regen", 0.0))
	delay = float(s.get("delay", 0.0))


## Apply damage. Returns { shield, hull } -- how much each layer absorbed.
func apply_damage(amount: float) -> Dictionary:
	if not hull.is_alive():
		return { "shield": 0.0, "hull": 0.0 }
	_since_hit = 0.0
	var to_shield := minf(shield, amount)
	shield -= to_shield
	var to_hull := amount - to_shield
	if to_hull > 0.0:
		hull.apply_damage(to_hull)
	return { "shield": to_shield, "hull": to_hull }


func step(dt: float) -> void:
	_since_hit += dt
	if hull.is_alive() and _since_hit >= delay and shield < shield_max:
		shield = minf(shield_max, shield + regen * dt)


func is_alive() -> bool:
	return hull.is_alive()


func hull_hp() -> int:
	return hull.hp


func hull_max() -> int:
	return hull.max_hp
