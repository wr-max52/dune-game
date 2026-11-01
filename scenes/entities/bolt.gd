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
## Issue #64: a ship's cannon bolt bursts where it lands, hurting everything within
## splash_radius (people on the ground), and bursts on the ground under it too
## (ground_at: (x, z) -> height; the desert's collider is not where a ship flies).
var splash_radius := 0.0
var splash_damage := 0.0
## A ship's cannon is built to hurt ships: `damage` is what a hit does to a ship's hull
## (ShipHull, the same in the air as in space), soft_damage what it does to anything
## else it hits (a trooper, a droid, a beast, a speeder). 0 = `damage` to everything.
var soft_damage := 0.0
var ground_at: Callable
## Issue #93: on the home planet's ball the ground is not a function of (x, z) (past the
## equator the same x, z is under the planet), so a ship's bolt there asks how high it is over
## the ground along the ground's up instead: over_ground: (p: Vector3) -> float (<= 0 is in
## it), ground_up: (p: Vector3) -> Vector3. When over_ground is set it replaces ground_at.
var over_ground: Callable
var ground_up: Callable
var stylize := false           ## a stretched glowing streak instead of the sphere
var sweep := false             ## ray-test each step so fast bolts cannot tunnel
var color := Color(1.0, 0.45, 0.2)
var streak_length := 0.9
var streak_radius := 0.035
var matte := false             ## issue #96: a thrown rock: plain colour, no glow, no light
## A ship's seeker in the air: it turns toward `seek` (a ShipHull, a node) by up to
## turn_rate radians a second while that is still there, and where it bursts it goes
## up like a vehicle (ExplosionFx.big at blast_size, with the boom) instead of the
## bolt's pop. No seek: it flies straight, like any bolt.
var seek: Node3D = null
var turn_rate := 0.0
var blast_size := 0.0
var reflected := 0             ## times a blade has sent it back
var _streak: MeshInstance3D

signal on_hit(target)
signal on_reflect
signal on_splash(target)        ## issue #181: each thing the burst damaged (not the direct hit)


func integrate(dt: float) -> Vector3:
	## Pure: compute the displacement for this frame and update range. The caller
	## applies it to its own node. No scene-tree access, so it is unit-testable.
	if not _alive:
		return Vector3.ZERO
	var step: Vector3 = direction * speed * dt
	_traveled += step.length()
	if _traveled >= range_m:
		_die()
	_trail()
	return step


## Apply this bolt's damage to a node that can take damage, then kill the bolt.
## `target` is typed Node (not Node3D) so RefCounted health components work too.
func apply_to(target: Object) -> void:
	if not _alive:
		return
	_die()
	# Whatever it landed on (a body, the ground, a blade that blocked it) gets the
	# bolt pop of sparks; a rock just thuds. One that runs out of range does not.
	if blast_size > 0.0 and is_inside_tree():
		ExplosionFx.big(get_parent(), global_position, blast_size)
		Sound.play("ship_boom", global_position)
	elif not matte and is_inside_tree():
		ExplosionFx.bolt(get_parent(), global_position)
	handle_hit(target)
	if splash_radius > 0.0:
		_splash(target)


## Damage everything within splash_radius of where it burst but the thing it hit
## (that took the full bolt) and whoever fired it.
func _splash(direct: Object) -> void:
	if not is_inside_tree():
		return
	var q := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = splash_radius
	q.shape = sphere
	q.transform = Transform3D(Basis.IDENTITY, global_position)
	q.collision_mask = 1 | 2
	q.collide_with_areas = false
	var seen := {}
	for r in get_world_3d().direct_space_state.intersect_shape(q, 32):
		var c: Object = r.collider
		if c == null or c == direct or c == shooter or seen.has(c) or friends.has(c):
			continue
		seen[c] = true
		if c.has_method("apply_damage_from"):
			c.apply_damage_from(splash_damage, shooter)
		elif c.has_method("apply_damage"):
			c.apply_damage(splash_damage)
		else:
			continue
		on_splash.emit(c)


