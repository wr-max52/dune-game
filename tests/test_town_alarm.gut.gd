extends GutTest
## The town-wide alarm (town_alarm.gd, pure), the parts of the garrison it relies
## on (sentry and barracks profiles, the brain's leash and tower rim, the shared
## sighting), and the smuggling plumbing (contraband item, cache count, fence,
## inventory panel). The same with real physics: tests/test_garrison_trace.

const CoreScript := preload("res://src/systems/dataload/core_content.gd")
const TownLayout := preload("res://src/systems/world/town_layout.gd")
const DT := 1.0 / 60.0

var cc
var cfg: Dictionary


func before_each() -> void:
	cc = CoreScript.new()
	cc.load_from()
	var t = TownLayout.new()
	t.load_town("port_town")
	cfg = t.data.get("garrison", {}).get("alarm", {})


func _tick(a: TownAlarm, seconds: float, s: Dictionary) -> Array:
	var ev: Array = []
	for i in maxi(1, int(seconds * 60.0)):
		a.update(DT, s)
		ev.append_array(a.drain())
	return ev


func test_raise_once() -> void:
	var a := TownAlarm.new(cfg)
	assert_true(a.raise("attacked", Vector3(1, 0, 2)))
	assert_false(a.raise("gate"), "already up")
	assert_true(a.active())
	assert_eq(a.why, "attacked")
	assert_eq(a.last_known, Vector3(1, 0, 2))
	assert_eq(a.drain().filter(func(e): return e.type == "alarm").size(), 1)


func test_shared_sighting_follows_whoever_sees() -> void:
	var a := TownAlarm.new(cfg)
	a.raise("gate", Vector3.ZERO)
	_tick(a, DT, { "seen": true, "player_pos": Vector3(50, 0, 7), "nearest_dist": 10.0, "alive": 3 })
	assert_eq(a.last_known, Vector3(50, 0, 7))
	_tick(a, 1.0, { "seen": false, "player_pos": Vector3(80, 0, 0), "nearest_dist": 10.0, "alive": 3 })
	assert_eq(a.last_known, Vector3(50, 0, 7), "nobody saw the move")


func test_hiding_close_by_does_not_end_it() -> void:
	var a := TownAlarm.new(cfg)
	a.raise("gate")
	_tick(a, 30.0, { "seen": false, "player_pos": Vector3.ZERO, "nearest_dist": 8.0, "alive": 3 })
	assert_true(a.active(), "out of sight but right there")


func test_getting_away() -> void:
	var a := TownAlarm.new(cfg)
	a.raise("gate")
	var ev := _tick(a, float(cfg.disengage_unseen_s) + 0.5,
		{ "seen": false, "player_pos": Vector3(200, 0, 0), "nearest_dist": float(cfg.disengage_dist) + 5.0, "alive": 3 })
	assert_false(a.active())
	assert_true(ev.any(func(e): return e.type == "calm" and e.why == "fled"))
	assert_true(ev.any(func(e): return e.type == "flag" and e.name == "fled_gate_fight"))
	assert_true(ev.any(func(e): return e.type == "standing" and int(e.delta) < 0))
	assert_true(a.remembers())


func test_everyone_down() -> void:
	var a := TownAlarm.new(cfg)
	a.raise("gate")
	var ev := _tick(a, DT, { "seen": true, "alive": 0 })
	assert_true(ev.any(func(e): return e.type == "calm" and e.why == "all_down"))
	assert_false(a.remembers(), "nobody left to remember")


func test_downed_player() -> void:
	var a := TownAlarm.new(cfg)
	a.raise("gate")
	a.stand_down()
	assert_false(a.active())
	assert_true(a.drain().any(func(e): return e.type == "calm" and e.why == "downed"))
	assert_true(a.remembers())


func test_escape_distance_beats_the_leash() -> void:
	# The alarm calms at disengage_dist from the nearest trooper, and no trooper
	# chases past its leash: running far enough really loses them.
	var yard: Dictionary = cc.get_soldier("yard_trooper")
	var gate: Dictionary = cc.get_soldier("gate_guard")
	var leash := maxf(float(yard.combat.chase_leash), float(gate.combat.chase_leash))
	assert_lt(float(cfg.disengage_dist), 120.0 - leash, "the desert is wide enough to get clear")


# ------------------------------------------------------------------ profiles

func test_profiles_inherit() -> void:
	var tower: Dictionary = cc.get_soldier("tower_sentry")
	var gate: Dictionary = cc.get_soldier("gate_guard")
	assert_eq(str(tower.role), "sentry")
	assert_eq(float(tower.perception.sight_range), 60.0, "its own longer eyes")
	assert_eq(float(tower.perception.eye_height), float(gate.perception.eye_height), "the rest from the gate guard")
	assert_true(bool(tower.combat.hold_ground))
	assert_eq(str(tower.weapon.base), "rifle_blaster")
	assert_eq(str(cc.get_soldier("yard_trooper").role), "yard")
	assert_false(cc.get_soldier("yard_trooper").combat.get("hold_ground", false))


