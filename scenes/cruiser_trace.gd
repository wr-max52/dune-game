extends SceneTree
## Issue #193 trace (headless, real physics, the real town scene): the Remnant
## cruiser in orbit. Oda has sent you (the story's cruiser chapter); a ship is put
## in the sky off the cruiser, Z docks it in the bay and it lands on the empty pad;
## you get out, the crew comes aboard over the next frames (with a garrison of their
## own and the cruiser's navmesh), and you walk the decks: every deck, landing and
## flight of the ramp stack is ground under your feet, up to the bridge. The general
## dies: the cruiser is taken, the purse paid, the locals delighted, the story over.
## Fly away and back: nobody is left aboard.
## Writes test_results/cruiser_trace.txt.
##
## Run: godot --headless --fixed-fps 60 --path . -s res://scenes/cruiser_trace.gd

const OUT := "res://test_results/cruiser_trace.txt"

var demo
var pilot: ShipPilot
var player
var lines := PackedStringArray()


func _initialize() -> void:
	WorldState.reset()
	GameFlow.reset()
	GameFlow.dogfight_override = false
	GameFlow.change_scene = func(_path: String) -> void: pass
	Story.skip_to("fleet")
	_run()


func out(k: String, v) -> void:
	lines.append("%s=%s" % [k, str(v)])
	print("  ", k, "=", v)


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	demo = load("res://scenes/town_demo.gd").new()
	demo.use_look = OS.get_environment("DUNE_CRUISER_LOOK") == "1"
	get_root().add_child(demo)
	await frames(10)
	pilot = demo.pilot
	player = demo._player
	var c = demo.cruiser
	out("CRUISER", c != null)
	if c == null:
		_finish()
		return
	out("CRUISER_AT", c.frame.origin.snapped(Vector3.ONE))
	out("CRUISER_ALTITUDE", int(pilot.ground.altitude(c.frame.origin)))
	out("CRUISER_BOXES", pilot.ground.boxes.filter(func(b): return str(b.id).begins_with("remnant_cruiser/")).size())
	out("CRUISER_UP", pilot.ground.up_at(c.frame.origin).snapped(Vector3.ONE * 0.001))
	out("PLANET_UP_OUTSIDE", pilot.ground.up_at(c.frame.origin + Vector3(0, 0, 900)).snapped(Vector3.ONE * 0.01))
	out("ENCOUNTER", pilot.encounter_id())
	# Below the port's horizon: the line from the port to it passes through the ball.
	var sp: PlanetSphere = pilot.ground.sphere()
	var d: Vector3 = c.frame.origin.normalized()
	var t := (sp.center).dot(d)
	out("HIDDEN_FROM_PORT", (sp.center - d * t).length() < sp.radius)
	_walkways(c)
	await _fight_by_the_hull(c)
	await _dock(c)
	await _aboard(c)
	_finish()


## Every deck you walk on is ground there (height over it ~1 m from 1 m above it).
func _walkways(c) -> void:
	var pts := {
		"dock_pad": CruiserHull.dock_pad().at,
		"bay_floor": Vector3(-10, CruiserHull.DECK_Y, -60),
		"gantry": Vector3(-44, CruiserHull.DECK_Y + 16.0, -90),
		"gantry_ramp": Vector3(-44, CruiserHull.DECK_Y + 8.0, 2),
		"corridor": Vector3(0, CruiserHull.DECK_Y, 150),
		"armoury": Vector3(20, CruiserHull.DECK_Y, 114),
		"shaft_floor": Vector3(0, CruiserHull.DECK_Y, 300),
		"bridge_walk": Vector3(0, CruiserHull.BRIDGE_Y, 240),
		"bridge_dais": Vector3(0, CruiserHull.BRIDGE_Y, 219),
		"bridge_pit": Vector3(18, CruiserHull.PIT_Y, 236),
		"top_landing": Vector3(-8, CruiserHull.BRIDGE_Y, 274),
	}
	for k in CruiserHull.FLIGHTS:
		var y0 := CruiserHull.DECK_Y + k * CruiserHull.FLIGHT_RISE
		var x := CruiserHull.FLIGHT_X if k % 2 == 0 else -CruiserHull.FLIGHT_X
		pts["flight_%d" % k] = Vector3(x, y0 + CruiserHull.FLIGHT_RISE * 0.5, 298)
		if k < CruiserHull.FLIGHTS - 1:
			var lz := 322.0 if k % 2 == 0 else 274.0
			pts["landing_%d" % k] = Vector3(0, y0 + CruiserHull.FLIGHT_RISE, lz)
	var bad: Array = []
	for name in pts:
		var w: Vector3 = c.frame * ((pts[name] as Vector3) + Vector3(0, 1.0, 0))
		var h: float = pilot.ground.height_above(w)
		if absf(h - 1.0) > 0.35:
			bad.append("%s:%.2f" % [name, h])
		if not c.aboard(w):
			bad.append("%s:not_aboard" % name)
	out("WALKWAYS", pts.size())
	out("WALKWAYS_BAD", bad)


