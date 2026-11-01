extends GutTest
## M10: the starfighter flight model. Pure math, so every claim is checked directly:
## throttle sets speed between the data limits, speed eases instead of snapping,
## each control axis turns the right way, boost is faster but turns slower and runs
## out, and the state survives a save round-trip.

const FlightModel := preload("res://src/systems/flight/flight_model.gd")
const CoreScript := preload("res://src/systems/dataload/core_content.gd")

var cfg: Dictionary


func before_each() -> void:
	var content = CoreScript.new()
	content.load_from()
	cfg = content.get_ship("interceptor").get("flight", {})


func _fly(f, seconds: float) -> void:
	for i in int(seconds * 60.0):
		f.step(1.0 / 60.0)


func test_tuning_comes_from_ship_data() -> void:
	var f = FlightModel.new(cfg)
	assert_eq(f.max_speed(), float(cfg.max_speed), "max speed is the ship's data value")
	assert_eq(f.boost_speed(), float(cfg.boost_speed), "boost speed is the ship's data value")
	assert_gt(f.boost_speed(), f.max_speed(), "boost is faster than full throttle")


func test_starts_facing_negative_z() -> void:
	var f = FlightModel.new(cfg)
	assert_almost_eq(f.forward().z, -1.0, 0.0001, "forward is -Z, Godot's convention")


func test_throttle_sets_speed_between_limits() -> void:
	var f = FlightModel.new(cfg)
	f.set_command(0, 0, 0, 1.0, false)
	_fly(f, 6.0)
	assert_almost_eq(f.speed, f.max_speed(), 0.01, "full throttle settles at max speed")
	f.set_command(0, 0, 0, 0.0, false)
	_fly(f, 6.0)
	assert_almost_eq(f.speed, f.min_speed(), 0.01, "zero throttle settles at min speed, never 0")


func test_speed_eases_instead_of_snapping() -> void:
	var f = FlightModel.new(cfg)
	f.set_command(0, 0, 0, 0.0, false)
	_fly(f, 6.0)
	var before: float = f.speed
	f.set_command(0, 0, 0, 1.0, false)
	f.step(1.0 / 60.0)
	assert_gt(f.speed, before, "speed rises after the throttle goes up")
	assert_lt(f.speed, f.max_speed(), "but not all the way in one frame")


func test_ship_moves_along_its_nose() -> void:
	var f = FlightModel.new(cfg)
	f.set_command(0, 0, 0, 0.5, false)
	_fly(f, 1.0)
	assert_lt(f.position.z, -5.0, "the ship travelled forward (-Z)")
	assert_almost_eq(f.position.x, 0.0, 0.001, "no sideways drift with no input")


func test_pitch_up_raises_the_nose() -> void:
	var f = FlightModel.new(cfg)
	f.set_command(1.0, 0, 0, 0.5, false)
	_fly(f, 0.3)
	assert_gt(f.forward().y, 0.2, "positive pitch points the nose up")


func test_yaw_right_turns_right() -> void:
	var f = FlightModel.new(cfg)
	f.set_command(0, 1.0, 0, 0.5, false)
	_fly(f, 0.3)
	assert_gt(f.forward().x, 0.2, "positive yaw turns the nose to +X (right)")


func test_roll_right_drops_the_right_wing() -> void:
	var f = FlightModel.new(cfg)
	f.set_command(0, 0, 1.0, 0.5, false)
	_fly(f, 0.2)
	assert_lt(f.right().y, -0.2, "positive roll lowers the right wing")
	assert_almost_eq(f.forward().z, -1.0, 0.01, "roll alone keeps the nose where it was")


func test_basis_stays_orthonormal_after_long_turns() -> void:
	var f = FlightModel.new(cfg)
	f.set_command(0.7, 0.4, 0.9, 0.8, false)
	_fly(f, 30.0)
	assert_almost_eq(f.basis.determinant(), 1.0, 0.0001, "no drift into skew or scale")


func test_boost_is_faster_and_runs_out() -> void:
	var f = FlightModel.new(cfg)
	f.set_command(0, 0, 0, 1.0, true)
	f.step(0.5)
	assert_true(f.boosting, "boost engages while the meter has charge")
	assert_lt(f.boost_left, f.boost_time(), "boost drains the meter")
	_fly(f, f.boost_time() + 1.0)
	assert_false(f.boosting, "an empty meter ends the boost even while held")
	# Still held: the recharge must not light it again (it used to flicker on
	# every other frame and hold boost speed for ever).
	var lit := 0
	for i in 600:
		f.step(1.0 / 60.0)
		lit += int(f.boosting)
	assert_eq(lit, 0, "held on an empty meter, boost stays off")
	assert_almost_eq(f.speed, f.max_speed(), 0.5, "back to full-throttle speed, not boost speed")
	f.set_command(0, 0, 0, 1.0, false)
	_fly(f, 1.0)
	assert_gt(f.boost_left, 0.0, "the meter recharges when not boosting")
	f.set_command(0, 0, 0, 1.0, true)
	f.step(1.0 / 60.0)
	assert_true(f.boosting, "let go and pressed again, what recharged boosts")


func test_boost_turns_slower() -> void:
	var plain = FlightModel.new(cfg)
	var boosted = FlightModel.new(cfg)
	plain.set_command(1.0, 0, 0, 1.0, false)
	boosted.set_command(1.0, 0, 0, 1.0, true)
	_fly(plain, 0.4)
	_fly(boosted, 0.4)
	assert_lt(boosted.forward().y, plain.forward().y, "boost trades turn rate for speed")


func test_face_points_the_nose() -> void:
	var f = FlightModel.new(cfg)
	f.face(Vector3(1, 0, 0))
	assert_almost_eq(f.forward().x, 1.0, 0.0001, "face() aims the nose along a direction")
	f.face(Vector3(0, 1, 0))
	assert_almost_eq(f.forward().y, 1.0, 0.0001, "face() works straight up too")


func test_save_round_trip() -> void:
	var f = FlightModel.new(cfg)
	f.set_command(0.5, 0.3, 0.2, 0.9, true)
	_fly(f, 2.0)
	var g = FlightModel.new(cfg)
	g.from_dict(JSON.parse_string(JSON.stringify(f.to_dict())))
	assert_almost_eq(g.position.distance_to(f.position), 0.0, 0.001, "position survives")
	assert_almost_eq(g.forward().dot(f.forward()), 1.0, 0.0001, "orientation survives")
	assert_almost_eq(g.speed, f.speed, 0.0001, "speed survives")
	assert_almost_eq(g.boost_left, f.boost_left, 0.0001, "boost meter survives")
