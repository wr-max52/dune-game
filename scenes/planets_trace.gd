extends SceneTree
## Issue #45 trace (headless, real physics, the real town scene): the test the
## issue asks for. Take off from the port, climb to space, fly to the asteroid
## station hanging in the port's sky; issue #99: its scene takes over in mid-
## flight with no fade, the ship exactly where it was. Drop under its edge of
## space and press Z to be landed in its landing pit, get out in its size-1 town
## (its own Oda, a stage, a guard at the door, a merchant in front, locals in the
## street), walk out through the ring wall's gate shield, along the windowed
## hallway and through its round shield into the pit; stand on the asteroid's
## rock and on its far side (a real ball), find the dome solid, then fly home
## again, the home scene taking over the same way. Writes test_results/planets_trace.txt for tests/test_planets_trace.gut.gd.
##
## Run: godot --headless --fixed-fps 60 --path . -s res://scenes/planets_trace.gd

const OUT := "res://test_results/planets_trace.txt"
const FighterBrain := preload("res://src/systems/ai/fighter_brain.gd")
const PerfTrace := preload("res://src/systems/diagnostics/performance_trace.gd")

var demo
var pilot: ShipPilot
var player
var lines := PackedStringArray()
var went: Array = []
var worst_ms := 0.0
var _last := 0
var _measure := false
var _phase := "setup"
var _perf := PerfTrace.new()
var scene_ready_ms: Array[float] = []
var terrain_scene_metrics: Array[Dictionary] = []


func _initialize() -> void:
	WorldState.reset()
	WorldState.set_flag("ships_unlocked")      # issue #64 locks ships behind the story; this trace flies
	GameFlow.reset()
	GameFlow.dogfight_override = false        # this trace is about travel, not the fight
	GameFlow.change_scene = func(path: String) -> void: went.append(path)
	_run()


func _process(_d: float) -> bool:
	var now := Time.get_ticks_usec()
	if _measure:
		_perf.sample(_d, _phase)
	if _measure and _last > 0:
		worst_ms = maxf(worst_ms, (now - _last) / 1000.0)
	_last = now
	return false


func out(k: String, v) -> void:
	lines.append("%s=%s" % [k, str(v)])
	print("  ", k, "=", v)


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func make_town() -> void:
	_measure = false
	if demo != null:
		_capture_terrain_scene()
		demo.queue_free()
		await frames(2)
	demo = load("res://scenes/town_demo.gd").new()
	demo.npc_brains = false
	demo.use_look = OS.get_environment("DUNE_PERF_VISUALS") == "1"
	var ready_started := Time.get_ticks_usec()
	get_root().add_child(demo)
	scene_ready_ms.append((Time.get_ticks_usec() - ready_started) / 1000.0)
	await frames(5)
	pilot = demo.pilot
	player = demo._player
	_measure = true


func _capture_terrain_scene() -> void:
	if demo == null or not is_instance_valid(demo) or demo.terrain == null:
		return
	var metrics: Dictionary = {}
	if demo.terrain.has_method("performance_snapshot"):
		metrics = demo.terrain.performance_snapshot()
	terrain_scene_metrics.append({ "planet_id": str(demo.planet.get("id", GameFlow.planet_id)), "terrain": metrics })


func _capture_hero_frame() -> void:
	var path := OS.get_environment("DUNE_PERF_SCREENSHOT")
	if path.is_empty():
		return
	if DisplayServer.get_name() == "headless":
		out("HERO_FRAME", "skipped_headless")
		return
	var was_measuring := _measure
	_measure = false # screenshot readback can stall; do not fold it into route timing
	await RenderingServer.frame_post_draw
	var image: Image = get_root().get_texture().get_image()
	var absolute_path := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	var image_error: Error = image.save_png(absolute_path)
	_last = Time.get_ticks_usec()
	_measure = was_measuring
	out("HERO_FRAME", path if image_error == OK else "error_%d" % image_error)


func place_player(p: Vector3) -> void:
	player.global_position = p + Vector3(0, 0.05, 0)
	player.velocity = Vector3.ZERO
	player.controller.velocity = Vector3.ZERO
	player.controller.body_pos = player.global_position


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


