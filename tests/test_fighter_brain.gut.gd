extends GutTest
## M10: the fighter pilot AI, flown through the real flight model. A pilot turns
## onto a target behind it, attacks and fires only with the nose on the lead, breaks
## when too close, extends and comes back, returns to the arena, and evades seekers.

const FlightModel := preload("res://src/systems/flight/flight_model.gd")
const FighterBrain := preload("res://src/systems/ai/fighter_brain.gd")
const LeadSolver := preload("res://src/systems/flight/lead_solver.gd")
const CoreScript := preload("res://src/systems/dataload/core_content.gd")

var content


func before_each() -> void:
	content = CoreScript.new()
	content.load_from()


func _pilot(pilot_id: String = "veteran", ship_id: String = "remnant_fighter"):
	var f = FlightModel.new(content.get_ship(ship_id).flight)
	var b = FighterBrain.new(content.get_pilot(pilot_id), f, 3)
	b.arena_radius = 5000.0
	return b


func _tick(b, seconds: float) -> void:
	for i in int(seconds * 60.0):
		b.update(1.0 / 60.0)
		b.flight.set_command_dict(b.command)
		b.flight.step(1.0 / 60.0)


func test_profile_comes_from_pilot_data() -> void:
	var b = _pilot("rookie")
	assert_eq(b.p("aim_cone_deg", -1.0), float(content.get_pilot("rookie").aim_cone_deg),
		"aim cone is the pilot's data value")


func test_turns_onto_a_target_behind_it() -> void:
	var b = _pilot()
	b.has_target = true
	b.target_pos = Vector3(0, 0, 500)   # directly behind
	b.target_vel = Vector3.ZERO
	var start := LeadSolver.angle_deg(b.flight.forward(), b.target_pos - b.flight.position)
	assert_gt(start, 170.0, "the target starts behind the ship")
	_tick(b, 6.0)
	var end := LeadSolver.angle_deg(b.flight.forward(), b.target_pos - b.flight.position)
	assert_lt(end, 15.0, "within six seconds the nose is on the target")


func test_pursues_when_far_and_attacks_when_close() -> void:
	var b = _pilot()
	b.has_target = true
	b.target_pos = Vector3(0, 0, -2000)
	b.update(1.0 / 60.0)
	assert_eq(b.state, FighterBrain.Action.PURSUE, "beyond engage range it pursues")
	assert_true(b.command.boost, "and boosts when far")
	b.target_pos = Vector3(0, 0, -300)
	b.update(1.0 / 60.0)
	assert_eq(b.state, FighterBrain.Action.ATTACK, "inside engage range it attacks")


func test_fires_only_with_the_nose_on_the_lead() -> void:
	var b = _pilot("ace")
	b.has_target = true
	b.target_pos = Vector3(0, 0, -300)
	b.update(1.0 / 60.0)
	assert_true(b.fire_primary, "dead ahead and in range: fire")
	var c = _pilot("ace")
	c.has_target = true
	c.target_pos = Vector3(250, 0, -300)
	c.update(1.0 / 60.0)
	assert_false(c.fire_primary, "40 degrees off the nose: hold fire")


func test_breaks_when_too_close_then_extends_then_pursues() -> void:
	var b = _pilot("veteran")
	b.has_target = true
	b.target_pos = Vector3(0, 0, -40)
	b.update(1.0 / 60.0)
	assert_eq(b.state, FighterBrain.Action.BREAK, "inside break distance it breaks off")
	var seen_extend := false
	var seen_pursue := false
	for i in 60 * 20:
		b.update(1.0 / 60.0)
		b.flight.set_command_dict(b.command)
		b.flight.step(1.0 / 60.0)
		if b.state == FighterBrain.Action.EXTEND:
			seen_extend = true
		if seen_extend and b.state in [FighterBrain.Action.PURSUE, FighterBrain.Action.ATTACK]:
			seen_pursue = true
			break
	assert_true(seen_extend, "after the break it extends away")
	assert_true(seen_pursue, "and then turns back in")


func test_returns_to_the_arena() -> void:
	var b = _pilot()
	b.arena_radius = 1000.0
	b.flight.position = Vector3(0, 0, 1500)
	b.has_target = true
	b.target_pos = Vector3(0, 0, 3000)
	b.update(1.0 / 60.0)
	assert_eq(b.state, FighterBrain.Action.RETURN, "outside the arena it heads home")


func test_patrols_without_a_target() -> void:
	var b = _pilot()
	b.has_target = false
	b.update(1.0 / 60.0)
	assert_eq(b.state, FighterBrain.Action.PATROL)
	assert_false(b.fire_primary, "nothing to shoot at")


func test_a_seeker_launch_makes_a_steady_pilot_break() -> void:
	var prof: Dictionary = content.get_pilot("ace").duplicate()
	prof["evade_missile"] = 1.0
	var b = FighterBrain.new(prof, FlightModel.new(content.get_ship("interceptor").flight), 1)
	b.arena_radius = 5000.0
	b.has_target = true
	b.target_pos = Vector3(0, 0, -300)
	b.update(1.0 / 60.0)
	assert_eq(b.state, FighterBrain.Action.ATTACK)
	b.notify_missile()
	b.update(1.0 / 60.0)
	assert_eq(b.state, FighterBrain.Action.BREAK, "a seeker warning triggers a break")


func test_only_missile_pilots_launch_seekers() -> void:
	for pid in ["rookie", "veteran"]:
		var b = _pilot(pid, "remnant_heavy")
		b.has_target = true
		b.target_pos = Vector3(0, 0, -300)
		b.has_missiles = true
		b.missile_locked = true
		b.update(1.0 / 60.0)
		assert_eq(b.fire_secondary, bool(content.get_pilot(pid).missile_use),
			"%s launches only if its profile allows it" % pid)


func test_same_seed_flies_the_same_line() -> void:
	var a = _pilot()
	var c = _pilot()
	for b in [a, c]:
		b.has_target = true
		b.target_pos = Vector3(200, 50, -60)
		_tick(b, 8.0)
	assert_almost_eq(a.flight.position.distance_to(c.flight.position), 0.0, 0.0001,
		"the AI is deterministic for a seed, so traces are reproducible")
