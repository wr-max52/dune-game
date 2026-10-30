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
## - With a rigged model (SkinnedBody, from characters.json "model") the skin is one
##   mesh, so first person shows the kit's primitive forearms and hands instead and
##   the whole skin goes shadow only.
## - The kit pieces and colours it wears are the player's (PlayerOutfit, picked in
##   the character builder); set_outfit() swaps them while playing.

const BodyAnimator := preload("res://src/systems/anim/body_animator.gd")
const SwordCombo := preload("res://src/systems/combat/sword_combo.gd")
const SwordTrail := preload("res://src/systems/anim/sword_trail.gd")
const RETINT := preload("res://src/systems/look/shaders/weapon_retint.gdshader")
const DARK := preload("res://src/systems/look/shaders/weapon_dark.gdshader")
const Ads := preload("res://src/systems/look/ads.gd")
const GunSights := preload("res://src/systems/look/gun_sights.gd")
const CharBody := preload("res://src/systems/player/character_body.gd")
const LOOK_PATH := "res://content/look/hand_weapons.json"

const POLE_R := Vector3(-0.5, -0.7, -0.5)
const POLE_L := Vector3(0.6, -0.7, -0.4)

var kit: CharacterKit
var body: Node3D
var joints: Dictionary = {}
var anim := BodyAnimator.new()
var look: Dictionary = {}
var weapons: Dictionary = {}       ## id -> wrapper Node3D (child of chest)
var blade_color := Color(0, 0, 0, 0)  ## issue #148: the sword's colour when not the default (alpha 0 = default)
var blade_hilt := ""  ## the sword's hilt model when not the default ("" = default)
var current := ""                  ## weapon in hand (or being drawn/holstered)
var drawn := 0.0                   ## 0 = holstered, 1 = ready
var sword_pose: Dictionary = {}    ## from SwordCombo.pose() while the sword is out
var sword_trail_on := false        ## the swing is cutting: the blade leaves a SwordTrail
var first_person := false
var facing_yaw := 0.0              ## world yaw the body faces
var turn_rate := 10.0              ## rad/s
var last_frame: Dictionary = {}
var _recoil := 0.0                 ## 1 right after a shot, decays to 0
## Issue #87: in third person a gun rests low (rifle across the body, pistol by the
## thigh) and comes up while the trigger or aim is held, then for a moment after.
## weapons sets aim_wanted; first person always holds the gun up.
var carry := WeaponCarry.new(1.0)
var aim_wanted := false
## Issue #133: sprinting. The gun drops to rest (first person too), the body faces
## where it runs, and gun_up() stays false so nothing fires.
var sprint_lowered := false
var _sprint_raise := false         ## first person: easing back up after a sprint
var _flash_left := 0.0

## Aim down sights (first person): the weapon blends to a pose solved from the
## camera so the sight sits on the screen centre. weapons sets ads_on and the camera.
var ads_on := false
var ads_camera: Camera3D
var ads_blend := 0.0               ## 0 = hip, 1 = fully aimed
var _last_upper := ""
var _last_pitch := 0.0

## Render smoothing (see _process): the facing of the last two physics ticks, the
## ground tilt from the last pose, and the avatar's rest position in its parent (the
## parent's origin; the smoothing offset is added on top of it).
var _facing_prev := 0.0
var _facing_curr := 0.0
var _last_tilt := Basis.IDENTITY
var _rest_position := Vector3.ZERO
## The sword's pose at the last two physics ticks: drawn between them (_draw_sword).
var _sword_prev: Dictionary = {}
var _sword_curr: Dictionary = {}
var _trail: SwordTrail

var skin: SkinnedBody              ## the rigged model over the joints (null = primitives)

var _arm_meshes: Array = []
var _other_meshes: Array = []
var _kit_arms: Array = []          ## the kit's own forearms and hands (hidden in first person; see FpvArms)
var _fpv: FpvArms                  ## the first person sleeves and gloves
var _kit_chest: Array = []         ## the chest's own children, as the kit built it


## outfit: CharacterKit's {part: "<piece>[:<colour>]"}; null wears the saved one.
func _init(materials: LookMaterials = null, outfit = null) -> void:
	name = "Avatar"
	kit = CharacterKit.new(materials if materials != null else LookMaterials.new(), -1000.0)
	look = CharacterKit._read_json(LOOK_PATH)
	process_priority = 1000          # after the camera rig, so the sight never lags it
	_build_body(PlayerOutfit.load_outfit() if outfit == null else outfit)
	_collect_meshes()


