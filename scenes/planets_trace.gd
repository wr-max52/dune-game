extends SceneTree
## Issue #45 trace (headless, real physics, the real town scene): the test the
## issue asks for. Take off from the port, climb to space, fly to the asteroid
## station hanging in the port's sky, arrive in its sky still flying the same
## ship, land on its bay, get out in its size-1 town (a cantina with its own
## owner, a guard at the door, a merchant out back), walk through the open gate's
## shield, fall off the edge and wake by the bay, find the glass solid, then fly
## home again. Writes test_results/planets_trace.txt for tests/test_planets_trace.gut.gd.
##
## Run: godot --headless --fixed-fps 60 --path . -s res://scenes/planets_trace.gd

const OUT := "res://test_results/planets_trace.txt"
const FighterBrain := preload("res://src/systems/ai/fighter_brain.gd")

var demo
var pilot: ShipPilot
var player
var lines := PackedStringArray()
var went: Array = []
var worst_ms := 0.0
var _last := 0
var _measure := false


func _initialize() -> void:
	WorldState.reset()
	WorldState.set_flag("ships_unlocked")      # issue #64 locks ships behind the story; this trace flies
	GameFlow.reset()
	GameFlow.dogfight_override = false        # this trace is about travel, not the fight
	GameFlow.change_scene = func(path: String) -> void: went.append(path)
	_run()


