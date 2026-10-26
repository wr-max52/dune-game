extends GutTest
## M11: the procedural body animator (pure).

func _step(a: BodyAnimator, n: int, inp: Dictionary) -> Dictionary:
	var out := {}
	for i in n:
		out = a.step(1.0 / 60.0, inp)
	return out


func test_idle_stays_in_locomotion_and_breathes() -> void:
	var a := BodyAnimator.new()
	var o := _step(a, 60, { "speed": 0.0 })
	assert_eq(o.state, "LOCOMOTION")
	assert_eq(a.phase, 0.0, "no gait when standing")


func test_walking_swings_legs_in_opposition() -> void:
	var a := BodyAnimator.new()
	var o := _step(a, 37, { "speed": 4.0, "move_local": Vector2(0, 1) })
	assert_gt(a.phase, 0.0)
	var l: Vector3 = o.joints.l_hip
	var r: Vector3 = o.joints.r_hip
	assert_lt(l.x * r.x, 0.0, "one leg forward, one back")


func test_arms_counter_swing_the_legs() -> void:
	var a := BodyAnimator.new()
	var o := _step(a, 37, { "speed": 4.0 })
	assert_lt(o.joints.l_hip.x * o.joints.l_shoulder.x, 0.0)


func test_jump_land_sequence() -> void:
	var a := BodyAnimator.new()
	_step(a, 5, { "grounded": true })
	_step(a, 5, { "grounded": false, "vy": 4.0 })
	assert_eq(a.state_name(), "AIRBORNE")
	_step(a, 5, { "grounded": false, "vy": -4.0 })
	_step(a, 2, { "grounded": true })
	assert_eq(a.state_name(), "LAND")
	_step(a, 30, { "grounded": true })
	assert_eq(a.state_name(), "LOCOMOTION")
	for s in ["JUMP", "FALL", "LAND", "AIRBORNE", "LOCOMOTION"]:
		assert_true(a.states_seen.has(s), s)


func test_crouch_lowers_pelvis() -> void:
	var a := BodyAnimator.new()
	var o := _step(a, 60, { "crouch": true })
	assert_lt(o.pelvis_y, 0.75)


func test_aim_follows_pitch_and_holds_the_torso() -> void:
	var a := BodyAnimator.new()
	var up := _step(a, 60, { "upper": BodyAnimator.UPPER_AIM, "aim_pitch": 0.6 })
	var b := BodyAnimator.new()
	var down := _step(b, 60, { "upper": BodyAnimator.UPPER_AIM, "aim_pitch": -0.6 })
	assert_lt(up.joints.chest.x, down.joints.chest.x, "looking up leans the chest back")


func test_backwards_walk_reverses_the_stride() -> void:
	var a := BodyAnimator.new()
	var f := _step(a, 20, { "speed": 3.0, "move_local": Vector2(0, 1) })
	var b := BodyAnimator.new()
	var back := _step(b, 20, { "speed": 3.0, "move_local": Vector2(0, -1) })
	assert_almost_eq(f.joints.l_hip.x, -back.joints.l_hip.x, 0.5)
