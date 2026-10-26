extends GutTest
## The demo flow: start in the town beside your ship, press E on the pit pad, fly
## the pad's encounter, and land back beside the ship when the fight ends.
## M14: the pad no longer quick-launches in the town (you fly the ship up; see the
## tests at the end and tests/test_m14_flight.gut.gd), but the pad's launch path,
## range and arrival toast are still the hand-off GameFlow uses.
## GameFlow.change_scene is swapped for a recorder so no test ever replaces the
## GUT scene tree.

const TownDemo := preload("res://scenes/town_demo.gd")
const Demo := preload("res://scenes/flight/dogfight_demo.gd")
const TOWN := "res://scenes/town_demo.tscn"
const FLIGHT := "res://scenes/flight/dogfight_demo.tscn"

var went: Array = []


func before_each() -> void:
	GameFlow.reset()
	went = []
	GameFlow.change_scene = func(path: String) -> void: went.append(path)


func after_each() -> void:
	GameFlow.reset()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _town() -> Node:
	var scene = TownDemo.new()
	scene.use_look = false   # flow does not need the look layer; keeps tests fast
	add_child_autofree(scene)
	return scene


func test_pad_data_points_at_real_scenes_and_encounter() -> void:
	var p := GameFlow.pad("town_pit")
	assert_false(p.is_empty(), "the town pit pad exists")
	assert_eq(str(p.scene), TOWN)
	assert_true(ResourceLoader.exists(TOWN), "town scene exists")
	assert_true(ResourceLoader.exists(str(GameFlow.data().flight_scene)), "flight scene exists")
	var content = preload("res://src/systems/dataload/core_content.gd").new()
	content.load_from()
	assert_true(content.encounters.has(str(p.encounter)), "the pad's encounter is real content")
	assert_true(InputMap.has_action("interact"), "E is bound to interact")


func test_main_scene_is_the_town() -> void:
	assert_eq(ProjectSettings.get_setting("application/run/main_scene"), TOWN,
		"pressing Play starts the one demo: the town")


func test_pad_sits_on_the_ship_in_the_pit() -> void:
	var t = _town()
	assert_eq(t.pads.size(), 1, "one launch pad")
	var ship: Dictionary = t.town.get_box("ship")
	var pad: Node3D = t.pads[0]
	assert_almost_eq(pad.global_position.x, (float(ship.min[0]) + float(ship.max[0])) * 0.5, 0.01)
	assert_almost_eq(pad.global_position.z, (float(ship.min[2]) + float(ship.max[2])) * 0.5, 0.01)
	assert_almost_eq(pad.global_position.y, -6.0, 0.01, "on the pit floor")


func test_spawn_is_in_range_and_the_rim_is_not() -> void:
	var t = _town()
	var pad = t.pads[0]
	assert_true(pad.is_player_in_range(), "you start beside your ship, so the prompt is up")
	t._player.global_position = Vector3(40.0, 0.05, 0.0)
	assert_false(pad.is_player_in_range(), "out in the street is not")
	t._player.global_position = Vector3(0.0, 4.0, 0.0)
	assert_false(pad.is_player_in_range(), "standing high above the pit is not")


func test_launch_hands_the_encounter_to_the_flight_scene() -> void:
	var t = _town()
	var pad = t.pads[0]
	pad.fade_time = 0.0
	assert_true(pad.launch(), "launch starts")
	assert_false(pad.launch(), "and cannot double-fire")
	assert_eq(went, [FLIGHT], "the flight scene is loaded")
	assert_true(GameFlow.in_flight)
	assert_eq(GameFlow.encounter_id, "orbital_skirmish")
	assert_eq(GameFlow.return_scene, TOWN)


func test_flight_returns_to_town_after_the_fight() -> void:
	GameFlow.launch(null, GameFlow.pad("town_pit"))
	went.clear()
	var demo = Demo.new()
	demo.autopilot = true
	add_child_autofree(demo)
	assert_eq(demo.encounter_id, "orbital_skirmish", "flies the pad's encounter")
	demo._on_event({ "type": "complete", "payout": 250 })
	assert_gte(demo.return_left, 0.0, "a return is queued")
	demo._tick_return(GameFlow.setting("return_delay", 4.0) + 0.1)
	assert_eq(went, [TOWN], "back to the town")
	assert_false(GameFlow.in_flight)
	assert_eq(int(GameFlow.arrival.payout), 250)


func test_standalone_dogfight_never_leaves() -> void:
	var demo = Demo.new()
	demo.autopilot = true
	add_child_autofree(demo)
	demo._on_event({ "type": "complete", "payout": 250 })
	assert_lt(demo.return_left, 0.0, "F6 on the dogfight stays in the dogfight")
	assert_false(GameFlow.finish_flight(null, "complete", 1), "nothing to finish")
	assert_eq(went, [], "no scene change")