func take_off() -> void:
	# Beside the ship, wherever it is parked (the walk up to it is not the point here).
	var sp: Vector3 = pilot.atmo.position()
	var spawn: Vector3 = demo.town.spawn_pos()
	var side := Vector3(spawn.x - sp.x, 0, spawn.z - sp.z).normalized() * 5.0
	place_player(Vector3(sp.x, spawn.y, sp.z) + (side if side.length() > 0.1 else Vector3(5, 0, 0)))
	await frames(3)
	pilot.board()
	pilot.set_external_command({ "throttle": 0.0 })
	pilot.takeoff()
	for i in 600:
		await physics_frame
		if pilot.atmo.state == AtmoFlight.State.FLYING:
			break


## Fly at a neighbour until the travel node leaves for it (the scene change is
## recorded, not made). Climb first, then straight at it with boost.
func fly_to_planet(id: String, climb_to: float, max_s: float) -> float:
	var body: Dictionary = {}
	for b in pilot.travel.bodies:
		if b.id == id:
			body = b
	if body.is_empty():
		return -9.0
	var t0 := Time.get_ticks_msec()
	var start := pilot.flight_time
	var up: Vector3 = pilot.atmo.position() + Vector3(0, climb_to, 0)
	await fly_to(up, 1.0, 60.0, func(): return pilot.atmo.altitude() >= climb_to * 0.9, true)
	var at: Vector3 = body.at
	var r := await fly_to(at, 1.0, max_s, func(): return pilot.travel.traveling != "", true)
	out("FLIGHT_WALL_MS_" + id.to_upper(), Time.get_ticks_msec() - t0)
	return pilot.flight_time - start if r >= 0.0 else r


