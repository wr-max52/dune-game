extends SceneTree
## Filmstrip of a rigged droid's clips (issue #25): idle, then frames through its
## walk, run and fall, side by side, as DroidKit builds it in game.
##
##   godot --path . -s res://tools/look/shoot_droid_walk.gd [-- kind=assassin variant=bone]

const CELL := Vector2i(360, 520)
## [role, seconds into the clip]
const FRAMES := [["idle", 0.5], ["walk", 0.0], ["walk", 0.26], ["walk", 0.52], ["run", 0.3], ["die", 2.5]]

var _kind := "assassin"
var _variant := "bone"
var _look: Node3D


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("kind="):
			_kind = a.substr(5)
		elif a.begins_with("variant="):
			_variant = a.substr(8)
	DisplayServer.window_set_size(CELL)
	root.size = CELL
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#b9ab98")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#6e7fa6")
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_color = Color("#ffc48a")
	key.light_energy = 2.0
	key.shadow_enabled = true
	key.rotation_degrees = Vector3(-40, -30, 0)
	root.add_child(key)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("#c9955a")
	ground.material_override = gm
	root.add_child(ground)
	var dc := DroidRoster.config()
	_look = DroidKit.build(_kind, DroidRoster.variant_cfg(_kind, _variant), LookMaterials.new(),
		dc.get("kinds", {}).get(_kind, {}).get("look", {}))
	root.add_child(_look)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.fov = 40.0
	cam.look_at_from_position(Vector3(4.2, 1.7, -1.6), Vector3(0, 1.0, 0.3))
	cam.make_current()
	_shoot.call_deferred()


func _shoot() -> void:
	var sheet := Image.create(CELL.x * FRAMES.size(), CELL.y, false, Image.FORMAT_RGBA8)
	var ap: AnimationPlayer = null
	for n in _look.find_children("*", "Node3D", true, false):
		if n.has_meta("anim"):
			ap = n.get_meta("anim")
	for i in FRAMES.size():
		DroidKit.play_anim(_look, str(FRAMES[i][0]), 1.0, 0.0)
		if ap != null:
			ap.seek(float(FRAMES[i][1]), true)
			ap.pause()
		await process_frame
		await process_frame
		var img := root.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		if img.get_size() != CELL:
			img.resize(CELL.x, CELL.y)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(i * CELL.x, 0))
	var p := ProjectSettings.globalize_path("res://docs/lookdev/gear/09_%s_clips.png" % _kind)
	sheet.save_png(p)
	print("droid_walk: wrote ", p, " (rigged: %s)" % (ap != null))
	quit()