func test_every_trooper_post_is_live() -> void:
	var t = TownLayout.new()
	t.load_town("port_town")
	for m in t.markers_with_role("trooper_post"):
		assert_true(m.has("soldier"), "%s has a soldier" % m.id)
		assert_false(cc.get_soldier(str(m.soldier)).is_empty())


# ------------------------------------------------------------------ brain

func _brain(id: String) -> GuardBrain:
	var b := GuardBrain.new(cc.get_soldier(id), 5)
	b.patrol_points = [Vector3(91, 12, 16)] if id == "tower_sentry" else [Vector3(95, 0, 9), Vector3(88, 0, 9)]
	b.pos = b.patrol_points[0]
	return b


func test_sentry_never_leaves_its_rim() -> void:
	var b := _brain("tower_sentry")
	b.visible = false
	b.alarm_pos = Vector3(60, 0, -20)
	b.engage()
	var farthest := 0.0
	for i in 60 * 10:
		b.update(DT)
		if b.go_to != Vector3.INF:
			b.pos = b.pos.move_toward(b.go_to, 2.0 * DT)
		farthest = maxf(farthest, Vector2(b.pos.x - 91, b.pos.z - 16).length())
	assert_lt(farthest, float(b.c("hold_radius", 2.3)) + 0.2, "up to the rim, no further")
	assert_gt(farthest, 1.0, "but it does step to the rim facing the trouble")


func test_troopers_do_not_chase_forever() -> void:
	var b := _brain("gate_guard")
	b.visible = false
	b.last_seen = Vector3(400, 0, 0)
	b.engage()
	b.want_cover = false
	b.cover = Vector3.INF
	var farthest := 0.0
	for i in 60 * 20:
		b.update(DT)
		if b.want_cover:
			b.want_cover = false
		if b.go_to != Vector3.INF:
			b.pos = b.pos.move_toward(b.go_to, 6.0 * DT)
		farthest = maxf(farthest, b.pos.distance_to(b.patrol_points[0]))
	assert_lte(farthest, float(b.c("chase_leash", 30.0)) + 0.5)
	assert_gt(farthest, 10.0, "they do push out after you")


func test_alarm_sighting_guides_the_blind() -> void:
	var b := _brain("yard_trooper")
	b.visible = false
	b.alarm_pos = Vector3(99, 0, 0)
	b.engage()
	b.want_cover = false
	b.cover = Vector3.INF
	for i in 60 * 5:
		b.update(DT)
		b.want_cover = false
	assert_eq(b.face, Vector3(99, 0, 0), "faces where the alarm says the player is")


# ------------------------------------------------------------------ smuggling plumbing

func test_contraband_item_and_fence() -> void:
	var it: Dictionary = cc.get_item("unmarked_cells")
	assert_true(bool(it.contraband))
	var fence: Dictionary = cc.get_vendor("fence")
	assert_eq(Inventory.sell_price(it, fence), int(it.value), "the fence pays full value")
	assert_eq(Inventory.sell_price(it, cc.get_vendor("gear_trader")), -1, "the gear trader will not touch it")


func test_cache_gives_several() -> void:
	var inv := Inventory.new()
	var cache: Dictionary = {}
	for p in cc.get_pickups("port_town"):
		if str(p.id) == "desert_cache":
			cache = p
	assert_false(cache.is_empty())
	assert_true(inv.pick_up(cache))
	assert_eq(inv.count("unmarked_cells"), int(cache.count))
	assert_false(inv.pick_up(cache), "once")


func test_inventory_panel_lists_and_tags() -> void:
	var saved = WorldState.inventory
	WorldState.inventory = Inventory.new()
	WorldState.inventory.add("unmarked_cells", 2)
	WorldState.inventory.add("jetpack")
	var panel := InventoryPanel.new()
	panel.content = cc
	add_child_autofree(panel)
	assert_false(panel.is_open())
	panel.toggle()
	assert_true(panel.is_open())
	assert_eq(panel.rows.size(), 2)
	var cells := panel.rows.filter(func(r): return r.begins_with("Unmarked"))
	assert_eq(cells.size(), 1)
	assert_true(cells[0].contains("x2") and cells[0].contains("CONTRABAND"))
	assert_false(panel.rows.filter(func(r): return r.begins_with("Jetpack"))[0].contains("CONTRABAND"))
	panel.toggle()
	assert_false(panel.is_open())
	assert_true(InputMap.has_action("inventory"), "bound in project.godot")
	var keys: Array = InputMap.action_get_events("inventory").map(func(e): return (e as InputEventKey).keycode)
	assert_true(keys.has(KEY_I), "on I")
	WorldState.inventory = saved
