extends GutTest
## Regression tests for the bugs found in the senior dev review
## (docs/review/REVIEW.html). Each test failed on the pre-review code.

const CameraRig := preload("res://src/systems/camera/camera_rig.gd")
const CameraRigNode := preload("res://src/systems/camera/camera_rig_node.gd")
const PlayerBody := preload("res://src/systems/player/character_body.gd")
const WeaponActor := preload("res://src/systems/combat/weapon_actor.gd")


class DamageBox extends StaticBody3D:
	var hits := 0
	func apply_damage(_amount) -> void:
		hits += 1


func test_camera_basis_is_a_rotation_not_a_mirror() -> void:
	var rig = CameraRig.new()
	for yaw in [0.0, 0.7, -2.1]:
		for pitch in [0.0, 0.4, -0.6]:
			rig.yaw = yaw
			rig.pitch = pitch
			var b: Basis = rig.camera_transform(Vector3.ZERO).basis
			assert_almost_eq(b.determinant(), 1.0, 0.0001, "basis must be right-handed")
			assert_true((-b.z).is_equal_approx(rig.look_direction()), "camera -Z looks along look_direction")


func test_bolt_scene_loads_with_a_hitbox() -> void:
	var scene: PackedScene = load("res://scenes/entities/bolt.tscn")
	assert_not_null(scene, "bolt.tscn must parse")
	var bolt = scene.instantiate()
	var shapes := 0
	for c in bolt.get_children():
		if c is CollisionShape3D and c.shape != null:
			shapes += 1
	assert_eq(shapes, 1, "the bolt needs a collision shape to detect hits")
	bolt.free()


func test_every_key_binding_actually_has_a_key() -> void:
	# project.godot used "key_code" (not Godot's "keycode"), so every key event
	# loaded as keycode 0: no keyboard binding in the game worked at all.
	for action in ["move_forward", "move_back", "move_left", "move_right", "jump", "toggle_view", "sprint_mod", "crouch_act"]:
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				assert_ne(ev.keycode, KEY_NONE, "%s has a key event with no key" % action)


func test_s_key_is_not_bound_to_forward() -> void:
	var s_key := false
	for ev in InputMap.action_get_events("move_forward"):
		if ev is InputEventKey and ev.keycode == KEY_S:
			s_key = true
	assert_false(s_key, "S must only be bound to move_back")


func test_toggle_view_uses_a_real_mouse_button() -> void:
	var ok := false
	for ev in InputMap.action_get_events("toggle_view"):
		if ev is InputEventMouseButton:
			ok = ev.button_index == MOUSE_BUTTON_MIDDLE
	assert_true(ok, "toggle_view should bind the middle mouse button (3)")


func test_player_rotation_does_not_accumulate() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var player = PlayerBody.new()
	root.add_child(player)
	var rig_node = CameraRigNode.new()
	root.add_child(rig_node)
	rig_node.set_player(player)
	rig_node.rig.yaw = 0.05
	for i in 30:
		rig_node._process(1.0 / 60.0)
	assert_almost_eq(player.rotation.y, 0.05, 0.0001, "rotation follows yaw, it must not keep adding it")


func test_player_has_collision_and_stops_at_walls() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(40, 1, 40)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(0, -0.5, 0)
	root.add_child(floor_body)
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(10, 4, 0.5)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	wall.position = Vector3(0, 2, 3)
	root.add_child(wall)

	var player = PlayerBody.new()
	player.position = Vector3(0, 0.5, 0)
	root.add_child(player)
	assert_almost_eq(player.controller.body_pos.y, 0.5, 0.001, "no teleport to the origin on spawn")
	await wait_physics_frames(2)
	for i in 120:
		player.set_command(Vector2(0, 1), false, false, false)
		await wait_physics_frames(1)
	# Wall front face is at z = 2.75; the capsule radius is 0.4.
	assert_lt(player.global_position.z, 2.75, "the wall must stop the player")
	assert_gt(player.global_position.z, 1.5, "the player should still have walked up to it")
	assert_gt(player.global_position.y, -0.1, "the floor must hold the player up")


func test_weapon_actor_spawns_bolts_that_hit() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var target := DamageBox.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 2, 2)
	shape.shape = box
	target.add_child(shape)
	target.position = Vector3(0, 0, -6)
	root.add_child(target)

	var actor = WeaponActor.new()
	actor.set_weapon({ "mag": 10, "rate": 0.1, "damage": 10, "bolt_speed": 30.0, "range": 60.0 })
	actor.bolt_parent = root
	actor.fire_at(target.position, Vector3.ZERO, 1.0 / 60.0, true)
	assert_eq(actor.shots_fired, 1)
	await wait_physics_frames(30)
	assert_eq(target.hits, 1, "the bolt should travel and hit the target once")
