extends GutTest
## M11: the energy sword's chain, block and pose keys (pure).

const CFG := { "light_damage": 16, "heavy_damage": 30, "deflect_window": 0.18 }


func _run(c: SwordCombo, secs: float) -> Array:
	var ev: Array = []
	var t := 0.0
	while t < secs:
		ev.append_array(c.update(1.0 / 60.0))
		t += 1.0 / 60.0
	return ev


func test_single_swing_returns_to_guard() -> void:
	var c := SwordCombo.new(CFG)
	assert_true(c.attack())
	assert_eq(c.mode, SwordCombo.Mode.SWING)
	var ev := _run(c, 0.6)
	assert_true(ev.has("swing_end"))
	assert_eq(c.mode, SwordCombo.Mode.GUARD)


func test_chain_three_with_buffered_presses() -> void:
	var c := SwordCombo.new(CFG)
	c.attack()
	_run(c, 0.25)
	c.attack()        # buffered
	_run(c, 0.3)
	assert_eq(c.swing_index, 1)
	_run(c, 0.25)
	c.attack()
	_run(c, 0.3)
	assert_eq(c.swing_index, 2)
	assert_eq(c.damage(), 30, "the third hit is heavy")
	assert_eq(c.swings_started, 3)


func test_early_press_does_not_buffer() -> void:
	var c := SwordCombo.new(CFG)
	c.attack()
	_run(c, 0.05)
	c.attack()        # too early: ignored
	_run(c, 0.6)
	assert_eq(c.swings_started, 1)


func test_active_window_is_mid_swing() -> void:
	var c := SwordCombo.new(CFG)
	c.attack()
	assert_false(c.is_active())
	_run(c, 0.25)
	assert_true(c.is_active())
	_run(c, 0.2)
	assert_false(c.is_active())


func test_block_and_timed_deflect() -> void:
	var c := SwordCombo.new(CFG)
	c.set_block(true)
	assert_eq(c.mode, SwordCombo.Mode.BLOCK)
	_run(c, 0.05)
	assert_eq(c.blade.intercept_bolt(), c.blade.BoltResult.DEFLECTED)
	_run(c, 0.4)
	assert_eq(c.blade.intercept_bolt(), c.blade.BoltResult.BLOCKED, "late block only absorbs")
	c.set_block(false)
	assert_eq(c.mode, SwordCombo.Mode.GUARD)


func test_cannot_swing_while_blocking() -> void:
	var c := SwordCombo.new(CFG)
	c.set_block(true)
	assert_false(c.attack())


func test_pose_keys_are_continuous() -> void:
	for i in SwordCombo.SWINGS.size():
		var prev: Dictionary = SwordCombo.sample(i, 0.0)
		for k in range(1, 41):
			var p := SwordCombo.sample(i, k / 40.0)
			assert_lt((p.pos as Vector3).distance_to(prev.pos), 0.12, "swing %d step %d" % [i, k])
			prev = p
		assert_almost_eq((SwordCombo.sample(i, 1.0).pos as Vector3).distance_to(SwordCombo.GUARD.pos), 0.0, 0.001)


func test_pose_transform_points_blade_along_dir() -> void:
	var xf := SwordCombo.pose_transform({ "pos": Vector3(1, 2, 3), "dir": Vector3(0, 0, 1) })
	assert_almost_eq(xf.basis.y.dot(Vector3(0, 0, 1)), 1.0, 0.001)
	assert_almost_eq(xf.basis.determinant(), 1.0, 0.001)


func test_first_person_keys_are_continuous_and_in_view() -> void:
	# Issue #229: first person has its own keys, from and back to GUARD_FPV, with no
	# jump between samples, and the blade never points back past the camera.
	for i in SwordCombo.SWINGS.size():
		assert_true(SwordCombo.SWINGS[i].has("fpv_keys"), "swing %d has first person keys" % i)
		var prev: Dictionary = SwordCombo.sample(i, 0.0, true)
		assert_almost_eq((prev.pos as Vector3).distance_to(SwordCombo.GUARD_FPV.pos), 0.0, 0.001)
		for k in range(1, 41):
			var p := SwordCombo.sample(i, k / 40.0, true)
			assert_lt((p.pos as Vector3).distance_to(prev.pos), 0.12, "swing %d step %d" % [i, k])
			assert_gt((p.dir as Vector3).z, -0.55, "swing %d step %d: blade not behind the eye" % [i, k])
			prev = p
		assert_almost_eq((prev.pos as Vector3).distance_to(SwordCombo.GUARD_FPV.pos), 0.0, 0.001)


func test_first_person_pose_uses_its_own_guard_and_block() -> void:
	var c := SwordCombo.new(CFG)
	assert_eq(c.pose(true), SwordCombo.GUARD_FPV)
	assert_eq(c.pose(false), SwordCombo.GUARD)
	c.set_block(true)
	assert_eq(c.pose(true), SwordCombo.BLOCK_FPV)
	assert_eq(c.pose(false), SwordCombo.BLOCK)