## The escort's fight is running when you reach the cruiser (it is above the edge of
## space): its hull is still solid, flying in through the bay's mouth takes you out
## of the fight without ending it, and C over the deck sets her down with a fight
## running. It is still running when Z docks her and when you walk the decks; the
## general's death ends it (_aboard).
func _fight_by_the_hull(c) -> void:
	pilot._seat_arriving()
	pilot.atmo.reached_space = true
	# Into the port flank at fighting speed: a crash on the hull, not through it.
	pilot.atmo.place_flying(c.frame * Vector3(-200, 0, 0), c.frame.basis * Vector3.RIGHT, 120.0, 1.0)
	out("FIGHT_HULL_STARTED", pilot.start_fight())
	for f in 60 * 4:
		pilot.set_external_command({ "throttle": 1.0 })
		await physics_frame
		if pilot.atmo.state != AtmoFlight.State.FLYING:
			break
	out("FIGHT_HULL_STATE", pilot.atmo.state_label())
	out("FIGHT_HULL_HIT", pilot.atmo.last_hit)
	out("FIGHT_HULL_X", int((c.inv * pilot.atmo.position()).x))
	pilot.crash_left = -1.0
	# In through the bay's mouth: out of the fight, which goes on.
	pilot.atmo.place_flying(c.frame * Vector3(200, 0, -62), c.frame.basis * Vector3.LEFT, 40.0, 0.3)
	pilot.start_fight()
	for f in 60 * 8:
		pilot.set_external_command({ "throttle": 0.3 })
		await physics_frame
		if c.aboard(pilot.atmo.position()):
			break
	await frames(2)
	out("FIGHT_BAY_HELD", pilot.fight != null and pilot.fight.sheltered and c.aboard(pilot.atmo.position()))
	# Over the deck with a fight running: C lands her.
	pilot.atmo.place_flying(c.frame * Vector3(30, -2, -62), c.frame.basis * Vector3.LEFT, 5.0, 0.0)
	pilot.start_fight()
	out("FIGHT_LAND", pilot.land())
	var waited := 0
	while pilot.atmo.state != AtmoFlight.State.PARKED and waited < 60 * 10:
		pilot.set_external_command({ "throttle": 0.0 })
		await physics_frame
		waited += 1
	out("FIGHT_LAND_STATE", pilot.atmo.state_label())
	out("FIGHT_LAND_ABOARD", c.aboard(pilot.atmo.position() + Vector3(0, 1, 0)))
	pilot.set_external_command({})


## Off the cruiser's bay side, Z: round the hull, in, down on the pad.
func _dock(c) -> void:
	pilot._seat_arriving()
	var start: Vector3 = c.frame * Vector3(-400, 120, -60)      # off the port side, the far one: over the top
	pilot.atmo.place_flying(start, Vector3.FORWARD, 0.0, 0.5)
	pilot._set_hull(true)
	out("NEAR_CRUISER", pilot.near_cruiser())
	out("DOCK_STARTED", pilot.dock())
	var waited := 0
	while pilot.atmo.state != AtmoFlight.State.PARKED and waited < 60 * 90:
		await physics_frame
		waited += 1
	out("DOCK_S", snappedf(waited / 60.0, 0.1))
	out("DOCK_STATE", pilot.atmo.state_label())
	var pad: Vector3 = c.frame * (CruiserHull.dock_pad().at as Vector3)
	out("DOCK_PAD_ERR_M", snappedf(Vector2(pilot.atmo.position().x - pad.x, pilot.atmo.position().z - pad.z).length(), 0.1))
	out("DOCKINGS", pilot.dockings)
	out("FIGHT_DOCKED_HELD", pilot.fight != null and pilot.fight.sheltered)
	out("EXITED", pilot.exit_ship())
	await frames(20)
	out("PLAYER_ABOARD", c.aboard(player.global_position))
	out("PLAYER_ON_FLOOR", player.is_on_floor())


