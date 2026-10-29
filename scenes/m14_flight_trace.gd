extends SceneTree
## M14 trace (headless): the whole loop, town -> sky -> space -> sky -> town, with
## real physics and the real scene. Writes test_results/m14_flight_trace.txt
## (KEY=value lines) for tests/test_m14_flight.gut.gd.
##
##   1. Board the ship in the pit, lift off, climb out of the atmosphere (timed).
##   2. Issue #46: space is the town's own sky. The pad's fight starts around the
##      ship, in this scene (no scene change, no jump); a bot flies and shoots for
##      a while, then dives back below the edge, which breaks the fight off.
##   3. Still flying, over the same ground. Fly a circuit over the town and the
##      desert, land in the desert, get out, walk, get back in.
##   4. Fly into a mesa: crash, the ship is towed to its pad, you stand beside it.
##      (The trace runs in the greybox, where the desert's landforms are not built;
##      it adds their columns to the ship's ground as the look build does.)
##   5. Take off again, fly back over the town, land on the pad, get out.
##
## A bot flies (the M10 fighter brain's steering, fed through ShipPilot's
## set_external_command), so the flight model, collision and hand-offs are the
## real ones. GameFlow.change_scene records scene changes instead of making them.
##
## Run: godot --headless --fixed-fps 60 --path . -s res://scenes/m14_flight_trace.gd

const OUT := "res://test_results/m14_flight_trace.txt"
const TOWN := "res://scenes/town_demo.tscn"
const FighterBrain := preload("res://src/systems/ai/fighter_brain.gd")
const Dogfight := preload("res://src/systems/flight/dogfight.gd")
const PerfTrace := preload("res://src/systems/diagnostics/performance_trace.gd")

var demo
var pilot: ShipPilot
var player
var lines := PackedStringArray()
var went: Array = []
var worst_ms := 0.0
var _last := 0
var _frames := 0
var _measure := false
var _phase := "setup"
var phase_worst := {}
var _perf := PerfTrace.new()
var scene_ready_ms: Array[float] = []


func _initialize() -> void:
	WorldState.reset()
	WorldState.set_flag("ships_unlocked")      # issue #64: the story unlocks the ships
	GameFlow.reset()
	GameFlow.change_scene = func(path: String) -> void: went.append(path)
	_run()


func _process(_d: float) -> bool:
	var now := Time.get_ticks_usec()
	if _measure:
		_perf.sample(_d, _phase)
	if _measure and _last > 0:
		var ms := (now - _last) / 1000.0
		worst_ms = maxf(worst_ms, ms)
		phase_worst[_phase] = maxf(float(phase_worst.get(_phase, 0.0)), ms)
	_last = now
	_frames += 1
	return false


func out(k: String, v) -> void:
	lines.append("%s=%s" % [k, str(v)])


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func make_town() -> void:
	if demo != null:
		demo.queue_free()
		await frames(2)
	demo = load("res://scenes/town_demo.gd").new()
	demo.npc_brains = false   # M15: guards hold their posts; this trace is about something else
	demo.use_look = OS.get_environment("DUNE_PERF_VISUALS") == "1"
	var ready_started := Time.get_ticks_usec()
	get_root().add_child(demo)
	scene_ready_ms.append((Time.get_ticks_usec() - ready_started) / 1000.0)
	await frames(5)
	pilot = demo.pilot
	player = demo._player


func _terrain_performance() -> Dictionary:
	if demo != null and is_instance_valid(demo) and demo.terrain != null and demo.terrain.has_method("performance_snapshot"):
		return demo.terrain.performance_snapshot()
	return {}


func place_player(p: Vector3) -> void:
	player.global_position = p + Vector3(0, 0.05, 0)
	player.velocity = Vector3.ZERO
	player.controller.velocity = Vector3.ZERO
	player.controller.body_pos = player.global_position


## Steer toward `point` like the dogfight AI does, for up to `max_s` seconds or
## until `done` returns true. Returns the seconds flown, -1 on a timeout.
func fly_to(point: Vector3, throttle: float, max_s: float, done: Callable, boost: bool = false) -> float:
	var b = FighterBrain.new({ "steer_gain": 3.0 }, pilot.atmo.flight, 1)
	for i in int(max_s * 60.0):
		b._steer_to(point, throttle, boost)
		pilot.set_external_command(b.command)
		await physics_frame
		if pilot.atmo.state == AtmoFlight.State.CRASHED:
			return -2.0
		if done.call():
			return i / 60.0
	return -1.0


