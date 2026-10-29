extends SceneTree
## Review stills of the energy saber: the default (blue, light hilt) and the red
## saber (red, black hilt) as the player holds them, plus the red saber pickup.
## One row per saber: full length, angled, hilt close-up.
##
##   godot --path . -s res://tools/look/shoot_saber.gd -- out=res://docs/lookdev/saber/02_sabers.png

const CELL := Vector2i(640, 640)
const RED := Color("#ff2a2a")
const DARK_HILT := "res://assets/gear/saber_hilt_dark.glb"

var _cam: Camera3D
var _out := "res://docs/lookdev/saber/02_sabers.png"


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
	DisplayServer.window_set_size(CELL)
	root.size = CELL
	root.msaa_3d = Viewport.MSAA_4X
	_stage()
	_shoot.call_deferred()


func _stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#16171c")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#8a90a0")
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.15
	env.glow_hdr_threshold = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_energy = 1.6
	key.rotation_degrees = Vector3(-30, -40, 0)
	root.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color("#aab8ff")
	rim.light_energy = 0.8
	rim.rotation_degrees = Vector3(-10, 150, 0)
	root.add_child(rim)
	_cam = Camera3D.new()
	_cam.fov = 30.0
	root.add_child(_cam)
	_cam.make_current()


func _shoot() -> void:
	var kit := CharacterKit.new(LookMaterials.new(), -1000.0)
	var rows := []
	var blue := kit.make_energy_sword()
	var red := kit.make_energy_sword()
	CharacterKit.recolor_energy_sword(red, RED)
	kit.set_sword_hilt(red, DARK_HILT)
	rows.append(blue)
	rows.append(red)
	# [camera position, look-at point, sword rotation]: full, angled, hilt close-up.
	var views := [
		[Vector3(0.0, 0.42, 2.6), Vector3(0, 0.42, 0), Vector3(0, 0, 0)],
		[Vector3(0.5, 0.35, 2.2), Vector3(0, 0.3, 0), Vector3(0, 30, -35)],
		[Vector3(0.18, -0.06, 0.55), Vector3(0, -0.1, 0), Vector3(0, -40, 0)],
	]
	var sheet: Image = null
	for r in rows.size():
		var sword: Node3D = rows[r]
		root.add_child(sword)
		for c in views.size():
			var v: Array = views[c]
			sword.rotation_degrees = v[2]
			_cam.position = v[0]
			_cam.look_at(v[1])
			var img := await _grab()
			if sheet == null:
				sheet = Image.create(CELL.x * views.size(), CELL.y * (rows.size() + 1), false, img.get_format())
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(c * CELL.x, r * CELL.y))
		sword.queue_free()
	# Last row: the red saber pickup as it lies in the wreck, from three sides.
	var pickup := ItemKit.new().build("red_saber")
	root.add_child(pickup)
	var pv := [Vector3(0.2, 0.9, 1.6), Vector3(1.4, 0.6, 0.6), Vector3(-0.6, 0.35, 0.5)]
	var targets := [Vector3(0.3, 0.05, 0), Vector3(0.3, 0.05, 0), Vector3(-0.15, 0.05, 0)]
	for c in pv.size():
		_cam.position = pv[c]
		_cam.look_at(targets[c])
		var img := await _grab()
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(c * CELL.x, rows.size() * CELL.y))
	var out := ProjectSettings.globalize_path(_out)
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	sheet.save_png(out)
	print("saber: wrote ", out)
	quit()


func _grab() -> Image:
	for f in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
