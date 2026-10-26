extends GutTest
## The gate checkpoint's rules (checkpoint.gd, pure): standing bands, night
## bribes, escalation for weapons and gunfire, every card choice, warnings,
## pushing through, going hostile, giving up a chase and remembering it.
## The same rules with real guards and physics: tests/test_combat_trace.

const CoreScript := preload("res://src/systems/dataload/core_content.gd")
const DT := 1.0 / 60.0
const GATE := Vector3(99, 0, 0)
const INSIDE := Vector3(93, 0, 0)

var cfg: Dictionary


func before_each() -> void:
	var cc = CoreScript.new()
	cc.load_from()
	cfg = cc.get_soldier("gate_guard").get("checkpoint", {})


func _cp() -> Checkpoint:
	return Checkpoint.new(cfg)


func _s(extra: Dictionary = {}) -> Dictionary:
	var s := { "standing": 10, "night": false, "credits": 60, "player_pos": INSIDE, "gate_pos": GATE,
		"gate_x": 99.0, "noticed": true, "unseen_s": 0.0, "armed": false, "recent_shot": false,
		"attacked": false, "guards_alive": 2 }
	s.merge(extra, true)
	return s


func _tick(c: Checkpoint, seconds: float, extra: Dictionary = {}) -> Array:
	var ev: Array = []
	for i in maxi(1, int(seconds * 60.0)):
		c.update(DT, _s(extra))
		ev.append_array(c.drain())
	return ev


func _types(ev: Array) -> Array:
	return ev.map(func(e): return str(e.type))


func _barks(ev: Array) -> Array:
	return ev.filter(func(e): return e.type == "bark").map(func(e): return str(e.key))


func test_bands_follow_standing() -> void:
	var c := _cp()
	assert_eq(c.base_band(80), "wave")
	assert_eq(c.base_band(40), "wave")
	assert_eq(c.base_band(39), "papers")
	assert_eq(c.base_band(0), "papers")
	assert_eq(c.base_band(-1), "search")
	assert_eq(c.base_band(-39), "search")
	assert_eq(c.base_band(-40), "hostile")
	assert_eq(c.base_band(-100), "hostile")


func test_weapons_and_gunfire_make_it_worse() -> void:
	var c := _cp()
	assert_eq(c.band_for(50, false, true, false), "papers", "armed: wave becomes papers")
	assert_eq(c.band_for(10, false, false, true), "search", "a recent shot: papers becomes search")
	assert_eq(c.band_for(10, false, true, true), "hostile", "both: two steps")
	assert_eq(c.band_for(-10, false, true, false), "hostile")


func test_night_bribes_work_one_band_lower() -> void:
	var c := _cp()
	assert_eq(c.band_for(-60, true, false, false), "night_hostile", "hostile at night will take coin")
	assert_eq(c.band_for(-60, false, false, false), "hostile", "not in daylight")
	assert_eq(c.bribe_price("search", true), c.bribe_price("papers", false), "the search bribe costs the papers price after dark")
	assert_gt(c.bribe_price("search", false), c.bribe_price("papers", false))


func test_high_standing_is_waved_through() -> void:
	var c := _cp()
	var ev := _tick(c, DT, { "standing": 55 })
	assert_true(_barks(ev).has("wave"))
	assert_false(_types(ev).has("card"), "no card")
	assert_eq(c.state, Checkpoint.State.CLEARED)


func test_nothing_happens_unnoticed_or_far() -> void:
	var c := _cp()
	assert_true(_tick(c, 1.0, { "noticed": false }).is_empty(), "nobody saw you")
	assert_true(_tick(c, 1.0, { "player_pos": Vector3(60, 0, 0) }).is_empty(), "too far from the gate")
	assert_eq(c.state, Checkpoint.State.IDLE)


func test_papers_band_card_and_papers() -> void:
	var c := _cp()
	var ev := _tick(c, DT)
	assert_eq(c.state, Checkpoint.State.CHALLENGE)
	assert_eq(c.band, "papers")
	var ids: Array = c.choices.map(func(x): return str(x.id))
	assert_eq(ids, ["papers", "bribe", "mouth_off", "walk_away"])
	assert_true(c.answer("papers"))
	ev = c.drain()
	assert_eq(c.state, Checkpoint.State.CLEARED)
	var st: Array = ev.filter(func(e): return e.type == "standing")
	assert_eq(int(st[0].delta), 1, "showing papers is a small plus")


func test_search_holds_you_and_clears() -> void:
	var c := _cp()
	_tick(c, DT, { "standing": -10 })
	assert_eq(c.band, "search")
	assert_true(c.answer("search"))
	var ev := c.drain()
	assert_true(_types(ev).has("lock_player"))
	assert_eq(c.state, Checkpoint.State.SEARCHING)
	ev = _tick(c, c.n("search_s", 3.0) + 0.2, { "standing": -10 })
	assert_true(_barks(ev).has("cleared_search"))
	assert_eq(c.state, Checkpoint.State.CLEARED)


func test_walking_off_mid_search_is_a_warning_then_a_fight() -> void:
	var c := _cp()
	_tick(c, DT, { "standing": -10 })
	c.answer("search")
	c.drain()
	_tick(c, 0.2, { "standing": -10, "player_pos": INSIDE + Vector3(-4, 0, 0) })
	assert_eq(c.state, Checkpoint.State.WARN)
	var ev := _tick(c, c.n("warn_s", 3.0) + 0.1, { "standing": -10, "player_pos": INSIDE + Vector3(-4, 0, 0) })
	assert_true(_types(ev).has("hostile"))


