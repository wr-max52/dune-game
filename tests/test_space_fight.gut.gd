extends GutTest
## Issue #46: flying out of the atmosphere stays in the town scene. The pad's
## encounter (SpaceFight) starts around the ship, can be switched off (the dogfight
## toggle), and ends three ways: won (paid), lost (towed home), or broken off by
## diving back below the edge. Altitude tiers cut render and CI cost on the way up.
## The full climb, fight and dive are in tests/test_m14_flight.gut.gd (the trace).

const TownDemo := preload("res://scenes/town_demo.gd")
const Dogfight := preload("res://src/systems/flight/dogfight.gd")

var went: Array = []


func before_each() -> void:
	GameFlow.reset()
	WorldState.reset()
	WorldState.set_flag("ships_unlocked")      # issue #64: the story unlocks the ships
	went = []
	GameFlow.change_scene = func(path: String) -> void: went.append(path)


func after_each() -> void:
	GameFlow.reset()
	WorldState.reset()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _town() -> Node:
	var scene = TownDemo.new()
	scene.use_look = false
	scene.npc_brains = false
	add_child_autofree(scene)
	return scene


## Board, lift off, and put the ship just past the edge of space, flying.
func _in_space(t) -> ShipPilot:
	var pilot: ShipPilot = t.pilot
	t._player.global_position = t.town.spawn_pos()
	assert_true(pilot.board(), "boards from the spawn")
	pilot.set_external_command({ "throttle": 0.6 })
	var c: Vector3 = pilot.pad.center
	pilot.atmo.place_flying(Vector3(c.x, pilot.atmo.space_altitude - 20.0, c.z), Vector3(0.3, 0.6, -1).normalized(), 200.0, 0.6)
	return pilot


func _step(pilot: ShipPilot, n: int) -> void:
	for i in n:
		pilot._physics_process(1.0 / 60.0)


# ---- placing the encounter -------------------------------------------------------

func test_the_encounter_is_moved_onto_the_ship() -> void:
	var enc := {
		"player": { "spawn": [0, 0, 0], "facing": [0, 0, -1] },
		"allies": [{ "spawn": [60, 12, 40], "facing": [0, 0, -1] }],
		"arena": { "center": [0, 0, 0], "radius": 1600.0 },
	}
	var at := Vector3(500, 4100, -300)
	var out := SpaceFight.placed(enc, at, PI * 0.5)
	assert_eq(Dogfight._vec(out.player.spawn), at, "the player spawn lands on the ship")
	assert_eq(Dogfight._vec(out.arena.center), at, "the arena is centred on it")
	var ally := Dogfight._vec(out.allies[0].spawn)
	assert_almost_eq(ally.distance_to(at), Vector3(60, 12, 40).length(), 0.01, "the wingman keeps his distance")
	assert_almost_eq(ally, at + Vector3(60, 12, 40).rotated(Vector3.UP, PI * 0.5), Vector3.ONE * 0.01, "turned with the ship's heading")
	assert_almost_eq(Dogfight._vec(out.allies[0].facing), Vector3(0, 0, -1).rotated(Vector3.UP, PI * 0.5), Vector3.ONE * 0.01)
	assert_eq(Dogfight._vec(enc.player.spawn), Vector3.ZERO, "the content's own encounter is untouched")


func test_waves_arrive_ahead_of_the_heading() -> void:
	var cc = load("res://src/systems/dataload/core_content.gd").new()
	cc.load_from()
	var f := SpaceFight.new()
	add_child_autofree(f)
	# Heading +X: yaw -90 degrees (the ship looks down -Z at yaw 0).
	var at := Transform3D(Basis.looking_at(Vector3.RIGHT, Vector3.UP), Vector3(0, 4100, 0))
	assert_true(f.begin(cc, "orbital_skirmish", at, 250.0))
	for i in 60 * 3:
		f.step(1.0 / 60.0, { "throttle": 0.0 })
	var hostiles: Array = f.df.alive_on(Dogfight.TEAM_HOSTILE)
	assert_gt(hostiles.size(), 0, "the first wave is in")
	for h in hostiles:
		assert_gt(h.flight.position.x, 300.0, "raiders come from ahead (+X), not from the north")


func test_an_unknown_encounter_starts_nothing() -> void:
	var cc = load("res://src/systems/dataload/core_content.gd").new()
	cc.load_from()
	var f := SpaceFight.new()
	add_child_autofree(f)
	assert_false(f.begin(cc, "no_such_fight", Transform3D(), 100.0))


# ---- the toggle --------------------------------------------------------------------

func test_the_dogfight_toggle_defaults_on_and_switches() -> void:
	assert_true(GameFlow.space_dogfight(), "on by default (launch_pads.json)")
	GameFlow.set_space_dogfight(false)
	assert_false(GameFlow.space_dogfight())
	GameFlow.reset()
	assert_true(GameFlow.space_dogfight(), "reset goes back to the data")


func test_reaching_space_starts_the_fight_in_the_town() -> void:
	var t = _town()
	var pilot := _in_space(t)
	_step(pilot, 120)
	assert_not_null(pilot.fight, "the pad's encounter starts")
	assert_eq(pilot.fight.get_parent(), t, "in the town scene")
	assert_eq(went, [], "and no scene change")
	assert_eq(pilot.fight.encounter_id, "orbital_skirmish")


