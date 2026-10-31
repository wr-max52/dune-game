extends SceneTree
## Issue #269 trace (headless, the real town scene): the home planet's party barge
## is built from its planet block (a planet without one has none); the band and a
## crowd on every deck; the barge plays the cantina's club music; the boss sells
## it; the new owner takes the helm and drives it, slowly, and the party goes on
## the whole time; then down to steerage (partying) and back up (still partying).
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
		if p.deck == deck:
			before[p.body] = (p.body as Node3D).transform
	for i in n:
		await physics_frame
	var moved := 0
	for b in before:
		if not (b as Node3D).transform.is_equal_approx(before[b]):
			moved += 1
	return before.size() > 0 and moved == before.size()


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
	out("NONE_WITHOUT_BLOCK", not PartyBarge.lives_on({ "id": "x" }))
	out("HOME_FROM_TOWN_M", int(barge.home.distance_to(demo.town.spawn_pos())))
	out("BAND", barge.band.size())
	for deck in ["top", "lower", "steerage"]:
		out("CROWD_" + deck.to_upper(), barge.people.filter(func(p): return p.deck == deck and p.kind == "dancer").size())
	out("CLUB", barge._music != null and barge._music.playlist == str(demo.planet.get("cfg", {}).get("club", "")))
	# ---------------------------------------------------------------- aboard, the boss
	_put(Vector3(0, barge._y[2] + 0.1, 14.0))
	await frames(10)
	out("ON_TOP_DECK", barge.deck_of(player.global_position) == "top")
	out("NEAR_BOSS", barge.near_boss())
	out("HELM_LOCKED", not barge.take_helm())
	WorldState.credits = 100
	out("TOO_POOR", not barge.buy())
	WorldState.credits = 5000
	out("BOUGHT", barge.buy())
	out("OWNED_FLAG", PartyBarge.is_owned(str(demo.planet.id)))
	out("CREDITS_AFTER", WorldState.credits)
	out("BOSS_BELOW_PARTYING", barge.people.filter(func(p): return p.kind == "boss")[0].deck == "lower")
	# ---------------------------------------------------------------- drive it
	_put(barge.helm_spot)
	await frames(3)
	out("NEAR_HELM", barge.near_helm())
	out("TOOK_HELM", barge.take_helm())
	var p0: Vector3 = barge.global_position
	var f0: int = barge.party_frames
	barge.external = { "throttle": 1.0, "steer": 0.3 }
	var top_party := await _danced("top", 60 * 15)
	out("DROVE_M", snappedf(barge.global_position.distance_to(p0), 0.1))
	out("TOP_SPEED", snappedf(barge.speed, 0.01))
	out("SLOW", barge.speed <= float(barge.cfg.drive.max_speed) + 0.01 and barge.speed < 7.0)
	out("PARTY_WHILE_DRIVING", top_party and barge.party_frames - f0 >= 60 * 15)
	out("BAND_PLAYS_WHILE_DRIVING", await _danced("top", 30))
	out("PLAYER_RIDES_AT_HELM", player.global_position.distance_to(barge.to_global(barge.helm_spot)) < 1.0)
	out("STILL_ON_DECK", barge.deck_of(player.global_position) == "top")
	barge.leave_helm()
	await frames(60 * 5)
	out("STOPPED", absf(barge.speed) < 0.05)
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
