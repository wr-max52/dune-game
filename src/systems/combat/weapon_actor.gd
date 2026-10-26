extends RefCounted
## Weapon actor (M2): the gameplay-facing wrapper around the pure Weapon state
## machine and a bolt factory. It fires visible bolts toward a target when the
## trigger is pulled, in the GUI. For headless CI it also tracks a shot log so a
## trace can verify "the blaster damages over time" without rendering.

const Weapon := preload("res://src/systems/combat/weapon.gd")
const BoltScene := preload("res://scenes/entities/bolt.tscn")

var weapon
## Defaults to the real bolt scene. It used to default to null and was never set
## anywhere, so _make_bolt() always returned early and no bolt ever spawned.
var bolt_scene: PackedScene = BoltScene
var bolt_parent: Node3D     ## must be set by the scene that owns this actor
var shots_fired := 0
var shots_log: Array = []   ## each: {target, damage}
## M15: called on each new bolt before it enters the tree (owner, look), so
## settings read in the bolt's _ready (the stretched streak) take effect.
var configure_bolt: Callable


func set_weapon(cfg: Dictionary) -> void:
	weapon = Weapon.new(cfg)


func _make_bolt(direction: Vector3, origin: Vector3, damage: float, speed: float) -> void:
	if bolt_scene == null or bolt_parent == null:
		return
	var bolt = bolt_scene.instantiate()
	bolt.direction = direction.normalized()
	bolt.speed = speed
	bolt.damage = damage
	bolt.range_m = float(weapon.config.get("range", 60.0))
	if configure_bolt.is_valid():
		configure_bolt.call(bolt)
	# Add to the tree first: setting global_position on a detached node is an error.
	bolt_parent.add_child(bolt)
	bolt.global_position = origin


func fire_at(target_pos: Vector3, origin: Vector3, dt: float, trigger: bool) -> void:
	var result: int = weapon.start_firing(dt, trigger)
	if result != Weapon.Result.SHOT:
		return
	var dir: Vector3 = (target_pos - origin).normalized()
	var dmg: float = float(weapon.config.get("damage", 10.0))
	var spd: float = float(weapon.config.get("bolt_speed", 30.0))
	_make_bolt(dir, origin, dmg, spd)
	shots_fired += 1
	shots_log.append({ "target": target_pos, "damage": dmg })
