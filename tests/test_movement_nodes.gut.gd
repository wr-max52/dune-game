extends GutTest
## M1: node-level proof that the movement and camera math drives real transforms.
## These use the exact code paths a human and a bot share, run headless, and are
## reproducible in CI. (The human/GUI "recording" is produced with scripts/
## record.sh; headless has no rendered window, so frame captures are not possible
## here -- see KNOWN_ISSUES.md.)

var CC
var RIG
var CRIGNODE


func before_each() -> void:
	CC = load("res://src/systems/player/character_controller.gd")
	RIG = load("res://src/systems/camera/camera_rig.gd")
	CRIGNODE = load("res://src/systems/camera/camera_rig_node.gd")


func test_walk_displaces_forward() -> void:
	var body = CC.new()
	body.set_command(Vector2(0.0, 1.0), false, false, false)
	var start: Vector3 = body.body_pos
	for i in range(60):
		body.step(1.0 / 60.0, 0.0, 0.0)
	var moved: float = (body.body_pos - start).length()
	assert_gt(moved, 0.5, "driving forward should displace the player")
	assert_gt(body.body_pos.z, 0.0, "forward should add +Z at yaw 0")


func test_sustained_walk_covers_ground() -> void:
	var body = CC.new()
	body.set_command(Vector2(0.0, 1.0), true, false, false)
	for i in range(1200):
		body.step(1.0 / 60.0, 0.0, 0.0)
	assert_gt(body.body_pos.z, 5.0, "20s of forward walk should cover several metres")


func test_camera_rig_toggle_moves_camera() -> void:
	var rig = RIG.new()
	rig.yaw = 0.5
	rig.pitch = 0.2
	var before: Vector3 = rig.camera_transform(Vector3(10, 0, 0)).origin
	rig.toggle_mode()
	var after: Vector3 = rig.camera_transform(Vector3(10, 0, 0)).origin
	assert_ne(before, after, "toggling FPV<->TPV moves the camera position")


func test_camera_rig_toggle_preserves_aim() -> void:
	var rig = RIG.new()
	rig.yaw = 0.5
	rig.pitch = 0.2
	var aim_before: Vector3 = rig.look_direction()
	rig.toggle_mode()
	rig.toggle_mode()
	var aim_after: Vector3 = rig.look_direction()
	assert_eq(aim_before, aim_after, "look direction unchanged across the toggle")


func test_rig_node_builds_and_toggles() -> void:
	var node = CRIGNODE.new()
	var t0: Vector3 = node.rig.camera_transform(Vector3(5, 0, 0)).origin
	node.rig.toggle_mode()
	var t1: Vector3 = node.rig.camera_transform(Vector3(5, 0, 0)).origin
	assert_ne(t0, t1, "rig node toggle moves the camera")
	node.queue_free()
