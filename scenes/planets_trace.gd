extends SceneTree
## Issue #45 trace (headless, real physics, the real town scene): the test the
## issue asks for. Take off from the port, climb to space, fly to the asteroid
## station hanging in the port's sky, arrive in its sky still flying the same
## ship, press Z and be landed in its landing pit (issue #75: the port's pit, out
## past the gate), get out in its size-1 town (a cantina with its own Oda and a
## stage, a guard at the door, a merchant in front, locals in the street, all
## under a glass dome on a cratered rock ball), walk out through the dome's
## shield and across the rock, slide off the side and wake by the bay, find the
## dome solid, then fly home again. Writes test_results/planets_trace.txt for tests/test_planets_trace.gut.gd.
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
	# Z: she flies herself in and lands in the pit.
	var h: Vector3 = pilot.home
	out("NEAR_BAY", pilot.near_bay())
	out("BAY_LAND", pilot.bay_land())
	for i in 60 * 60:
		await physics_frame
		if pilot.atmo.state == AtmoFlight.State.PARKED:
			break
	out("LANDED_STATE", pilot.atmo.state_label())
	out("LANDED_IN_PIT", absf(pilot.atmo.position().y - h.y) < 1.5)
	out("LANDED_FROM_BAY_M", snappedf(Vector2(pilot.atmo.position().x - h.x, pilot.atmo.position().z - h.z).length(), 0.1))
	out("EXIT_AT_STATION", pilot.exit_ship())
	await frames(20)
	out("IN_PIT", player.is_on_floor() and absf(player.global_position.y + 6.0) < 0.3)
	# Out through the dome's door: the shield is no wall.
	var rock: AsteroidWorld = demo.platform
	var dome: Dictionary = rock.dome
	var door := Vector3(float(dome.door_x), 0.0, float(dome.door_z))
	place_player(door + Vector3(-5, 0, 0))
	await frames(10)
	demo._rig.rig.yaw = 0.0
	for i in 240:
		player.set_command(Vector2(1, 0), false, false, false)
		await physics_frame
	player.set_command(Vector2.ZERO, false, false, false)
	await frames(10)
	out("SHIELD_WALK_X", snappedf(player.global_position.x - door.x, 0.1))
	out("THROUGH_THE_SHIELD", player.global_position.x > door.x + 3.0 and player.is_on_floor())
	# The rock is ground: stand on it well away from the town.
	var c: Vector3 = rock.center
	var far := Vector3(c.x + 150.0, rock.height_at(c.x + 150.0, c.z - 60.0), c.z - 60.0)
	place_player(far + Vector3(0, 1.0, 0))
	await frames(60)
	out("WALK_ON_ROCK", player.is_on_floor() and absf(player.global_position.y - rock.height_at(player.global_position.x, player.global_position.z)) < 0.6)
	out("ROCK_DROP_M", snappedf(-far.y, 0.1))
	# Off the side of the ball: down, dead, back by the bay.
	var falls0: int = demo.platform.falls
	var edge := c.x + rock.extent + 15.0
	place_player(Vector3(edge, rock.height_at(edge - 20.0, c.z), c.z))
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
	# The dome is solid: a jetpack-high push at it from inside stays inside.
	var dc: Vector3 = dome.c
	var shell_z := dc.z + float(dome.b) * sqrt(1.0 - pow((9.0 - dc.y) / float(dome.h), 2.0))
	place_player(Vector3(dc.x, 9.0, shell_z - 3.0))
	for i in 90:
		player.set_command(Vector2(0, 1), false, false, false)
		player.velocity.y = maxf(player.velocity.y, 0.0)
		await physics_frame
	player.set_command(Vector2.ZERO, false, false, false)
	out("GLASS_HOLDS", player.global_position.z < shell_z)
	out("DOME_TRIS", rock.dome_tris)
	out("SHIP_HITS_GLASS", pilot.ground.hit(Vector3(dc.x, 10.0, dc.z + float(dome.b) * 0.9), 2.0).begins_with("glass_"))

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