func _build_body(outfit: Dictionary) -> void:
	body = kit.build(PlayerOutfit.ARCHETYPE, "idle", outfit)
	body.name = "Body"
	add_child(body)
	joints = body.get_meta("joints")
	skin = body.get_meta("skin") if body.has_meta("skin") else null
	_kit_chest = (joints.chest as Node3D).get_children()


## What the body wears now, every part filled in.
func worn_outfit() -> Dictionary:
	return body.get_meta("outfit", {})


## Wear another outfit (the character builder). The body is rebuilt; whatever rides
## on the chest and is not the kit's own (weapons, the worn pack) moves across.
func set_outfit(outfit: Dictionary) -> void:
	var old := body
	var old_chest: Node3D = joints.chest
	var old_kit := _kit_chest
	remove_child(old)
	_build_body(outfit)
	var chest: Node3D = joints.chest
	for c in old_chest.get_children():
		if old_kit.has(c):
			continue
		var xf: Transform3D = c.transform
		old_chest.remove_child(c)
		chest.add_child(c)
		c.transform = xf
	old.free()
	_collect_meshes()
	set_first_person(first_person)


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
			var sword := kit.make_energy_sword(blade_color, -1.0, blade_hilt)
			wrap.add_child(sword)
			wrap.set_meta("grips", sword.get_meta("grips"))
			wrap.set_meta("sword", sword)
		else:
			var model := _load_model(str(spec.get("model", "")), spec)
			var s := float(spec.get("scale", 1.0))
			if model != null:
				model.scale = Vector3.ONE * s
				wrap.add_child(model)
			if model != null:
				GunSights.add_to(model, spec)
			var g: Dictionary = spec.get("grips", {})
			wrap.set_meta("grips", { "r": _v3(g.get("r", [0, 0, 0])) * s, "l": _v3(g.get("l", [0, 0, 0.3])) * s })
			var muzzle := Marker3D.new()
			muzzle.name = "Muzzle"
			muzzle.position = _v3(spec.get("muzzle", [0, 0, 1])) * s
			wrap.add_child(muzzle)
			var tint: Dictionary = spec.get("tint", {})
			var gcol := Color.html(str(tint.get("glow", "#ff7a3a")))
			# Emitter ring around the barrel tip (faces forward, +Z), a dim core
			# inside it, and a flash sprite that only shows when firing.
			var ring := MeshInstance3D.new()
			ring.name = "EmitterRing"
			var tor := TorusMesh.new()
			tor.inner_radius = 0.016
			tor.outer_radius = 0.024
			tor.rings = 16
			tor.ring_segments = 8
			ring.mesh = tor
			ring.rotation_degrees = Vector3(90, 0, 0)
			ring.material_override = _emissive(gcol, 2.5)
			ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			muzzle.add_child(ring)
			var core := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.013
			cm.bottom_radius = 0.013
			cm.height = 0.004
			core.mesh = cm
			core.rotation_degrees = Vector3(90, 0, 0)
			core.material_override = _emissive(gcol.darkened(0.5), 0.8)
			core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			muzzle.add_child(core)
			var flash := MeshInstance3D.new()
			flash.name = "Flash"
			var fm := SphereMesh.new()
			fm.radius = 0.05
			fm.height = 0.1
			flash.mesh = fm
			flash.scale = Vector3(1.0, 1.0, 2.2)
			flash.position = Vector3(0, 0, 0.06)
			flash.material_override = _emissive(gcol.lerp(Color.WHITE, 0.4), 8.0)
			flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			flash.visible = false
			muzzle.add_child(flash)
		wrap.visible = false
		(joints.chest as Node3D).add_child(wrap)
		weapons[id] = wrap
	_collect_meshes()
	set_first_person(first_person)


func _load_model(path: String, spec: Dictionary) -> Node3D:
	if path == "" or not ResourceLoader.exists(path):
		push_warning("PlayerAvatar: missing weapon model " + path)
		return null
	var scene = ModelCache.scene(path)
	if not (scene is PackedScene):
		return null
	var n: Node3D = scene.instantiate()
	if spec.get("dark") is Dictionary:
		_darken(n, spec.dark)
		return n
	if spec.get("retint", true) == false:
		return n
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