func _aboard(c) -> void:
	var n: int = (c.cfg.get("crew", []) as Array).size() + 2
	await frames(n + 30)
	out("WOKE", c.woke)
	out("CREW", c.crew.size())
	out("GENERAL", c.general != null and is_instance_valid(c.general))
	out("GARRISON", c.garrison != null and c.garrison.members.size())
	out("GARRISON_HOSTILE", c.garrison != null and c.garrison.always_hostile)
	var waited := 0
	while not c.nav_ready and waited < 600:
		await physics_frame
		waited += 1
	out("NAV_READY", c.nav_ready)
	if c.nav_ready:
		var a: Vector3 = c.frame * Vector3(0, CruiserHull.DECK_Y, -60)
		var b: Vector3 = c.frame * Vector3(0, CruiserHull.BRIDGE_Y, 230)
		var path: PackedVector3Array = demo.nav.path(a, b)
		out("NAV_BAY_TO_BRIDGE", path.size() >= 2 and path[path.size() - 1].distance_to(b) < 2.0)
	# The crew stand on their decks (none fell through).
	var fallen := 0
	for g in c.crew:
		if is_instance_valid(g) and not c.aboard(g.global_position):
			fallen += 1
	out("CREW_FALLEN", fallen)
	out("FIGHT_ABOARD_HELD", pilot.fight != null and pilot.fight.sheltered)
	pilot.end_fight("left", true)      # the ship's own guns next, flown outside the mouth: no fight to take her
	await _ship_guns(c)
	await _shot_asleep(c)
	await _downed_aboard(c)
	var credits: int = WorldState.credits
	var locals: int = WorldState.standing.get("locals", 0)
	pilot.start_fight()                # a fight in the sky again, you on foot: his death ends it
	if c.general != null:
		c.general.apply_damage_from(10000.0, player)
	await frames(5)
	out("TAKEN", Story.cruiser_taken())
	out("FIGHT_ENDED_BY_GENERAL", pilot.fight == null and not pilot.fight_log.is_empty() \
		and str(pilot.fight_log.back().outcome) == "general")
	out("PAID", WorldState.credits - credits)
	out("LOCALS_GAIN", int(WorldState.standing.get("locals", 0)) - locals)
	out("CHAPTER", Story.chapter())
	out("ENCOUNTER_AFTER", pilot.encounter_id())
	# Away and back: the survivors are gone.
	player.global_position = c.frame.origin + Vector3(0, 0, 4000)
	await frames(5)
	out("CREW_AFTER_LEAVING", c.crew.size())


## Your ship's guns at troopers in the bay: from outside its mouth (through the
## shield) and parked on the pad. The guns cross on what is under the nose.
func _ship_guns(c) -> void:
	pilot._seat_arriving()
	pilot.atmo.reached_space = true
	out("GUNS_FROM_OUTSIDE", await _guns_at(c, c.crew[2], Vector3(140, -8, -30), false))
	out("GUNS_PARKED", await _guns_at(c, c.crew[3], CruiserHull.dock_pad().at, true))
	pilot.exit_ship()
	await frames(10)


## The nose on g's chest from `local` (cruiser frame), the trigger held up to 2 s:
## whether he died.
func _guns_at(c, g, local: Vector3, parked: bool) -> bool:
	for f in 120:
		if g.dead:
			break
		var chest: Vector3 = g.global_position + Vector3(0, 1.2, 0)
		var at: Vector3 = c.frame * local
		if parked:
			if f == 0:
				var flat := chest - at
				pilot.atmo.park(at, atan2(-flat.x, -flat.z))
		else:
			pilot.atmo.place_flying(at, (chest - at).normalized(), 0.0, 0.0)
			pilot.atmo.flight.basis = Basis.looking_at(chest - at, Vector3.UP)
		pilot.set_external_command({ "fire": true, "throttle": 0.0 })
		await physics_frame
	pilot.set_external_command({})
	return g.dead


## A trooper asleep (you far off, as in your ship) is still solid to a bolt, and
## wakes to fall when it kills him.
func _shot_asleep(c) -> void:
	var g = c.crew[5]
	c._was_aboard = false
	player.global_position = g.global_position + Vector3(0, 0, 700)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	await frames(3)
	out("ASLEEP", not g.can_process())
	var b = load("res://scenes/entities/bolt.tscn").instantiate()
	b.direction = Vector3.RIGHT
	b.speed = 60.0
	b.damage = 1000.0
	b.range_m = 30.0
	b.shooter = player
	b.sweep = true
	demo.add_child(b)
	b.global_position = g.global_position + Vector3(-3, 1.2, 0)
	await frames(30)
	out("ASLEEP_SHOT_DEAD", g.dead)
	out("ASLEEP_SHOT_WOKE", g.can_process())
	player.process_mode = Node.PROCESS_MODE_INHERIT


## Downed aboard: woken in the port's pit, and left there (not pulled back aboard).
func _downed_aboard(c) -> void:
	player.global_position = c.frame * ((CruiserHull.dock_pad().at as Vector3) + Vector3(-16, 0.1, 0))
	player.align_to_ground(true)
	await frames(10)
	player.apply_damage(100000.0)
	out("DOWNED_ABOARD", player.is_downed)
	await frames(60 * 4)
	out("DOWNED_WOKE", not player.is_downed and not player.locked)
	await frames(60 * 2)
	out("DOWNED_IN_TOWN_KM", snappedf(c.distance(player.global_position) / 1000.0, 0.1))
	player.global_position = c.frame * ((CruiserHull.dock_pad().at as Vector3) + Vector3(-16, 0.1, 0))
	player.align_to_ground(true)
	await frames(10)


func _finish() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_results"))
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines) + "\n")
	if demo != null:
		demo.queue_free()
		await frames(10)
	quit()