func test_arrival_lands_beside_the_ship_facing_it() -> void:
	GameFlow.launch(null, GameFlow.pad("town_pit"))
	GameFlow.finish_flight(null, "complete", 250)
	var t = _town()
	var arrive: Vector3 = t.town.marker_pos("player_spawn")
	assert_almost_eq(t._player.global_position.distance_to(arrive + Vector3(0, 0.05, 0)), 0.0, 0.01, "at the arrive marker")
	var look: Vector3 = t._rig.rig.look_direction()
	var to_ship: Vector3 = t.pads[0].global_position - arrive
	assert_gt(Vector2(look.x, look.z).normalized().dot(Vector2(to_ship.x, to_ship.z).normalized()), 0.95, "facing the ship")
	assert_true(GameFlow.take_arrival().is_empty(), "arrival is consumed once")
	assert_true(t.pads[0]._toast.visible, "the outcome is shown")
	assert_true(t.pads[0]._toast.text.contains("250"), "with the payout")


func test_walking_from_the_rim_down_the_ramp_reaches_the_pad() -> void:
	# Real collision: start on the rim at the top of the NE ramp, walk down it, then
	# toward the ship. The prompt must come up and nobody falls through.
	var t = _town()
	var pad = t.pads[0]
	var ramp: Dictionary = t.town.get_box("ramp_ne")
	var mid_z := (float(ramp.min[2]) + float(ramp.max[2])) * 0.5
	var path := [
		Vector3(float(ramp.min[0]) + 0.5, 0.0, mid_z),   # bottom of the ramp
		t.town.spawn_pos(),                               # beside the ship
	]
	t._player.global_position = Vector3(float(ramp.max[0]) + 1.0, 0.05, mid_z)
	t._player.velocity = Vector3.ZERO
	t._player.controller.velocity = Vector3.ZERO
	await wait_physics_frames(2)
	assert_false(pad.is_player_in_range(), "the rim is off the pad")
	var wp := 0
	for i in 900:
		var p: Vector3 = t._player.global_position
		var to := Vector2(path[wp].x - p.x, path[wp].z - p.z)
		if to.length() < 0.75:
			wp = mini(wp + 1, path.size() - 1)
		t._player.rotation.y = 0.0
		t._player.set_command(to.normalized(), true, false, false)
		await wait_physics_frames(1)
		if pad.is_player_in_range():
			break
	assert_true(pad.is_player_in_range(), "walking down the ramp reaches the pad (at %s)" % t._player.global_position)
	assert_gt(t._player.global_position.y, -6.5, "and never fell through")


# ---- M14: fly up, fall back ----------------------------------------------------

func test_town_ship_replaces_the_quick_launch() -> void:
	var t = _town()
	assert_not_null(t.pilot, "the pit's ship is flyable")
	assert_false(t.pads[0].quick_launch, "E boards the ship; the pad no longer launches")
	assert_eq(t.pilot.atmo.state, AtmoFlight.State.PARKED)


func test_ascent_hands_the_pad_encounter_to_space() -> void:
	GameFlow.ascend(null, GameFlow.pad("town_pit"))
	assert_eq(went, [FLIGHT])
	assert_eq(GameFlow.mode, "ascent")
	assert_eq(GameFlow.encounter_id, "orbital_skirmish")


func test_a_won_fight_after_an_ascent_reenters_the_sky() -> void:
	GameFlow.ascend(null, GameFlow.pad("town_pit"))
	went.clear()
	var demo = Demo.new()
	demo.autopilot = true
	add_child_autofree(demo)
	demo._on_event({ "type": "complete", "payout": 250 })
	assert_almost_eq(demo.return_left, GameFlow.setting("reentry_delay", 25.0), 0.001,
		"time to dive down yourself first")
	demo._tick_return(GameFlow.setting("reentry_delay", 25.0) + 0.1)
	assert_eq(went, [TOWN])
	assert_eq(str(GameFlow.arrival.mode), "reentry")
	assert_eq(int(GameFlow.arrival.payout), 250)


func test_a_lost_ship_after_an_ascent_still_limps_to_the_pad() -> void:
	GameFlow.ascend(null, GameFlow.pad("town_pit"))
	var demo = Demo.new()
	demo.autopilot = true
	add_child_autofree(demo)
	demo._on_event({ "type": "failed" })
	demo._tick_return(GameFlow.setting("return_delay", 4.0) + 0.1)
	assert_eq(str(GameFlow.arrival.mode), "pad")


func test_reentry_arrival_starts_in_the_cockpit() -> void:
	GameFlow.ascend(null, GameFlow.pad("town_pit"))
	GameFlow.finish_flight(null, "left", 0, "reentry")
	var t = _town()
	assert_true(t.pilot.piloting, "seated")
	assert_eq(t.pilot.atmo.state, AtmoFlight.State.FLYING)
	assert_gt(t.pilot.atmo.altitude(), 4000.0, "high above the port")
	assert_eq(GameFlow.arrival_text({ "mode": "reentry", "outcome": "left" }), GameFlow.label("arrive_reentry"))