## Dark variant of a gun that keeps its own textures: neutral texels go dark, the
## saturated glow panels stay (weapon_dark.gdshader). Static: the guards' rifles
## use it too (CharacterKit._rifle).
static func _darken(n: Node3D, d: Dictionary) -> void:
	for mi in _meshes_under(n):
		if mi.mesh == null or mi.mesh.get_surface_count() == 0:
			continue
		var src: Material = mi.mesh.surface_get_material(0)
		var mat := ShaderMaterial.new()
		mat.shader = DARK
		if src is BaseMaterial3D:
			var b := src as BaseMaterial3D
			mat.set_shader_parameter("albedo_tex", b.albedo_texture)
			if b.normal_texture != null:
				mat.set_shader_parameter("normal_tex", b.normal_texture)
				mat.set_shader_parameter("use_normal", true)
			if b.roughness_texture != null:
				mat.set_shader_parameter("orm_tex", b.roughness_texture)
				mat.set_shader_parameter("use_orm", true)
		for k in ["body_mul", "accent_mul", "glow"]:
			if d.has(k):
				mat.set_shader_parameter(k, float(d[k]))
		mi.material_override = mat


func _emissive(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


## A shot: the weapon kicks back and up, and the muzzle flashes for a moment.
func fire_kick() -> void:
	_recoil = 1.0
	var w := weapon_node(current)
	if w != null and w.has_node("Muzzle/Flash"):
		_flash_left = 0.05
		(w.get_node("Muzzle/Flash") as Node3D).visible = true
		(w.get_node("Muzzle/Flash") as Node3D).rotation.z = randf() * TAU


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


## Issue #148: the energy sword's colour and hilt (the red saber's black hilt); the
## sword already built is recoloured, one built later starts in it.
func set_blade_color(color: Color, hilt: String = "") -> void:
	blade_color = color
	blade_hilt = hilt
	var w := weapon_node("energy_blade")
	if w != null and color.a > 0.0:
		CharacterKit.recolor_energy_sword(w.get_meta("sword"), color)
		kit.set_sword_hilt(w.get_meta("sword"), hilt)


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
	# FpvArms replace the kit's forearms and hands in the view. Over a skin the kit's
	# stay hidden always; primitives keep them for the shadow and third person.
	for m in _kit_arms:
		var g := m as GeometryInstance3D
		g.visible = skin == null
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if skin != null \
				else (shadow_only if on else normal)
	if _fpv != null:
		_fpv.set_visible(on)


func _collect_meshes() -> void:
	_arm_meshes.clear()
	_other_meshes.clear()
	_kit_arms.clear()
	if _fpv == null or not _fpv.fits(joints):
		_fpv = FpvArms.attach(joints, kit)
	var keep := {}
	for jn in ["l_elbow", "r_elbow"]:
		for m in _meshes_under(joints[jn]):
			if not FpvArms.owns(m):
				keep[m] = true
	var weapon_meshes := {}
	for w in weapons.values():
		for m in _meshes_under(w):
			keep[m] = true
			weapon_meshes[m] = true
	if skin != null:
		_other_meshes = skin.skin_meshes()
		for m in keep:
			if weapon_meshes.has(m):
				_arm_meshes.append(m)
			else:
				_kit_arms.append(m)
		return
	for m in _meshes_under(body):
		if FpvArms.owns(m):
			continue
		if weapon_meshes.has(m):
			_arm_meshes.append(m)
		elif keep.has(m):
			_kit_arms.append(m)
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

## Set the full local basis so the avatar is upright in the parent's ground frame.
func align_to_ground(ground_tilt: Basis) -> void:
	var parent := get_parent() as Node3D
	var parent_basis := parent.global_basis.orthonormalized() if parent != null else Basis.IDENTITY
	_last_tilt = ground_tilt
	basis = compose_basis(parent_basis, ground_tilt, facing_yaw)


## The avatar's local basis: upright in the ground frame, facing `yaw` in the world,
## whatever yaw the parent is turned to. (parent_basis: the parent's world basis.)
static func compose_basis(parent_basis: Basis, ground_tilt: Basis, yaw: float) -> Basis:
	return parent_basis.inverse() * ground_tilt * Basis(Vector3.UP, yaw)


## The facing to draw at physics fraction `f` between the last two ticks.
static func smoothed_yaw(prev: float, curr: float, f: float) -> float:
	return lerp_angle(prev, curr, clampf(f, 0.0, 1.0))


## Drop the render smoothing state (teleport, leaving a vehicle): sit on the parent's
## origin facing exactly `facing_yaw`.
func reset_render_smoothing() -> void:
	position = _rest_position
	_facing_prev = facing_yaw
	_facing_curr = facing_yaw


## inp: velocity (world Vector3), grounded, crouch, sprint, cam_yaw, aim_pitch,
## upper (BodyAnimator.UPPER_*), dt is seconds.
func animate(dt: float, inp: Dictionary) -> void:
	var vel: Vector3 = inp.get("velocity", Vector3.ZERO)
	# Issue #77: on the home planet, read the velocity in the ground's own frame.
	var tilt = get_parent().get("tilt") if get_parent() != null else null
	if tilt is Basis and tilt != Basis.IDENTITY:
		vel = tilt.inverse() * vel
	var flat := Vector3(vel.x, 0, vel.z)
	var speed := flat.length()
	var cam_yaw: float = inp.get("cam_yaw", 0.0)
	var upper: String = inp.get("upper", BodyAnimator.UPPER_FREE)
	var armed := upper != BodyAnimator.UPPER_FREE
	var gun := upper == BodyAnimator.UPPER_AIM or upper == BodyAnimator.UPPER_RIFLE
	carry.step(dt, first_person or aim_wanted or not gun, sprint_lowered)
	# First person holds the gun up outright, except coming out of a sprint, when
	# it rises on the carry's own timing instead of popping back.
	if sprint_lowered:
		_sprint_raise = true
	elif carry.ready >= 1.0:
		_sprint_raise = false
	var held_up := first_person and not _sprint_raise

	# Facing: toward the aim when a weapon is up or in first person, else toward
	# travel (a gun at rest walks where you go, issue #87).
	var want := facing_yaw
	if (armed and not sprint_lowered and (not gun or carry.ready > 0.3)) or first_person:
		want = cam_yaw
	elif speed > 0.4:
		want = atan2(flat.x, flat.z)
	_facing_prev = facing_yaw             # includes anything that set it from outside (leaving a vehicle)
	facing_yaw = _approach_angle(facing_yaw, want, (turn_rate * 2.0 if first_person else turn_rate) * dt)
	_facing_curr = facing_yaw
	# Always replace the full basis. On a ball, the ground frame can be tilted;
	# after a teleport back to a flat surface, the same calculation removes any
	# pitch/roll left by the previous frame instead of only rewriting rotation.y.
	var ground_tilt: Basis = tilt if tilt is Basis else Basis.IDENTITY
	align_to_ground(ground_tilt)

	var local := Basis(Vector3.UP, facing_yaw).inverse() * flat
	var move_local := Vector2(local.x, local.z) / maxf(speed, 0.001) if speed > 0.05 else Vector2(0, 1)
	var pitch: float = inp.get("aim_pitch", 0.0)
	var twist := 0.0
	if upper == BodyAnimator.UPPER_SWORD and not sword_pose.is_empty():
		twist = float(sword_pose.get("twist", 0.0))
	var out := anim.step(dt, {
		"speed": speed, "move_local": move_local, "grounded": inp.get("grounded", true),
		"vy": vel.y, "crouch": inp.get("crouch", false), "sprint": inp.get("sprint", false),
		"slide": inp.get("slide", false),
		"upper": upper, "aim_pitch": pitch * (1.6 if first_person else 1.0), "twist": twist,
		"ready": 1.0 if held_up else carry.eased(),
	})
	last_frame = out
	for jn in out.joints:
		if joints.has(jn):
			(joints[jn] as Node3D).rotation_degrees = out.joints[jn]
	(joints.pelvis as Node3D).position.y = out.pelvis_y
	(joints.pelvis as Node3D).position.x = out.pelvis_x
	var rc: Dictionary = look.get("recoil", {})
	_recoil = maxf(0.0, _recoil - dt / float(rc.get("recover_s", 0.12)))
	if _flash_left > 0.0:
		_flash_left -= dt
		if _flash_left <= 0.0:
			var w := weapon_node(current)
			if w != null and w.has_node("Muzzle/Flash"):
				(w.get_node("Muzzle/Flash") as Node3D).visible = false
	_last_upper = upper
	_last_pitch = pitch
	_sword_prev = _sword_curr if not _sword_curr.is_empty() else sword_pose
	_sword_curr = sword_pose
	_place_weapon(upper, pitch)
	_fpv_grips(upper, dt)
	if skin != null:
		skin.sync(body)


## Runs after the camera moves each frame: step the ADS blend and, while any of it
## is on, re-place the weapon against this frame's camera (animate only runs on
## physics ticks, so the sight would otherwise trail the view).
func _process(delta: float) -> void:
	_smooth_render()
	var want := ads_on and first_person and ads_camera != null and drawn >= 0.99 \
		and Ads.has_ads(look, current) and _last_upper != BodyAnimator.UPPER_FREE
	var t := maxf(0.01, float(Ads.spec(look, current).blend_s))
	ads_blend = move_toward(ads_blend, 1.0 if want else 0.0, delta / t)
	if current != "" and weapons.has(current):
		GunSights.scope_view(weapons[current], ads_blend > 0.85)
	if ads_blend > 0.0 and current != "" and weapons.has(current):
		_place_weapon(_last_upper, _last_pitch)
		if skin != null:
			skin.sync(body)
	_draw_sword(delta)


## A swipe turns the blade 15-20 degrees per 60 Hz tick, which strobes on a faster
## display: draw the sword (and the arms on it) between the last two ticks' poses,
## as the body's position already is. Then feed the swing trail.
func _draw_sword(delta: float) -> void:
	if current != "energy_blade":
		if _trail != null and not _trail.is_empty():
			_trail.clear()
		return
	if CharBody.smoothing_active() and not _sword_prev.is_empty() and not _sword_curr.is_empty() \
			and _sword_prev != _sword_curr:
		var tick_pose := sword_pose
		sword_pose = SwordCombo.mix(_sword_prev, _sword_curr, Engine.get_physics_interpolation_fraction())
		_place_weapon(_last_upper, _last_pitch)
		sword_pose = tick_pose
		if skin != null:
			skin.sync(body)
	if sword_trail_on:
		if _trail == null:
			_trail = SwordTrail.new()
			add_child(_trail)
		var w := weapon_node("energy_blade")
		if w != null:
			_trail.color = (w.get_meta("sword") as Node3D).get_meta("color", _trail.color)
		var p := blade_points([0.45, 1.0])
		if p.size() == 2:
			_trail.add(p[0], p[1])
	if _trail != null:
		_trail.tick(delta)


## Every render frame (120 Hz on a 120 Hz display; physics is 60): keep the body where
## and how the player is drawn, not where the last physics tick left it.
##  - facing: re-apply the full basis with the facing interpolated between the last two
##    ticks. The camera rig rewrites the parent's yaw every frame, and the body's local
##    basis compensates for it, so without this the body swings with the mouse until
##    the next tick.
##  - position: sit at the parent's render-smoothed origin.
## A no-op headless, so traces and tests see exactly what physics made.
func _smooth_render() -> void:
	if not CharBody.smoothing_active():
		return
	var parent := get_parent() as Node3D
	if parent == null or not parent.has_method("render_origin"):
		return
	var yaw := facing_yaw
	if facing_yaw == _facing_curr:       # else something set it from outside: take it as is
		yaw = smoothed_yaw(_facing_prev, _facing_curr, Engine.get_physics_interpolation_fraction())
	var pbasis := parent.global_basis
	basis = compose_basis(pbasis.orthonormalized(), _last_tilt, yaw)
	position = _rest_position + CharBody.local_offset(pbasis, parent.call("render_origin"), parent.global_position)


func _place_weapon(upper: String, pitch: float) -> void:
	for id in weapons:
		(weapons[id] as Node3D).visible = (id == current and current != "")
	if current == "" or not weapons.has(current):
		return
	var w: Node3D = weapons[current]
	var grips: Dictionary = w.get_meta("grips", {})
	var ready := _ready_xf(current, pitch)
	var holster := _holster_xf(current)
	var up := 1.0 if (first_person and not _sprint_raise) or current == "energy_blade" else carry.eased()
	if up < 1.0:
		ready = WeaponCarry.blend(WeaponCarry.rest_xf(carry_kind(current), grips.get("r", Vector3.ZERO)), ready, up)
	var f := drawn * drawn * (3.0 - 2.0 * drawn)
	if _recoil > 0.0 and current != "energy_blade":
		var rc: Dictionary = look.get("recoil", {})
		var k := _recoil * _recoil
		ready = Transform3D(ready.basis * Basis(Vector3.RIGHT, -deg_to_rad(float(rc.get("up_deg", 7.0))) * k),
			ready.origin + Vector3(0, 0.01, -float(rc.get("back", 0.05))) * k)
	if ads_blend > 0.0 and first_person and ads_camera != null and is_inside_tree() and current != "energy_blade":
		var a := Ads.spec(look, current)
		var sc := float((look.get(current, {}) as Dictionary).get("scale", 1.0))
		var aimed := Ads.weapon_global(ads_camera.global_transform, Ads.sight_point(look, current) * sc, float(a.relief))
		if _recoil > 0.0:
			var rc2: Dictionary = look.get("recoil", {})
			var k2 := _recoil * _recoil * 0.5
			aimed = aimed * Transform3D(Basis(Vector3.RIGHT, -deg_to_rad(float(rc2.get("up_deg", 7.0))) * k2),
				Vector3(0, 0.005, -float(rc2.get("back", 0.05))) * k2)
		var to_chest := (joints.chest as Node3D).global_transform.affine_inverse() * aimed
		ready = ready.interpolate_with(to_chest, ads_blend * ads_blend * (3.0 - 2.0 * ads_blend))
	w.transform = holster.interpolate_with(ready, f)
	if upper == BodyAnimator.UPPER_FREE:
		_fpv_stance(false)
		return
	_fpv_stance(first_person)
	# The right hand always rides the grip; the left joins once the weapon is up.
	# In first person a one-handed weapon (aim_fpv "one_hand") leaves the left arm
	# alone: reaching across to a grip right of centre lays the forearm sideways
	# through the view, reading as a second arm.
	if grips.has("r"):
		kit.reach(body, "r", w.transform * (grips.r as Vector3), POLE_R)
	var one_hand := first_person and bool((look.get(current, {}) as Dictionary).get("aim_fpv", {}).get("one_hand", false))
	# A pistol at rest hangs from the right hand alone; the left arm swings free.
	if carry_kind(current) == "pistol" and up < 0.5:
		one_hand = true
	if grips.has("l") and drawn > 0.6 and not one_hand:
		kit.reach(body, "l", w.transform * (grips.l as Vector3), POLE_L)


## Issue #229: in first person the shoulders cheat into a bladed stance (the left
## one forward and in, both a little low; fpv_arms.json "stance") so the support
## arm rises from the bottom corner instead of crossing the view flat, fully
## stretched. The body is shadow-only there; third person keeps the real shoulders.
func _fpv_stance(on: bool) -> void:
	var stance: Dictionary = _fpv.spec.get("stance", {}) if _fpv != null else {}
	for side in ["l", "r"]:
		var sh: Node3D = joints[side + "_shoulder"]
		if not sh.has_meta("rest"):
			sh.set_meta("rest", sh.position)
		sh.position = (sh.get_meta("rest") as Vector3) + (_v3(stance.get(side, [])) if on else Vector3.ZERO)


## Fingers close on a grip: the right hand whenever a weapon is out, the left while it
## rides a grip (same test as _place_weapon); otherwise they hang relaxed.
func _fpv_grips(upper: String, dt: float) -> void:
	if _fpv == null:
		return
	var relaxed := float(_fpv._hand().get("relaxed", 0.3))
	var armed := upper != BodyAnimator.UPPER_FREE and current != "" and weapons.has(current)
	var left: bool = armed and (weapons[current] as Node3D).get_meta("grips", {}).has("l") and drawn > 0.6
	if left and first_person and bool((look.get(current, {}) as Dictionary).get("aim_fpv", {}).get("one_hand", false)):
		left = false
	# Issue #229: each weapon names how each hand holds it (hand_weapons "fpv_pose").
	var poses: Dictionary = (look.get(current, {}) as Dictionary).get("fpv_pose", {}) if armed else {}
	_fpv.set_pose("r", str(poses.get("r", "trigger")) if armed else "relaxed")
	_fpv.set_pose("l", str(poses.get("l", "support")) if left else "relaxed")
	_fpv.ease_grip("r", 1.0 if armed else relaxed, dt)
	_fpv.ease_grip("l", 1.0 if left else relaxed, dt)


## True once the gun is up far enough to shoot (weapons holds the trigger until then).
func gun_up() -> bool:
	if sprint_lowered:
		return false
	return (first_person and not _sprint_raise) or current == "energy_blade" or carry.on_target()


## "pistol" or "rifle": how the weapon rests (hand_weapons.json "carry", else by name).
func carry_kind(id: String) -> String:
	return str((look.get(id, {}) as Dictionary).get("carry", "pistol" if id.contains("pistol") else "rifle"))


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