func handle_hit(target: Object) -> void:
	if target == null:
		return
	var amount := damage if soft_damage <= 0.0 or target is ShipHull else soft_damage
	# A target that cares who shot it (an NPC: no friendly fire, and "the player
	# shot me" starts a fight) gets the shooter too.
	if target.has_method("apply_damage_from"):
		target.apply_damage_from(amount, shooter)
	elif target.has_method("apply_damage"):
		target.apply_damage(amount)
	elif target.get_parent() != null and target.get_parent().has_method("apply_damage"):
		target.get_parent().apply_damage(amount)
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
	if not matte:
		# The cockpit's glass catches it going by (CockpitView.gather_lights).
		add_to_group("glints")
		set_meta("glint_color", color)
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
	_streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if matte:
		m.albedo_color = color
		m.roughness = 1.0
		_streak.material_override = m
		add_child(_streak)
		_orient()
		return
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color.lerp(Color.WHITE, 0.45)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 5.0
	_streak.material_override = m
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
	_trail()


## Issue #229: the streak's head is the bolt; its tail trails only as far as the
## bolt has come (since it was fired or turned). Centred on the bolt, a fresh one
## reached half its length back past the muzzle: from the eye, a pale slab over
## the shooter's own hand.
func _trail() -> void:
	if _streak == null or direction.length() < 0.01:
		return
	var vis := clampf(_traveled + 0.08, 0.12, streak_length)
	var k := vis / streak_length
	var y := direction.normalized()
	_streak.basis = Basis(_streak.basis.x.normalized(), y * k, _streak.basis.z.normalized())
	_streak.position = -y * (vis * 0.5 - streak_radius)


## A seeker turns toward what it is after (not once that is gone or dead).
func _home(dt: float) -> void:
	if seek == null:
		return
	if not is_instance_valid(seek) or seek.get("dead") == true or not seek.is_inside_tree() or not is_inside_tree():
		seek = null
		return
	var want := (seek.global_position - global_position).normalized()
	var cur := direction.normalized()
	var ang := cur.angle_to(want)
	if ang < 0.0001 or want == Vector3.ZERO:
		return
	direction = cur.slerp(want, minf(1.0, turn_rate * dt / ang)).normalized()
	_orient()


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
	# who left town): a freed shooter is an error to even test with `is`. No
	# `!= null` first: Godot counts a freed object as equal to null.
	if not is_instance_valid(shooter):
		shooter = null
	_home(dt)
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
		# Issue #193: a body marked "bolts_pass" (the cruiser bay's shield) stops
		# people, not shots.
		while not hit.is_empty() and (hit.collider as Object).has_meta("bolts_pass"):
			skip.append(hit.rid)
			q.exclude = skip
			hit = space.intersect_ray(q)
		if not hit.is_empty():
			global_position = hit.position
			apply_to(hit.collider if hit_target == null else hit_target)
			return
	global_position += step
	if _alive and _in_ground():
		apply_to(null)


## Whether the ground has stopped the bolt; if so it is moved to the surface it hit.
func _in_ground() -> bool:
	if over_ground.is_valid():
		var h := float(over_ground.call(global_position))
		if h > 0.0:
			return false
		var up: Vector3 = ground_up.call(global_position) if ground_up.is_valid() else Vector3.UP
		global_position -= up * h
		return true
	if ground_at.is_valid():
		var gy := float(ground_at.call(global_position.x, global_position.z))
		if global_position.y <= gy:
			global_position.y = gy
			return true
	return false


func _on_body_entered(body: Node3D) -> void:
	if not _alive:
		return
	if not is_instance_valid(shooter):
		shooter = null
	if shooter != null and body == shooter:
		return
	if friends.has(body) or body.has_meta("bolts_pass"):
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
