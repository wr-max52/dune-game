class_name PlayerAvatar
extends Node3D
## The player's visible body (M11): a CharacterKit smuggler animated by
## BodyAnimator, holding whatever the weapon controller has out.
##
## - Faces where it moves (third person, hands free); faces the camera when a
##   weapon is out or in first person, so the legs strafe under an aimed torso.
## - Weapons are children of the chest. Their chest-space transform blends from the
##   holster to the ready pose while drawing; hands reach for the grips with the
##   kit's two-bone IK, so whatever the weapon does, the hands follow.
## - First person: the body stays (feet and shadow are real) but every mesh except
##   the forearms, hands and weapon renders as shadow only, and the chest follows
##   the camera pitch so the weapon stays in view. One body, both cameras.

const BodyAnimator := preload("res://src/systems/anim/body_animator.gd")
const SwordCombo := preload("res://src/systems/combat/sword_combo.gd")
const RETINT := preload("res://src/systems/look/shaders/weapon_retint.gdshader")
const LOOK_PATH := "res://content/look/hand_weapons.json"

const POLE_R := Vector3(-0.5, -0.7, -0.5)
const POLE_L := Vector3(0.6, -0.7, -0.4)

var kit: CharacterKit
var body: Node3D
var joints: Dictionary = {}
var anim := BodyAnimator.new()
var look: Dictionary = {}
var weapons: Dictionary = {}       ## id -> wrapper Node3D (child of chest)
var current := ""                  ## weapon in hand (or being drawn/holstered)
var drawn := 0.0                   ## 0 = holstered, 1 = ready
var sword_pose: Dictionary = {}    ## from SwordCombo.pose() while the sword is out
var first_person := false
var facing_yaw := 0.0              ## world yaw the body faces
var turn_rate := 10.0              ## rad/s
var last_frame: Dictionary = {}

var _arm_meshes: Array = []
var _other_meshes: Array = []


func _init(materials: LookMaterials = null) -> void:
	name = "Avatar"
	kit = CharacterKit.new(materials if materials != null else LookMaterials.new(), -1000.0)
	body = kit.build("player_smuggler", "idle")
	body.name = "Body"
	add_child(body)
	joints = body.get_meta("joints")
	look = CharacterKit._read_json(LOOK_PATH)
	_collect_meshes()


# ------------------------------------------------------------------ weapons

## Build the hand-weapon models once. `blade` is the sword node from the kit.
func build_weapons(ids: Array) -> void:
	for id in ids:
		if weapons.has(id):
			continue
		var wrap := Node3D.new()
		wrap.name = "W_" + str(id)
		var spec: Dictionary = look.get(id, {})
		if id == "energy_blade":
			var sword := kit.make_energy_sword()
			wrap.add_child(sword)
			wrap.set_meta("grips", sword.get_meta("grips"))
			wrap.set_meta("sword", sword)
		else:
			var model := _load_model(str(spec.get("model", "")), spec)
			var s := float(spec.get("scale", 1.0))
			if model != null:
				model.scale = Vector3.ONE * s
				wrap.add_child(model)
			var g: Dictionary = spec.get("grips", {})
			wrap.set_meta("grips", { "r": _v3(g.get("r", [0, 0, 0])) * s, "l": _v3(g.get("l", [0, 0, 0.3])) * s })
			var muzzle := Marker3D.new()
			muzzle.name = "Muzzle"
			muzzle.position = _v3(spec.get("muzzle", [0, 0, 1])) * s
			wrap.add_child(muzzle)
			var glow := MeshInstance3D.new()
			var gm := SphereMesh.new()
			gm.radius = 0.012
			gm.height = 0.024
			glow.mesh = gm
			var tint: Dictionary = spec.get("tint", {})
			var gmat := StandardMaterial3D.new()
			gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			gmat.albedo_color = Color.html(str(tint.get("glow", "#ff7a3a")))
			gmat.emission_enabled = true
			gmat.emission = gmat.albedo_color
			gmat.emission_energy_multiplier = 3.0
			glow.material_override = gmat
			muzzle.add_child(glow)
		wrap.visible = false
		(joints.chest as Node3D).add_child(wrap)
		weapons[id] = wrap
	_collect_meshes()
	set_first_person(first_person)


