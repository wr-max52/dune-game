extends RefCounted
## Weapon actor (M2): the gameplay-facing wrapper around the pure Weapon state
## machine and a bolt factory. It fires visible bolts toward a target when the
## trigger is pulled, in the GUI. For headless CI it also tracks a shot log so a
## trace can verify "the blaster damages over time" without rendering.

var weapon
var bolt_scene
var bolt_parent: Node3D
var shots_fired := 0
var shots_log: Array = []   ## each: {time, target, damage}


func set_weapon(cfg: Dictionary) -> void:
	weapon = load("res://src/systems/combat/weapon.gd").new(cfg)


func _make_bolt(direction: Vector3, origin: Vector3, damage: float, speed: float) -> void:
	if bolt_scene == null or bolt_parent == null:
		return
	var bolt = bolt_scene.instantiate()
	bolt.direction = direction.normalized()
	bolt.speed = speed
	bolt.damage = damage
	bolt.range_m = float(weapon.config.get("range", 60.0))
	bolt.global_position = origin
	bolt_parent.add_child(bolt)


func fire_at(target_pos: Vector3, origin: Vector3, dt: float, trigger: bool) -> void:
	var result: int = weapon.start_firing(dt, trigger)
	# Load the Result enum constants fresh to fire only on a genuine SHOT.
	var R = load("res://src/systems/combat/weapon.gd").Result
	if result != int(R.SHOT):
		return
	var dir: Vector3 = (target_pos - origin).normalized()
	var dmg: float = float(weapon.config.get("damage", 10.0))
	var spd: float = float(weapon.config.get("bolt_speed", 30.0))
	_make_bolt(dir, origin, dmg, spd)
	shots_fired += 1
	shots_log.append({ "target": target_pos, "damage": dmg })