func _process(_d: float) -> bool:
	var now := Time.get_ticks_usec()
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
		demo.queue_free()
		await frames(2)
	demo = load("res://scenes/town_demo.gd").new()
	demo.npc_brains = false
	demo.use_look = false
	get_root().add_child(demo)
	await frames(5)
	pilot = demo.pilot
	player = demo._player
	_measure = true


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
	await frames(60)                          # the fade, then GameFlow.travel
	out("SCENE_AFTER_TRAVEL", went.back() if not went.is_empty() else "")
	out("PLANET_AFTER_TRAVEL", GameFlow.planet_id)
	out("FLOWN_SHIP", GameFlow.flown_ship)
	out("ARRIVAL_MODE", str(GameFlow.arrival.get("mode", "")))

	# ---------------------------------------------------------------- the station
	await make_town()
	var t = demo.town
	out("STATION_TOWN", t.data.get("id", ""))
	out("STATION_TOWN_VALID", t.validate().is_empty())
	out("STATION_TOWN_SIZE", t.data.get("generated", {}).get("size", -1))
	out("STATION_GROUND", demo.planet.get("ground", ""))
	out("STATION_PLATFORM", demo.platform != null)
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
	out("STATION_OWNER_LOOK", om.get("look", ""))
	var guard = demo.npcs[0] if not demo.npcs.is_empty() else null
	out("GUARD_AT_CANTINA_DOOR", guard != null and guard.post_pos.distance_to(t.marker_pos("cantina_door")) < 5.0)
	var merchant = demo.locals.filter(func(n): return str(n.profile.get("id", "")) == "local_merchant")
	out("MERCHANT_OUT_BACK", not merchant.is_empty() and merchant[0].post_pos.x < float(t.get_box("cantina_wall_w").min[0]))
	out("ARRIVED_PILOTING", pilot.piloting)
	out("ARRIVED_STATE", pilot.atmo.state_label())
	out("ARRIVED_ALTITUDE", int(pilot.atmo.altitude()))
	out("ARRIVED_SHIP", pilot.ship_id)
	out("STATION_NEIGHBOURS", ",".join(PackedStringArray(pilot.travel.bodies.map(func(b): return str(b.id)))))
	out("STATION_SPACE_ALTITUDE", int(pilot.atmo.space_altitude))
	# Down onto the bay.
	var h: Vector3 = pilot.home
	var back := await fly_to(Vector3(h.x, 60, h.z), 0.3, 120.0,
		func(): return Vector2(pilot.atmo.position().x - h.x, pilot.atmo.position().z - h.z).length() < 40.0)
	# Settle over the bay: creep in slowly, stop, and again until right over it.
	for attempt in 4:
		await fly_to(Vector3(h.x, 50, h.z), 0.08, 30.0,
			func(): return Vector2(pilot.atmo.position().x - h.x, pilot.atmo.position().z - h.z).length() < 4.0)
		for i in 600:
			pilot.set_external_command({ "throttle": 0.0 })
			await physics_frame
			if pilot.atmo.speed() < 0.5:
				break
		if Vector2(pilot.atmo.position().x - h.x, pilot.atmo.position().z - h.z).length() < 6.0:
			break
	out("REACHED_BAY", back >= 0.0)
	out("LAND_ON_BAY", pilot.land())
	for i in 60 * 30:
		pilot.set_external_command({ "throttle": 0.0 })
		await physics_frame
		if pilot.atmo.state == AtmoFlight.State.PARKED:
			break
	out("LANDED_STATE", pilot.atmo.state_label())
	out("LANDED_ON_DECK", absf(pilot.atmo.position().y - pilot.atmo.clearance) < 0.6)
	out("LANDED_FROM_BAY_M", snappedf(Vector2(pilot.atmo.position().x - h.x, pilot.atmo.position().z - h.z).length(), 0.1))
	out("EXIT_AT_STATION", pilot.exit_ship())
	await frames(20)
	out("ON_DECK", player.is_on_floor() and absf(player.global_position.y) < 0.3)
	# Out through the open gate: the shield is no wall.
	var gate: Vector3 = t.marker_pos("gate")
	place_player(gate + Vector3(-5, 0, 0))
	await frames(10)
	demo._rig.rig.yaw = 0.0
	for i in 240:
		player.set_command(Vector2(1, 0), false, false, false)
		await physics_frame
	player.set_command(Vector2.ZERO, false, false, false)
	await frames(10)
	out("SHIELD_WALK_X", snappedf(player.global_position.x - gate.x, 0.1))
	out("THROUGH_THE_SHIELD", player.global_position.x > gate.x + 3.0 and player.is_on_floor())
	# Off the end of the apron: down, dead, back by the bay.
	var falls0: int = demo.platform.falls
	var edge := float(demo.platform.deck.end.x)
	place_player(Vector3(edge - 3.0, 0, 0))
	await frames(5)
	var fell_y := 0.0
	for i in 60 * 8:
		player.set_command(Vector2(1, 0), false, false, false)
		await physics_frame
		fell_y = minf(fell_y, player.global_position.y)
		if demo.platform.falls > falls0:
			break
	player.set_command(Vector2.ZERO, false, false, false)
	await frames(30)
	out("FELL_OFF", fell_y < -20.0)
	out("FALLS", demo.platform.falls - falls0)
	out("WOKE_BY_BAY", player.global_position.distance_to(t.spawn_pos()) < 3.0 and player.is_on_floor())
	out("FALL_LOGGED", WorldState.count("falls"))
	# The glass is solid: a jetpack-high push at the wall stays inside.
	var wall: Dictionary = t.get_box("wall_north")
	var wz := float(wall.min[2])
	place_player(Vector3(t.marker_pos("cantina_door").x + 4.0, 9.0, wz - 2.0))
	for i in 90:
		player.set_command(Vector2(0, 1), false, false, false)
		player.velocity.y = maxf(player.velocity.y, 0.0)
		await physics_frame
	player.set_command(Vector2.ZERO, false, false, false)
	out("GLASS_HOLDS", player.global_position.z < wz)
	out("GLASS_PANES", demo.platform.glass_boxes.size())
	out("SHIP_HITS_GLASS", pilot.ground.hit(Vector3(0, 15.0, float(wall.max[2])), 2.0).begins_with("glass_"))

	# ---------------------------------------------------------------- home again
	went.clear()
	await take_off()
	out("HOME_TAKEOFF", "%s %s" % [pilot.piloting, pilot.atmo.state_label()])
	var home_flight := await fly_to_planet("port_desert", 600.0, 150.0)
	out("FLEW_HOME_S", snappedf(home_flight, 0.1))
	await frames(60)
	out("PLANET_AFTER_RETURN", GameFlow.planet_id)
	await make_town()
	out("HOME_AGAIN_TOWN", demo.town.data.get("id", ""))
	out("HOME_AGAIN_PILOTING", pilot.piloting and pilot.atmo.state == AtmoFlight.State.FLYING)
	out("HOME_AGAIN_FROM_STATION_SIDE", Vector2(pilot.atmo.position().x, pilot.atmo.position().z).dot(Vector2(9000, -6500)) > 0.0)
	out("STATION_NAME_SAME", pilot.travel.bodies.filter(func(b): return b.id == "grit_station")[0].name == lines_get("STATION_NAME"))
	out("WORST_MS", snappedf(worst_ms, 0.01))

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
