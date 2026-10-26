extends GutTest
## M13: the jetpack model and its hook into the character controller. Pure math,
## so every rule is checked directly: a tap never burns fuel, a hold lights the
## pack after the kick-in, thrust beats gravity, the climb is capped, the pack runs
## dry and needs a little fuel to relight, fuel refills only after the delay and
## only on the ground, and old callers of set_command() see no change.

const Jetpack := preload("res://src/systems/player/jetpack.gd")
const CharacterController := preload("res://src/systems/player/character_controller.gd")
const CoreScript := preload("res://src/systems/dataload/core_content.gd")
const DT := 1.0 / 60.0

var cfg: Dictionary


func before_each() -> void:
	var content = CoreScript.new()
	content.load_from()
	cfg = content.get_item("jetpack").get("jetpack", {})


func _run(j, seconds: float, held: bool, ground: bool) -> float:
	var lift := 0.0
	for i in int(round(seconds / DT)):
		lift = j.step(DT, held, ground)
	return lift


func test_tuning_comes_from_item_data() -> void:
	var j = Jetpack.new(cfg)
	assert_eq(j.fuel_max(), float(cfg.fuel), "fuel is the item's data value")
	assert_eq(j.fuel, j.fuel_max(), "a new pack starts full")
	assert_gt(j.thrust(), 20.0, "thrust beats gravity (20), or it could not climb")


func test_tap_never_burns_fuel() -> void:
	var j = Jetpack.new(cfg)
	_run(j, j.kick_in() * 0.5, true, false)
	_run(j, 0.5, false, false)
	assert_eq(j.fuel, j.fuel_max(), "a jump tap is shorter than the kick-in")
	assert_eq(j.burns, 0)


func test_hold_in_the_air_lights_after_kick_in() -> void:
	var j = Jetpack.new(cfg)
	assert_eq(_run(j, j.kick_in() * 0.5, true, false), 0.0, "not yet")
	assert_eq(_run(j, j.kick_in(), true, false), j.thrust(), "lit after the kick-in")
	assert_true(j.thrusting)
	assert_lt(j.fuel, j.fuel_max(), "burning uses fuel")
	assert_eq(j.burns, 1)


func test_no_thrust_on_the_ground() -> void:
	var j = Jetpack.new(cfg)
	assert_eq(_run(j, 1.0, true, true), 0.0, "holding jump on the ground does nothing")
	assert_eq(j.fuel, j.fuel_max())


func test_fuel_runs_out_after_its_seconds() -> void:
	var j = Jetpack.new(cfg)
	_run(j, j.kick_in(), true, false)
	_run(j, j.fuel_max() + 0.2, true, false)
	assert_almost_eq(j.fuel, 0.0, 0.0001, "empty")
	assert_false(j.thrusting, "an empty pack cuts out even while held")
	assert_almost_eq(j.burned, j.fuel_max(), DT * 1.5, "burn time equals the fuel")


func test_empty_pack_needs_fuel_to_relight() -> void:
	var j = Jetpack.new(cfg)
	j.fuel = j.min_fuel_to_start() * 0.5
	assert_eq(_run(j, j.kick_in() + 0.1, true, false), 0.0, "too little to light")
	j.fuel = j.min_fuel_to_start() + 0.1
	_run(j, 0.05, false, false)
	assert_gt(_run(j, j.kick_in() + DT, true, false), 0.0, "enough to light")


func test_recharge_waits_for_the_delay_and_the_ground() -> void:
	var j = Jetpack.new(cfg)
	_run(j, j.kick_in() + 0.5, true, false)
	var low: float = j.fuel
	_run(j, j.recharge_delay() * 0.5, false, true)
	assert_eq(j.fuel, low, "no refill inside the delay")
	_run(j, j.recharge_delay() + 1.0, false, false)
	assert_eq(j.fuel, low, "no refill in the air (recharge_air is 0)")
	_run(j, 0.5, false, true)
	assert_gt(j.fuel, low, "refills on the ground after the delay")
	_run(j, j.fuel_max() / j.recharge_ground() + 0.1, false, true)
	assert_eq(j.fuel, j.fuel_max(), "and stops at full")


func test_save_round_trip() -> void:
	var j = Jetpack.new(cfg)
	j.fuel = 0.7
	var k = Jetpack.new(cfg)
	k.from_dict(JSON.parse_string(JSON.stringify(j.to_dict())))
	assert_almost_eq(k.fuel, 0.7, 0.0001)
	k.from_dict({ "fuel": 99.0 })
	assert_eq(k.fuel, k.fuel_max(), "a bad save is clamped")


# ---- controller hook -------------------------------------------------------------

func test_lift_beats_gravity_and_is_capped() -> void:
	var c = CharacterController.new()
	c.on_ground = false
	c.body_pos = Vector3(0, 10, 0)
	c.velocity = Vector3.ZERO
	c.lift = 36.0
	c.max_rise = 9.0
	for i in 120:
		c.step(DT, 0.0, -INF)
	assert_almost_eq(c.velocity.y, 9.0, 0.0001, "climbs, capped at max_rise")
	c.lift = 0.0
	c.step(DT, 0.0, -INF)
	assert_lt(c.velocity.y, 9.0, "gravity takes over without lift")


func test_old_set_command_callers_are_unchanged() -> void:
	var c = CharacterController.new()
	c.set_command(Vector2(0, 1), false, false, false)
	assert_false(c.command.jump_held, "four-argument calls never hold jump")
	c.set_command(Vector2.ZERO, false, false, true)
	assert_true(c.command.jump_held, "a jump press counts as held for its frame")
	c.set_command(Vector2.ZERO, false, false, false, true)
	assert_true(c.command.jump_held)
	assert_eq(c.lift, 0.0, "no lift unless a jetpack sets it")


func test_plain_jump_height_is_unchanged() -> void:
	var c = CharacterController.new()
	c.set_command(Vector2.ZERO, false, false, true)
	c.step(DT, 0.0, 0.0)
	var top := 0.0
	c.set_command(Vector2.ZERO, false, false, false, true)
	for i in 120:
		c.step(DT, 0.0, 0.0)
		top = maxf(top, c.body_pos.y)
	assert_almost_eq(top, 0.6, 0.06, "holding jump without a pack is the M1 jump")
