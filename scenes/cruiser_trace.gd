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
	Story.skip_to("cruiser")
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
	var credits: int = WorldState.credits
	var locals: int = WorldState.standing.get("locals", 0)
	if c.general != null:
		c.general.apply_damage_from(10000.0, player)
	await frames(5)
	out("TAKEN", Story.cruiser_taken())
	out("PAID", WorldState.credits - credits)
	out("LOCALS_GAIN", int(WorldState.standing.get("locals", 0)) - locals)
	out("CHAPTER", Story.chapter())
	out("ENCOUNTER_AFTER", pilot.encounter_id())
	# Away and back: the survivors are gone.
	player.global_position = c.frame.origin + Vector3(0, 0, 4000)
	await frames(5)
	out("CREW_AFTER_LEAVING", c.crew.size())


func _finish() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_results"))
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines) + "\n")
	if demo != null:
		demo.queue_free()
		await frames(10)
	quit()
