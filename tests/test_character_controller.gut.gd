extends GutTest
## M1: character controller math. Proves walk/sprint/crouch/jump produce the
## expected horizontal speed and vertical arcs. The bot in M5 drives this same
## math, so these tests are also the proof that "movement works" without a human.

var cc


func before_each() -> void:
	cc = load("res://src/systems/player/character_controller.gd").new()


func _hvel() -> float:
	return Vector2(cc.velocity.x, cc.velocity.z).length()


func _walk(frames: int, sprint: bool, crouch: bool, dir: Vector2 = Vector2(1.0, 0.0)) -> void:
	cc.set_command(dir, sprint, crouch, false)
	for i in range(frames):
		cc.step(1.0 / 60.0, 0.0, 0.0)


func test_idle_does_not_move() -> void:
	cc.set_command(Vector2.ZERO, false, false, false)
	cc.step(0.016, 0.0, 0.0)
	var x: float = cc.body_pos.x
	var z: float = cc.body_pos.z
	assert_almost_eq(x, 0.0, 0.001, "no input => no x drift")
	assert_almost_eq(z, 0.0, 0.001, "no input => no z drift")


func test_forward_moves_along_z() -> void:
	# With yaw 0, forward (dir.y = +1) maps to +world Z.
	cc.set_command(Vector2(0.0, 1.0), false, false, false)
	cc.step(0.1, 0.0, 0.0)
	var z: float = cc.body_pos.z
	assert_gt(z, 0.0, "forward should advance +Z at yaw 0")


func test_walk_speed_reaches_walk() -> void:
	_walk(300, false, false)
	var speed: float = _hvel()
	assert_almost_eq(speed, cc.walk_speed, 0.25, "approaches terminal walk speed")


func test_sprint_is_faster_than_walk() -> void:
	_walk(300, true, false)
	var speed: float = _hvel()
	assert_gt(speed, cc.walk_speed, "sprint exceeds walk speed")


func test_crouch_is_slowest() -> void:
	_walk(120, false, true)
	var speed: float = _hvel()
	assert_lt(speed, cc.walk_speed, "crouch is slower than walk")
	assert_eq(cc.pose, 1, "pose registers as crouch")


func test_jump_goes_up_then_returns_to_ground() -> void:
	cc.set_command(Vector2.ZERO, false, false, false)
	cc.command.jump = true
	cc.step(1.0 / 60.0, 0.0, 0.0)
	var vy: float = cc.velocity.y
	assert_true(vy > 0.0, "velocity up right after jump")
	var peak: float = -100.0
	for i in range(300):
		cc.command.jump = false
		cc.step(1.0 / 60.0, 0.0, 0.0)
		peak = maxf(peak, cc.body_pos.y)
	assert_gt(peak, 0.1, "player rises above the ground during the hop")
	var land: float = cc.body_pos.y
	assert_almost_eq(land, 0.0, 0.02, "lands back on the ground")


func test_body_height_differs_by_pose() -> void:
	cc.pose = 0  # STAND
	var h_stand: float = cc.body_height()
	cc.pose = 1  # CROUCH
	var h_crouch: float = cc.body_height()
	assert_lt(h_crouch, h_stand, "crouch is shorter than stand")


# ---- issue #133: the Shift sprint

func _dash(frames: int) -> void:
	cc.set_command(Vector2(0.0, 1.0), true, false, false, false, true)
	for i in range(frames):
		cc.step(1.0 / 60.0, 0.0, 0.0)


func test_shift_sprint_is_faster_than_the_run() -> void:
	_dash(120)
	assert_almost_eq(_hvel(), cc.dash_speed, 0.2, "sprint reaches 10 m/s")
	assert_gt(cc.dash_speed, cc.sprint_speed)
	assert_true(cc.is_dashing())


func test_out_of_stamina_drops_to_the_run() -> void:
	cc.dash_allowed = false
	_dash(120)
	assert_almost_eq(_hvel(), cc.sprint_speed, 0.2, "winded: back to the 7 m/s run")
	assert_false(cc.is_dashing())


func test_standing_still_with_shift_is_not_sprinting() -> void:
	cc.set_command(Vector2.ZERO, false, false, false, false, true)
	cc.step(1.0 / 60.0, 0.0, 0.0)
	assert_false(cc.is_dashing())