func test_bribe_takes_credits_or_refuses() -> void:
	var c := _cp()
	_tick(c, DT, { "standing": -10, "credits": 60 })
	assert_true(c.answer("bribe"))
	var ev := c.drain()
	var b: Array = ev.filter(func(e): return e.type == "bribe")
	assert_eq(int(b[0].price), c.bribe_price("search", false))
	assert_eq(c.state, Checkpoint.State.CLEARED)
	var broke := _cp()
	_tick(broke, DT, { "standing": -10, "credits": 3 })
	var bribe: Dictionary = broke.choices.filter(func(x): return x.id == "bribe")[0]
	assert_false(bool(bribe.enabled), "greyed out when you cannot pay")
	assert_false(broke.answer("bribe"))
	assert_true(_barks(broke.drain()).has("no_credits"))
	assert_eq(broke.state, Checkpoint.State.CHALLENGE, "the question still stands")


func test_hostile_band_warns_then_fights() -> void:
	var c := _cp()
	var ev := _tick(c, DT, { "standing": -60, "player_pos": Vector3(115, 0, 0) })
	assert_true(_barks(ev).has("halt_hostile"), "a warning first, even at 16 m")
	assert_eq(c.state, Checkpoint.State.WARN)
	ev = _tick(c, c.n("warn_s", 3.0) + 0.1, { "standing": -60, "player_pos": Vector3(115, 0, 0) })
	assert_true(_types(ev).has("hostile"))
	assert_eq(c.state, Checkpoint.State.HOSTILE)
	var st: Array = ev.filter(func(e): return e.type == "standing")
	assert_eq(int(st[0].delta), int(cfg.standing.fight))


func test_backing_off_from_a_hostile_warning_is_allowed() -> void:
	var c := _cp()
	_tick(c, DT, { "standing": -60, "player_pos": Vector3(115, 0, 0) })
	var ev := _tick(c, 1.0, { "standing": -60, "player_pos": Vector3(140, 0, 0) })
	assert_true(_barks(ev).has("stay_out"))
	assert_eq(c.state, Checkpoint.State.IDLE)


func test_mouthing_off_escalates() -> void:
	var c := _cp()
	_tick(c, DT)
	c.answer("mouth_off")
	assert_eq(c.band, "search", "papers becomes a search")
	assert_true(c.card_open, "with a new card")
	c.drain()
	c.answer("mouth_off")
	assert_eq(c.state, Checkpoint.State.WARN, "twice is a warning")
	var ev := _tick(c, c.n("warn_s", 3.0) + 0.1)
	assert_true(_types(ev).has("hostile"))


func test_pushing_through_the_gate() -> void:
	var c := _cp()
	_tick(c, DT)
	c.answer("walk_away")
	c.drain()
	var ev := _tick(c, 0.2, { "player_pos": Vector3(103, 0, 0) })
	assert_true(_barks(ev).has("warn"))
	assert_eq(c.state, Checkpoint.State.WARN)
	ev = _tick(c, c.n("warn_s", 3.0) + 0.1, { "player_pos": Vector3(104, 0, 0) })
	assert_true(_types(ev).has("hostile"), "kept going")


func test_stepping_back_from_the_line_asks_again() -> void:
	var c := _cp()
	_tick(c, DT)
	_tick(c, 0.2, { "player_pos": Vector3(103, 0, 0) })
	assert_eq(c.state, Checkpoint.State.WARN)
	var ev := _tick(c, 0.2, { "player_pos": INSIDE })
	assert_eq(c.state, Checkpoint.State.CHALLENGE)
	assert_true(_types(ev).has("card"), "the card comes back")


func test_shooting_a_guard_starts_a_fight_from_anywhere() -> void:
	var c := _cp()
	_tick(c, DT, { "standing": 80 })
	assert_eq(c.state, Checkpoint.State.CLEARED)
	var ev := _tick(c, DT, { "standing": 80, "attacked": true })
	assert_true(_types(ev).has("hostile"))


func test_running_away_ends_it_and_they_remember() -> void:
	var c := _cp()
	_tick(c, DT, { "attacked": true })
	assert_eq(c.state, Checkpoint.State.HOSTILE)
	var ev := _tick(c, c.n("disengage_unseen_s", 12.0) + 0.5,
		{ "player_pos": Vector3(200, 0, 0), "unseen_s": 30.0, "noticed": false })
	assert_true(_types(ev).has("calm"))
	assert_true(ev.filter(func(e): return e.type == "flag" and e.name == "fled_gate_fight").size() == 1)
	assert_eq(c.state, Checkpoint.State.IDLE)
	ev = _tick(c, DT, { "player_pos": Vector3(110, 0, 0) })
	assert_true(_types(ev).has("hostile"), "seen again within memory_s: straight to a fight")


func test_all_guards_down_ends_it() -> void:
	var c := _cp()
	_tick(c, DT, { "attacked": true })
	var ev := _tick(c, DT, { "guards_alive": 0 })
	assert_true(_types(ev).has("calm"))
	assert_eq(c.state, Checkpoint.State.IDLE)
	assert_true(_tick(c, 1.0, { "guards_alive": 0 }).is_empty(), "nobody left to care")


func test_downed_player_stands_them_down() -> void:
	var c := _cp()
	_tick(c, DT, { "attacked": true })
	c.on_player_downed()
	var ev := c.drain()
	assert_true(_types(ev).has("calm"))
	assert_eq(c.state, Checkpoint.State.IDLE)
	assert_gt(c.memory_left, 0.0, "but they remember")


func test_cleared_lasts_then_lapses() -> void:
	var c := _cp()
	_tick(c, DT)
	c.answer("papers")
	c.drain()
	_tick(c, 5.0)
	assert_eq(c.state, Checkpoint.State.CLEARED)
	c.cleared_left = 0.01
	_tick(c, DT, { "noticed": false })
	assert_eq(c.state, Checkpoint.State.IDLE)