func _load_model(path: String, spec: Dictionary) -> Node3D:
	if path == "" or not ResourceLoader.exists(path):
		push_warning("PlayerAvatar: missing weapon model " + path)
		return null
	var scene = load(path)
	if not (scene is PackedScene):
		return null
	var n: Node3D = scene.instantiate()
	var tint: Dictionary = spec.get("tint", {})
	for mi in _meshes_under(n):
		var src: Material = mi.mesh.surface_get_material(0) if mi.mesh != null and mi.mesh.get_surface_count() > 0 else null
		var mat := ShaderMaterial.new()
		mat.shader = RETINT
		if src is BaseMaterial3D and (src as BaseMaterial3D).albedo_texture != null:
			mat.set_shader_parameter("albedo_tex", (src as BaseMaterial3D).albedo_texture)
		mat.set_shader_parameter("dark", Color.html(str(tint.get("dark", "#17171a"))))
		mat.set_shader_parameter("light", Color.html(str(tint.get("light", "#6b6a68"))))
		mat.set_shader_parameter("accent", Color.html(str(tint.get("accent", "#7a5636"))))
		mi.material_override = mat
	return n


func weapon_node(id: String) -> Node3D:
	return weapons.get(id, null)


## World position of the current blaster's muzzle (falls back to the chest).
func muzzle_position() -> Vector3:
	var w := weapon_node(current)
	if w != null and w.has_node("Muzzle"):
		return (w.get_node("Muzzle") as Node3D).global_position
	return (joints.chest as Node3D).global_position + global_basis.z * 0.5


## Points along the sword blade in world space (guard -> tip), for hit tests.
func blade_points(fractions: Array = [0.3, 0.65, 1.0]) -> Array:
	var out: Array = []
	var w := weapon_node("energy_blade")
	if w == null:
		return out
	var sword: Node3D = w.get_meta("sword")
	var blade := sword.get_node("Blade") as Node3D
	var length := float(sword.get_meta("length", 1.05)) * blade.scale.y
	for f in fractions:
		out.append(sword.global_transform * Vector3(0, length * float(f), 0))
	return out


## 0 = retracted, 1 = full length.
func set_blade_extent(v: float) -> void:
	var w := weapon_node("energy_blade")
	if w == null:
		return
	var blade := (w.get_meta("sword") as Node3D).get_node("Blade") as Node3D
	blade.scale = Vector3(1.0, maxf(v, 0.001), 1.0)
	blade.visible = v > 0.01


# ------------------------------------------------------------------ view

func set_first_person(on: bool) -> void:
	first_person = on
	var shadow_only := GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	var normal := GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for m in _other_meshes:
		(m as GeometryInstance3D).cast_shadow = shadow_only if on else normal
	for m in _arm_meshes:
		(m as GeometryInstance3D).cast_shadow = normal


func _collect_meshes() -> void:
	_arm_meshes.clear()
	_other_meshes.clear()
	var keep := {}
	for jn in ["l_elbow", "r_elbow"]:
		for m in _meshes_under(joints[jn]):
			keep[m] = true
	for w in weapons.values():
		for m in _meshes_under(w):
			keep[m] = true
	for m in _meshes_under(body):
		if keep.has(m):
			_arm_meshes.append(m)
		else:
			_other_meshes.append(m)


static func _meshes_under(n: Node) -> Array:
	var out: Array = []
	if n is GeometryInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes_under(c))
	return out


# ------------------------------------------------------------------ per frame

