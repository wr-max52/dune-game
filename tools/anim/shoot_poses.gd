extends SceneTree
## Issue #87: a contact sheet of the procedural body poses (BodyAnimator + the
## weapon carry), one character per tile on a bare floor, so a change to the
## animation can be looked at without playing the game. Saves
## test_results/anim/poses.png (and one PNG per tile).
##
## Needs a real renderer: ./tools/anim/shoot_poses.sh [archetype=remnant_trooper]
## archetype=player drives the real PlayerAvatar (pistol and rifle, third person).

const OUT := "res://test_results/anim"
const TILE := Vector2i(320, 420)
const COLS := 5

var kit: CharacterKit
var cam: Camera3D
var archetype := "remnant_trooper"
var _cases: Array = []
var _i := -1
var _wait := 0
var _frame := 0
var _body: Node3D
var _sheet: Image
var _label := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("archetype="):
			archetype = a.substr(10)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var root := Node3D.new()
	get_root().add_child(root)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#c8b89a")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("#9a8f80")
	env.environment.ambient_light_energy = 0.9
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.shadow_enabled = true
	root.add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("#b08a5a")
	floor_mi.material_override = fm
	root.add_child(floor_mi)
	cam = Camera3D.new()
	cam.fov = 40.0
	root.add_child(cam)
	cam.current = true
	kit = CharacterKit.new(LookMaterials.new(), -1000.0)
	var free := BodyAnimator.UPPER_FREE
	var rifle := BodyAnimator.UPPER_RIFLE
	_cases = [
		["idle", { "speed": 0.0 }, 90, free, -1.0],
		["walk_a", { "speed": 3.2 }, 41, free, -1.0],
		["walk_b", { "speed": 3.2 }, 52, free, -1.0],
		["sprint_a", { "speed": 7.0, "sprint": true }, 40, free, -1.0],
		["sprint_b", { "speed": 7.0, "sprint": true }, 47, free, -1.0],
		["jump_up", { "speed": 0.0, "grounded": false, "vy": 5.0 }, 30, free, -1.0],
		["jump_run", { "speed": 6.0, "grounded": false, "vy": 0.5 }, 30, free, -1.0],
		["fall", { "speed": 0.0, "grounded": false, "vy": -7.0 }, 30, free, -1.0],
		["kneel", { "speed": 0.0, "crouch": true }, 60, free, -1.0],
		["duck_walk", { "speed": 1.8, "crouch": true }, 50, free, -1.0],
		["slide", { "speed": 6.0, "slide": true }, 40, free, -1.0],
		["rifle_rest", { "speed": 0.0 }, 60, rifle, 0.0],
		["rifle_rest_walk", { "speed": 3.2 }, 45, rifle, 0.0],
		["rifle_aim", { "speed": 0.0, "aim_pitch": 0.0 }, 60, rifle, 1.0],
		["rifle_walk_aim", { "speed": 3.0, "aim_pitch": 0.0 }, 45, rifle, 1.0],
		["rifle_kneel_aim", { "speed": 0.0, "crouch": true }, 60, rifle, 1.0],
		["rifle_sprint", { "speed": 6.5, "sprint": true }, 45, rifle, 0.0],
		["rifle_half", { "speed": 0.0 }, 60, rifle, 0.5],
	]
	if archetype == "player":
		var aim := BodyAnimator.UPPER_AIM
		_cases = [
			["pistol_rest", { "speed": 0.0 }, 60, aim, 0.0],
			["pistol_rest_walk", { "speed": 3.2 }, 45, aim, 0.0],
			["pistol_aim", { "speed": 0.0 }, 60, aim, 1.0],
			["pistol_walk_aim", { "speed": 3.0 }, 45, aim, 1.0],
			["pistol_kneel_aim", { "speed": 0.0, "crouch": true }, 60, aim, 1.0],
			["rifle_rest", { "speed": 0.0 }, 60, rifle, 0.0],
			["rifle_rest_walk", { "speed": 3.2 }, 45, rifle, 0.0],
			["rifle_aim", { "speed": 0.0 }, 60, rifle, 1.0],
			["rifle_walk_aim", { "speed": 3.0 }, 45, rifle, 1.0],
			["rifle_sprint", { "speed": 6.5, "sprint": true }, 45, rifle, 0.0],
		]
	var rows := int(ceil(_cases.size() / float(COLS)))
	_sheet = Image.create(TILE.x * COLS, TILE.y * rows, false, Image.FORMAT_RGBA8)


