extends GutTest
## M1: camera rig math. The key requirement is "toggle FPV<->TPV without breaking
## aim." Aim = the look DIRECTION, which is independent of camera mode. These tests
## prove that: toggling changes position (view) but not the look direction (aim).

var rig


func before_each() -> void:
	rig = load("res://src/systems/camera/camera_rig.gd").new()
	rig.yaw = 0.7
	rig.pitch = 0.2


func test_default_mode_is_first_person() -> void:
	assert_true(rig.is_first_person())


func test_toggle_cycles_first_third_cinematic() -> void:
	assert_true(rig.toggle_mode())
	assert_eq(rig.mode, rig.Mode.TPV)
	assert_false(rig.is_first_person())
	assert_true(rig.toggle_mode())
	assert_true(rig.is_cinematic())
	assert_false(rig.is_first_person())
	assert_true(rig.toggle_mode())
	assert_true(rig.is_first_person())


func test_look_direction_is_normalized() -> void:
	var d: Vector3 = rig.look_direction()
	assert_almost_eq(d.length(), 1.0, 0.001, "look direction must be unit length")


func test_toggle_preserves_aim() -> void:
	## THE "don't break aim" test.
	var aim_before: Vector3 = rig.look_direction()
	rig.mode = 1  # TPV
	rig.toggle_mode()  # on to cinematic
	assert_eq(rig.look_direction(), aim_before, "cinematic keeps the aim too")
	rig.toggle_mode()  # back to FPV
	var aim_after: Vector3 = rig.look_direction()
	assert_eq(aim_before, aim_after, "look direction must be identical after toggle")


func test_toggle_changes_camera_position() -> void:
	## FPV and TPV must put the camera in different places (a real view change).
	## Aim (look direction) preserved is a separate test above; here we check the
	## position actually differs.
	var pos: Vector3 = Vector3(10.0, 0.0, 0.0)
	rig.mode = 0
	var tf_fpv: Transform3D = rig.camera_transform(pos)
	rig.mode = 1
	var tf_tpv: Transform3D = rig.camera_transform(pos)
	assert_ne(tf_fpv.origin, tf_tpv.origin, "FPV and TPV camera positions must differ")


func test_pitch_is_clamped() -> void:
	rig.add_pitch(100.0)
	assert_almost_eq(rig.pitch, rig.max_pitch, 0.001, "pitch clamps at max")
	rig.add_pitch(-1000.0)
	assert_almost_eq(rig.pitch, rig.min_pitch, 0.001, "pitch clamps at min")
