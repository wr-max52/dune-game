extends SceneTree
## Renders a filmstrip of a body falling as a ragdoll (issue #25): a trooper shot
## from the front, one frame at each of TIMES, side by side.
##
##   godot --path . -s res://tools/look/shoot_ragdoll.gd [-- who=trooper kick=3.5 out=res://docs/lookdev/gear/06_ragdoll.png]

const TIMES := [0.0, 0.15, 0.3, 0.5, 0.8, 2.5]
const CELL := Vector2i(420, 520)

var _who := "trooper"
var _kick := 3.5
var _out := "res://docs/lookdev/gear/06_ragdoll.png"
var _body: Node3D
var _cam: Camera3D


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("who="):
			_who = a.substr(4)
		elif a.begins_with("kick="):
			_kick = float(a.substr(5))
		elif a.begins_with("out="):
			_out = a.substr(4)
	DisplayServer.window_set_size(CELL)
	root.size = CELL
	_stage()
	_shoot.call_deferred()


func _stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#b9ab98")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#6e7fa6")
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_color = Color("#ffc48a")
	key.light_energy = 2.0
	key.shadow_enabled = true
	key.rotation_degrees = Vector3(-40, -30, 0)
	root.add_child(key)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	mi.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("#c9955a")
	gm.roughness = 1.0
	mi.material_override = gm
	ground.add_child(mi)
	root.add_child(ground)
	_body = CharacterKit.new(LookMaterials.new()).build(_who)
	root.add_child(_body)
	_cam = Camera3D.new()
	root.add_child(_cam)
	_cam.fov = 40.0
	_cam.look_at_from_position(Vector3(4.6, 1.7, -0.6), Vector3(0, 0.6, -0.7))
	_cam.make_current()


func _shoot() -> void:
	await process_frame
	await physics_frame
	if _body.has_meta("skin"):
		(_body.get_meta("skin") as SkinnedBody).sync(_body)
	var rd := Ragdoll.new(_body.get_meta("joints"))
	# Shot from the front (+Z is the body's front), so it falls back toward -Z; the
	# camera sits to the side.
	var kick := Ragdoll.kick_for(_body.global_position, Vector3(0, 1.2, 6.0), 30.0, rd.cfg).normalized() * _kick
	rd.start(Vector3.ZERO, kick, root.get_world_3d().direct_space_state)
	var sheet := Image.create(CELL.x * TIMES.size(), CELL.y, false, Image.FORMAT_RGBA8)
	var t := 0.0
	var dt := 1.0 / 60.0
	for i in TIMES.size():
		while t < float(TIMES[i]) - 0.0001:
			rd.step(dt)
			t += dt
		if _body.has_meta("skin"):
			(_body.get_meta("skin") as SkinnedBody).sync(_body)
		await process_frame
		await process_frame
		var img := root.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		if img.get_size() != CELL:
			img.resize(CELL.x, CELL.y)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(i * CELL.x, 0))
	var p := ProjectSettings.globalize_path(_out)
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	sheet.save_png(p)
	print("ragdoll: wrote ", p, "  (asleep %s after %.1fs, %d rays)" % [rd.asleep, rd.elapsed, rd.rays_cast])
	quit()