## Build a fresh body and pose it the way npc_body.gd / player_avatar.gd do.
func _pose_case(c: Array) -> void:
	if _body != null:
		_body.queue_free()
	if archetype == "player":
		_pose_player(c)
		return
	_body = kit.build(archetype)
	get_root().get_child(get_root().get_child_count() - 1).add_child(_body)
	var joints: Dictionary = _body.get_meta("joints")
	var w: Node3D = _body.get_meta("weapon") if _body.has_meta("weapon") else null
	var aim_xf := w.transform if w != null else Transform3D()
	var anim := BodyAnimator.new()
	var inp: Dictionary = (c[1] as Dictionary).duplicate()
	inp["upper"] = c[3]
	if float(c[4]) >= 0.0:
		inp["ready"] = float(c[4])
	if not inp.has("aim_pitch"):
		inp["aim_pitch"] = -0.25
	var out := {}
	for f in int(c[2]):
		out = anim.step(1.0 / 60.0, inp)
	for jn in out.joints:
		if joints.has(jn):
			(joints[jn] as Node3D).rotation_degrees = out.joints[jn]
	(joints.pelvis as Node3D).position.y = out.pelvis_y
	(joints.pelvis as Node3D).position.x = out.pelvis_x
	if w != null:
		var grips: Dictionary = w.get_meta("grips", {})
		if c[3] == BodyAnimator.UPPER_FREE:
			w.visible = false
		else:
			var t := float(c[4])
			t = t * t * (3.0 - 2.0 * t)
			w.transform = WeaponCarry.blend(WeaponCarry.rest_xf("rifle", grips.get("r", Vector3.ZERO)), aim_xf, t)
			if grips.has("r"):
				kit.reach(_body, "r", w.transform * (grips.r as Vector3), Vector3(-0.5, -0.7, -0.5))
			if grips.has("l"):
				kit.reach(_body, "l", w.transform * (grips.l as Vector3), Vector3(0.6, -0.7, -0.4))
	if _body.has_meta("skin"):
		(_body.get_meta("skin") as SkinnedBody).sync(_body)
	# Three-quarter view from the model's front right.
	var at := Vector3(0, 0.85, 0)
	cam.global_transform = Transform3D(Basis(), at + Vector3(-2.4, 0.4, 2.4)).looking_at(at, Vector3.UP)


func _process(_d: float) -> bool:
	_frame += 1
	if _frame < 5:
		return false
	if _wait > 0:
		_wait -= 1
		if _wait == 0:
			var img := get_root().get_texture().get_image()
			# The window may render at a HiDPI scale: crop the same share of it.
			var vs := img.get_size()
			var k := vs.y / 720.0
			var sz := Vector2i(int(TILE.x * k * 1.6), int(TILE.y * k * 1.6))
			var tile := img.get_region(Rect2i((vs.x - sz.x) / 2, (vs.y - sz.y) / 2, sz.x, sz.y))
			tile.resize(TILE.x, TILE.y)
			tile.convert(Image.FORMAT_RGBA8)
			tile.save_png(ProjectSettings.globalize_path("%s/%s.png" % [OUT, _label]))
			_sheet.blit_rect(tile, Rect2i(Vector2i.ZERO, TILE), Vector2i(_i % COLS * TILE.x, _i / COLS * TILE.y))
			print("POSE ", _label)
		return false
	_i += 1
	if _i >= _cases.size():
		_sheet.save_png(ProjectSettings.globalize_path(OUT + "/poses.png"))
		print("SHOOT POSES: done -> ", ProjectSettings.globalize_path(OUT + "/poses.png"))
		return true
	_label = str(_cases[_i][0])
	_pose_case(_cases[_i])
	_wait = 4
	return false


## The real player avatar: the weapon in hand, carry held at the case's ready.
func _pose_player(c: Array) -> void:
	var av := PlayerAvatar.new(LookMaterials.new(), {})
	_body = av
	get_root().get_child(get_root().get_child_count() - 1).add_child(av)
	av.build_weapons(["pistol_blaster", "rifle_blaster"])
	av.current = "pistol_blaster" if c[3] == BodyAnimator.UPPER_AIM else "rifle_blaster"
	av.drawn = 1.0
	var inp: Dictionary = (c[1] as Dictionary).duplicate()
	var v := Vector3(0, 0, float(inp.get("speed", 0.0)))
	for f in int(c[2]):
		av.carry.ready = float(c[4])
		av.carry._hold = 0.0 if float(c[4]) < 0.5 else 1.0
		av.aim_wanted = float(c[4]) >= 0.5
		av.animate(1.0 / 60.0, { "velocity": v, "grounded": true, "crouch": inp.get("crouch", false),
			"sprint": inp.get("sprint", false), "cam_yaw": 0.0, "aim_pitch": 0.0, "upper": c[3] })
	var at := Vector3(0, 0.85, 0)
	cam.global_transform = Transform3D(Basis(), at + Vector3(-2.4, 0.4, 2.4)).looking_at(at, Vector3.UP)
