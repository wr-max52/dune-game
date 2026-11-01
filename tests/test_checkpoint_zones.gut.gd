extends GutTest
## Issue #308: the barracks yard and the ring round each outpost stop you like
## the gate. Below the wave band the nearest trooper there walks up and the gate's
## card opens; at 40 and up you walk in; leave and the card closes; cleared, the
## zone leaves you alone; wanted by day, a warning and then the alarm. Headless (no
## look layer); the garrison is stepped by hand with the troopers seeing you.

const TownDemo := preload("res://scenes/town_demo.gd")
const DT := 1.0 / 60.0


func before_each() -> void:
	WorldState.new_game(WorldState.FREEPLAY)
	WorldState.time_of_day = "golden"


func after_each() -> void:
	WorldState.reset()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _town() -> Node:
	var t = TownDemo.new()
	t.use_look = false
	t.npc_brains = true
	add_child_autofree(t)
	return t


func _zone(g: Garrison, id: String) -> Dictionary:
	for z in g.zones:
		if str(z.spec.get("id", "")) == id:
			return z
	return {}


## A spot in the barracks yard: in front of the hall, between the yard walls.
func _in_yard(z: Dictionary) -> Vector3:
	var lo: Array = z.spec.min
	var hi: Array = z.spec.max
	return Vector3(lerpf(float(lo[0]), float(hi[0]), 0.4), 0.0, float(lo[1]) + 6.0)


## `seconds` of the garrison with the player held at `at` and the zone's troopers seeing them.
func _step(g: Garrison, z: Dictionary, seconds: float, at: Vector3) -> void:
	for i in maxi(1, int(seconds / DT)):
		g.player.global_position = at
		for trooper in z.guards:
			if is_instance_valid(trooper) and not trooper.dead:
				trooper.perception.noticed = true
		g._physics_process(DT)


func _barracks(t) -> Dictionary:
	var g: Garrison = t.garrison
	assert_not_null(g, "the town has a garrison")
	var z := _zone(g, "barracks")
	assert_false(z.is_empty(), "the barracks yard is a checkpoint zone")
	assert_gt(z.guards.size(), 0, "with the barracks troopers on it")
	assert_lte(Garrison.zone_out(z.spec, _in_yard(z)), 0.0, "and the spot is inside it")
	return z


func test_in_good_standing_you_walk_into_the_barracks() -> void:
	var t = _town()
	var z := _barracks(t)
	WorldState.standing.imperial_remnant = 50
	_step(t.garrison, z, 8.0, _in_yard(z))
	assert_false((z.checkpoint as Checkpoint).card_open, "no card")
	assert_eq(t.garrison.cards_shown, 0)
	assert_false(t.garrison.alarm.active())


func test_below_forty_a_trooper_walks_up_with_the_card_and_a_bribe_clears_you() -> void:
	var t = _town()
	var z := _barracks(t)
	var g: Garrison = t.garrison
	var cp: Checkpoint = z.checkpoint
	cp.cfg["spot_check_chance"] = 0.0
	WorldState.standing.imperial_remnant = 10
	WorldState.credits = 100
	_step(g, z, 8.0, _in_yard(z))
	assert_true(cp.card_open, "the card opens")
	assert_eq(cp.band, "papers")
	var ids: Array = cp.choices.map(func(c): return str(c.id))
	assert_has(ids, "papers")
	assert_has(ids, "bribe")
	assert_eq(g.cards_shown, 1, "once the trooper has walked up")
	assert_true(g.barks_said.has("papers"), "he asks for papers")
	var lead := g._lead(z.guards)
	assert_eq(g.brains[lead].state, GuardBrain.State.ATTEND)
	var price := cp.bribe_price("papers", false)
	assert_true(g.choose("bribe"))
	assert_eq(WorldState.credits, 100 - price, "the credits are gone")
	_step(g, z, 2.0, _in_yard(z) + Vector3(2.0, 0, 0))
	assert_false(cp.card_open, "no card on the next step")
	assert_eq(cp.state, Checkpoint.State.CLEARED)
	assert_eq(g.cards_shown, 1)


func test_leaving_the_zone_closes_the_card() -> void:
	var t = _town()
	var z := _barracks(t)
	var cp: Checkpoint = z.checkpoint
	WorldState.standing.imperial_remnant = 10
	_step(t.garrison, z, 1.0, _in_yard(z))
	assert_true(cp.card_open)
	var out := _in_yard(z) - Vector3(0, 0, 6.0 + 8.0)       # out past the yard wall into the street
	assert_gt(Garrison.zone_out(z.spec, out), 3.0)
	_step(t.garrison, z, 0.5, out)
	assert_false(cp.card_open, "walked away: it closes")
	assert_eq(cp.state, Checkpoint.State.IDLE)


func test_wanted_by_day_a_warning_then_the_alarm() -> void:
	var t = _town()
	var z := _barracks(t)
	var g: Garrison = t.garrison
	WorldState.standing.imperial_remnant = -50
	_step(g, z, 1.0, _in_yard(z))
	assert_true(g.barks_said.has("halt_hostile"), "a warning first")
	assert_false(g.alarm.active(), "not yet")
	_step(g, z, float(z.checkpoint.cfg.get("warn_s", 3.0)) + 0.5, _in_yard(z))
	assert_true(g.alarm.active(), "then the alarm")


func test_an_outpost_stops_you_too() -> void:
	var t = _town()
	assert_not_null(t.outposts, "the town builds the outposts")
	var o: Dictionary = t.outposts.outposts[0]
	var og: Garrison = t.outposts.garrisons[str(o.id)]
	var z := _zone(og, str(o.id))
	assert_false(z.is_empty(), "the outpost's ring is a checkpoint zone")
	assert_eq(z.guards.size(), 3, "its three troopers")
	var at: Vector3 = (o.origin as Vector3) + Vector3(12.0, 0.0, 0.0)
	assert_lt(Garrison.zone_out(z.spec, at), 0.0)
	WorldState.standing.imperial_remnant = 10
	_step(og, z, 8.0, at)
	assert_true((z.checkpoint as Checkpoint).card_open, "the card opens out there")
	assert_eq(og.cards_shown, 1)
	assert_false(og.alarm.active())
