extends GutTest
## Issue #42: speeders and Skrugs. The hover model (rides the ground, launches off
## a ramp, lands with no damage, only gunfire hurts it), Skrugs's card (sells, no
## jobs, knows Oda), and buying one at his stall outside the back gate.

const TownDemo := preload("res://scenes/town_demo.gd")

var cfg: Dictionary


func before_each() -> void:
	WorldState.reset()
	cfg = HoverModel.load_config("speeder")


func after_each() -> void:
	WorldState.reset()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Flat sand at 0, a ramp rising toward -z (2.4 m at its far end) and a wall.
func _ground() -> WorldGround:
	var g := WorldGround.new()
	g.setup({ "terrain": { "extent": 2000.0 } })
	g.add_box("ramp", "solid", Vector3(-3, 0, -40), Vector3(3, 2.4, -30), "-z")
	g.add_box("wall", "solid", Vector3(40, 0, -5), Vector3(42, 4, 5))
	return g


func _model() -> HoverModel:
	var m := HoverModel.new(cfg, _ground())
	m.place(Vector3.ZERO, 0.0)
	return m


func _drive(m: HoverModel, seconds: float, throttle: float, steer: float = 0.0, boost: bool = false) -> Array:
	var ev: Array = []
	for i in int(seconds * 60.0):
		m.set_command(throttle, steer, boost)
		ev.append_array(m.step(1.0 / 60.0))
	return ev


# ---- the hover model ---------------------------------------------------------------

func test_it_hovers_at_its_height() -> void:
	var m := _model()
	_drive(m, 1.0, 0.0)
	assert_almost_eq(m.position.y, float(cfg.hover_height), 0.05)
	assert_false(m.airborne)


func test_it_speeds_up_and_boosts_faster() -> void:
	var m := _model()
	m.yaw = PI * 0.5                 # face -x, away from the ramp and the wall
	_drive(m, 4.0, 1.0)
	assert_almost_eq(m.speed, float(cfg.max_speed), 1.0, "full throttle: top speed")
	_drive(m, 2.0, 1.0, 0.0, true)
	assert_gt(m.speed, float(cfg.max_speed) + 5.0, "boost goes faster")


func test_it_launches_off_a_ramp_and_lands_unhurt() -> void:
	var m := _model()
	var ev := _drive(m, 6.0, 1.0)     # straight down -z: up the ramp and off its end
	var types := ev.map(func(e): return str(e.type))
	assert_has(types, "launch", "the ground fell away at the ramp's end")
	assert_has(types, "landed")
	var landed: Dictionary = ev.filter(func(e): return str(e.type) == "landed")[0]
	assert_gt(float(landed.top), 1.5, "real air under it")
	assert_gt(float(landed.air_time), 0.3)
	assert_lt(m.position.z, -42.0, "came down past the ramp")
	assert_eq(m.hp, m.max_hp, "no fall damage")


func test_it_is_light_and_has_no_jump_button() -> void:
	assert_lte(float(cfg.gravity), 10.0, "a light sled: low gravity")
	assert_false(cfg.has("hop_speed"), "no jump button: ramps do the jumping")
	var m := _model()
	var ev := _drive(m, 6.0, 1.0)
	var landed: Array = ev.filter(func(e): return str(e.type) == "landed")
	assert_false(landed.is_empty())
	assert_gt(float(landed[0].air_time), 0.8, "it floats off the ramp")


func test_buildings_stop_it_but_never_hurt_it() -> void:
	var m := _model()
	m.yaw = -PI * 0.5                # face +x, at the wall
	var ev := _drive(m, 3.0, 1.0)
	assert_has(ev.map(func(e): return str(e.type)), "bump")
	assert_lt(m.position.x, 40.0, "stopped short of the wall")
	assert_eq(m.hp, m.max_hp, "no crash damage")


func test_gunfire_hurts_it_and_can_destroy_it() -> void:
	var m := _model()
	assert_false(m.apply_damage(30.0))
	assert_eq(m.hp, m.max_hp - 30)
	while m.alive():
		m.apply_damage(25.0)
	assert_has(m.events.map(func(e): return str(e.type)), "destroyed")


# ---- Skrugs's card -------------------------------------------------------------------

func _skrugs() -> NpcBrain:
	return NpcBrain.new(null, SpeederPost.CARD_PATH)


func test_skrugs_sells_and_never_offers_jobs() -> void:
	var b := _skrugs()
	assert_eq(b.id(), "skrugs")
	var rules := str(b.builder.rules_message().content)
	assert_string_contains(rules, "offer_speeder")
	assert_false(rules.contains("offer_job"), "no job board")
	assert_false(rules.contains("pour_drink"), "no drinks")
	var persona := str(b.builder.persona_message().content)
	assert_string_contains(persona, "100 credits")
	assert_string_contains(persona, "Oda", "he knows the Cantina Owner")
	assert_string_contains(persona, "back gate")


func test_skrugs_offline_still_sells_and_still_has_no_jobs() -> void:
	var b := _skrugs()
	var buy := b.canned_reply("How much for the speeder?")
	assert_eq(str(buy.actions[0].type), "offer_speeder")
	var job := b.canned_reply("Got any jobs for me?")
	assert_true((job.actions as Array).filter(func(a): return str(a.type) == "offer_job").is_empty())


# ---- buying at the stall -----------------------------------------------------------------

func _town() -> Node:
	var t = TownDemo.new()
	t.use_look = false
	t.npc_brains = false
	add_child_autofree(t)
	t._build_bar([ScriptedProvider.new("scripted_test")], "")
	t.speeder_post.attach_host(t.bar)
	return t


