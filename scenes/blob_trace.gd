extends SceneTree
## Issue #220 trace (headless, the real town scene): the desert blob is built on
## the home planet, out in the desert; it rolls about on the ground; it farts; and
## touching it kills the player on the spot, who then wakes again.
## Writes test_results/blob_trace.txt for tests/test_blob_trace.gut.gd.
##
## Run: godot --headless --fixed-fps 60 --path . -s res://scenes/blob_trace.gd

const OUT := "res://test_results/blob_trace.txt"

var demo
var player
var blob   ## DesertBlob (untyped: the scene's classes need the autoloads)
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


func _run() -> void:
	demo = load("res://scenes/town_demo.gd").new()
	demo.use_look = false
	demo.npc_brains = false
	get_root().add_child(demo)
	await frames(5)
	player = demo._player
	blob = demo.blob
	out("BLOB_BUILT", blob != null)
	if blob == null:
		_write()
		return
	out("RADIUS", blob.radius)
	out("PURPLE", blob._mat.albedo_color.b > blob._mat.albedo_color.g and blob._mat.albedo_color.r > blob._mat.albedo_color.g)
	var town: Vector3 = demo.town.spawn_pos()
	out("HOME_FROM_TOWN_M", int(blob.home.distance_to(town)))
	# ---------------------------------------------------------------- it rolls
	var p0: Vector3 = blob.global_position
	var b0: Basis = blob._ball.basis
	await frames(60 * 6)
	out("ROLLED_M", snappedf(blob.travelled, 0.1))
	out("MOVED", blob.global_position.distance_to(p0) > 2.0)
	out("SPUN", not blob._ball.basis.is_equal_approx(b0))
	var gp: Vector3 = blob._ground_at(blob.global_position)
	out("ON_GROUND", absf(blob.global_position.distance_to(gp) - blob.radius) < blob.radius * 0.25)
	# ---------------------------------------------------------------- it farts
	var f0: int = blob.farts
	blob._fart_left = 0.0
	await frames(2)
	out("FARTED", blob.farts > f0)
	out("FART_SOUND", blob._sfx.stream != null)
	# ---------------------------------------------------------------- touch = death
	var up: Vector3 = blob._up(blob.global_position)
	var side: Vector3 = up.cross(blob.heading).normalized()
	var at: Vector3 = blob._ground_at(blob.global_position + side * (blob.radius - 0.5))
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.controller.velocity = Vector3.ZERO
	player.controller.body_pos = at
	var died := false
	for i in 30:
		await physics_frame
		if player.is_downed:
			died = true
			break
	out("DIED_ON_TOUCH", died)
	out("KILLS", blob.kills)
	var woke := false
	for i in 60 * 12:
		await physics_frame
		if not player.is_downed:
			woke = true
			break
	out("WOKE", woke)
	out("WOKE_AWAY_FROM_BLOB", player.global_position.distance_to(blob.global_position) > blob.radius * 3.0)
	_write()


func _write() -> void:
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_results"))
		f = FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("BLOBTRACE wrote ", OUT, " (", lines.size(), " lines)")
	quit()
