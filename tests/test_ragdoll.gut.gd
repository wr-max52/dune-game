extends GutTest
## Issue #25: bodies fall as ragdolls. A trooper dropped on a floor lands lying down,
## away from the shot, with every bone its own length, then sleeps; stop() stands it
## back up exactly as it was.

var kit: CharacterKit
var world: Node3D
var body: Node3D


func before_each() -> void:
	kit = CharacterKit.new(LookMaterials.new())
	world = Node3D.new()
	add_child_autofree(world)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	floor_body.add_child(shape)
	world.add_child(floor_body)
	body = kit.build("trooper")
	world.add_child(body)
	await wait_physics_frames(2)


func _drop(kick: Vector3, seconds := 4.0) -> Ragdoll:
	var r := Ragdoll.new(body.get_meta("joints"))
	r.start(Vector3.ZERO, kick, world.get_world_3d().direct_space_state)
	var dt := 1.0 / 60.0
	for i in int(seconds * 60.0):
		r.step(dt)
	return r


func test_falls_flat_and_rests_on_the_floor() -> void:
	var r := _drop(Vector3(0, 0, 3))
	var head := r.point("head")
	var pelvis := r.point("pelvis")
	assert_lt(head.y, 0.45, "the head ends near the ground (%s)" % head)
	assert_lt(pelvis.y, 0.4, "the pelvis ends near the ground (%s)" % pelvis)
	for p in ["head", "pelvis", "l_toe", "r_hand"]:
		assert_gt(r.point(p).y, -0.05, p + " stays above the floor")
	assert_true(r.asleep, "it goes to sleep once it stops")


func test_falls_away_from_the_shot() -> void:
	var start := (body.get_meta("joints").head as Node3D).global_position
	var r := _drop(Vector3(3, 0, 0))
	assert_gt(r.point("head").x - start.x, 0.4, "pushed toward +X, the head lands on that side")


func test_bones_keep_their_length() -> void:
	var j: Dictionary = body.get_meta("joints")
	var thigh := (j.l_hip as Node3D).global_position.distance_to((j.l_knee as Node3D).global_position)
	var arm := (j.r_shoulder as Node3D).global_position.distance_to((j.r_elbow as Node3D).global_position)
	var r := _drop(Vector3(0, 0, -3))
	assert_almost_eq(r.point("l_hip").distance_to(r.point("l_knee")), thigh, 0.03)
	assert_almost_eq(r.point("r_shoulder").distance_to(r.point("r_elbow")), arm, 0.03)
	# The joints follow the particles: the knee joint sits on the knee particle.
	assert_almost_eq((j.l_knee as Node3D).global_position.distance_to(r.point("l_knee")), 0.0, 0.08)


func test_stop_puts_the_pose_back() -> void:
	var j: Dictionary = body.get_meta("joints")
	var before := {}
	for jn in j:
		before[jn] = (j[jn] as Node3D).transform
	var r := _drop(Vector3(2, 0, 0), 1.0)
	assert_ne((j.pelvis as Node3D).transform, before.pelvis, "the body moved")
	r.stop()
	for jn in j:
		assert_eq((j[jn] as Node3D).transform, before[jn], jn + " is back")


func test_kick_points_away_from_the_shooter() -> void:
	var cfg := Ragdoll.load_config()
	var k := Ragdoll.kick_for(Vector3(5, 0, 0), Vector3.ZERO, 20.0, cfg)
	assert_gt(k.x, 0.0)
	assert_gt(k.y, 0.0, "a little lift")
	assert_between(k.length(), float(cfg.kick_min), float(cfg.kick_max) + 0.001)
	assert_eq(Ragdoll.kick_for(Vector3.ZERO, Vector3.INF, 20.0, cfg), Vector3.ZERO, "no shooter, no push")