func test_the_post_is_outside_the_back_gate() -> void:
	var t = _town()
	var post: SpeederPost = t.speeder_post
	var gap: Vector3 = t.town.marker_pos("back_gap")
	var stall := post.world_point("customer")
	assert_lt(stall.x, gap.x, "outside the wall")
	assert_lt(Vector2(stall.x - gap.x, stall.z - gap.z).length(), 45.0, "a short walk from the back gate")
	assert_not_null(post.spot, "Skrugs is someone to talk to")
	assert_true(t.bar.spots.has(post.spot))
	assert_false(post.display.rideable, "the display model is not for riding")


func test_buying_a_speeder_at_the_stall() -> void:
	var t = _town()
	var post: SpeederPost = t.speeder_post
	WorldState.credits = 150
	t.bar.start_talk(post.spot)
	post.spot.brain.sale_offered.emit({ "id": "speeder", "name": "speeder", "price": 100 })
	assert_true(t.bar.panel.job_open(), "the price card is up")
	t.bar.panel.answer_card(true)
	assert_eq(WorldState.credits, 50, "100 credits")
	assert_eq(post.speeders.size(), 1, "one speeder")
	assert_eq(WorldState.count("speeders_owned"), 1, "saved as owned")
	var s: SpeederNode = post.speeders[0]
	assert_lt(s.model.position.x, post.origin.x - 7.0, "parked behind the house, away from the stall")
	assert_eq(post.spot.brain.rel.mood, "warm", "Skrugs is happy")
	assert_true(WorldState.has_flag("bought_speeder"))
	t.bar.end_talk()


func test_no_money_no_speeder() -> void:
	var t = _town()
	var post: SpeederPost = t.speeder_post
	WorldState.credits = 40
	t.bar.start_talk(post.spot)
	post.spot.brain.sale_offered.emit({ "id": "speeder", "name": "speeder", "price": 100 })
	t.bar.panel.answer_card(true)
	assert_eq(WorldState.credits, 40, "nothing charged")
	assert_eq(post.speeders.size(), 0)
	t.bar.panel.answer_card(false)
	t.bar.end_talk()


func test_ride_it_and_get_off() -> void:
	var t = _town()
	var post: SpeederPost = t.speeder_post
	WorldState.credits = 100
	post.buy()
	var s: SpeederNode = post.speeders[0]
	var p = t._player
	p.global_position = s.model.position + Vector3(1.5, -1.0, 0)
	assert_true(s.can_mount(), "close enough to climb on")
	assert_true(s.mount())
	assert_true(p.piloting, "the player is aboard")
	var start := s.model.position
	s.set_external_command({ "throttle": 1.0 })
	for i in 150:
		s._physics_process(1.0 / 60.0)
	assert_gt(s.model.position.distance_to(start), 35.0, "it goes (2.5 s from a standstill)")
	s.set_external_command({ "throttle": 0.0 })
	for i in 120:
		s._physics_process(1.0 / 60.0)
	assert_true(s.dismount())
	assert_false(p.piloting)
	assert_true(p.visible)
	assert_lt(p.global_position.distance_to(s.model.position), 5.0, "stepped off beside it")


func test_space_fires_both_lasers_at_once() -> void:
	var t = _town()
	var post: SpeederPost = t.speeder_post
	WorldState.credits = 100
	post.buy()
	var s: SpeederNode = post.speeders[0]
	await wait_frames(1)
	var p = t._player
	p.global_position = s.model.position + Vector3(1.5, -1.0, 0)
	assert_true(s.mount())
	var bolts_before := t.get_tree().get_nodes_in_group("bolts").size()
	s.set_external_command({ "fire": true })
	s._physics_process(1.0 / 60.0)
	assert_eq(s.gun.shots_fired, 2, "one pull, two bolts")
	assert_eq(t.get_tree().get_nodes_in_group("bolts").size() - bolts_before, 2, "left and right")
	s.dismount()


func test_a_bolt_on_the_hull_damages_it() -> void:
	var t = _town()
	var post: SpeederPost = t.speeder_post
	WorldState.credits = 100
	post.buy()
	var s: SpeederNode = post.speeders[0]
	await wait_frames(1)
	# What bolt.gd does with whatever it hit: the hull's parent takes the damage.
	var target: Object = s.hull
	if target.has_method("apply_damage"):
		target.apply_damage(40.0)
	elif target.get_parent().has_method("apply_damage"):
		target.get_parent().apply_damage(40.0)
	assert_eq(s.model.hp, s.model.max_hp - 40)
	s.apply_damage(9999.0)
	await wait_frames(2)
	assert_eq(post.speeders.size(), 0, "burned out")
	assert_eq(WorldState.count("speeders_owned"), 0, "and no longer owned")


## Issue #64: the speeder's lasers kill what they hit (a trooper standing in front of it).
func test_lasers_kill_an_enemy() -> void:
	var t = _town()
	var post: SpeederPost = t.speeder_post
	WorldState.credits = 100
	post.buy()
	var s: SpeederNode = post.speeders[0]
	await wait_frames(1)
	var p = t._player
	p.global_position = s.model.position + Vector3(1.5, -1.0, 0)
	assert_true(s.mount())
	var ahead: Vector3 = s.model.position + s.model.forward() * 14.0
	ahead.y = t.terrain.height_at(ahead.x, ahead.z) if t.terrain != null else s.model.position.y
	var g: NpcBody = t.make_soldier("gate_guard", ahead, 0.0, "probe", "npc:test/probe")
	g.nav = null
	await wait_physics_frames(3)
	s.set_external_command({ "fire": true })
	for i in 240:
		await wait_physics_frames(1)
		if g.dead:
			break
	assert_gt(g.hits_taken, 0, "the bolts hit them")
	assert_true(g.dead, "and kill them")
	s.set_external_command({})
	s.dismount()
