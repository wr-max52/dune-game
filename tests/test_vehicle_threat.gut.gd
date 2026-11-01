extends GutTest
## Issue #55: bug fixes and hardening. A speeder ridden into town, or a ship lifting
## off in it, is hostile: the garrison watches it, raises the alarm and shoots its
## hull. The ship's guns work in the air (from the moment you sit down) and its
## hull takes bolts. At the desert outposts the troopers and droids fight the
## player in a speeder or ship as on foot. The cantina has fill light. (Solid props: test_town_decor.)

const TownDemo := preload("res://scenes/town_demo.gd")
const TownLayout := preload("res://src/systems/world/town_layout.gd")

const DT := 1.0 / 60.0


func before_each() -> void:
	WorldState.reset()
	WorldState.set_flag("ships_unlocked")      # issue #64: the story unlocks the ships


func after_each() -> void:
	WorldState.reset()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _town(brains: bool) -> Node:
	var t = TownDemo.new()
	t.use_look = false
	t.npc_brains = brains
	add_child_autofree(t)
	t._build_bar([ScriptedProvider.new("scripted_test")], "")
	t.speeder_post.attach_host(t.bar)
	return t


## Buy a speeder, climb on, and park it at `at` (one ride frame moves the player too).
func _ride_to(t, at: Vector3) -> SpeederNode:
	WorldState.credits = 100
	t.speeder_post.buy()
	var s: SpeederNode = t.speeder_post.speeders[0]
	t._player.global_position = s.model.position + Vector3(1.5, -1.0, 0)
	assert_true(s.mount(), "aboard")
	_move(s, at)
	return s


func _move(s: SpeederNode, at: Vector3) -> void:
	s.model.place(at, 0.0)
	s.set_external_command({ "throttle": 0.0 })
	s._physics_process(DT)


func _far_outside(t) -> Vector3:
	var b := TownNav.town_bounds(t.town)
	return Vector3(b.end.x + 400.0, 0.0, b.end.z + 400.0)


func _board(t) -> ShipPilot:
	var pilot: ShipPilot = t.pilot
	var v: Node3D = pilot.visual
	var c: float = pilot.berths[pilot.berth].clearance
	t._player.global_position = Vector3(v.global_position.x + 3.0, v.global_position.y - c, v.global_position.z)
	assert_true(pilot.board(), "in the seat")
	return pilot


# ---- the speeder ----------------------------------------------------------------

func test_a_speeder_is_hostile_in_town_only() -> void:
	var t = _town(false)
	var s := _ride_to(t, t.town.marker_pos("gate"))
	assert_eq(t._player.vehicle, s, "the player knows what they are riding")
	assert_true(s.hostile_in_town(), "ridden through the gate")
	_move(s, _far_outside(t))
	assert_false(s.hostile_in_town(), "nobody minds it out in the desert")
	s.dismount()
	assert_null(t._player.vehicle, "on foot again")


func test_the_garrison_targets_a_speeder_in_town() -> void:
	var t = _town(true)
	var g: Garrison = t.garrison
	var s := _ride_to(t, t.town.marker_pos("gate"))
	assert_eq(g._player_pos(), t._player.global_position, "the speeder is the target")
	var trooper: NpcBody = g.members[0]
	assert_eq(trooper.hostile_vehicle(), s, "troopers watch it")
	assert_eq(trooper.target_chest_height(), 0.0, "and aim at the hull")
	assert_true(g._is_player(s.hull), "its lasers count as the player's")
	_move(s, _far_outside(t))
	assert_eq(g._player_pos(), Vector3.INF, "outside town it is left alone")
	assert_null(trooper.hostile_vehicle())


func test_a_trooper_noticing_a_speeder_sounds_the_alarm() -> void:
	var t = _town(true)
	var g: Garrison = t.garrison
	_ride_to(t, t.town.marker_pos("gate"))
	assert_false(g.alarm.active())
	var trooper: NpcBody = g.members[0]
	trooper.perception.noticed = true
	g._physics_process(DT)
	assert_true(g.alarm.active(), "a speeder loose in town is a fight")
	assert_eq(g.alarm.why, "vehicle")


func test_townsfolk_do_not_watch_vehicles() -> void:
	var t = _town(true)
	for n in t.locals:
		assert_false((n as NpcBody).sees_vehicles, "%s is not a trooper" % n.name)
	for n in t.npcs:
		assert_true((n as NpcBody).sees_vehicles, "%s is" % n.name)


# ---- the ship ---------------------------------------------------------------------

func test_ship_guns_fire_from_the_pad() -> void:
	var t = _town(false)
	var pilot := _board(t)
	await wait_frames(1)
	assert_eq(t._player.vehicle, pilot)
	var before := t.get_tree().get_nodes_in_group("bolts").size()
	pilot.set_external_command({ "fire": true })
	pilot._physics_process(DT)
	assert_gt(pilot.shots, 0, "the cannons fire as soon as you sit down")
	assert_gt(t.get_tree().get_nodes_in_group("bolts").size(), before, "real bolts")
	assert_eq(pilot.atmo.state, AtmoFlight.State.PARKED, "still on the pad")


func test_ship_guns_fire_in_the_air() -> void:
	var t = _town(false)
	var pilot := _board(t)
	assert_true(pilot.takeoff())
	pilot.set_external_command({ "throttle": 0.0 })
	for i in 30:
		pilot._physics_process(DT)
	assert_eq(pilot.shots, 0, "no trigger, no bolts")
	pilot.set_external_command({ "throttle": 0.0, "fire": true })
	for i in 30:
		pilot._physics_process(DT)
	assert_gt(pilot.shots, 2, "a stream of bolts in the air")