func test_toggle_off_reaching_space_is_just_sky() -> void:
	GameFlow.set_space_dogfight(false)
	var t = _town()
	var pilot := _in_space(t)
	_step(pilot, 120)
	assert_true(pilot.atmo.reached_space, "out of the atmosphere")
	assert_null(pilot.fight, "with the toggle off, nobody shows up")
	assert_eq(pilot.atmo.state, AtmoFlight.State.FLYING, "still flying")
	assert_eq(went, [])


# ---- three ways out --------------------------------------------------------------

func test_winning_pays_and_keeps_you_flying() -> void:
	var t = _town()
	var pilot := _in_space(t)
	_step(pilot, 120)
	var credits := WorldState.credits
	var where := pilot.atmo.position()
	pilot.end_fight("complete")
	assert_null(pilot.fight)
	assert_eq(WorldState.credits, credits + 1000, "the encounter's payout")
	assert_true(WorldState.has_flag("remnant_patrol_beaten"), "the town hears about it")
	assert_eq(pilot.atmo.state, AtmoFlight.State.FLYING, "you fly on from where the fight left you")
	assert_almost_eq(pilot.atmo.position(), where, Vector3.ONE * 0.01)
	assert_eq(pilot.fight_log.back().outcome, "complete")


func test_losing_tows_the_ship_home() -> void:
	var t = _town()
	var pilot := _in_space(t)
	_step(pilot, 120)
	var credits := WorldState.credits
	pilot.end_fight("failed")
	assert_eq(pilot.atmo.state, AtmoFlight.State.CRASHED)
	assert_eq(WorldState.credits, credits, "no payout")
	assert_true(WorldState.has_flag("ship_limped_home"))
	_step(pilot, int(60 * (ShipPilot.CRASH_TOW_TIME + 0.5)))
	assert_true(pilot.is_parked_home(), "towed back to the pad")
	assert_false(pilot.piloting, "and you are on foot beside it")


func test_diving_out_breaks_off_and_rearms() -> void:
	var t = _town()
	var pilot := _in_space(t)
	_step(pilot, 120)
	assert_not_null(pilot.fight)
	var credits := WorldState.credits
	# Straight down, below the edge by more than the margin.
	var p := pilot.atmo.position()
	pilot.fight.player_flight().position = Vector3(p.x, pilot.atmo.space_altitude - pilot.space_exit_margin - 50.0, p.z)
	_step(pilot, 2)
	assert_null(pilot.fight, "broken off")
	assert_eq(pilot.fight_log.back().outcome, "left")
	assert_eq(WorldState.credits, credits, "no payout")
	assert_false(WorldState.has_flag("ship_limped_home"), "nothing to limp home from")
	assert_eq(pilot.atmo.state, AtmoFlight.State.FLYING)
	assert_false(pilot.atmo.reached_space, "the next climb out is a new sortie")


# ---- detail by altitude --------------------------------------------------------------

func test_detail_tiers_climb_and_come_back_with_hysteresis() -> void:
	var d := AltitudeDetail.new()
	d.setup({ "hysteresis": 40.0, "tiers": [
		{ "above": 60.0, "off": ["sdfgi"] },
		{ "above": 500.0, "off": ["ssao"], "hide": ["people"] },
	] })
	add_child_autofree(d)
	assert_eq(d.tier_for(10.0, -1), -1)
	assert_eq(d.tier_for(70.0, -1), 0)
	assert_eq(d.tier_for(510.0, 0), 1)
	assert_eq(d.tier_for(480.0, 1), 1, "just under the edge: hold the tier")
	assert_eq(d.tier_for(450.0, 1), 0, "40 m under: let go")
	assert_eq(d.tier_for(30.0, 0), 0, "inside the 40 m of hysteresis: still holding")
	assert_eq(d.tier_for(15.0, 0), -1)


func test_detail_hides_and_pauses_groups() -> void:
	var d := AltitudeDetail.new()
	d.setup({ "tiers": [{ "above": 500.0, "off": [], "hide": ["people"] }] })
	add_child_autofree(d)
	var body := Node3D.new()
	var brain := Node.new()
	add_child_autofree(body)
	add_child_autofree(brain)
	d.add_group("people", [body, brain, null])
	d.update_for(600.0)
	assert_false(body.visible, "hidden")
	assert_eq(brain.process_mode, Node.PROCESS_MODE_DISABLED, "and not running")
	d.update_for(0.0)
	assert_true(body.visible)
	assert_eq(brain.process_mode, Node.PROCESS_MODE_INHERIT)


func test_detail_switches_render_features_off_and_back() -> void:
	var look := LookEnvironment.new()
	add_child_autofree(look)
	look.apply("noon")
	assert_true(look.env.sdfgi_enabled, "the preset wants GI")
	look.set_suppressed(["sdfgi", "shadows"])
	assert_false(look.env.sdfgi_enabled)
	assert_false(look.sun.shadow_enabled)
	look.apply("dusk")
	assert_false(look.env.sdfgi_enabled, "a new preset (L) does not bring it back mid-flight")
	look.set_suppressed([])
	assert_true(look.env.sdfgi_enabled)
	assert_true(look.sun.shadow_enabled)


func test_the_town_registers_people_and_props() -> void:
	var t = _town()
	assert_not_null(t.detail)
	assert_true(t.detail.groups.has("people"))
	assert_gt(t.detail.tiers.size(), 0, "tiers come from the world data")
