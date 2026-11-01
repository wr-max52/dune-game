extends SceneTree
## Issue #269 trace (headless, the real town scene): the home planet's party barge
## is built from its planet block (a planet without one has none); the cantina's
## band on top, a DJ below, a crowd on every deck; the barge plays the cantina's
## club music; the boss sells it. It is parked at home until it is yours, and
## its people are only built once you come near.
## #269 cleanup: anyone on board can be killed (brains are off here, so nobody
## fights back; with them on the crowd does, see PartyBarge._provoke), standing never
## moves, and they are back after respawn_s of play; kill the whole band and the
## music stops until they are back. The owner dials a course at the control
## panel, engages and steps away: it swings round and cruises on autopilot with
## the player riding along on deck and the gangplank up; it stops dead against a
## box put in its way, sets off again on a new course; it blows up running into
## the beast (hurting the player aboard) and is built again at home later.
## Writes test_results/barge_trace.txt for tests/test_barge_trace.gut.gd.
##
## Run: godot --headless --fixed-fps 60 --path . -s res://scenes/barge_trace.gd

const OUT := "res://test_results/barge_trace.txt"

var demo
var player
var barge   ## PartyBarge (untyped: the scene's classes need the autoloads)
var lines := PackedStringArray()


func _initialize() -> void:
	WorldState.reset()
	GameFlow.reset()
	GameFlow.change_scene = func(_p: String) -> void: pass
	_run()


func out(k: String, v) -> void:
	lines.append("%s=%s" % [k, str(v)])
	print("  ", k, "=", v)


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func _put(local: Vector3) -> void:
	var at: Vector3 = barge.to_global(local) + barge._up(barge.global_position) * 0.1
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.controller.velocity = Vector3.ZERO
	player.controller.body_pos = at


func _danced(deck: String, n: int) -> bool:
	var before := {}
	for p in barge.people:
		if p.deck == deck and not p.dead:
			before[p.body] = (p.body as Node3D).transform
	for i in n:
		await physics_frame
	var moved := 0
	for b in before:
		if not (b as Node3D).transform.is_equal_approx(before[b]):
			moved += 1
	return before.size() > 0 and moved == before.size()


func _local(p: Vector3) -> Vector3:
	return barge.global_transform.affine_inverse() * p