func _run() -> void:
	# ---------------------------------------------------------------- 1. up
	_phase = "up"
	await make_town()
	pilot.ground.add_landforms(DesertLandforms.load_data(), demo.desert_site().floor)
	out("DESERT_BUILT", demo.terrain != null and pilot.scenery != null)
	out("GROUND_IS_THE_DESERT", absf(pilot.ground.terrain.height_at(700, 500) - demo.terrain.height_at(700, 500)) < 0.001)
	out("DESERT_EXTENT", int(pilot.ground.terrain.extent))
	out("COLLIDER_FOLLOWS_PLAYER_ON_FOOT", demo.terrain._target == player)
	out("OUTPOST_BUILDINGS", pilot.ground.boxes.filter(func(b): return str(b.id).begins_with("outpost/")).size())
	out("PAD_QUICK_LAUNCH", demo.pads[0].quick_launch)
	out("SHIP_STATE_START", pilot.atmo.state_label())
	out("SHIP_AT_HOME", pilot.is_parked_home())
	out("CAN_BOARD_FROM_SPAWN", pilot.can_board())
	place_player(Vector3(40, 0, 0))
	await frames(3)
	out("CAN_BOARD_FROM_STREET", pilot.can_board())
	place_player(demo.town.spawn_pos())
	await frames(3)
	out("BOARD", pilot.board())
	await frames(2)
	out("PILOTING", pilot.piloting and player.piloting)
	out("COLLIDER_STOPS_FOLLOWING_SEATED", demo.terrain._target == null)
	out("PLAYER_HIDDEN", not player.visible)
	out("HUD_VISIBLE", pilot.hud.visible)
	out("EXIT_WHILE_PARKED_WORKS", pilot.exit_ship())
	await frames(2)
	out("BOARD_AGAIN", pilot.board())
	_measure = true
	pilot.set_external_command({ "throttle": 0.0 })
	var pad_box: Node = demo.get_node_or_null("Town/" + str(pilot.pad.get("town_box", "ship")))
	out("PAD_BOX_RETIRED", pad_box != null and pad_box.get_children().filter(
		func(c): return c is CollisionShape3D and not c.disabled).is_empty())
	out("HULL_SOLID_PARKED", not pilot.hull.get_child(0).disabled)
	out("TAKEOFF", pilot.takeoff())
	await frames(2)
	# Issue #55: the hull flies with the ship, so the garrison's bolts can hit it.
	out("HULL_SOLID_IN_FLIGHT", not pilot.hull.get_child(0).disabled)
	var t0 := 0
	for i in 600:
		await physics_frame
		t0 += 1
		if pilot.atmo.state == AtmoFlight.State.FLYING:
			break
	out("LIFTOFF_SECONDS", snappedf(t0 / 60.0, 0.01))
	out("AGL_AFTER_LIFTOFF", snappedf(pilot.atmo.agl(), 0.1))
	out("HOVERS_AT_ZERO_THROTTLE", absf(pilot.atmo.speed()) < 0.01)
	# Climb: nose up 80 degrees, full throttle and boost, until space.
	var want := sin(deg_to_rad(80.0))
	var max_alt := 0.0
	out("DETAIL_TIER_ON_PAD", demo.detail.tier)
	var space_at := Vector3.ZERO
	for i in 60 * 90:
		var fy: float = pilot.atmo.flight.forward().y
		pilot.set_external_command({ "pitch": clampf((want - fy) * 4.0, -1.0, 1.0), "throttle": 1.0, "boost": true })
		await physics_frame
		max_alt = maxf(max_alt, pilot.atmo.altitude())
		if pilot.space_time >= 0.0 or pilot.atmo.state == AtmoFlight.State.CRASHED:
			space_at = pilot.atmo.position()
			break
	out("SPACE_SECONDS", snappedf(pilot.space_time, 0.1))
	out("SPACE_ALTITUDE", int(pilot.atmo.space_altitude))
	out("TOP_SPEED_IN_CLIMB", int(pilot.atmo.speed()))
	out("DETAIL_TIER_AT_SPACE", demo.detail.tier)
	out("DETAIL_HIDDEN_AT_SPACE", ",".join(PackedStringArray(demo.detail.hidden_groups())))
	out("PEOPLE_HIDDEN_AT_SPACE", not demo.get_node("Markers").visible)

	# ---------------------------------------------------------------- 2. space, same scene
	_phase = "space"
	var fight: SpaceFight = pilot.fight
	out("SCENE_AFTER_CLIMB", went.back() if not went.is_empty() else "")
	out("TOWN_STILL_LOADED", is_instance_valid(demo) and demo.is_inside_tree())
	out("FIGHT_STARTED", fight != null)
	out("SPACE_ENCOUNTER", fight.encounter_id if fight != null else "")
	out("FIGHT_IN_TOWN_SCENE", fight != null and fight.get_parent() == demo)
	var me = fight.player_flight() if fight != null else null
	out("FIGHT_STARTS_AT_SHIP_M", snappedf(me.position.distance_to(space_at), 0.1) if me != null else -1)
	var allies: Array = fight.df.alive_on("player").filter(func(sh): return not sh.is_player) if fight != null else []
	out("WINGMAN_BESIDE_M", int(allies[0].flight.position.distance_to(me.position)) if not allies.is_empty() and me != null else -1)
	# The fighter AI flies the ship for 10 s (as the M10 trace's bot pilot does):
	# the fight runs here, in the town, and the town's ship follows it.
	var max_step := 0.0
	var last: Vector3 = pilot.atmo.position()
	if fight != null:
		fight.df.set_player_autopilot(true)
	for i in 60 * 10:
		await physics_frame
		max_step = maxf(max_step, pilot.atmo.position().distance_to(last))
		last = pilot.atmo.position()
		if pilot.fight == null:
			break
	out("SPACE_WAVES_SEEN", fight.df.stats.waves if is_instance_valid(fight) and fight.df != null else -1)
	out("SPACE_SHOTS", fight.df.stats.shots if is_instance_valid(fight) and fight.df != null else -1)
	out("SHIP_FOLLOWS_FIGHT", pilot.fight != null and pilot.atmo.position().distance_to(pilot.fight.player_flight().position) < 0.01)
	out("VISUAL_FOLLOWS_FIGHT", pilot.fight != null and pilot.visual.global_position.distance_to(pilot.atmo.position()) < 0.01)
	# Dive: nose down, full throttle, until the fight lets go.
	if is_instance_valid(fight) and pilot.fight != null:
		fight.df.set_player_autopilot(false)
	var dive_from: Vector3 = pilot.atmo.position()
	for i in 60 * 60:
		var fy: float = pilot.atmo.flight.forward().y
		pilot.set_external_command({ "pitch": clampf((-0.8 - fy) * 4.0, -1.0, 1.0), "throttle": 1.0 })
		await physics_frame
		max_step = maxf(max_step, pilot.atmo.position().distance_to(last))
		last = pilot.atmo.position()
		if pilot.fight == null:
			break
	await frames(2)
	var down: Vector3 = pilot.atmo.position()
	out("SPACE_MAX_STEP_M", snappedf(max_step, 0.1))
	out("SCENE_AFTER_DIVE", went.back() if not went.is_empty() else "")
	out("FIGHT_OUTCOME", str(pilot.fight_log.back().outcome) if not pilot.fight_log.is_empty() else "")
	out("FIGHT_CLEARED", pilot.fight == null and demo.get_node_or_null("SpaceFight") == null)
	out("BACK_DOWN_ALTITUDE", int(pilot.atmo.altitude()))
	out("BACK_DOWN_DRIFT_M", int(Vector2(down.x - dive_from.x, down.z - dive_from.z).length()))
	out("BACK_DOWN_FROM_PAD_M", int(Vector2(down.x - pilot.pad.center.x, down.z - pilot.pad.center.z).length()))

	# ---------------------------------------------------------------- 3. back in the sky
	_phase = "sky"
	out("LANDMARKS", pilot.ground.columns.size())
	out("OUTPOST_IN_SKY_SCENE", pilot.scenery.landmark_boxes().filter(func(b): return str(b.id).begins_with("outpost/")).size())
	out("REENTRY_COLLIDER_NOT_FOLLOWING", demo.terrain._target == null)
	out("REENTRY_PILOTING", pilot.piloting)
	out("REENTRY_STATE", pilot.atmo.state_label())
	out("REENTRY_ALTITUDE", int(pilot.atmo.altitude()))
	out("SPACE_REARMED", not pilot.atmo.reached_space)
	var c: Vector3 = pilot.pad.center
	# Dive back to the port: 300 m over the town.
	var dive := await fly_to(Vector3(c.x, 300, c.z), 0.8, 120.0,
		func(): return Vector2(pilot.atmo.position().x - c.x, pilot.atmo.position().z - c.z).length() < 400.0)
	out("DIVE_TO_PORT_SECONDS", snappedf(dive, 0.1))
	out("ALT_OVER_PORT", int(pilot.atmo.altitude()))
	# A circuit: over the town, out past the outpost, over the hoodoos to the north-west, back.
	# (lambdas capture locals by value, so the stats live in a dictionary)
	var st := { "min_agl": INF, "top_speed": 0.0, "max_dist": 0.0 }
	var circuit := [Vector3(60, 120, 40), Vector3(2400, 320, -1600), Vector3(-1500, 380, 1800), Vector3(0, 160, 0)]
	var circuit_ok := true
	var circuit_s := 0.0
	for wp in circuit:
		var r := await fly_to(wp, 0.9, 90.0, func():
			var q: Vector3 = pilot.atmo.position()
			st.min_agl = minf(st.min_agl, pilot.atmo.agl())
			st.top_speed = maxf(st.top_speed, pilot.atmo.speed())
			st.max_dist = maxf(st.max_dist, Vector2(q.x, q.z).length())
			return Vector2(q.x - wp.x, q.z - wp.z).length() < 120.0)
		if r < 0.0:
			circuit_ok = false
		circuit_s += maxf(r, 0.0)
	out("CIRCUIT_OK", circuit_ok)
	out("CIRCUIT_SECONDS", snappedf(circuit_s, 0.1))
	out("CIRCUIT_MIN_AGL", int(st.min_agl))
	out("CIRCUIT_TOP_SPEED", int(st.top_speed))
	out("CIRCUIT_MAX_DISTANCE", int(st.max_dist))
	# Land in the open desert east of town.
	var lz := Vector3(700, 0, 500)
	# 120 m over the sand there (issue #77: on the ball the ground falls away from y = 0).
	var app := await fly_to(Vector3(lz.x, pilot.ground.terrain.height_at(lz.x, lz.z) + 120.0, lz.z), 0.35, 90.0,
		func(): return Vector2(pilot.atmo.position().x - lz.x, pilot.atmo.position().z - lz.z).length() < 60.0)
	out("APPROACH_OK", app >= 0.0)
	out("CAN_LAND", pilot.atmo.can_land())
	out("LAND", pilot.land())
	for i in 60 * 30:
		pilot.set_external_command({ "throttle": 0.0 })
		await physics_frame
		if pilot.atmo.state == AtmoFlight.State.PARKED:
			break
	var sp: Vector3 = pilot.atmo.position()
	out("LANDED_STATE", pilot.atmo.state_label())
	out("LANDED_DISTANCE_FROM_TOWN", int(Vector2(sp.x, sp.z).length()))
	out("LANDED_ON_GROUND", absf(sp.y - pilot.atmo.clearance - pilot.atmo.ground_below()) < 0.1)
	var snaps0: int = demo.terrain.snaps
	out("GROUND_PREFETCHED", demo.terrain.collider_covers(sp.x, sp.z, 8.0) or demo.terrain.is_rebuilding())
	out("EXIT_IN_DESERT", pilot.exit_ship())
	await frames(30)
	out("PLAYER_ON_DESERT", player.is_on_floor())
	out("COLLIDER_FOLLOWS_AGAIN", demo.terrain._target == player)
	out("SNAPS_ON_EXIT", demo.terrain.snaps - snaps0)
	out("COLLIDER_WORST_STEP_MS", snappedf(demo.terrain.worst_step_ms, 0.01))
	out("COLLIDER_WORST_SWAP_MS", snappedf(demo.terrain.worst_swap_ms, 0.01))
	var ty: float = pilot.ground.terrain.height_at(player.global_position.x, player.global_position.z)
	out("PLAYER_ON_TERRAIN_HEIGHT", absf(player.global_position.y - ty) < 0.6)
	var w0: Vector3 = player.global_position
	var away := Vector2(w0.x - sp.x, w0.z - sp.z).normalized()   # away from the ship
	demo._rig.rig.yaw = 0.0          # yaw 0: command x -> world x, y -> world z
	player.set_command(away, true, false, false)
	await frames(180)
	player.set_command(Vector2.ZERO, false, false, false)
	await frames(10)
	var walked := Vector2(player.global_position.x - w0.x, player.global_position.z - w0.z).length()
	out("WALKED_ON_DESERT_M", snappedf(walked, 0.1))
	out("WALKED_ON_DESERT", player.is_on_floor() and walked > 8.0)
	out("HULL_SOLID_IN_DESERT", not pilot.hull.get_child(0).disabled)
	# Back to the ship and in.
	place_player(sp + Vector3(4, 0, 0) - Vector3(0, pilot.atmo.clearance, 0))
	await frames(5)
	out("REBOARD_IN_DESERT", pilot.board())
	pilot.set_external_command({ "throttle": 0.0 })
	pilot.takeoff()
	for i in 600:
		await physics_frame
		if pilot.atmo.state == AtmoFlight.State.FLYING:
			break

	# ---------------------------------------------------------------- 4. crash
	_phase = "crash"
	var mesa: Dictionary = pilot.ground.columns.filter(func(m): return str(m.id) == "mesa_1500_1700")[0]
	# Issue #77: on the ball the mesa leans with the ground: aim along its own up.
	var mup: Vector3 = mesa.get("up", Vector3.UP)
	var mid: Vector3 = (mesa.center as Vector3) + mup * float(mesa.get("h", float(mesa.top) - (mesa.center as Vector3).y)) * 0.4
	var side := (Vector3.FORWARD - mup * mup.dot(Vector3.FORWARD)).normalized()
	var start := mid + side * 900.0
	await fly_to(start, 0.6, 120.0, func(): return pilot.atmo.position().distance_to(start) < 150.0)
	var crash := await fly_to(mid, 1.0, 60.0, func(): return false)
	out("CRASHED", crash == -2.0)
	out("CRASHED_INTO", pilot.atmo.last_hit if pilot.atmo.last_hit != "" else str(pilot.log_events.back().get("what", "")))
	await frames(int(60 * (ShipPilot.CRASH_TOW_TIME + 0.5)))
	out("TOWED_HOME", pilot.is_parked_home())
	out("HULL_SOLID_AFTER_TOW", not pilot.hull.get_child(0).disabled)
	out("ON_FOOT_AFTER_CRASH", not pilot.piloting and player.visible)
	out("BESIDE_THE_SHIP", player.global_position.distance_to(pilot.atmo.position()) < 15.0)

	# ---------------------------------------------------------------- 5. home
	_phase = "home"
	place_player(demo.town.spawn_pos())
	await frames(5)
	pilot.board()
	pilot.set_external_command({ "throttle": 0.0 })
	pilot.takeoff()
	for i in 600:
		await physics_frame
		if pilot.atmo.state == AtmoFlight.State.FLYING:
			break
	var outbound := await fly_to(Vector3(-400, 150, 300), 0.6, 60.0,
		func(): return Vector2(pilot.atmo.position().x + 400, pilot.atmo.position().z - 300).length() < 80.0)
	var h: Vector3 = pilot.home
	var back := await fly_to(Vector3(h.x, 60, h.z), 0.3, 90.0,
		func(): return Vector2(pilot.atmo.position().x - h.x, pilot.atmo.position().z - h.z).length() < 25.0)
	out("FLEW_HOME", outbound >= 0.0 and back >= 0.0)
	# Hover over the pad, then land on it.
	for i in 120:
		pilot.set_external_command({ "throttle": 0.0 })
		await physics_frame
	out("LAND_ON_PAD", pilot.land())
	for i in 60 * 30:
		pilot.set_external_command({ "throttle": 0.0 })
		await physics_frame
		if pilot.atmo.state == AtmoFlight.State.PARKED:
			break
	var hp: Vector3 = pilot.atmo.position()
	out("PAD_LANDING_ERROR_M", snappedf(Vector2(hp.x - h.x, hp.z - h.z).length(), 0.1))
	out("ON_PIT_FLOOR", absf(hp.y - pilot.atmo.clearance + 6.0) < 0.2)
	out("EXIT_AT_PAD", pilot.exit_ship())
	await frames(20)
	out("FINAL_ON_FLOOR", player.is_on_floor())
	out("FINAL_IN_PIT", player.global_position.y < -5.0)
	# Walk straight at the parked ship: its hull stops you.
	var s0: Vector3 = pilot.atmo.position()
	var to_ship := Vector2(s0.x - player.global_position.x, s0.z - player.global_position.z).normalized()
	demo._rig.rig.yaw = 0.0
	for i in 120:
		player.set_command(to_ship, false, false, false)
		await physics_frame
	player.set_command(Vector2.ZERO, false, false, false)
	out("SHIP_IS_SOLID", Vector2(player.global_position.x - s0.x, player.global_position.z - s0.z).length() > 2.5)

	# ---------------------------------------------------------------- 6. jetpack over the wall
	_phase = "jetpack"
	WorldState.inventory.add("jetpack")
	WorldState.inventory.attach("jetpack", demo.gear.content.get_item("jetpack"))
	demo.gear.sync_gear()
	place_player(Vector3(-84, 0, 71))
	await frames(20)
	player.jetpack.refill()
	var rec0: int = demo.gear.recoveries
	var top := -INF
	var far := -INF
	player.set_command(Vector2.ZERO, false, false, true, true)
	await physics_frame
	demo._rig.rig.yaw = 0.0
	for i in 60 * 10:
		player.set_command(Vector2(0, 1), false, false, false, true)
		await physics_frame
		top = maxf(top, player.global_position.y)
		far = maxf(far, player.global_position.z)
		if player.is_on_floor() and i > 60:
			break
	player.set_command(Vector2.ZERO, false, false, false)
	await frames(20)
	out("JETPACK_OVER_WALL", top > 6.5 and far > 75.0)
	out("JETPACK_LANDED_ON_DESERT", player.is_on_floor() and player.global_position.z > 75.0)
	out("JETPACK_NO_RESCUE_NEEDED", demo.gear.recoveries == rec0)
	out("EVENTS", ",".join(PackedStringArray(pilot.log_events.map(func(e): return str(e.type)))))
	out("WORST_MS", snappedf(worst_ms, 0.01))
	var pw := PackedStringArray()
	for k in phase_worst:
		pw.append("%s:%.1f" % [k, phase_worst[k]])
	out("WORST_MS_BY_PHASE", " ".join(pw))

	var terrain_metrics := _terrain_performance()
	var perf_report := _perf.report("m14_flight", {
		"scene_ready_ms": scene_ready_ms,
		"terrain": terrain_metrics,
		"visuals_enabled": OS.get_environment("DUNE_PERF_VISUALS") == "1"
	})
	var frame_stats: Dictionary = perf_report.frame_time_ms
	var process_stats: Dictionary = perf_report.main_thread_process_ms
	var physics_stats: Dictionary = perf_report.physics_process_ms
	out("FRAME_P50_MS", frame_stats.get("p50", -1.0))
	out("FRAME_P95_MS", frame_stats.get("p95", -1.0))
	out("FRAME_P99_MS", frame_stats.get("p99", -1.0))
	out("CPU_PROCESS_P95_MS", process_stats.get("p95", -1.0))
	out("CPU_PHYSICS_P95_MS", physics_stats.get("p95", -1.0))
	out("GPU_FRAME_MS", "unavailable" if perf_report.gpu_frame_ms == null else perf_report.gpu_frame_ms)
	var perf_path := OS.get_environment("DUNE_PERF_OUT")
	if not perf_path.is_empty():
		var perf_error: Error = _perf.write_json(perf_path, perf_report)
		out("PERF_JSON_PATH", perf_path)
		out("PERF_JSON_ERROR", perf_error)

	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_results"))
		f = FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("M14TRACE wrote ", OUT, " (", lines.size(), " lines)")
	GameFlow.reset()
	quit()