func _run() -> void:
	# ---------------------------------------------------------------- the port
	await make_town()
	_phase = "port_to_station"
	await _capture_hero_frame()
	out("HOME_PLANET", GameFlow.current_planet_id())
	out("HOME_TOWN", demo.town.data.get("id", ""))
	out("HOME_NEIGHBOURS", ",".join(PackedStringArray(pilot.travel.bodies.map(func(b): return str(b.id)))))
	var station: Dictionary = pilot.travel.bodies.filter(func(b): return b.id == "grit_station")[0]
	out("STATION_NAME_IN_PORT_SKY", station.name)
	out("STATION_DISTANCE_FROM_PAD_KM", snappedf((station.at as Vector3).distance_to(pilot.home) / 1000.0, 0.1))
	await take_off()
	out("PORT_SHIP", pilot.ship_id)
	var to_station := await fly_to_planet("grit_station", 1200.0, 150.0)
	out("FLEW_TO_STATION_S", snappedf(to_station, 0.1))
	out("TRAVEL_STARTED", pilot.travel.traveling)
	await frames(5)                           # issue #99: no fade, the switch is immediate
	out("SCENE_AFTER_TRAVEL", went.back() if not went.is_empty() else "")
	out("PLANET_AFTER_TRAVEL", GameFlow.planet_id)
	out("FLOWN_SHIP", GameFlow.flown_ship)
	out("ARRIVAL_MODE", str(GameFlow.arrival.get("mode", "")))

	# ---------------------------------------------------------------- the station
	await make_town()
	_phase = "station"
	var t = demo.town
	out("STATION_TOWN", t.data.get("id", ""))
	out("STATION_TOWN_VALID", t.validate().is_empty())
	out("STATION_TOWN_SIZE", t.data.get("generated", {}).get("size", -1))
	out("STATION_GROUND", demo.planet.get("ground", ""))
	out("STATION_ROCK", demo.platform is AsteroidWorld)
	out("STATION_TERRAIN", demo.terrain != null)
	out("STATION_STYLE", demo.style.spec)
	out("STATION_NAME", demo.planet_name)
	out("STATION_TOWN_NAME", demo.town_name)
	out("STATION_GUARDS", demo.npcs.size())
	out("STATION_LOCALS", demo.locals.size())
	out("STATION_BUILDINGS", t.boxes().filter(func(b): return str(b.get("look", "")).begins_with("hut") or str(b.get("look", "")).begins_with("tower")).size())
	out("STATION_CANTINA", not t.get_box("bar_counter").is_empty())
	var om: Dictionary = t.get_marker("cantina_owner")
	out("STATION_OWNER_CARD", om.get("card", ""))
	out("STATION_OWNER_PLANET", om.get("planet", ""))
	out("STATION_OWNER_LOOK", om.get("look", ""))
	var oda := PlanetOwner.card(demo.planet)
	out("STATION_OWNER_ID", oda.id)
	out("STATION_OWNER_NAME", oda.name)
	out("STATION_OWNER_KNOWS_PLANET", str(oda.identity).contains(demo.planet_name))
	out("STATION_STAGE", not t.get_box("cantina_stage").is_empty())
	out("STATION_ROAMERS", t.markers().filter(func(m): return str(m.id).begins_with("roamer_")).size())
	out("STATION_PIT_OUTSIDE", float(t.get_box("pit_bowl").min[0]) > float(t.data.bounds.max[0]))
	var guard = demo.npcs[0] if not demo.npcs.is_empty() else null
	out("GUARD_AT_CANTINA_DOOR", guard != null and guard.post_pos.distance_to(t.marker_pos("cantina_door")) < 5.0)
	var merchant = demo.locals.filter(func(n): return str(n.profile.get("id", "")) == "local_merchant")
	out("MERCHANT_IN_FRONT", not merchant.is_empty() and merchant[0].post_pos.x > float(t.get_box("cantina_wall_e_s").max[0]))
	out("ARRIVED_PILOTING", pilot.piloting)
	out("ARRIVED_STATE", pilot.atmo.state_label())
	out("ARRIVED_ALTITUDE", int(pilot.atmo.altitude()))
	out("ARRIVED_SHIP", pilot.ship_id)
	out("STATION_NEIGHBOURS", ",".join(PackedStringArray(pilot.travel.bodies.map(func(b): return str(b.id)))))
	out("STATION_SPACE_ALTITUDE", int(pilot.atmo.space_altitude))
	# Down under the edge of space toward the bay, then Z: she flies herself in.
	var h: Vector3 = pilot.home
	await fly_to(Vector3(h.x, 450.0, h.z), 0.5, 120.0,
		func(): return pilot.atmo.altitude() < 600.0 and Vector2(pilot.atmo.position().x - h.x, pilot.atmo.position().z - h.z).length() < 2500.0)
	out("NEAR_BAY", pilot.near_bay())
	out("BAY_LAND", pilot.bay_land())
	for i in 60 * 90:
		await physics_frame
		if pilot.atmo.state == AtmoFlight.State.PARKED:
			break
	out("LANDED_STATE", pilot.atmo.state_label())
	out("LANDED_IN_PIT", absf(pilot.atmo.position().y - h.y) < 1.5)
	out("LANDED_FROM_BAY_M", snappedf(Vector2(pilot.atmo.position().x - h.x, pilot.atmo.position().z - h.z).length(), 0.1))
	out("EXIT_AT_STATION", pilot.exit_ship())
	await frames(20)
	out("IN_PIT", player.is_on_floor() and absf(player.global_position.y + 6.0) < 0.3)
	# Issue #99: sealed. Out of the ring through the gate's shield, into the hallway.
	var stn: AsteroidWorld = demo.platform
	var hall: Dictionary = stn.hall
	out("STATION_RING_M", stn.rw)
	place_player(stn.rc + Vector3(stn.rw - 5.0, 0, 0))
	await frames(10)
	demo._rig.rig.yaw = 0.0
	for i in 200:
		player.set_command(Vector2(1, 0), false, false, false)
		await physics_frame
	player.set_command(Vector2.ZERO, false, false, false)
	await frames(10)
	out("SHIELD_WALK_X", snappedf(player.global_position.x - (stn.rc.x + stn.rw), 0.1))
	out("THROUGH_THE_SHIELD", player.global_position.x > stn.rc.x + stn.rw + 3.0 and player.is_on_floor())
	# The hallway's windows hold.
	for i in 120:
		player.set_command(Vector2(0, 1), false, false, false)
		await physics_frame
	player.set_command(Vector2.ZERO, false, false, false)
	out("HALL_HOLDS", absf(player.global_position.z) < float(hall.half))
	# On down the hallway, over the ramp, out through its round shield onto the pit floor.
	place_player(Vector3(float(hall.rim) - 3.0, 0, 0))
	await frames(10)
	for i in 420:
		player.set_command(Vector2(1, 0), false, false, false)
		await physics_frame
	player.set_command(Vector2.ZERO, false, false, false)
	await frames(10)
	out("INTO_PIT_THROUGH_SHIELD", player.global_position.x > float(hall.end) + 1.0 and player.global_position.y < -5.0)
	# The asteroid is a real ball: stand on its rock, and on its far side.
	var sp: PlanetSphere = PlanetSphere.current
	out("ROCK_BALL_RADIUS", int(sp.radius) if sp != null else 0)
	for m in [["WALK_ON_ROCK", Vector2(500.0, -200.0)], ["WALK_ROUND_THE_BALL", Vector2(PI * sp.radius * 0.8, 0.0)]]:
		var g := sp.surface_at(m[1].x, m[1].y)
		var up := sp.up_at(g)
		player.global_position = g + up * 1.2
		player.velocity = Vector3.ZERO
		player.controller.velocity = Vector3.ZERO
		player.controller.body_pos = player.global_position
		demo.terrain.snap_to(player.global_position)
		await frames(60)
		out(m[0], player.is_on_floor() and sp.height_above_ground(player.global_position) < 0.6)
	out("FAR_SIDE_UP_Y", snappedf(sp.up_at(player.global_position).y, 0.01))
	place_player(t.spawn_pos())
	demo.terrain.snap_to(player.global_position)
	await frames(10)
	# The dome is solid: a jetpack-high push at it from inside stays inside.
	var y := stn.wall_h + 3.0
	var el := asin((y - stn.wall_h) / stn.dome_h)
	var shell_z := stn.rc.z + stn.rw * cos(el)
	place_player(Vector3(stn.rc.x, y, shell_z - 3.0))
	for i in 90:
		player.set_command(Vector2(0, 1), false, false, false)
		player.velocity.y = maxf(player.velocity.y, 0.0)
		await physics_frame
	player.set_command(Vector2.ZERO, false, false, false)
	out("GLASS_HOLDS", player.global_position.z < shell_z)
	out("DOME_TRIS", stn.dome_tris)
	out("SHIP_HITS_GLASS", pilot.ground.hit(Vector3(stn.rc.x, 10.0, stn.rc.z + stn.rw * 0.9), 2.0).begins_with("glass_"))
	place_player(t.spawn_pos())
	await frames(10)

	# ---------------------------------------------------------------- home again
	went.clear()
	_phase = "station_to_home"
	await take_off()
	out("HOME_TAKEOFF", "%s %s" % [pilot.piloting, pilot.atmo.state_label()])
	var home_flight := await fly_to_planet("port_desert", 600.0, 150.0)
	out("FLEW_HOME_S", snappedf(home_flight, 0.1))
	await frames(60)
	out("PLANET_AFTER_RETURN", GameFlow.planet_id)
	await make_town()
	_phase = "home"
	out("HOME_AGAIN_TOWN", demo.town.data.get("id", ""))
	out("HOME_AGAIN_PILOTING", pilot.piloting and pilot.atmo.state == AtmoFlight.State.FLYING)
	out("HOME_AGAIN_FROM_STATION_SIDE", Vector2(pilot.atmo.position().x, pilot.atmo.position().z).dot(Vector2(9000, -6500)) > 0.0)
	out("STATION_NAME_SAME", pilot.travel.bodies.filter(func(b): return b.id == "grit_station")[0].name == lines_get("STATION_NAME"))
	out("WORST_MS", snappedf(worst_ms, 0.01))
	_capture_terrain_scene()
	var perf_report := _perf.report("planet_handoffs", {
		"scene_ready_ms": scene_ready_ms,
		"terrain_scenes": terrain_scene_metrics,
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
	print("PLANETSTRACE wrote ", OUT, " (", lines.size(), " lines)")
	GameFlow.reset()
	quit()


func lines_get(k: String) -> String:
	for l in lines:
		if l.begins_with(k + "="):
			return l.substr(k.length() + 1)
	return ""
