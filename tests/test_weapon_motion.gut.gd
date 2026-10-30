extends GutTest
## Issue #229: first person weapon motion (sway, bob, landing, breathing, walls).

const WeaponMotion := preload("res://src/systems/look/weapon_motion.gd")


func _run(m, frames: int, look := Vector2.ZERO, speed := 0.0, grounded := true, vy := 0.0, wall := INF) -> void:
	for i in frames:
		m.step(1.0 / 60.0, look, speed, grounded, vy, wall)


func test_turning_drags_the_gun_behind_then_it_settles() -> void:
	var m := WeaponMotion.new()
	_run(m, 20, Vector2(3.0, 0.0))
	assert_lt(m.sway.x, -0.02, "turning right (+yaw) lags the gun the other way")
	assert_gt(m.sway.x, -WeaponMotion.SWAY_MAX - 0.001, "capped")
	_run(m, 90)
	assert_almost_eq(m.sway.x, 0.0, 0.002, "springs back once the view stops")


func test_walking_bobs_and_standing_does_not() -> void:
	var m := WeaponMotion.new()
	_run(m, 120)
	var still := m.offset().origin
	assert_lt(Vector2(still.x, still.y).length(), 0.004, "only breathing when still")
	_run(m, 47, Vector2.ZERO, 5.5)
	assert_gt(m.bob_amount, 0.5)
	assert_gt(absf(m.offset().origin.x), 0.001, "a step moves the gun sideways")


func test_landing_dips_harder_from_higher() -> void:
	var low := WeaponMotion.new()
	var high := WeaponMotion.new()
	for m in [low, high]:
		_run(m, 10, Vector2.ZERO, 0.0, false, -1.0)
	_run(low, 1, Vector2.ZERO, 0.0, true, -3.0)
	_run(high, 1, Vector2.ZERO, 0.0, true, -9.0)
	_run(low, 6)
	_run(high, 6)
	assert_gt(low.land, 0.0, "a landing dips the gun")
	assert_gt(high.land, low.land, "harder from higher")
	_run(high, 120)
	assert_almost_eq(high.land, 0.0, 0.002, "and it settles")


func test_a_wall_pulls_the_gun_back_and_blocks_the_shot() -> void:
	var m := WeaponMotion.new()
	_run(m, 30, Vector2.ZERO, 0.0, true, 0.0, 0.3)
	assert_true(m.blocked(), "too close to shoot straight")
	assert_lt(m.offset().origin.z, -0.1, "pulled back toward the body")
	var tip := m.wall_local(Vector3(0, -0.05, -0.08)) * Vector3(0, 0, 0.5)
	assert_gt(tip.y, 0.2, "muzzle tipped up")
	assert_almost_eq((m.wall_local(Vector3(0, -0.05, -0.08)) * Vector3(0, -0.05, -0.08)).distance_to(Vector3(0, -0.05, -0.08)), 0.0, 0.0001, "about the grip")
	_run(m, 60)
	assert_false(m.blocked(), "clear again away from the wall")


func test_aiming_all_but_removes_it() -> void:
	var m := WeaponMotion.new()
	_run(m, 47, Vector2(4.0, 1.0), 5.5)
	var hip := m.offset(0.0)
	var aimed := m.offset(1.0)
	assert_lt(aimed.origin.length(), hip.origin.length() * 0.2 + 0.0001)
	assert_lt(aimed.basis.get_euler().length(), hip.basis.get_euler().length() * 0.2 + 0.0001)
