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


# ---- issue #87

func test_crouch_still_kneels_and_moving_duck_walks() -> void:
	var a := BodyAnimator.new()
	var kneel := _step(a, 60, { "crouch": true, "speed": 0.0 })
	assert_lt(kneel.joints.l_hip.x, -70.0, "front thigh forward")
	assert_lt(absf(kneel.joints.r_hip.x), 15.0, "back thigh straight down to the knee")
	assert_gt(kneel.joints.r_knee.x, 80.0, "shin flat behind")
	var b := BodyAnimator.new()
	var duck := _step(b, 60, { "crouch": true, "speed": 1.8 })
	assert_gt(duck.pelvis_y, kneel.pelvis_y, "the duck walk rides higher than the kneel")
	assert_lt(duck.pelvis_y, 0.75)
	assert_gt(duck.joints.l_knee.x, 85.0, "both knees deep")
	assert_gt(duck.joints.r_knee.x, 85.0)


func test_sprint_leans_into_a_longer_stride() -> void:
	var w := BodyAnimator.new()
	var walk := _step(w, 60, { "speed": 3.5 })
	var s := BodyAnimator.new()
	var sprint := _step(s, 60, { "speed": 7.0, "sprint": true })
	assert_gt(sprint.joints.spine.x + sprint.joints.chest.x, walk.joints.spine.x + walk.joints.chest.x + 10.0, "leans forward")
	# Cadence: one second of each; the sprint covers twice the ground in well
	# under twice the strides.
	var w2 := BodyAnimator.new()
	var s2 := BodyAnimator.new()
	var cyc_w := 0.0
	var cyc_s := 0.0
	for i in 60:
		var pw := w2.phase
		var ps := s2.phase
		w2.step(1.0 / 60.0, { "speed": 3.5 })
		s2.step(1.0 / 60.0, { "speed": 7.0 })
		cyc_w += wrapf(w2.phase - pw, 0.0, TAU)
		cyc_s += wrapf(s2.phase - ps, 0.0, TAU)
	assert_lt(cyc_s, cyc_w * 1.5, "longer, slower strides")


func test_walk_shifts_the_hips_side_to_side() -> void:
	var a := BodyAnimator.new()
	var seen_l := false
	var seen_r := false
	for i in 90:
		var o := a.step(1.0 / 60.0, { "speed": 3.0 })
		seen_l = seen_l or o.pelvis_x > 0.01
		seen_r = seen_r or o.pelvis_x < -0.01
	assert_true(seen_l and seen_r, "the weight moves over each foot")


func test_gun_at_rest_keeps_the_swagger_aimed_squares_up() -> void:
	var r := BodyAnimator.new()
	var rest := _step(r, 37, { "speed": 3.5, "upper": BodyAnimator.UPPER_RIFLE, "ready": 0.0 })
	var a := BodyAnimator.new()
	var aim := _step(a, 37, { "speed": 3.5, "upper": BodyAnimator.UPPER_RIFLE, "ready": 1.0 })
	assert_eq(aim.joints.chest.y, 0.0, "aimed: no shoulder twist")
	assert_gt(absf(rest.joints.chest.y), 0.5, "at rest the shoulders still swing a little")
	assert_almost_eq(aim.joints.spine.y, -14.0, 0.5, "rifle stance turns the torso")
	assert_almost_eq(rest.joints.spine.y, 0.0, 0.5)


func test_airborne_tucks_rising_and_reaches_falling() -> void:
	var a := BodyAnimator.new()
	_step(a, 2, { "grounded": true })
	var up := _step(a, 20, { "grounded": false, "vy": 5.0 })
	var down := _step(a, 20, { "grounded": false, "vy": -7.0 })
	assert_gt(up.joints.l_knee.x, down.joints.l_knee.x, "knees tucked on the way up")
	assert_gt(absf(down.joints.l_shoulder.z), absf(up.joints.l_shoulder.z), "arms out for the landing")


func test_cantina_dance_is_a_ten_second_loop_with_a_wall_turn_and_bend() -> void:
	var start := BodyAnimator.dance_pose(0.0)
	var end := BodyAnimator.dance_pose(BodyAnimator.DANCE_LOOP_S)
	assert_almost_eq(start.yaw, end.yaw, 0.001, "the loop closes facing the audience")
	assert_almost_eq(start.pelvis_x, end.pelvis_x, 0.001)
	for joint in start.joints:
		assert_almost_eq(start.joints[joint].x, end.joints[joint].x, 0.001, str(joint) + " loops cleanly")
	var facing_wall := BodyAnimator.dance_pose(4.5)
	assert_gt(facing_wall.yaw, 2.9, "the dancer turns to face the wall")
	var bent := BodyAnimator.dance_pose(5.55)
	assert_gt(bent.joints.chest.x, 20.0, "the bend reaches the waist")
	assert_lt(bent.pelvis_y, start.pelvis_y, "the bend lowers the hips")


func test_cantina_dance_state_advances_without_walking() -> void:
	var a := BodyAnimator.new()
	var out := _step(a, 600, { "dance": true, "speed": 0.0, "grounded": true })
	assert_eq(out.state, "DANCE")
	assert_almost_eq(a.dance_time, 0.0, 0.001, "600 frames at 60 Hz complete one loop")
	assert_eq(a.phase, 0.0, "dancing never advances the walk cycle")