func test_a_ship_lifting_off_in_town_is_hostile() -> void:
	var t = _town(false)
	var pilot := _board(t)
	assert_false(pilot.hostile_in_town(), "sitting on the pad is fine")
	assert_true(pilot.takeoff())
	assert_true(pilot.hostile_in_town(), "lifting off in town is not")


func test_the_ship_hull_takes_bolts_and_goes_down() -> void:
	var t = _town(false)
	var pilot: ShipPilot = t.pilot
	pilot.hull.apply_damage(50.0)
	assert_eq(pilot.defense.hull_hp(), pilot.defense.hull_max(), "an empty parked ship keeps no score")
	_board(t)
	assert_true(pilot.takeoff())
	var shield: float = pilot.defense.shield
	# What bolt.gd does with the collider it hit.
	pilot.hull.apply_damage(10.0)
	assert_lt(pilot.defense.shield, shield, "the shield takes it first")
	pilot.hull.apply_damage(9999.0)
	assert_eq(pilot.atmo.state, AtmoFlight.State.CRASHED, "shot down")
	assert_gt(pilot.crash_left, 0.0, "and towed home like a crash")


# ---- at the outposts ----------------------------------------------------------------
# Out in the desert a speeder or ship is no offence by itself, but an outpost's
# troopers and droids fight the player in one as they would on foot.

func _outpost(t) -> Dictionary:
	assert_not_null(t.outposts, "the town builds the outposts")
	var o: Dictionary = t.outposts.outposts[0]
	assert_true(t.outposts.garrisons.has(str(o.id)), "with a garrison of its own")
	return o


func test_an_outpost_garrison_targets_a_speeder_out_there() -> void:
	var t = _town(true)
	var o := _outpost(t)
	var og: Garrison = t.outposts.garrisons[str(o.id)]
	var s := _ride_to(t, o.origin + Vector3(12.0, 0.0, 0.0))
	assert_false(s.hostile_in_town(), "out in the desert")
	assert_eq(og.target_vehicle(), s, "the outpost fights the speeder")
	assert_eq(og._player_pos(), t._player.global_position, "it carries the player's position")
	var trooper: NpcBody = og.members[0]
	assert_eq(trooper.hostile_vehicle(), s, "troopers watch it")
	assert_eq(trooper.target_chest_height(), 0.0, "and aim at the hull")
	assert_null(t.garrison.target_vehicle(), "the town's garrison does not mind it out here")
	s.dismount()
	assert_null(og.target_vehicle(), "on foot again")


func test_a_speeder_at_an_outpost_is_no_alarm_by_itself() -> void:
	var t = _town(true)
	var o := _outpost(t)
	var og: Garrison = t.outposts.garrisons[str(o.id)]
	_ride_to(t, o.origin + Vector3(12.0, 0.0, 0.0))
	var trooper: NpcBody = og.members[0]
	trooper.perception.noticed = true
	og._physics_process(DT)
	assert_false(og.alarm.active(), "riding past is not a fight")


func test_outpost_troopers_shoot_back_at_a_speeder() -> void:
	var t = _town(true)
	var o := _outpost(t)
	var og: Garrison = t.outposts.garrisons[str(o.id)]
	var s := _ride_to(t, o.origin + Vector3(12.0, 0.0, 0.0))
	og._on_guard_hit(s.hull, 10.0, og.members[0])
	og._physics_process(DT)
	assert_true(og.alarm.active(), "shot at from the speeder: a fight")
	for g in og._alive():
		var b: GuardBrain = og.brains[g]
		assert_eq(b.state, GuardBrain.State.COMBAT, "%s fights" % g.name)
		assert_eq(b.target_pos, t._player.global_position, "%s has the speeder to shoot at" % g.name)


func test_an_outpost_garrison_targets_a_ship() -> void:
	var t = _town(true)
	var o := _outpost(t)
	var og: Garrison = t.outposts.garrisons[str(o.id)]
	var pilot := _board(t)
	assert_true(pilot.targetable(), "sat in on the pad")
	assert_eq(og.target_vehicle(), pilot, "the outpost fights the ship")
	assert_null(t.garrison.target_vehicle(), "parked in town it is no threat to the town")
	assert_true(pilot.takeoff())
	assert_eq(og.target_vehicle(), pilot, "and in the air")


func test_outpost_droids_aim_at_the_speeder() -> void:
	var t = _town(true)
	if t.droids == null:
		pending("no droids in this town")
		return
	var o := _outpost(t)
	var bots: Array = t.droids.remnant.filter(func(u): return str(u.spec.get("outpost", "")) == str(o.id))
	assert_false(bots.is_empty(), "the outpost has droids")
	var s := _ride_to(t, o.origin + Vector3(12.0, 0.0, 0.0))
	assert_eq(t.droids._vehicle_hull(bots[0]), s.hull, "its droids shoot the hull")
	s.dismount()
	assert_null(t.droids._vehicle_hull(bots[0]), "on foot they aim at you")


# ---- the cantina ------------------------------------------------------------------

func test_the_cantina_has_fill_light() -> void:
	var town := TownLayout.new()
	assert_true(town.load_town("port_town"))
	var d := CantinaDressing.new()
	add_child_autofree(d)
	d.dress(town, LookMaterials.new())
	assert_eq(d.fills.size(), 4, "a fill light over each quarter of the room")
	var w: Dictionary = town.get_box("cantina_wall_w")
	var e: Dictionary = town.get_box("cantina_wall_e_s")
	for l in d.fills:
		assert_gt(l.light_energy, 0.0, "on by day too")
		assert_between(l.position.x, float(w.max[0]), float(e.min[0]), "inside the room")
		assert_gt(l.omni_range, 10.0, "reaches the corners")
