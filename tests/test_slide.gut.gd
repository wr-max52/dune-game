extends GutTest
## Issue #65: the sprint slide. Pure controller tests first (no nodes), then one
## real CharacterBody3D on a floor.

const CC := preload("res://src/systems/player/character_controller.gd")
const PlayerBody := preload("res://src/systems/player/character_body.gd")
const DT := 1.0 / 60.0

var cc


func before_each() -> void:
	cc = CC.new()
	cc.can_slide = true


func _hspeed() -> float:
	return Vector2(cc.velocity.x, cc.velocity.z).length()


func _run(frames: int, sprint: bool, crouch: bool, dir := Vector2(0, 1), jump := false) -> void:
	cc.set_command(dir, sprint, crouch, jump)
	for i in frames:
		cc.step(DT, 0.0, 0.0)
		cc.command.jump = false


func _sprinting() -> void:
	_run(90, true, false)


func test_starts_from_sprint_plus_crouch_press() -> void:
	_sprinting()
	_run(1, true, true)
	assert_true(cc.is_sliding(), "crouch press while sprinting slides")
	assert_eq(cc.pose, CC.Pose.CROUCH, "short pose while sliding")


func test_not_from_held_crouch() -> void:
	_run(90, true, true)  # crouch down from the start, then sprint on
	assert_false(cc.is_sliding(), "crouch held before sprinting is not a press while moving")
	# Held through a sprint: still no slide.
	_run(60, true, true)
	assert_false(cc.is_sliding(), "held crouch never slides")


func test_not_while_walking_or_standing() -> void:
	_run(90, false, false)
	_run(1, false, true)
	assert_false(cc.is_sliding(), "walking + crouch is a plain crouch")
	cc = CC.new()
	cc.can_slide = true
	_run(1, true, true)
	assert_false(cc.is_sliding(), "no speed yet, no slide")


func test_not_in_the_air() -> void:
	_sprinting()
	_run(1, true, false, Vector2(0, 1), true)
	assert_false(cc.on_ground)
	_run(1, true, true)
	assert_false(cc.is_sliding(), "airborne crouch does not slide")


func test_speed_boosts_then_decays() -> void:
	_sprinting()
	_run(1, true, true)
	var start := _hspeed()
	assert_gt(start, cc.sprint_speed * 1.2, "boosted past sprint speed")
	_run(20, true, true)
	var mid := _hspeed()
	assert_lt(mid, start, "friction slows the slide")
	assert_gt(mid, cc.crouch_speed, "still moving")


func test_ends_within_duration_and_stands_with_crouch_held() -> void:
	_sprinting()
	_run(1, true, true)
	_run(int(cc.slide_duration * 60.0) + 3, true, true)
	assert_false(cc.is_sliding(), "slide ran out")
	assert_eq(cc.pose, CC.Pose.STAND, "stands even though crouch is still held")
	assert_false(cc.crouching(), "crouch must be released and pressed again")


func test_sprint_resumes_right_after() -> void:
	_sprinting()
	_run(1, true, true)
	_run(int(cc.slide_duration * 60.0) + 3, true, true)
	assert_gt(_hspeed(), cc.walk_speed + 0.5, "no dip to crouch speed on exit")
	_run(40, true, true)
	assert_almost_eq(_hspeed(), cc.sprint_speed, 0.1, "back to sprint speed with crouch still held")


func test_crouch_again_after_release() -> void:
	_sprinting()
	_run(1, true, true)
	_run(60, true, true)
	_run(2, false, false)
	_run(1, false, true)
	assert_eq(cc.pose, CC.Pose.CROUCH, "press again to crouch")
	assert_false(cc.is_sliding())


func test_jump_cancels_and_keeps_momentum() -> void:
	_sprinting()
	_run(1, true, true)
	_run(10, true, true)
	var before := _hspeed()
	_run(1, true, true, Vector2(0, 1), true)
	assert_false(cc.is_sliding(), "jump ends the slide")
	assert_false(cc.on_ground)
	assert_gt(_hspeed(), before * 0.9, "keeps its speed on the jump frame")


func test_progress_runs_zero_to_one() -> void:
	assert_eq(cc.slide_progress(), 0.0)
	_sprinting()
	_run(1, true, true)
	_run(20, true, true)
	var p: float = cc.slide_progress()
	assert_between(p, 0.1, 0.9)


func test_steering_is_slight() -> void:
	_sprinting()
	_run(1, true, true)
	_run(30, true, true, Vector2(1, 0))  # input hard sideways
	var v := Vector3(cc.velocity.x, 0, cc.velocity.z)
	assert_gt(v.z, 0.0, "still mostly forward after 0.5 s")
	assert_gt(absf(v.x), 0.0, "turned a little")
	assert_gt(v.angle_to(Vector3(0, 0, 1)), 0.1)
	assert_lt(v.angle_to(Vector3(0, 0, 1)), 1.0)


func test_guards_never_slide_by_default() -> void:
	var guard := CC.new()  # can_slide defaults to false
	guard.set_command(Vector2(0, 1), true, false, false)
	for i in 90:
		guard.step(DT, 0.0, 0.0)
	guard.set_command(Vector2(0, 1), true, true, false)
	for i in 30:
		guard.step(DT, 0.0, 0.0)
	assert_false(guard.is_sliding())
	assert_lt(Vector2(guard.velocity.x, guard.velocity.z).length(), guard.sprint_speed + 0.01)
	assert_eq(guard.pose, CC.Pose.CROUCH, "guard crouch is the old crouch")


func test_player_kit_gate_default_off_on_body() -> void:
	var b := PlayerBody.new()
	add_child_autofree(b)
	assert_false(b.controller.can_slide, "bodies do not slide until a player kit turns it on")


func test_real_body_slides_farther_and_capsule_restores() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var floor_body := StaticBody3D.new()
	var fs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	fs.shape = box
	floor_body.add_child(fs)
	floor_body.position = Vector3(0, -0.5, 0)
	root.add_child(floor_body)

	var sprinter := PlayerBody.new()
	sprinter.position = Vector3(-50, 0.1, 0)
	sprinter.can_slide = true
	root.add_child(sprinter)
	var slider := PlayerBody.new()
	slider.position = Vector3(50, 0.1, 0)
	slider.can_slide = true
	root.add_child(slider)
	await wait_physics_frames(3)
	# Yaw 0 maps forward to +Z. Get both up to sprint speed.
	for i in 90:
		sprinter.set_command(Vector2(0, 1), true, false, false)
		slider.set_command(Vector2(0, 1), true, false, false)
		await wait_physics_frames(1)
	var s0 := sprinter.global_position
	var l0 := slider.global_position
	var h_stand: float = slider.current_height()
	var short_seen := false
	for i in 45:  # 0.75 s
		sprinter.set_command(Vector2(0, 1), true, false, false)
		slider.set_command(Vector2(0, 1), true, i < 2 or i >= 0, false)  # press, then held
		if i == 20:
			short_seen = slider.current_height() < h_stand - 0.5 and slider.sliding
		await wait_physics_frames(1)
	var d_sprint := sprinter.global_position.distance_to(s0)
	var d_slide := slider.global_position.distance_to(l0)
	assert_gt(d_slide, d_sprint, "a slide covers more ground than the same time sprinting")
	assert_true(short_seen, "capsule is short mid slide")
	for i in 20:
		slider.set_command(Vector2(0, 1), true, true, false)
		await wait_physics_frames(1)
	assert_false(slider.sliding)
	assert_almost_eq(slider.current_height(), h_stand, 0.01, "capsule restored to full height")
