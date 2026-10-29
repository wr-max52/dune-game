extends GutTest
## Issue #87: raising a gun to aim, holding it up, lowering it to rest.


func _run(c: WeaponCarry, seconds: float, want: bool) -> void:
	for i in int(seconds * 60.0):
		c.step(1.0 / 60.0, want)


func test_comes_up_fast_before_a_shot() -> void:
	var c := WeaponCarry.new()
	assert_false(c.on_target(), "starts at rest")
	_run(c, 0.25, true)
	assert_true(c.on_target(), "up inside a quarter second")
	assert_almost_eq(c.eased(), 1.0, 0.001)


func test_stays_up_for_a_moment_then_rests() -> void:
	var c := WeaponCarry.new()
	_run(c, 0.5, true)
	_run(c, WeaponCarry.HOLD_S - 0.2, false)
	assert_true(c.on_target(), "held up after the last shot")
	_run(c, 0.2 + WeaponCarry.LOWER_S + 0.1, false)
	assert_almost_eq(c.ready, 0.0, 0.001, "back at rest")


func test_rest_puts_the_grip_in_the_hand() -> void:
	var grip := Vector3(0.0, -0.06, 0.1)
	for kind in ["rifle", "pistol"]:
		var xf := WeaponCarry.rest_xf(kind, grip)
		assert_almost_eq((xf * grip - WeaponCarry.REST[kind][0]).length(), 0.0, 0.0001, kind)


func test_rest_points_the_muzzle_down() -> void:
	for kind in ["rifle", "pistol"]:
		var fwd := WeaponCarry.rest_xf(kind, Vector3.ZERO).basis * Vector3(0, 0, 1)
		assert_lt(fwd.y, -0.3, kind + " muzzle low")
	var rifle := WeaponCarry.rest_xf("rifle", Vector3.ZERO).basis * Vector3(0, 0, 1)
	assert_gt(rifle.x, 0.3, "the rifle lies across the body, muzzle to the left")
	var pistol := WeaponCarry.rest_xf("pistol", Vector3.ZERO).origin
	assert_lt(pistol.x, -0.2, "the pistol hangs by the right side")


func test_blend_ends_at_each_pose() -> void:
	var rest := WeaponCarry.rest_xf("rifle", Vector3.ZERO)
	var aim := Transform3D(Basis(), Vector3(0, 0, 0.4))
	assert_true(WeaponCarry.blend(rest, aim, 0.0).is_equal_approx(rest))
	assert_almost_eq((WeaponCarry.blend(rest, aim, 1.0).origin - aim.origin).length(), 0.0, 0.0001)


func test_sprinting_drops_the_gun_at_once() -> void:
	# Issue #133: no hold-up time while sprinting, even with the trigger down.
	var c := WeaponCarry.new()
	_run(c, 0.5, true)
	for i in int((WeaponCarry.LOWER_S + 0.05) * 60.0):
		c.step(1.0 / 60.0, true, true)
	assert_almost_eq(c.ready, 0.0, 0.001, "down within the lower time")
	assert_false(c.on_target())