## inp: velocity (world Vector3), grounded, crouch, sprint, cam_yaw, aim_pitch,
## upper (BodyAnimator.UPPER_*), dt is seconds.
func animate(dt: float, inp: Dictionary) -> void:
	var vel: Vector3 = inp.get("velocity", Vector3.ZERO)
	var flat := Vector3(vel.x, 0, vel.z)
	var speed := flat.length()
	var cam_yaw: float = inp.get("cam_yaw", 0.0)
	var upper: String = inp.get("upper", BodyAnimator.UPPER_FREE)
	var armed := upper != BodyAnimator.UPPER_FREE

	# Facing: toward the aim when armed or in first person, else toward travel.
	var want := facing_yaw
	if armed or first_person:
		want = cam_yaw
	elif speed > 0.4:
		want = atan2(flat.x, flat.z)
	facing_yaw = _approach_angle(facing_yaw, want, (turn_rate * 2.0 if first_person else turn_rate) * dt)
	var parent_yaw := (get_parent() as Node3D).global_rotation.y if get_parent() is Node3D else 0.0
	rotation.y = facing_yaw - parent_yaw

	var local := Basis(Vector3.UP, facing_yaw).inverse() * flat
	var move_local := Vector2(local.x, local.z) / maxf(speed, 0.001) if speed > 0.05 else Vector2(0, 1)
	var pitch: float = inp.get("aim_pitch", 0.0)
	var twist := 0.0
	if upper == BodyAnimator.UPPER_SWORD and not sword_pose.is_empty():
		twist = float(sword_pose.get("twist", 0.0))
	var out := anim.step(dt, {
		"speed": speed, "move_local": move_local, "grounded": inp.get("grounded", true),
		"vy": vel.y, "crouch": inp.get("crouch", false), "sprint": inp.get("sprint", false),
		"upper": upper, "aim_pitch": pitch * (1.6 if first_person else 1.0), "twist": twist,
	})
	last_frame = out
	for jn in out.joints:
		if joints.has(jn):
			(joints[jn] as Node3D).rotation_degrees = out.joints[jn]
	(joints.pelvis as Node3D).position.y = out.pelvis_y
	_place_weapon(upper, pitch)


func _place_weapon(upper: String, pitch: float) -> void:
	for id in weapons:
		(weapons[id] as Node3D).visible = (id == current and current != "")
	if current == "" or not weapons.has(current):
		return
	var w: Node3D = weapons[current]
	var ready := _ready_xf(current, pitch)
	var holster := _holster_xf(current)
	var f := drawn * drawn * (3.0 - 2.0 * drawn)
	w.transform = holster.interpolate_with(ready, f)
	var grips: Dictionary = w.get_meta("grips", {})
	if upper == BodyAnimator.UPPER_FREE:
		return
	# The right hand always rides the grip; the left joins once the weapon is up.
	if grips.has("r"):
		kit.reach(body, "r", w.transform * (grips.r as Vector3), POLE_R)
	if grips.has("l") and drawn > 0.6:
		kit.reach(body, "l", w.transform * (grips.l as Vector3), POLE_L)


func _ready_xf(id: String, _pitch: float) -> Transform3D:
	if id == "energy_blade":
		var p: Dictionary = sword_pose if not sword_pose.is_empty() else SwordCombo.GUARD
		var xf := SwordCombo.pose_transform(p)
		if first_person:
			xf.origin += Vector3(0.0, 0.1, 0.06)
		return xf
	var spec: Dictionary = look.get(id, {})
	var a: Dictionary = spec.get("aim_fpv" if first_person else "aim", {})
	var rot := _v3(a.get("rot", [0, 0, 0]))
	return Transform3D(Basis.from_euler(rot * PI / 180.0), _v3(a.get("pos", [0, 0, 0.4])))


func _holster_xf(id: String) -> Transform3D:
	var spec: Dictionary = look.get(id, {})
	match str(spec.get("holster", "")):
		"holster_grip":
			if body.has_meta("holster_grip"):
				var at := kit.chest_space(body, body.get_meta("holster_grip"))
				return Transform3D(at.basis * Basis(Vector3.RIGHT, PI * 0.5), at.origin + Vector3(0, -0.02, 0))
		"l_hip":
			var hip := kit.chest_space(body, joints.l_hip)
			return Transform3D(hip.basis * Basis.from_euler(Vector3(PI * 0.85, 0, 0.25)), hip.origin + Vector3(0.14, -0.02, 0.06))
		"back":
			return Transform3D(Basis.from_euler(Vector3(-PI * 0.5, 0, 0.7)), Vector3(0.0, 0.05, -0.22))
	return Transform3D(Basis(), Vector3(0, -0.4, 0.1))


static func _approach_angle(from: float, to: float, max_step: float) -> float:
	var d := wrapf(to - from, -PI, PI)
	return from + clampf(d, -max_step, max_step)


static func _v3(a) -> Vector3:
	if a is Array and a.size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	if a is Vector3:
		return a
	return Vector3.ZERO
