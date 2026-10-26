extends GutTest
## Port <-> flight flow: walk to the port's landing bay, press E, fly the pad's
## encounter, and come back to the bay when the fight ends.
## GameFlow.change_scene is swapped for a recorder so no test ever replaces the
## GUT scene tree.

const BeautyCorner := preload("res://scenes/lookdev/beauty_corner.gd")
const Demo := preload("res://scenes/flight/dogfight_demo.gd")
const PORT := "res://scenes/lookdev/beauty_corner.tscn"
const FLIGHT := "res://scenes/flight/dogfight_demo.tscn"

var went: Array = []


func before_each() -> void:
	GameFlow.reset()
	went = []
	GameFlow.change_scene = func(path: String) -> void: went.append(path)


func after_each() -> void:
	GameFlow.reset()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _port() -> Node:
	var scene = BeautyCorner.new()
	scene.terrain_resolution = 48
	add_child_autofree(scene)
	return scene


func test_pad_data_points_at_real_scenes_and_encounter() -> void:
	var p := GameFlow.pad("port_landing_bay")
	assert_false(p.is_empty(), "the landing bay pad exists")
	assert_eq(str(p.scene), PORT)
	assert_true(ResourceLoader.exists(PORT), "port scene exists")
	assert_true(ResourceLoader.exists(str(GameFlow.data().flight_scene)), "flight scene exists")
	var content = preload("res://src/systems/dataload/core_content.gd").new()
	content.load_from()
	assert_true(content.encounters.has(str(p.encounter)), "the pad's encounter is real content")
	assert_true(InputMap.has_action("interact"), "E is bound to interact")


func test_main_scene_is_the_port() -> void:
	assert_eq(ProjectSettings.get_setting("application/run/main_scene"), PORT,
		"pressing Play starts on foot in the port")


func test_port_builds_a_pad_and_parks_the_ship_on_it() -> void:
	var port = _port()
	assert_eq(port.pads.size(), 1, "one launch pad in play mode")
	assert_eq(port.parked_ships.size(), 1, "a ship is parked on the pad")
	var pad = port.pads[0]
	var c := GameFlow.vec(GameFlow.pad("port_landing_bay").center)
	assert_almost_eq(pad.global_position.distance_to(c), 0.0, 0.01, "pad sits on the landing bay")
	assert_lt(Vector2(port.parked_ships[0].global_position.x - c.x, port.parked_ships[0].global_position.z - c.z).length(), 1.0,
		"ship is on the bay")


func test_lookdev_mode_has_the_ship_but_no_trigger() -> void:
	var scene = BeautyCorner.new()
	scene.lookdev_mode = true
	scene.terrain_resolution = 48
	add_child_autofree(scene)
	assert_eq(scene.pads.size(), 0, "review cameras never launch anything")
	assert_eq(scene.parked_ships.size(), 1, "review shots match play")


func test_pad_only_triggers_near_the_bay() -> void:
	var port = _port()
	var pad = port.pads[0]
	assert_false(pad.is_player_in_range(), "the default spawn is far from the bay")
	port._player.global_position = Vector3(40.0, 8.05, -40.0)
	assert_true(pad.is_player_in_range(), "standing on the bay is in range")
	port._player.global_position = Vector3(40.0, 30.0, -40.0)
	assert_false(pad.is_player_in_range(), "flying over it is not")


func test_launch_hands_the_encounter_to_the_flight_scene() -> void:
	var port = _port()
	var pad = port.pads[0]
	pad.fade_time = 0.0
	port._player.global_position = Vector3(40.0, 8.05, -40.0)
	assert_true(pad.launch(), "launch starts")
	assert_false(pad.launch(), "and cannot double-fire")
	assert_eq(went, [FLIGHT], "the flight scene is loaded")
	assert_true(GameFlow.in_flight)
	assert_eq(GameFlow.encounter_id, "orbital_skirmish")
	assert_eq(GameFlow.return_scene, PORT)


func test_flight_returns_to_port_after_the_fight() -> void:
	GameFlow.launch(null, GameFlow.pad("port_landing_bay"))
	went.clear()
	var demo = Demo.new()
	demo.autopilot = true
	add_child_autofree(demo)
	assert_eq(demo.encounter_id, "orbital_skirmish", "flies the pad's encounter")
	demo._on_event({ "type": "complete", "payout": 250 })
	assert_gte(demo.return_left, 0.0, "a return is queued")
	demo._tick_return(GameFlow.setting("return_delay", 4.0) + 0.1)
	assert_eq(went, [PORT], "back to the port it left from")
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


func test_arrival_spawns_beside_the_pad_facing_it() -> void:
	GameFlow.launch(null, GameFlow.pad("port_landing_bay"))
	GameFlow.finish_flight(null, "complete", 250)
	var port = _port()
	var p := GameFlow.pad("port_landing_bay")
	var arrive := GameFlow.vec(p.arrive)
	assert_almost_eq(port._player.global_position.distance_to(arrive), 0.0, 0.01, "spawned at the arrive point")
	var look: Vector3 = port._rig.rig.look_direction()
	var to_pad := (GameFlow.vec(p.center) - arrive)
	to_pad.y = 0.0
	assert_gt(Vector2(look.x, look.z).normalized().dot(Vector2(to_pad.x, to_pad.z).normalized()), 0.95, "facing the pad")
	assert_true(GameFlow.take_arrival().is_empty(), "arrival is consumed once")
	assert_true(port.pads[0]._toast.visible, "the outcome is shown")
	assert_true(port.pads[0]._toast.text.contains("250"), "with the payout")


func test_walking_from_the_arrive_point_reaches_the_pad() -> void:
	# Real collision: walk +X from the arrive point and the prompt must come up
	# before anything (the bay's curb, a house) stops the player.
	GameFlow.launch(null, GameFlow.pad("port_landing_bay"))
	GameFlow.finish_flight(null, "complete", 0)
	var port = _port()
	var pad = port.pads[0]
	assert_false(pad.is_player_in_range(), "arrive point is just off the pad")
	for i in 240:
		port._player.set_command(Vector2(0, 1), false, false, false)
		await wait_physics_frames(1)
		if pad.is_player_in_range():
			break
	assert_true(pad.is_player_in_range(), "walking forward reaches the pad (at %s)" % port._player.global_position)