func _run() -> void:
	demo = load("res://scenes/town_demo.gd").new()
	demo.use_look = false
	demo.npc_brains = false
	get_root().add_child(demo)
	await frames(5)
	player = demo._player
	barge = demo.barge
	out("BARGE_BUILT", barge != null)
	if barge == null:
		_write()
		return
	out("NAME", barge.barge_name)
	out("BOSS", barge.boss_name)
	out("NONE_WITHOUT_BLOCK", not load("res://src/systems/world/party_barge.gd").lives_on({ "id": "x" }))
	out("HOME_FROM_TOWN_M", int(barge.home.distance_to(demo.town.spawn_pos())))
	# ---------------------------------------------------------------- built late, parked till bought
	out("NO_PARTY_FROM_TOWN", barge.people.is_empty() and not barge.party_built)
	var parked_at: Vector3 = barge.global_position
	_put(Vector3(0, barge._y[2] + 0.1, 14.0))
	var built_in := -1
	for i in 600:
		await physics_frame
		if barge.party_built:
			built_in = i
			break
	out("PARTY_BUILT_NEAR_TICKS", built_in)
	out("PARTY_BUILT_NEAR", built_in > 0)
	out("PARKED_UNTIL_BOUGHT", barge.global_position.distance_to(parked_at) < 0.001 and barge.speed == 0.0)
	out("BAND", barge.band.size())
	out("BAND_ON_TOP", barge.band.filter(func(p): return p.deck == "top").size())
	out("DJ_BELOW", barge.band.filter(func(p): return p.deck == "lower" and p.perform == "dj").size())
	for deck in ["top", "lower", "steerage"]:
		out("CROWD_" + deck.to_upper(), barge.people.filter(func(p): return p.deck == deck and p.kind == "dancer").size())
	out("CLUB", barge._music != null and barge._music.playlist == str(demo.planet.get("cfg", {}).get("club", "")))
	# ---------------------------------------------------------------- the people: killable, back later
	var standing: Dictionary = WorldState.standing.duplicate(true)
	var dancer: Dictionary = barge.people.filter(func(p): return p.kind == "dancer" and p.deck == "top")[0]
	dancer.hit.apply_damage(20.0)
	out("HURT_NOT_DEAD", not dancer.dead and float(dancer.hp) < float(barge.cfg.person_hp))
	dancer.hit.apply_damage_from(500.0, player)
	await frames(30)
	out("KILLED", dancer.dead and barge.kills == 1)
	out("BODY_DOWN", (dancer.body as Node3D).transform != dancer.rest)
	out("HIT_OFF_WHEN_DEAD", dancer.hit.collision_layer == 0)
	out("STANDING_UNCHANGED", WorldState.standing == standing)
	var guard: Dictionary = barge.people.filter(func(p): return p.kind == "guard")[0]
	guard.hit.apply_blade_hit(500.0, Vector3.RIGHT)
	out("GUARD_KILLED", guard.dead)
	WorldState.clock += float(barge.cfg.respawn_s) + 1.0
	await frames(40)
	out("RESPAWNED", not dancer.dead and not guard.dead and barge.respawned >= 2)
	out("HIT_BACK", dancer.hit.collision_layer != 0)
	for p in barge.band:
		p.hit.apply_damage(1000.0)
	await frames(2)
	out("BAND_DEAD_MUSIC_OFF", barge._music != null and barge._music.playlist == "" and not barge.party_on())
	WorldState.clock += float(barge.cfg.respawn_s) + 1.0
	await frames(40)
	out("BAND_BACK_MUSIC_ON", barge._music != null and barge._music.playlist != "" and barge.party_on())
	out("STANDING_STILL_UNCHANGED", WorldState.standing == standing)
	# ---------------------------------------------------------------- aboard, the boss
	_put(Vector3(0, barge._y[2] + 0.1, 14.0))
	await frames(10)
	out("ON_TOP_DECK", barge.deck_of(player.global_position) == "top")
	out("NEAR_BOSS", barge.near_boss())
	out("PANEL_LOCKED", not barge.take_console())
	WorldState.credits = 100
	out("TOO_POOR", not barge.buy())
	WorldState.credits = 5000
	out("BOUGHT", barge.buy())
	out("OWNED_FLAG", load("res://src/systems/world/party_barge.gd").is_owned(str(demo.planet.id)))
	out("CREDITS_AFTER", WorldState.credits)
	out("BOSS_BELOW_PARTYING", barge.people.filter(func(p): return p.kind == "boss")[0].deck == "lower")
	# ---------------------------------------------------------------- the control panel, autopilot
	_put(barge.console_spot)
	await frames(3)
	out("NEAR_CONSOLE", barge.near_console())
	out("TOOK_CONSOLE", barge.take_console())
	out("LOCKED_AT_CONSOLE", player.locked)
	var h_start: Vector3 = barge.heading
	barge.external = { "dial": 1.0 }
	await frames(60)
	var dialled: float = rad_to_deg(barge._turn_to(barge.heading, barge.course, barge._up(barge.global_position)))
	out("DIALLED_DEG", snappedf(dialled, 0.1))
	out("DIAL_STARBOARD", dialled > 20.0 and dialled < 40.0)
	out("STILL_PARKED", absf(barge.speed) < 0.01)
	barge.external = { "engage": true }
	await frames(2)
	out("ENGAGED", barge.autopilot)
	barge.leave_console()
	out("WALK_FREE", not player.locked and not barge.at_console)
	var p0: Vector3 = barge.global_position
	var at0 := _local(player.global_position)
	var f0: int = barge.party_frames
	var top_party: bool = await _danced("top", 60 * 15)
	out("DROVE_M", snappedf(barge.global_position.distance_to(p0), 0.1))
	out("TOP_SPEED", snappedf(barge.speed, 0.01))
	out("SLOW", barge.speed <= float(barge.cfg.drive.max_speed) + 0.01 and barge.speed < 7.0)
	out("STILL_ON_AUTOPILOT", barge.autopilot)
	out("ON_COURSE", rad_to_deg(barge.heading.angle_to(barge.course)) < 3.0 and rad_to_deg(h_start.angle_to(barge.heading)) > 20.0)
	out("GANGPLANK_UP", not barge.gangplank_down)
	out("PARTY_WHILE_CRUISING", top_party and barge.party_frames - f0 >= 60 * 15)
	var slid: float = _local(player.global_position).distance_to(at0)
	out("PLAYER_SLID_M", snappedf(slid, 0.01))
	out("PLAYER_RIDES_ON_DECK", slid < 1.0 and barge.deck_of(player.global_position) == "top")
	# ---------------------------------------------------------------- it stops dead against something
	var up: Vector3 = barge._up(barge.global_position)
	var ahead: Vector3 = barge.to_global(Vector3(0, barge._y[1], -barge._L * 0.5 - 12.0))
	var rock := Transform3D(barge.global_transform.basis, ahead)
	demo.pilot.ground.add_box("trace_rock", "solid", Vector3(-8, -6, -2), Vector3(8, 6, 2), "", false, rock)
	var stopped := false
	for i in 60 * 10:
		await physics_frame
		if not barge.autopilot:
			stopped = true
			break
	out("STOPPED_AGAINST", stopped and absf(barge.speed) < 0.01 and barge.blocked_by == "trace_rock")
	out("STOPPED_SHORT", _local(ahead).z < -barge._L * 0.5 - float(barge.cfg.prow_m) * 0.5)
	out("STOPS", barge.stops)
	await frames(10)
	out("GANGPLANK_DOWN_WHEN_STOPPED", barge.gangplank_down)
	_put(barge.console_spot)
	await frames(2)
	barge.take_console()
	barge.course = -barge.heading
	barge.external = { "engage": true }
	var t0: float = barge.travelled
	await frames(60 * 20)
	out("OFF_AGAIN", barge.autopilot and barge.travelled - t0 > 5.0)
	barge.external = { "stop": true }
	await frames(60 * 5)
	out("ALL_STOP", not barge.autopilot and absf(barge.speed) < 0.05)
	barge.leave_console()
	# ---------------------------------------------------------------- below deck
	_put(Vector3(0.0, barge._y[1] + 0.1, -12.0))
	await frames(20)
	out("IN_LOWER", barge.deck_of(player.global_position) == "lower")
	out("LOWER_PARTY", await _danced("lower", 30))
	_put(Vector3(-2.0, barge._y[0] + 0.1, 0.0))
	await frames(20)
	out("IN_STEERAGE", barge.deck_of(player.global_position) == "steerage")
	out("STEERAGE_PARTY", await _danced("steerage", 30))
	out("STEERAGE_HEARS_CLUB", barge._music != null and barge._music.inside_fn.call(player.global_position))
	_put(Vector3(0, barge._y[2] + 0.1, 0.0))
	await frames(20)
	out("BACK_UP_TOP", barge.deck_of(player.global_position) == "top")
	out("TOP_STILL_PARTY", await _danced("top", 30))
	# ---------------------------------------------------------------- into the beast: boom
	var beast = demo.beast
	out("BEAST_HERE", beast != null)
	if beast != null:
		beast.set_physics_process(false)
		beast.set_process(false)
		beast.global_position = barge.to_global(Vector3(0, barge._y[0], -barge._L * 0.5 - 10.0))
		for s in beast.segments:
			(s.node as Node3D).global_position = beast.global_position
		_put(Vector3(-2.0, barge._y[2] + 0.1, 4.0))
		await frames(5)
		var hp0: float = float(player.health.hp)
		barge.course = barge.heading
		barge.engage()
		var boom := false
		for i in 60 * 20:
			await physics_frame
			if barge.wrecked:
				boom = true
				break
		out("EXPLODED", boom and barge.wrecks == 1)
		out("PLAYER_HURT", float(player.health.hp) < hp0 or bool(player.get("is_downed")))
		out("GONE", not barge.look.visible and barge.deck_of(barge.global_position + up * (barge._y[2] + 0.1)) == "")
		out("MUSIC_OFF_WRECKED", barge._music != null and barge._music.playlist == "")
		WorldState.clock += float(barge.cfg.rebuild_s) + 1.0
		await frames(5)
		out("REBUILT", not barge.wrecked and barge.look.visible)
		out("REBUILT_AT_HOME", barge._ground.distance_to(barge.home) < 1.0)
		out("STILL_YOURS", barge.owned)
		out("MUSIC_BACK", barge._music != null and barge._music.playlist != "")
	_write()


func _write() -> void:
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_results"))
		f = FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("BARGETRACE wrote ", OUT, " (", lines.size(), " lines)")
	quit()
