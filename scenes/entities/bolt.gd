extends Area3D
## Visible projectile -- the "bolt" (M2). Travels straight, leaves a short glow,
## and on first contact with anything that can take damage, it deals its damage and
## dies. The weapon actor spawns bolts in different collision layers so they hit
## enemies but not their own owner. In the GUI the bolt is visible; in headless CI
## the bolt's behavior (it travels and deals damage on hit) is proven by GUT.

var direction := Vector3.FORWARD
var damage := 10.0
var speed := 30.0
var range_m := 60.0
var _traveled := 0.0
var _alive := true
## Test seam: if set, a hit applies damage to this node instead of the colliding body.
var hit_target

## M11 (player weapons). All opt-in so the M2 trooper bolts behave exactly as before.
var shooter: Node = null       ## never hits its own shooter
var friends: Array = []        ## issue #64: never hits these either (your droid's bolts fly past you)
var stylize := false           ## a stretched glowing streak instead of the sphere
var sweep := false             ## ray-test each step so fast bolts cannot tunnel
var color := Color(1.0, 0.45, 0.2)
var streak_length := 0.9
var streak_radius := 0.035
var reflected := 0             ## times a blade has sent it back
var _streak: MeshInstance3D

signal on_hit(target)
signal on_reflect


func integrate(dt: float) -> Vector3:
	## Pure: compute the displacement for this frame and update range. The caller
	## applies it to its own node. No scene-tree access, so it is unit-testable.
	if not _alive:
		return Vector3.ZERO
	var step: Vector3 = direction * speed * dt
	_traveled += step.length()
	if _traveled >= range_m:
		_die()
	return step


## Apply this bolt's damage to a node that can take damage, then kill the bolt.
## `target` is typed Node (not Node3D) so RefCounted health components work too.
func apply_to(target: Object) -> void:
	if not _alive:
		return
	_die()
	handle_hit(target)


func handle_hit(target: Object) -> void:
	if target == null:
		return
	# A target that cares who shot it (an NPC: no friendly fire, and "the player
	# shot me" starts a fight) gets the shooter too.
	if target.has_method("apply_damage_from"):
		target.apply_damage_from(damage, shooter)
	elif target.has_method("apply_damage"):
		target.apply_damage(damage)
	elif target.get_parent() != null and target.get_parent().has_method("apply_damage"):
		target.get_parent().apply_damage(damage)
	on_hit.emit(target)


func _ready() -> void:
	# The bolt.tscn already carries a Glow MeshInstance3D; this branch only runs
	# when a bolt is created without the scene (e.g. in a headless test).
	if not has_node("Glow"):
		var mesh := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.18
		mesh.mesh = sphere
		mesh.name = "Glow"
		add_child(mesh)
	body_entered.connect(_on_body_entered)
	add_to_group("bolts")
	if stylize:
		_build_streak()


func _build_streak() -> void:
	var glow := get_node_or_null("Glow") as MeshInstance3D
	if glow != null:
		glow.visible = false
	_streak = MeshInstance3D.new()
	_streak.name = "Streak"
	var cap := CapsuleMesh.new()
	cap.radius = streak_radius
	cap.height = streak_length
	cap.radial_segments = 8
	cap.rings = 2
	_streak.mesh = cap
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color.lerp(Color.WHITE, 0.45)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 5.0
	_streak.material_override = m
	_streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_streak)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 0.8
	light.omni_range = 2.5
	light.shadow_enabled = false
	add_child(light)
	_orient()


## Point the streak along the direction of travel (a capsule's long axis is Y).
func _orient() -> void:
	if _streak == null or direction.length() < 0.01:
		return
	var y := direction.normalized()
	var hint := Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT
	var x := hint.cross(y).normalized()
	_streak.basis = Basis(x, y, x.cross(y))


## A blade sent it back: new heading, new owner, a little faster.
func reflect(new_direction: Vector3, new_shooter: Node) -> void:
	direction = new_direction.normalized()
	shooter = new_shooter
	speed *= 1.15
	_traveled = 0.0
	reflected += 1
	_orient()
	on_reflect.emit()


func _physics_process(dt: float) -> void:
	# Whoever fired it may be gone already (a droid that respawned, a trooper
	# who left town): a freed shooter is an error to even test with `is`.
	if shooter != null and not is_instance_valid(shooter):
		shooter = null
	# Advance the bolt along its direction by one frame.
	var step := integrate(dt)
	if sweep and _alive and is_inside_tree() and step.length() > 0.0:
		var space := get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(global_position, global_position + step)
		q.collide_with_areas = false
		var skip: Array[RID] = []
		if shooter is CollisionObject3D:
			skip.append((shooter as CollisionObject3D).get_rid())
		for f in friends:
			if is_instance_valid(f) and f is CollisionObject3D:
				skip.append((f as CollisionObject3D).get_rid())
		q.exclude = skip
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			global_position = hit.position
			apply_to(hit.collider if hit_target == null else hit_target)
			return
	global_position += step


func _on_body_entered(body: Node3D) -> void:
	if not _alive:
		return
	if shooter != null and not is_instance_valid(shooter):
		shooter = null
	if shooter != null and body == shooter:
		return
	if friends.has(body):
		return
	if hit_target != null:
		apply_to(hit_target)
	else:
		apply_to(body)


func _die() -> void:
	_alive = false
	# A bolt in the scene tree is freed by the engine; a detached bolt (created in
	# a headless unit test) is freed at process exit. GUT reports this as one
	# orphan, which does not fail the suite. (Documented in KNOWN_ISSUES.md.)
	queue_free()
