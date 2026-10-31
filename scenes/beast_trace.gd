extends SceneTree
## Issue #220 trace (headless, the real town scene): the home planet's beast is
## built from the planet's data (its name, out in the desert); a beetle-centipede
## (issue #266), it crawls about on the ground, its body following and legs stepping; it farts; touching it kills the player on the spot, who then wakes
## again; a stray bolt from someone else only hurts it, but the player's sets it
## chasing until they are 1 km away; the locals talk of it by name and the AI
## characters are briefed on it; and killed, it stays dead.
## Writes test_results/beast_trace.txt for tests/test_beast_trace.gut.gd.
##
## Run: godot --headless --fixed-fps 60 --path . -s res://scenes/beast_trace.gd

const OUT := "res://test_results/beast_trace.txt"

var demo
var player
var beast   ## PlanetBeast (untyped: the scene's classes need the autoloads)
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


func _put_player(at: Vector3) -> void:
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.controller.velocity = Vector3.ZERO
	player.controller.body_pos = at


func _run() -> void:
	demo = load("res://scenes/town_demo.gd").new()
	demo.use_look = false
	demo.npc_brains = false
	get_root().add_child(demo)
	await frames(5)
	player = demo._player
	beast = demo.beast
	out("BEAST_BUILT", beast != null)
	if beast == null:
		_write()
		return
	out("NAME", beast.beast_name)
	out("NAME_FROM_PLANET", beast.beast_name == str(demo.planet.get("beast", {}).get("name", "")) and beast.beast_name != "")
	out("HP", int(beast.hp))
	out("RADIUS", beast.radius)
	out("SEGMENTS", beast.segments.size())
	out("LEGS", beast._legs.size())
	out("MANDIBLES", beast._mandibles.size())
	out("DESERT_HIDE", beast._mat.albedo_color.r >= beast._mat.albedo_color.b)
	var town: Vector3 = demo.town.spawn_pos()
	out("HOME_FROM_TOWN_M", int(beast.home.distance_to(town)))
	# ---------------------------------------------------------------- known of
	var brief: String = PlanetBeast.brief(demo.planet)
	out("BRIEF_NAMES_IT", brief.contains(beast.beast_name))
	var lore: Array = PlanetBeast.lore(demo.planet)
	out("LORE_LINES", lore.size())
	out("LORE_NAMES_IT", lore.any(func(l): return str(l).contains(beast.beast_name)))
	var folk = demo.get("townsfolk")
	if folk == null and not demo.locals.is_empty():
		folk = load("res://src/systems/npc/townsfolk.gd").new()      # npc_brains is off here: run the locals ourselves
		demo.add_child(folk)
		folk.setup(demo, demo.locals)
	if folk != null and not folk.members.is_empty():
		folk._beast_next = 0.0
		var local = folk.members[0]
		_put_player(local.global_position + local.global_basis.z * 1.5)
		await frames(3)
		out("LOCAL_SPOKE_OF_IT", not folk.beast_said.is_empty() and lore.has(folk.beast_said[0]))
		_put_player(town)
		await frames(2)
	else:
		out("LOCAL_SPOKE_OF_IT", "no_locals")
	# ---------------------------------------------------------------- it rolls
	var p0: Vector3 = beast.global_position
	var tail0: Vector3 = beast.segments[-1].node.global_position
	var leg0: Vector3 = beast._legs[0].rotation
	await frames(60 * 6)
	out("ROLLED_M", snappedf(beast.travelled, 0.1))
	out("MOVED", beast.global_position.distance_to(p0) > 2.0)
	out("BODY_FOLLOWS", beast.segments[-1].node.global_position.distance_to(tail0) > 2.0
		and beast.segments[0].node.global_position.distance_to(beast.global_position) < float(beast.cfg.get("segment_gap", 3.2)) * 2.0)
	out("LEGS_STEP", not beast._legs[0].rotation.is_equal_approx(leg0))
	var s_last = beast.segments[-1]
	var tg: Vector3 = beast._ground_at(s_last.node.global_position)
	out("TAIL_ON_GROUND", absf(s_last.node.global_position.distance_to(tg) - float(s_last.r)) < float(s_last.r) * 0.35)
	var gp: Vector3 = beast._ground_at(beast.global_position)
	out("ON_GROUND", absf(beast.global_position.distance_to(gp) - beast.radius) < beast.radius * 0.25)
	# ---------------------------------------------------------------- it farts
	var f0: int = beast.farts
	beast._fart_left = 0.0
	await frames(2)
	out("FARTED", beast.farts > f0)
	out("FART_SOUND", beast._sfx.stream != null)
	# ---------------------------------------------------------------- bolts find it
	var up: Vector3 = beast._up(beast.global_position)
	var side: Vector3 = up.cross(beast.heading).normalized()
	var q := PhysicsRayQueryParameters3D.create(beast.global_position + side * (beast.radius + 20.0), beast.global_position)
	var hit: Dictionary = beast.get_world_3d().direct_space_state.intersect_ray(q)
	out("RAY_HITS_IT", not hit.is_empty() and hit.collider == beast)
	# ---------------------------------------------------------------- touch = death
	var mid = beast.segments[beast.segments.size() / 2]
	_put_player(beast._ground_at(mid.node.global_position + side * float(mid.r) * 0.8))
	var died := false
	for i in 30:
		await physics_frame
		if player.is_downed:
			died = true
			break
	out("DIED_ON_TOUCH", died)
	out("BODY_KILLS", died)
	out("KILLS", beast.kills)
	var woke := false
	for i in 60 * 12:
		await physics_frame
		if not player.is_downed:
			woke = true
			break
	out("WOKE", woke)
	out("WOKE_AWAY_FROM_BEAST", player.global_position.distance_to(beast.global_position) > beast.radius * 3.0)
	await frames(60 * 4)      # out of the revive grace
	# ---------------------------------------------------------------- hurt by someone else
	var stranger := Node3D.new()
	demo.add_child(stranger)
	beast.apply_damage_from(10.0, stranger)
	out("STRAY_BOLT_HURTS", int(beast.hp) == 990)
	out("STRAY_BOLT_NO_CHASE", not beast.chasing)
	# ---------------------------------------------------------------- hurt by the player: chase
	up = beast._up(beast.global_position)
	side = up.cross(beast.heading).normalized()
	_put_player(beast._ground_at(beast.global_position + side * 60.0))
	player.locked = true
	await frames(2)
	beast.apply_damage_from(12.0, player)
	out("PLAYER_HIT_CHASES", beast.chasing)
	var d0: float = beast.global_position.distance_to(player.global_position)
	var died_to_chase := false
	for i in 60 * 20:
		await physics_frame
		if player.is_downed:
			died_to_chase = true
			break
	out("CHASE_CLOSED_M", int(d0 - beast.global_position.distance_to(player.global_position)))
	out("CHASE_CAUGHT", died_to_chase)
	out("CHASE_STOPS_ON_KILL", not beast.chasing)
	_put_player(town)          # back on your feet, away from it
	player.revive(0.0)
	player.locked = false
	await frames(2)
	out("ALIVE_BEFORE_BLADE", not player.is_downed and beast.kills == 2)
	# Hurt it, then be far away: it gives up.
	beast.apply_damage(20.0)
	out("BLADE_HIT_CHASES", beast.chasing)
	var far_side: Vector3 = beast._up(beast.global_position).cross(beast.heading).normalized()
	_put_player(beast._ground_at(beast.global_position + far_side * 1100.0))
	player.locked = true
	await frames(5)
	out("GAVE_UP_AT_1KM", not beast.chasing)
	player.locked = false
	# ---------------------------------------------------------------- 1000 hp, then dead for good
	var hits := 0
	while not beast.dead and hits < 200:
		beast.apply_damage_from(24.0, player)
		hits += 1
	out("DEAD", beast.dead)
	out("HITS_TO_KILL", hits)
	out("SLAIN_FLAG", PlanetBeast.is_slain(str(demo.planet.id)))
	out("NOT_REBUILT", not PlanetBeast.lives_on(demo.planet))
	out("LORE_AFTER", PlanetBeast.lore(demo.planet) != lore and not PlanetBeast.lore(demo.planet).is_empty())
	out("BRIEF_AFTER_SLAIN", PlanetBeast.brief(demo.planet).contains("killed it"))
	var k0: int = beast.kills
	_put_player(beast._ground_at(beast.global_position))
	await frames(10)
	out("DEAD_DOES_NOT_KILL", beast.kills == k0 and not player.is_downed)
	_write()


func _write() -> void:
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_results"))
		f = FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("BEASTTRACE wrote ", OUT, " (", lines.size(), " lines)")
	quit()
