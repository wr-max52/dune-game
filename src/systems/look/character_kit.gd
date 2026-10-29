class_name CharacterKit
extends RefCounted
## Stylized, original characters for look-dev. A jointed body (real joint rotations,
## so a rigged model can replace it later) with two-bone IK for hands on weapons,
## dressed per archetype. Palettes and proportions: content/look/characters.json.
##
## Design rules (docs/ART_DIRECTION.md, Characters; research notes in the same doc):
## - Silhouette first: each faction must read as a black shape at 50 m.
## - One busy focal zone per character (head + chest), quiet "rest" areas elsewhere.
## - Gear has a reason to exist and shows its history: dust, scuffs, faded cloth.
## - Heroic proportions: broad shoulders, narrow waist, small heads, big hands/boots.
## - Faces covered. Remnant = hard plated slabs; smuggler = hat, flared coat, straps;
##   duelist = lean, asymmetric mantle, mask, yellow energy sword; locals = draped.
##
## Models face +Z and stand on y = 0. Their left is +X.

const PALETTES_PATH := "res://content/look/characters.json"
const BLADE_PATH := "res://content/core/weapons/energy_blade.json"
const HAND_WEAPONS_PATH := "res://content/look/hand_weapons.json"   ## issue #82: the guards' rifle model
const GunSights := preload("res://src/systems/look/gun_sights.gd")
const ENERGY := preload("res://src/systems/look/shaders/energy.gdshader")
const GEAR := preload("res://src/systems/look/shaders/gear.gdshader")
const REF_HEIGHT := 1.8

var mats: LookMaterials
var palettes: Dictionary = {}
var blade_cfg: Dictionary = {}
var floor_y := 8.0
var rng := RandomNumberGenerator.new()   ## picks the colours of a split model's parts
var _cache := {}
static var _outfits := {}   ## issue #162: texture path -> outfit material, shared by every kit


func _init(materials: LookMaterials, floor_height: float = 8.0) -> void:
	mats = materials
	floor_y = floor_height
	rng.randomize()
	palettes = _read_json(PALETTES_PATH).get("archetypes", {})
	blade_cfg = _read_json(BLADE_PATH)


static func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func archetypes() -> Array:
	return palettes.keys()


## Build one character. pose is optional; each archetype has a default. outfit picks
## each part of a split model: its colour ({"head": "blue", ...}), or on a kit model
## its piece and colour ({"head": "guard", "torso": "player:rust"}); a part left out
## gets a random choice from its list (characters.json, model.parts).
func build(archetype: String, pose: String = "", outfit: Dictionary = {}) -> Node3D:
	var p: Dictionary = palettes.get(archetype, {})
	# Issue #45: a variant names a "base" archetype and changes only what it lists
	# (another planet's cantina owner is Oda's body, re-tinted).
	var base := str(p.get("base", archetype))
	if base != archetype and palettes.has(base):
		p = _merged(palettes[base], p)
	var root := Node3D.new()
	root.name = archetype.to_pascal_case()
	_body(root, p)
	var default_pose := "idle"
	match base:
		"remnant_trooper":
			_dress_trooper(root, p, false)
			default_pose = "rifle"
		"remnant_commander", "remnant_marked":
			_dress_trooper(root, p, true)
			default_pose = "parade_rest"
			if base == "remnant_marked":
				_pistol(root)
		"smuggler":
			_dress_smuggler(root, p)
			default_pose = "gunslinger"
		"duelist":
			_dress_duelist(root, p)
			default_pose = "ox_guard"
		"cantina_owner":
			_dress_cantina_owner(root, p)
			default_pose = "idle"
		"player_smuggler":
			_dress_smuggler(root, p)
			default_pose = "idle"
		_:
			_dress_local(root, p)
			default_pose = "walker"
	_pose(root, pose if pose != "" else default_pose)
	# A rigged model replaces the primitives (characters.json "model"). The joints
	# keep the pose; animated users call skin.sync() every frame after moving them.
	var skins: Array[SkinnedBody] = []
	var skin := SkinnedBody.dress(root, p.get("model", {}))
	if skin != null:
		_wear_outfit(root, skin, p.model, outfit)
		if p.has("tint"):
			_tint(skin.model, Color.html(str(p.tint)))
		root.set_meta("skin", skin)
		skins.append(skin)
	for layer in p.get("skin_layers", []):
		if not layer is Dictionary:
			continue
		var layer_skin := SkinnedBody.dress(root, layer)
		if layer_skin == null:
			continue
		var layer_outfit := outfit.duplicate(true)
		var layer_choices: Dictionary = layer.get("outfit", {})
		layer_outfit.merge(layer_choices, true)
		_wear_outfit(root, layer_skin, layer, layer_outfit)
		skins.append(layer_skin)
	if not skins.is_empty():
		root.set_meta("skins", skins)
		skins[0].sync(root)
	var s := float(p.get("height", REF_HEIGHT)) / REF_HEIGHT
	var bulk := float(p.get("bulk", 1.0))
	root.scale = Vector3(s * bulk, s, s * bulk)
	return root


## A split model has one mesh per part (prep_character.gd, split), all on one shared
## texture, and one recoloured copy of that texture per colour (recolor_parts.gd).
## Each part gets a colour; the model's own texture is "sand".
## A kit model ("pieces": true; the player, the guards and the locals) holds several pieces of
## every part on one skeleton (fit_parts.gd, dress), the mesh "<piece>_<part>". A
## choice is "<piece>" or "<piece>:<colour>", the colour a texture of that piece
## ("colors" % "<piece>_<part>_<colour>" when the part has its own texture, else
## "<piece>_<colour>": recolor_fitted.gd); the pieces not chosen are removed.
## The choice is stored on the body as meta "outfit".
func _wear_outfit(root: Node3D, skin: SkinnedBody, cfg: Dictionary, outfit: Dictionary) -> void:
	var parts: Dictionary = cfg.get("parts", {})
	if parts.is_empty() and cfg.get("hide_parts", []).is_empty():
		return
	var pieces := bool(cfg.get("pieces", false))
	var worn := {}
	var keep := {}
	for part in parts:
		var choices: Array = parts[part]
		if choices.is_empty():
			continue
		var choice := str(outfit.get(part, choices[rng.randi() % choices.size()]))
		var color := choice
		var mesh_name := str(part)
		if pieces:
			var pc := choice.split(":", true, 1)
			mesh_name = "%s_%s" % [pc[0], part]
			color = ""
			if pc.size() == 2:
				# A piece with its own texture (the player's head) has its own colours.
				color = "%s_%s" % [mesh_name, pc[1]]
				if not ResourceLoader.exists(str(cfg.get("colors", "")) % color):
					color = "%s_%s" % [pc[0], pc[1]]
		var mi := skin.model.find_child(mesh_name, true, false) as MeshInstance3D
		if mi == null:
			continue
		worn[part] = choice
		keep[mi] = true
		var mat := _outfit_material(mi.mesh.surface_get_material(0), str(cfg.get("colors", "")), color)
		if mat != null:
			mi.set_surface_override_material(0, mat)
	if pieces:
		for mi in skin.model.find_children("*", "MeshInstance3D", true, false):
			if not keep.has(mi):
				mi.get_parent().remove_child(mi)
				mi.free()
	for part in cfg.get("hide_parts", []):
		var hidden := skin.model.find_child(str(part), true, false) as GeometryInstance3D
		if hidden != null:
			hidden.visible = false
	var all_worn: Dictionary = root.get_meta("outfit", {}).duplicate(true)
	all_worn.merge(worn, true)
	root.set_meta("outfit", all_worn)


## The part's material with the colour's texture, shared by every body that wears it.
## null keeps the model's own material (the base colour, or a missing texture).
func _outfit_material(base: Material, pattern: String, color: String) -> Material:
	var path := pattern % color if pattern.contains("%s") and color != "" else ""
	if not base is BaseMaterial3D or path == "" or not ResourceLoader.exists(path):
		return null
	# Issue #162: every NPC has its own kit, so a per-kit cache shared nothing.
	if not _outfits.has(path):
		var m := (base as BaseMaterial3D).duplicate() as BaseMaterial3D
		m.albedo_texture = ModelCache.scene(path)
		_outfits[path] = m
	return _outfits[path]


## Issue #162: every outfit colour texture the characters can wear (characters.json
## "colors" patterns), for ModelCache.prefetch().
static func outfit_textures() -> Array:
	var out: Array = []
	var cfgs: Array = []
	for p in _read_json(PALETTES_PATH).get("archetypes", {}).values():
		cfgs.append((p as Dictionary).get("model", {}))
		cfgs.append_array((p as Dictionary).get("skin_layers", []))
	for cfg in cfgs:
		var pattern := str((cfg as Dictionary).get("colors", "")) if cfg is Dictionary else ""
		if not pattern.contains("%s"):
			continue
		var dir := pattern.get_base_dir()
		var head := pattern.get_file().get_slice("%s", 0)
		var tail := pattern.get_file().get_slice("%s", 1)
		for f in ResourceLoader.list_directory(dir):
			var path := dir.path_join(f)
			if f.begins_with(head) and f.ends_with(tail) and not out.has(path):
				out.append(path)
	return out


## Issue #64: a palette's "tint" multiplies every piece's colour (the red Remnant
## officer). Each body gets its own copies, so the shared outfit materials stay as they are.
func _tint(model: Node, tint: Color) -> void:
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		for i in (mi as MeshInstance3D).mesh.get_surface_count():
			var m := (mi as MeshInstance3D).get_active_material(i)
			if m is BaseMaterial3D:
				var t := (m as BaseMaterial3D).duplicate() as BaseMaterial3D
				t.albedo_color = t.albedo_color * tint
				(mi as MeshInstance3D).set_surface_override_material(i, t)


# ------------------------------------------------------------------ materials

func _c(p: Dictionary, key: String, fallback: String = "#808080") -> Color:
	return Color.html(p.get(key, fallback))


## kind: "metal", "leather", "cloth", "dark"
func _m(color: Color, kind: String = "cloth", wear: float = 0.5) -> ShaderMaterial:
	var key := "%s_%s_%s" % [color.to_html(), kind, wear]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = GEAR
	m.set_shader_parameter("noise_tex", mats.noise)
	m.set_shader_parameter("base", color)
	m.set_shader_parameter("floor_y", floor_y)
	m.set_shader_parameter("wear", wear)
	match kind:
		"metal":
			m.set_shader_parameter("metallic", 0.55)
			m.set_shader_parameter("roughness", 0.5)
		"leather":
			m.set_shader_parameter("roughness", 0.62)
			m.set_shader_parameter("sheen", 0.12)
		"dark":
			m.set_shader_parameter("roughness", 0.85)
		_:
			m.set_shader_parameter("roughness", 0.96)
			m.set_shader_parameter("sheen", 0.2)
	_cache[key] = m
	return m


# ------------------------------------------------------------------ mesh helpers

func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3 = Vector3.ZERO,
		rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.rotation_degrees = rot
	m.scale = scl
	parent.add_child(m)
	return m


func _joint(parent: Node3D, jname: String, pos: Vector3) -> Node3D:
	var j := Node3D.new()
	j.name = jname
	j.position = pos
	parent.add_child(j)
	return j


func _cyl(top: float, bottom: float, h: float, seg: int = 10) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _sphere(r: float, h: float = -1.0, seg: int = 14) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = h if h > 0.0 else r * 2.0
	s.radial_segments = seg
	s.rings = maxi(seg / 2, 4)
	return s


func _limb(parent: Node3D, jname: String, length: float, r_top: float, r_bot: float, mat: Material) -> Node3D:
	_mi(parent, _cyl(r_bot, r_top, length), mat, Vector3(0, -length * 0.5, 0))
	return _joint(parent, jname, Vector3(0, -length, 0))


# ------------------------------------------------------------------ the body

const UPPER_ARM := 0.29
const FOREARM := 0.27
const HAND_REACH := 0.07


func _body(root: Node3D, p: Dictionary) -> void:
	var under := _m(_c(p, "under", "#5b4a3a"), "cloth", 0.3)
	var boots := _m(_c(p, "boots", "#2a2220"), "leather", 0.6)
	var gloves := _m(_c(p, "gloves", "#1e1c1c"), "leather", 0.4)
	var pelvis := _joint(root, "pelvis", Vector3(0, 0.97, 0))
	_mi(pelvis, _box(Vector3(0.3, 0.18, 0.2)), under)
	var spine := _joint(pelvis, "spine", Vector3(0, 0.07, 0))
	var chest := _joint(spine, "chest", Vector3(0, 0.22, 0))
	# V-taper: narrow waist, broad chest.
	_mi(chest, LookMeshKit.frustum(0.29, 0.19, 0.44, -0.3), under)
	var neck := _joint(chest, "neck", Vector3(0, 0.22, 0))
	_mi(neck, _cyl(0.05, 0.062, 0.12), under, Vector3(0, 0.04, 0))
	var head := _joint(neck, "head", Vector3(0, 0.15, 0))
	var joints := { "pelvis": pelvis, "spine": spine, "chest": chest, "neck": neck, "head": head }
	for side in [["l", 1.0], ["r", -1.0]]:
		var sname: String = side[0]
		var sx: float = side[1]
		var sh := _joint(chest, sname + "_shoulder", Vector3(0.22 * sx, 0.18, 0))
		_mi(sh, _sphere(0.064), under)
		var el := _limb(sh, sname + "_elbow", UPPER_ARM, 0.058, 0.048, under)
		var wr := _limb(el, sname + "_wrist", FOREARM, 0.047, 0.037, under)
		_mi(wr, _box(Vector3(0.055, 0.11, 0.1)), gloves, Vector3(0, -0.055, 0.01))   # big hands
		var hip := _joint(pelvis, sname + "_hip", Vector3(0.09 * sx, -0.04, 0))
		var kn := _limb(hip, sname + "_knee", 0.46, 0.088, 0.062, under)
		var an := _limb(kn, sname + "_ankle", 0.43, 0.06, 0.045, boots)
		_mi(an, _box(Vector3(0.12, 0.1, 0.28)), boots, Vector3(0, -0.035, 0.065))      # big boots
		joints[sname + "_shoulder"] = sh
		joints[sname + "_elbow"] = el
		joints[sname + "_wrist"] = wr
		joints[sname + "_hip"] = hip
		joints[sname + "_knee"] = kn
		joints[sname + "_ankle"] = an
	root.set_meta("joints", joints)


func _j(body: Node3D, jname: String) -> Node3D:
	return body.get_meta("joints")[jname]


# ------------------------------------------------------------------ poses + IK

## FK joint rotations (degrees). "weapon" places the held item in chest space
## [position, rotation]; hands then reach for its grips with IK.
const POSES := {
	"idle": {
		"l_shoulder": Vector3(0, 0, 7), "r_shoulder": Vector3(0, 0, -7),
		"l_elbow": Vector3(-12, 0, 0), "r_elbow": Vector3(-12, 0, 0),
		"l_hip": Vector3(0, 0, 2), "r_hip": Vector3(0, 0, -2),
	},
	"walker": {
		"pelvis": Vector3(0, 0, 3), "chest": Vector3(10, 0, 0), "head": Vector3(-6, 0, 0),
		"l_shoulder": Vector3(14, 0, 8), "l_elbow": Vector3(-20, 0, 0),
		"r_shoulder": Vector3(-22, 0, -8), "r_elbow": Vector3(-50, 0, 0),
		"l_hip": Vector3(-14, 0, 2), "r_hip": Vector3(10, 0, -2), "r_knee": Vector3(12, 0, 0),
	},
	"rifle": {
		"pelvis": Vector3(0, 10, 0), "chest": Vector3(6, -14, 0), "head": Vector3(-2, 4, 0),
		"l_hip": Vector3(-8, 0, 6), "r_hip": Vector3(6, 0, -6), "r_knee": Vector3(8, 0, 0), "l_knee": Vector3(4, 0, 0),
		"weapon": [Vector3(-0.05, -0.08, 0.16), Vector3(26, 14, 0)],
	},
	"parade_rest": {
		"chest": Vector3(-4, 0, 0), "head": Vector3(-6, 0, 0),
		"l_shoulder": Vector3(24, 0, 8), "r_shoulder": Vector3(24, 0, -8),
		"l_elbow": Vector3(-80, -50, 0), "r_elbow": Vector3(-80, 50, 0),
		"l_hip": Vector3(0, 0, 7), "r_hip": Vector3(0, 0, -7),
	},
	"gunslinger": {
		"pelvis": Vector3(0, 10, 5), "chest": Vector3(0, -14, -5), "head": Vector3(-4, 8, 4),
		"l_shoulder": Vector3(10, 0, 22), "l_elbow": Vector3(-75, -40, 0),
		"l_hip": Vector3(-6, 0, 8), "r_hip": Vector3(4, 0, -2), "l_knee": Vector3(14, 0, 0),
		"r_hand_to": "holster_grip",
	},
	"ox_guard": {
		"pelvis": Vector3(0, -28, 0), "spine": Vector3(6, 0, 0), "chest": Vector3(4, 22, 0), "head": Vector3(-8, 6, 0),
		"l_hip": Vector3(-30, 0, 10), "l_knee": Vector3(30, 0, 0), "l_ankle": Vector3(4, 0, 0),
		"r_hip": Vector3(24, 0, -12), "r_knee": Vector3(22, 0, 0), "r_ankle": Vector3(-14, 0, 0),
		"weapon": [Vector3(-0.1, 0.06, 0.34), Vector3(-38, 0, 28)],
	},
	"low_guard": {
		"pelvis": Vector3(0, -22, 0), "spine": Vector3(8, 0, 0), "chest": Vector3(6, 28, 0), "head": Vector3(-6, -10, 0),
		"l_shoulder": Vector3(-48, 0, 26), "l_elbow": Vector3(-34, 0, 0),
		"l_hip": Vector3(-30, 0, 9), "l_knee": Vector3(34, 0, 0),
		"r_hip": Vector3(22, 0, -10), "r_knee": Vector3(18, 0, 0), "r_ankle": Vector3(-14, 0, 0),
		"weapon": [Vector3(-0.3, -0.42, 0.12), Vector3(150, 0, -30)],
		"one_hand": true,
	},
}


func _pose(body: Node3D, pose: String) -> void:
	var p: Dictionary = POSES.get(pose, POSES["idle"])
	for jname in p:
		if body.get_meta("joints").has(jname):
			_j(body, jname).rotation_degrees = p[jname]
	body.set_meta("pose", pose)
	var chest := _j(body, "chest")
	if body.has_meta("weapon"):
		var w: Node3D = body.get_meta("weapon")
		if p.has("weapon"):
			w.position = p["weapon"][0]
			w.rotation_degrees = p["weapon"][1]
		var grips: Dictionary = w.get_meta("grips", {})
		if grips.has("r"):
			_reach(body, "r", w.transform * (grips["r"] as Vector3), Vector3(-0.5, -0.7, -0.5))
		if grips.has("l") and not p.get("one_hand", false):
			_reach(body, "l", w.transform * (grips["l"] as Vector3), Vector3(0.6, -0.7, -0.4))
	if p.has("r_hand_to") and body.has_meta(p["r_hand_to"]):
		var target: Node3D = body.get_meta(p["r_hand_to"])
		_reach(body, "r", _rel(body, chest).affine_inverse() * _rel(body, target) * Vector3.ZERO, Vector3(-0.7, -0.2, -0.6))


## Transform of `node` relative to the character root (works before it is in a tree).
func _rel(root: Node3D, node: Node3D) -> Transform3D:
	var t := Transform3D()
	var n: Node = node
	while n != null and n != root:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


## Public IK hook for runtime animators (player_avatar.gd, cantina_owner_npc.gd).
func reach(body: Node3D, side: String, target: Vector3, pole: Vector3) -> void:
	_reach(body, side, target, pole)


## Transform of `node` in the character's chest space.
func chest_space(body: Node3D, node: Node3D) -> Transform3D:
	return _rel(body, _j(body, "chest")).affine_inverse() * _rel(body, node)


## Two-bone IK: put the hand of arm `side` ("l"/"r") at `target` (chest space).
## The elbow swings toward `pole`. Joints: shoulder rotates freely, elbow bends on X.
func _reach(body: Node3D, side: String, target: Vector3, pole: Vector3) -> void:
	var sh := _j(body, side + "_shoulder")
	var el := _j(body, side + "_elbow")
	var l1 := UPPER_ARM
	var l2 := FOREARM + HAND_REACH
	var d := target - sh.position
	var dist := clampf(d.length(), absf(l1 - l2) + 0.01, l1 + l2 - 0.005)
	var dn := d.normalized()
	var a := acos(clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0))
	var b := acos(clampf((l1 * l1 + l2 * l2 - dist * dist) / (2.0 * l1 * l2), -1.0, 1.0))
	var pp := (pole - dn * pole.dot(dn)).normalized()
	var u := (dn * cos(a) + pp * sin(a)).normalized()       # upper arm direction
	var y := -u                                              # limbs hang along local -Y
	var z := (dn - u * dn.dot(u)).normalized()               # the forearm swings toward +Z
	var x := y.cross(z).normalized()
	sh.transform.basis = Basis(x, y, z)
	el.rotation = Vector3(-(PI - b), 0, 0)


# ------------------------------------------------------------------ Remnant

func _dress_trooper(body: Node3D, p: Dictionary, commander: bool) -> void:
	var armor := _m(_c(p, "armor"), "metal", 0.55)
	var armor_l := _m(_c(p, "armor_light"), "metal", 0.45)
	var trim := _m(_c(p, "trim"), "metal", 0.3)
	var cloth := _m(_c(p, "cloth"), "cloth", 0.6)
	var dark := _m(Color("#24201e"), "leather", 0.5)
	var visor := mats.glow(_c(p, "visor"))
	visor.emission_energy_multiplier = 4.0
	var chest := _j(body, "chest")
	var pelvis := _j(body, "pelvis")
	var head := _j(body, "head")

	# Cuirass with a centre keel (reads as forged plate, not a box), gorget, brass collar.
	_mi(chest, LookMeshKit.frustum(0.4, 0.27, 0.34, -0.16), armor, Vector3(0, 0.05, 0.015))
	_mi(chest, LookMeshKit.frustum(0.05, 0.05, 0.3, 0.4), armor_l, Vector3(0, 0.05, 0.145), Vector3(0, 45, 0))
	_mi(chest, LookMeshKit.shell(0.105, 0.15, 0.33, 0.2, 0.0, TAU, 0.02, 16, 1), armor)
	_mi(chest, LookMeshKit.shell(0.152, 0.16, 0.215, 0.195, 0.0, TAU, 0.02, 16, 1), trim)
	for i in 3:
		_mi(chest, _box(Vector3(0.31 - i * 0.015, 0.05, 0.22)), armor_l, Vector3(0, -0.15 - i * 0.055, 0.012))
	# Power pack on the back: a silhouette bump with vents and a whip antenna.
	_mi(chest, LookMeshKit.frustum(0.3, 0.12, 0.34, 0.12), armor_l, Vector3(0, 0.02, -0.18))
	for x in [-0.08, 0.0, 0.08]:
		_mi(chest, _box(Vector3(0.02, 0.24, 0.05)), armor, Vector3(x, 0.03, -0.25))
	_mi(chest, _cyl(0.004, 0.006, 0.55, 4), dark, Vector3(0.12, 0.42, -0.2), Vector3(-10, 0, -8))
	# Belt and kit.
	_mi(pelvis, _box(Vector3(0.35, 0.07, 0.23)), dark, Vector3(0, 0.03, 0))
	for x in [-0.12, -0.04, 0.04, 0.12]:
		_mi(pelvis, _box(Vector3(0.065, 0.075, 0.05)), dark, Vector3(x, 0.01, 0.125))
	# Asymmetric shoulders: layered pauldron on the left (shield side), small on the right.
	var ls := _j(body, "l_shoulder")
	for i in 3:
		_mi(ls, _sphere(0.14 - i * 0.012, 0.15, 12), armor if i % 2 == 0 else armor_l,
			Vector3(0.045 + i * 0.02, 0.035 - i * 0.05, 0), Vector3(0, 0, -16 - i * 11), Vector3(1.0, 0.7, 1.15))
	_mi(ls, _box(Vector3(0.18, 0.015, 0.2)), trim, Vector3(0.06, 0.085, 0), Vector3(0, 0, -16))
	_mi(_j(body, "r_shoulder"), _sphere(0.09, 0.1, 10), armor, Vector3(-0.02, 0.025, 0), Vector3(0, 0, 15))
	for s in ["l", "r"]:
		_mi(_j(body, s + "_elbow"), _cyl(0.054, 0.06, 0.17, 10), armor_l, Vector3(0, -0.15, 0))
		_mi(_j(body, s + "_knee"), _sphere(0.075, 0.1, 10), armor, Vector3(0, 0.0, 0.05))
		_mi(_j(body, s + "_knee"), _cyl(0.058, 0.074, 0.3, 10), armor, Vector3(0, -0.2, 0.014))
		_mi(_j(body, s + "_hip"), _box(Vector3(0.16, 0.24, 0.18)), armor_l, Vector3(0, -0.15, 0.02))
	# Tabard front and back, with a brass stripe.
	var tab := _mi(pelvis, LookMeshKit.cloth(0.24, 0.62 if commander else 0.5, 0.02, 2, 4), cloth, Vector3(0, -0.02, 0.14))
	tab.rotation_degrees = Vector3(-4, 0, 0)
	_mi(pelvis, _box(Vector3(0.035, 0.46, 0.01)), trim, Vector3(0, -0.26, 0.15))
	var tab_b := _mi(pelvis, LookMeshKit.cloth(0.26, 0.55, 0.02, 2, 4), cloth, Vector3(0, -0.02, -0.12))
	tab_b.rotation_degrees = Vector3(4, 180, 0)

	# Helmet: a swept sallet. Brow overhang shades a single burning visor slit.
	_mi(head, _sphere(0.13, 0.28, 16), armor, Vector3(0, 0.03, -0.012), Vector3.ZERO, Vector3(1.0, 1.05, 1.2))
	_mi(head, _box(Vector3(0.24, 0.05, 0.21)), armor, Vector3(0, -0.06, -0.12), Vector3(-30, 0, 0))
	_mi(head, _box(Vector3(0.2, 0.13, 0.05)), armor_l, Vector3(0, -0.04, 0.12), Vector3(-10, 0, 0))
	_mi(head, _box(Vector3(0.23, 0.03, 0.07)), armor, Vector3(0, 0.035, 0.12), Vector3(12, 0, 0))
	_mi(head, _box(Vector3(0.17, 0.016, 0.012)), visor, Vector3(0, 0.008, 0.148))
	_mi(head, _box(Vector3(0.022, 0.05, 0.3)), trim if commander else armor_l, Vector3(0, 0.162, -0.02))
	for sx in [-1.0, 1.0]:
		_mi(head, _box(Vector3(0.03, 0.12, 0.1)), armor, Vector3(0.122 * sx, -0.05, 0.06), Vector3(0, 0, 12 * sx))

	if commander:
		var coat := _m(_c(p, "coat"), "cloth", 0.4)
		_mi(chest, LookMeshKit.shell(0.21, 0.25, 0.16, -0.5, PI * 0.5 + 0.55, PI * 0.5 + TAU - 0.55, 0.02, 22, 4), coat)
		_mi(pelvis, LookMeshKit.shell(0.25, 0.37, 0.0, -0.82, PI * 0.5 + 0.35, PI * 0.5 + TAU - 0.35, 0.02, 24, 7, 0.07), coat)
		_mi(chest, LookMeshKit.shell(0.13, 0.18, 0.36, 0.18, PI * 0.5 + 0.5, PI * 0.5 + TAU - 0.5, 0.02, 16, 1), coat)
		# Short shoulder cape and brass epaulettes: rank you can read from across the port.
		_mi(chest, LookMeshKit.shell(0.2, 0.33, 0.24, 0.0, PI * 0.5 + 0.9, PI * 0.5 + TAU - 0.9, 0.02, 20, 2, 0.02), cloth)
		for sx in [-1.0, 1.0]:
			_mi(chest, _box(Vector3(0.13, 0.025, 0.14)), trim, Vector3(0.2 * sx, 0.255, 0), Vector3(0, 0, -14 * sx))
		_mi(head, _box(Vector3(0.035, 0.1, 0.36)), cloth, Vector3(0, 0.215, -0.04), Vector3(-6, 0, 0))   # crest
		_mi(chest, _box(Vector3(0.05, 0.5, 0.012)), trim, Vector3(0.05, 0.0, 0.165), Vector3(0, 0, 38))   # sash
		_mi(_j(body, "r_hip"), _box(Vector3(0.05, 0.17, 0.09)), dark, Vector3(-0.1, -0.08, 0.02))
	else:
		var cape := _mi(_j(body, "l_shoulder"), LookMeshKit.cloth(0.34, 0.85, 0.08, 3, 5), cloth, Vector3(0.02, 0.08, -0.09))
		cape.rotation_degrees = Vector3(8, 180, -6)
		_rifle(body, p)


## Remnant line rifle. Issue #82: the rendered rifle the player carries
## (content/look/hand_weapons.json "rifle_blaster", darkened and scoped the same
## way), slid so its grips sit where the old one's did and the poses still fit.
## Without the model it is the old slab-sided box rifle. Grips for IK.
func _rifle(body: Node3D, p: Dictionary) -> void:
	var r := Node3D.new()
	r.name = "Rifle"
	_j(body, "chest").add_child(r)
	body.set_meta("weapon", r)
	var grips := { "r": Vector3(0, -0.06, 0.0), "l": Vector3(0, -0.04, 0.26) }
	r.set_meta("grips", grips)
	var spec: Dictionary = _read_json(HAND_WEAPONS_PATH).get("rifle_blaster", {})
	var path := str(spec.get("model", ""))
	# Issue #162: ModelCache keeps the rifle loaded. load() twice with nothing
	# holding it read rifle.glb from disk twice per trooper (~78 ms each).
	var packed = ModelCache.scene(path) if path != "" and ResourceLoader.exists(path) else null
	if packed is PackedScene:
		var model: Node3D = (packed as PackedScene).instantiate()
		var k := float(spec.get("scale", 1.0))
		var g: Dictionary = spec.get("grips", {})
		var gr := Vector3(float(g.r[0]), float(g.r[1]), float(g.r[2])) * k if g.has("r") else Vector3.ZERO
		var gl := Vector3(float(g.l[0]), float(g.l[1]), float(g.l[2])) * k if g.has("l") else gr + Vector3(0, 0, 0.3)
		model.scale = Vector3.ONE * k
		model.position = grips.r - gr
		if spec.get("dark") is Dictionary:
			PlayerAvatar._darken(model, spec.dark)
		GunSights.add_to(model, spec)
		r.add_child(model)
		r.set_meta("grips", { "r": grips.r, "l": model.position + gl })
		return
	var metal := _m(Color("#2a2a2a"), "metal", 0.35)
	var furn := _m(_c(p, "armor_light", "#4a4a4a"), "metal", 0.5)
	var cell := _m(_c(p, "cloth", "#6b1e1e"), "metal", 0.3)
	_mi(r, _box(Vector3(0.05, 0.1, 0.52)), metal, Vector3(0, 0.05, 0.12))
	_mi(r, _cyl(0.016, 0.016, 0.4, 8), metal, Vector3(0, 0.07, 0.56), Vector3(90, 0, 0))
	_mi(r, _cyl(0.03, 0.03, 0.16, 8), furn, Vector3(0, 0.07, 0.44), Vector3(90, 0, 0))
	_mi(r, _box(Vector3(0.045, 0.13, 0.2)), furn, Vector3(0, 0.0, -0.22), Vector3(-10, 0, 0))
	_mi(r, _box(Vector3(0.035, 0.1, 0.05)), metal, Vector3(0, -0.045, 0.0), Vector3(-15, 0, 0))
	_mi(r, _box(Vector3(0.03, 0.05, 0.17)), metal, Vector3(0, 0.125, 0.1))
	_mi(r, _box(Vector3(0.07, 0.06, 0.12)), cell, Vector3(0.05, 0.03, 0.18))
	_mi(r, _box(Vector3(0.035, 0.06, 0.05)), metal, Vector3(0, -0.02, 0.3))


## Issue #76: the marked officer's sidearm: the player's pistol model
## (hand_weapons.json "pistol_blaster"), darkened the same way. Held one-handed:
## aimed where the player's third-person pistol sits ("aim"), rested by the right
## thigh by WeaponCarry (the prop's "carry" meta). No model, no pistol.
func _pistol(body: Node3D) -> void:
	var spec: Dictionary = _read_json(HAND_WEAPONS_PATH).get("pistol_blaster", {})
	var path := str(spec.get("model", ""))
	var packed = ModelCache.scene(path) if path != "" and ResourceLoader.exists(path) else null
	if not (packed is PackedScene):
		return
	var r := Node3D.new()
	r.name = "Pistol"
	_j(body, "chest").add_child(r)
	var model: Node3D = (packed as PackedScene).instantiate()
	var k := float(spec.get("scale", 1.0))
	model.scale = Vector3.ONE * k
	if spec.get("dark") is Dictionary:
		PlayerAvatar._darken(model, spec.dark)
	r.add_child(model)
	var g: Array = spec.get("grips", {}).get("r", [0, 0, 0])
	r.set_meta("grips", { "r": Vector3(float(g[0]), float(g[1]), float(g[2])) * k })
	r.set_meta("carry", "pistol")
	var aim: Dictionary = spec.get("aim", {})
	var ap: Array = aim.get("pos", [-0.08, 0.1, 0.45])
	var ar: Array = aim.get("rot", [0, 0, 0])
	r.transform = Transform3D(Basis.from_euler(Vector3(float(ar[0]), float(ar[1]), float(ar[2])) * PI / 180.0),
		Vector3(float(ap[0]), float(ap[1]), float(ap[2])))
	body.set_meta("weapon", r)


# ------------------------------------------------------------------ smuggler

func _dress_smuggler(body: Node3D, p: Dictionary) -> void:
	var coat := _m(_c(p, "coat"), "leather", 0.7)
	var shirt := _m(_c(p, "shirt"), "cloth", 0.5)
	var trousers := _m(_c(p, "trousers"), "cloth", 0.6)
	var leather := _m(_c(p, "leather"), "leather", 0.6)
	var boots := _m(_c(p, "boots"), "leather", 0.7)
	var hat := _m(_c(p, "hat"), "leather", 0.6)
	var wrap := _m(_c(p, "skin_wrap"), "cloth", 0.5)
	var brass := _m(Color("#b08e50"), "metal", 0.3)
	var chest := _j(body, "chest")
	var pelvis := _j(body, "pelvis")
	var head := _j(body, "head")
	for s in ["l", "r"]:
		_mi(_j(body, s + "_hip"), _cyl(0.066, 0.09, 0.46, 10), trousers, Vector3(0, -0.23, 0))
		_mi(_j(body, s + "_knee"), _cyl(0.064, 0.07, 0.27, 10), boots, Vector3(0, -0.29, 0))
		_mi(_j(body, s + "_knee"), _cyl(0.075, 0.075, 0.04, 10), boots, Vector3(0, -0.16, 0))   # boot cuff
		_mi(_j(body, s + "_shoulder"), _cyl(0.054, 0.066, 0.3, 10), coat, Vector3(0, -0.15, 0))
		_mi(_j(body, s + "_elbow"), _cyl(0.05, 0.056, 0.12, 10), coat, Vector3(0, -0.2, 0))      # turned-back cuff
	_mi(chest, LookMeshKit.frustum(0.3, 0.2, 0.42, -0.26), shirt, Vector3(0, 0.0, 0.003))
	# Long duster, open at the front, flaring as it falls; collar turned up against sand.
	_mi(chest, LookMeshKit.shell(0.21, 0.205, 0.2, -0.24, PI * 0.5 + 0.48, PI * 0.5 + TAU - 0.48, 0.018, 22, 3), coat)
	_mi(pelvis, LookMeshKit.shell(0.205, 0.31, 0.05, -0.95, PI * 0.5 + 0.4, PI * 0.5 + TAU - 0.4, 0.018, 26, 7, 0.12), coat)
	_mi(chest, LookMeshKit.shell(0.15, 0.22, 0.33, 0.16, PI * 0.5 + 0.7, PI * 0.5 + TAU - 0.7, 0.02, 16, 1), coat)
	# Short weather cape over the left shoulder: asymmetry, and a second colour block.
	_mi(chest, LookMeshKit.shell(0.15, 0.235, 0.29, 0.1, -0.7, 1.5, 0.02, 14, 2), wrap)
	# Gun belt slung low, brass buckle, holster on the right thigh with a grip to reach for.
	_mi(pelvis, _box(Vector3(0.35, 0.06, 0.235)), leather, Vector3(0, 0.0, 0), Vector3(0, 0, -5))
	_mi(pelvis, _box(Vector3(0.06, 0.05, 0.02)), brass, Vector3(0.02, 0.0, 0.122))
	var rh := _j(body, "r_hip")
	_mi(rh, _box(Vector3(0.065, 0.22, 0.11)), leather, Vector3(-0.1, -0.13, 0.0), Vector3(0, 0, 4))
	_mi(rh, _box(Vector3(0.04, 0.12, 0.075)), _m(Color("#262626"), "metal", 0.4), Vector3(-0.1, 0.0, 0.015), Vector3(18, 0, 4))
	_mi(rh, _cyl(0.03, 0.03, 0.03, 10), _m(Color("#b0703a"), "metal", 0.3), Vector3(-0.1, -0.03, 0.06), Vector3(90, 0, 0))   # coil
	var grip := _joint(rh, "holster_grip", Vector3(-0.1, 0.02, 0.03))
	body.set_meta("holster_grip", grip)
	# Bandolier of charge cells across the chest.
	var band := Node3D.new()
	band.rotation_degrees = Vector3(0, 0, -38)
	chest.add_child(band)
	_mi(band, _box(Vector3(0.05, 0.66, 0.012)), leather, Vector3(0, -0.02, 0.122))
	for i in 6:
		_mi(band, _box(Vector3(0.04, 0.035, 0.03)), brass if i % 2 == 0 else leather, Vector3(0, 0.16 - i * 0.07, 0.135))
	_mi(_j(body, "l_hip"), _box(Vector3(0.09, 0.2, 0.22)), leather, Vector3(0.13, 0.02, -0.03))
	# Head: face wrap up to the eyes, goggles, a scarf tail, and the wide hat.
	_mi(head, _sphere(0.108, 0.24, 14), _m(Color("#3a2a20"), "cloth", 0.2))
	_mi(head, _cyl(0.114, 0.126, 0.13, 14), _m(_c(p, "face_wrap", "#2c2622"), "cloth", 0.4), Vector3(0, -0.06, 0.005))
	_mi(head, _cyl(0.13, 0.15, 0.06, 14), wrap, Vector3(0, -0.13, 0.0))   # scarf knot at the neck
	var tail := _mi(head, LookMeshKit.cloth(0.1, 0.42, 0.04, 1, 4), wrap, Vector3(0.05, -0.12, -0.11))
	tail.rotation_degrees = Vector3(25, 160, -20)
	var g := _m(_c(p, "goggles"), "metal", 0.5)
	var lens := mats.glow(_c(p, "lens"))
	lens.emission_energy_multiplier = 0.8
	for sx in [-1.0, 1.0]:
		_mi(head, _cyl(0.034, 0.034, 0.03, 10), g, Vector3(0.045 * sx, 0.02, 0.098), Vector3(90, 0, 0))
		_mi(head, _cyl(0.026, 0.026, 0.01, 10), lens, Vector3(0.045 * sx, 0.02, 0.115), Vector3(90, 0, 0))
	_mi(head, _box(Vector3(0.235, 0.014, 0.18)), g, Vector3(0, 0.03, 0.0))
	var hat_node := Node3D.new()
	hat_node.position = Vector3(0, 0.0, -0.005)
	hat_node.rotation_degrees = Vector3(-8, 0, 4)
	head.add_child(hat_node)
	_mi(hat_node, LookMeshKit.shell(0.29, 0.28, 0.072, 0.09, 0.0, TAU, 0.18, 24, 1), hat)       # brim
	_mi(hat_node, _cyl(0.08, 0.11, 0.14, 14), hat, Vector3(0, 0.145, 0))                     # crown
	_mi(hat_node, _box(Vector3(0.02, 0.05, 0.16)), _m(Color("#4a3624"), "leather", 0.5), Vector3(0, 0.215, 0))  # pinch
	_mi(hat_node, _cyl(0.112, 0.112, 0.024, 14), _m(Color("#2a2018"), "leather", 0.4), Vector3(0, 0.09, 0))


# ------------------------------------------------------------------ duelist

func _dress_duelist(body: Node3D, p: Dictionary) -> void:
	var wraps := _m(_c(p, "wraps"), "cloth", 0.5)
	var mantle := _m(_c(p, "mantle"), "cloth", 0.6)
	var sash := _m(_c(p, "sash"), "cloth", 0.5)
	var bandage := _m(_c(p, "bandage"), "cloth", 0.5)
	var mask := _m(_c(p, "mask"), "leather", 0.25)
	var chest := _j(body, "chest")
	var pelvis := _j(body, "pelvis")
	var head := _j(body, "head")
	_mi(chest, LookMeshKit.frustum(0.29, 0.2, 0.44, -0.24), wraps, Vector3(0, 0.0, 0.002))
	# Crossed chest wraps (focal zone detail).
	for sx in [-1.0, 1.0]:
		_mi(chest, _box(Vector3(0.045, 0.5, 0.012)), bandage, Vector3(0, 0.0, 0.112), Vector3(0, 0, 30 * sx))
	for s in ["l", "r"]:
		for i in 4:
			_mi(_j(body, s + "_elbow"), _cyl(0.05, 0.05, 0.035, 10), bandage, Vector3(0, -0.07 - i * 0.05, 0), Vector3(0, 0, 8 if i % 2 == 0 else -8))
	_mi(pelvis, LookMeshKit.shell(0.19, 0.31, 0.06, -0.86, PI * 0.5 + 0.3, PI * 0.5 + PI - 0.15, 0.015, 12, 6, 0.06), wraps)
	_mi(pelvis, LookMeshKit.shell(0.19, 0.31, 0.06, -0.86, PI * 0.5 + PI + 0.15, PI * 0.5 + TAU - 0.3, 0.015, 12, 6, 0.06), wraps)
	_mi(pelvis, _cyl(0.175, 0.18, 0.1, 14), sash, Vector3(0, 0.05, 0))
	var tail := _mi(pelvis, LookMeshKit.cloth(0.09, 0.66, 0.05, 1, 5), sash, Vector3(0.1, 0.02, 0.12))
	tail.rotation_degrees = Vector3(-8, 20, 6)
	# Asymmetric mantle: heavy over the right shoulder and down the back.
	var mt := _mi(chest, LookMeshKit.shell(0.18, 0.3, 0.27, -0.2, -0.3, PI + 0.6, 0.025, 18, 4, 0.04), mantle)
	mt.rotation_degrees = Vector3(0, 180, -8)
	_mi(chest, LookMeshKit.shell(0.13, 0.155, 0.31, 0.2, 0.0, TAU, 0.02, 16, 1), mantle)
	# Hood thrown back over a sculpted mask: smooth, one vertical slit, a brass seam.
	_mi(head, LookMeshKit.shell(0.12, 0.135, 0.12, -0.12, PI * 0.5 + 1.2, PI * 0.5 + TAU - 1.2, 0.02, 16, 3), wraps, Vector3(0, 0, -0.025))
	_mi(head, _sphere(0.108, 0.26, 16), mask, Vector3.ZERO, Vector3.ZERO, Vector3(0.95, 1.0, 1.05))
	_mi(head, _box(Vector3(0.012, 0.12, 0.02)), _m(Color("#120f0e"), "dark", 0.0), Vector3(0, 0.0, 0.108))
	var seam := mats.glow(_c(p, "mask_line"))
	seam.emission_energy_multiplier = 0.5
	_mi(head, _box(Vector3(0.006, 0.09, 0.01)), seam, Vector3(-0.05, 0.03, 0.102), Vector3(0, 25, 18))
	_energy_sword(body)


## The default melee weapon: a metal hilt and a glowing staff of energy.
## Colour, length and hilt model come from content/core/weapons/energy_blade.json.
## Local +Y runs up the blade from the emitter.
func _energy_sword(body: Node3D) -> Node3D:
	var sword := make_energy_sword()
	_j(body, "chest").add_child(sword)
	body.set_meta("weapon", sword)
	return sword


## A free-standing energy sword (not attached to a body). The player's weapon
## controller uses this too, so the hero's blade and the duelist's are one design.
## Children: "Hilt" (the model, or a stand-in grip) and "Blade" (scale.y 0..1
## ignites it) holding "BladeLight". `hilt_override` is a hilt .glb path.
func make_energy_sword(color_override: Color = Color(0, 0, 0, 0), length_override: float = -1.0,
		hilt_override: String = "") -> Node3D:
	var color := Color.html(blade_cfg.get("blade_color", "#3aa0ff"))
	if color_override.a > 0.0:
		color = color_override
	var length := float(blade_cfg.get("blade_length", 1.05)) if length_override <= 0.0 else length_override
	var sword := Node3D.new()
	sword.name = "EnergySword"
	sword.add_child(_sword_hilt(hilt_override if hilt_override != "" else str(blade_cfg.get("hilt", ""))))
	var blade := Node3D.new()
	blade.name = "Blade"
	blade.position = Vector3(0, 0.015, 0)
	sword.add_child(blade)
	var core := ShaderMaterial.new()
	core.shader = ENERGY
	core.set_shader_parameter("color", color.lerp(Color.WHITE, 0.6))
	core.set_shader_parameter("energy", 4.0)
	core.set_shader_parameter("core", 1.0)
	var glow := ShaderMaterial.new()
	glow.shader = ENERGY
	glow.set_shader_parameter("color", color)
	glow.set_shader_parameter("energy", 1.5)
	glow.set_shader_parameter("falloff", 1.2)
	var halo := ShaderMaterial.new()
	halo.shader = ENERGY
	halo.set_shader_parameter("color", color)
	halo.set_shader_parameter("energy", 0.6)
	halo.set_shader_parameter("falloff", 2.2)
	# A round staff: white-hot core, a coloured shell, and a wide soft halo.
	_mi(blade, _cyl(0.008, 0.01, length, 12), core, Vector3(0, length * 0.5, 0)).name = "Core"
	_mi(blade, _sphere(0.008, 0.016, 12), core, Vector3(0, length, 0)).name = "Tip"
	_mi(blade, _cyl(0.022, 0.025, length * 1.03, 14), glow, Vector3(0, length * 0.515, 0)).name = "Glow"
	_mi(blade, _cyl(0.05, 0.055, length * 1.06, 14), halo, Vector3(0, length * 0.52, 0)).name = "Halo"
	var light := OmniLight3D.new()
	light.name = "BladeLight"
	light.light_color = color
	light.light_energy = 1.8
	light.omni_range = 3.2
	light.position = Vector3(0, length * 0.5, 0)
	blade.add_child(light)
	sword.set_meta("grips", { "r": Vector3(0, -0.05, 0), "l": Vector3(0, -0.18, 0) })
	sword.set_meta("length", length)
	sword.set_meta("color", color)
	return sword


## The sword's "Hilt": the model at `path` (assets/gear/, 0.28 m along +Y, centred,
## emitter up) with its emitter at the blade's root, or a plain grip without one.
func _sword_hilt(path: String) -> Node3D:
	var hilt := Node3D.new()
	hilt.name = "Hilt"
	hilt.set_meta("path", path)
	var packed = ModelCache.scene(path) if path != "" and ResourceLoader.exists(path) else null
	if packed is PackedScene:
		var model: Node3D = (packed as PackedScene).instantiate()
		model.position = Vector3(0, -0.13, 0)
		hilt.add_child(model)
		return hilt
	var metal := _m(Color("#9a9ea4"), "metal", 0.6)
	_mi(hilt, _cyl(0.019, 0.021, 0.25, 10), _m(Color("#2a2826"), "leather", 0.4), Vector3(0, -0.13, 0))
	_mi(hilt, _cyl(0.024, 0.02, 0.04, 10), metal, Vector3(0, 0.0, 0))
	_mi(hilt, _sphere(0.024, 0.04, 10), metal, Vector3(0, -0.26, 0))
	return hilt


## Issue #148: give a built energy sword a new colour (the red saber from the wreck).
static func recolor_energy_sword(sword: Node3D, color: Color) -> void:
	var blade := sword.get_node_or_null("Blade")
	if blade == null:
		return
	for part in ["Core", "Tip"]:
		var mi := blade.get_node_or_null(part) as MeshInstance3D
		if mi != null:
			(mi.material_override as ShaderMaterial).set_shader_parameter("color", color.lerp(Color.WHITE, 0.6))
	for part in ["Glow", "Halo"]:
		var mi := blade.get_node_or_null(part) as MeshInstance3D
		if mi != null:
			(mi.material_override as ShaderMaterial).set_shader_parameter("color", color)
	var light := blade.get_node_or_null("BladeLight") as OmniLight3D
	if light != null:
		light.light_color = color
	sword.set_meta("color", color)


## Swap a built energy sword's hilt for the model at `path` (the red saber's black one).
func set_sword_hilt(sword: Node3D, path: String) -> void:
	var old := sword.get_node_or_null("Hilt")
	if path == "" or (old != null and str(old.get_meta("path", "")) == path):
		return
	if old != null:
		sword.remove_child(old)
		old.queue_free()
	sword.add_child(_sword_hilt(path))


# ------------------------------------------------------------------ cantina owner

## The cantina's cantina_owner: a working outfit, not a costume. Rolled sleeves and an
## apron (she works), a mechanical left forearm (an old injury, a story she sells
## by the drink), goggles pushed up on a head wrap, a breather mask (faces stay
## covered), and a bar towel over the right shoulder. Her silhouette is the apron's
## long straight front against the counter.
func _dress_cantina_owner(body: Node3D, p: Dictionary) -> void:
	var vest := _m(_c(p, "vest"), "leather", 0.5)
	var shirt := _m(_c(p, "shirt"), "cloth", 0.4)
	var apron := _m(_c(p, "apron"), "leather", 0.7)
	var wrap := _m(_c(p, "wrap"), "cloth", 0.5)
	var trousers := _m(_c(p, "trousers"), "cloth", 0.6)
	var towel := _m(_c(p, "towel"), "cloth", 0.4)
	var metal := _m(_c(p, "prosthetic", "#6b6660"), "metal", 0.45)
	var brass := _m(Color("#b08e50"), "metal", 0.3)
	var dark := _m(Color("#1c1816"), "dark", 0.0)
	var chest := _j(body, "chest")
	var pelvis := _j(body, "pelvis")
	var head := _j(body, "head")
	for s in ["l", "r"]:
		_mi(_j(body, s + "_hip"), _cyl(0.066, 0.088, 0.46, 10), trousers, Vector3(0, -0.23, 0))
		_mi(_j(body, s + "_shoulder"), _cyl(0.056, 0.064, 0.24, 10), shirt, Vector3(0, -0.12, 0))
		_mi(_j(body, s + "_shoulder"), _cyl(0.064, 0.064, 0.05, 10), shirt, Vector3(0, -0.25, 0))   # rolled cuff
	_mi(chest, LookMeshKit.frustum(0.3, 0.2, 0.43, -0.26), shirt, Vector3(0, 0.0, 0.002))
	# Vest: open, cut short; a second colour block over the shirt.
	_mi(chest, LookMeshKit.shell(0.205, 0.2, 0.2, -0.22, PI * 0.5 + 0.42, PI * 0.5 + TAU - 0.42, 0.016, 20, 2), vest)
	for sx in [-1.0, 1.0]:
		_mi(chest, _box(Vector3(0.016, 0.02, 0.02)), brass, Vector3(0.07 * sx, -0.02, 0.125))
	# Apron: long, straight, to mid-shin. Neck strap and a waist tie.
	_mi(pelvis, _box(Vector3(0.36, 0.72, 0.012)), apron, Vector3(0, -0.32, 0.135), Vector3(-3, 0, 0))
	_mi(chest, _box(Vector3(0.24, 0.3, 0.012)), apron, Vector3(0, 0.0, 0.128), Vector3(-6, 0, 0))
	for sx in [-1.0, 1.0]:
		_mi(chest, _box(Vector3(0.02, 0.26, 0.01)), apron, Vector3(0.09 * sx, 0.24, 0.07), Vector3(-30, 0, -14 * sx))
	_mi(pelvis, _cyl(0.18, 0.185, 0.04, 14), apron, Vector3(0, 0.03, 0))
	_mi(pelvis, _box(Vector3(0.12, 0.08, 0.05)), towel, Vector3(-0.12, -0.08, 0.15))   # pocket rag
	# Mechanical left forearm: plates, a piston, a glowing joint.
	var le := _j(body, "l_elbow")
	_mi(le, _cyl(0.042, 0.05, 0.25, 8), metal, Vector3(0, -0.13, 0))
	_mi(le, _cyl(0.008, 0.008, 0.22, 6), brass, Vector3(0.04, -0.13, 0.02))
	_mi(le, _sphere(0.05, 0.08, 10), metal, Vector3(0, 0.0, 0))
	var core := mats.glow(_c(p, "prosthetic_glow", "#7fd0c8"))
	core.emission_energy_multiplier = 1.4
	_mi(le, _cyl(0.02, 0.02, 0.02, 8), core, Vector3(0, -0.02, 0.045), Vector3(90, 0, 0))
	# Bar towel over the right shoulder.
	var t1 := _mi(chest, LookMeshKit.cloth(0.11, 0.42, 0.03, 1, 3), towel, Vector3(-0.17, 0.27, 0.02))
	t1.rotation_degrees = Vector3(0, 0, 8)
	# Head: wrap, goggles pushed up on the forehead, breather mask over mouth and nose.
	_mi(head, _sphere(0.104, 0.235, 14), dark)
	for i in 3:
		_mi(head, _cyl(0.112 - i * 0.012, 0.118 - i * 0.008, 0.05, 14), wrap,
			Vector3(0, 0.05 + i * 0.045, -0.012), Vector3(-10 + i * 4, 0, -3 + i * 3))
	var tail := _mi(head, LookMeshKit.cloth(0.08, 0.3, 0.03, 1, 3), wrap, Vector3(0.04, 0.06, -0.11))
	tail.rotation_degrees = Vector3(14, 165, 10)
	var g := _m(Color("#2a2a2a"), "metal", 0.5)
	var lens := mats.glow(_c(p, "lens", "#e0a050"))
	lens.emission_energy_multiplier = 0.6
	for sx in [-1.0, 1.0]:
		_mi(head, _cyl(0.03, 0.03, 0.03, 10), g, Vector3(0.042 * sx, 0.1, 0.085), Vector3(60, 0, 0))
		_mi(head, _cyl(0.023, 0.023, 0.01, 10), lens, Vector3(0.042 * sx, 0.11, 0.1), Vector3(60, 0, 0))
	_mi(head, _box(Vector3(0.22, 0.012, 0.16)), g, Vector3(0, 0.1, 0.0), Vector3(-15, 0, 0))
	_mi(head, _sphere(0.07, 0.09, 12), _m(_c(p, "mask", "#3c3a36"), "metal", 0.4), Vector3(0, -0.055, 0.075), Vector3.ZERO, Vector3(1.0, 0.8, 0.75))
	for sx in [-1.0, 1.0]:
		_mi(head, _cyl(0.022, 0.022, 0.03, 8), g, Vector3(0.05 * sx, -0.07, 0.11), Vector3(90, 0, 0))   # filters


## A glass and a rag: the cantina owner's props (the npc's animator moves her hands).
func make_bar_glass() -> Node3D:
	var root := Node3D.new()
	root.name = "Glass"
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.75, 0.85, 0.85, 0.35)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.1
	glass.metallic_specular = 0.8
	_mi(root, _cyl(0.035, 0.03, 0.11, 12), glass, Vector3(0, 0.055, 0))
	var drink := StandardMaterial3D.new()
	drink.albedo_color = Color(0.85, 0.5, 0.15, 0.8)
	drink.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mi(root, _cyl(0.031, 0.028, 0.06, 12), drink, Vector3(0, 0.033, 0))
	return root


# ------------------------------------------------------------------ locals

func _dress_local(body: Node3D, p: Dictionary) -> void:
	var robe := _m(_c(p, "robe"), "cloth", 0.6)
	var hood := _m(_c(p, "hood"), "cloth", 0.6)
	var wrap := _m(_c(p, "wrap"), "cloth", 0.5)
	var wood := _m(Color("#4a3a2c"), "leather", 0.5)
	var chest := _j(body, "chest")
	var pelvis := _j(body, "pelvis")
	var head := _j(body, "head")
	_mi(chest, LookMeshKit.shell(0.21, 0.22, 0.24, -0.25, 0.0, TAU, 0.03, 18, 3), robe)
	_mi(pelvis, LookMeshKit.shell(0.22, 0.35, 0.08, -0.93, 0.0, TAU, 0.03, 20, 6, 0.05), robe)
	for s in ["l", "r"]:
		_mi(_j(body, s + "_shoulder"), _cyl(0.06, 0.09, 0.42, 10), robe, Vector3(0, -0.22, 0))
	_mi(chest, LookMeshKit.shell(0.2, 0.26, 0.28, 0.04, 0.0, TAU, 0.03, 18, 2), hood)
	# Head wrap: layered bands, slightly askew, and a veil over the lower face.
	_mi(head, _sphere(0.1, 0.23, 12), _m(Color("#1c1816"), "dark", 0.0))
	for i in 4:
		_mi(head, _cyl(0.118 - i * 0.012, 0.124 - i * 0.008, 0.05, 14), hood if i % 2 == 0 else robe,
			Vector3(0.005 * i, 0.03 + i * 0.04, -0.01), Vector3(-8 + i * 3, 0, 4 - i * 3))
	_mi(head, _sphere(0.07, 0.07, 10), hood, Vector3(0.01, 0.2, -0.02))
	var veil := _mi(head, LookMeshKit.cloth(0.2, 0.2, 0.05, 2, 2), wrap, Vector3(0, -0.01, 0.105))
	veil.rotation_degrees = Vector3(6, 0, 0)
	var tail := _mi(head, LookMeshKit.cloth(0.1, 0.36, 0.05, 1, 3), hood, Vector3(-0.07, 0.08, -0.1))
	tail.rotation_degrees = Vector3(18, 200, 0)
	_mi(pelvis, _cyl(0.2, 0.21, 0.07, 14), wrap, Vector3(0, 0.06, 0))
	# A woven pack on the back: the silhouette says "carries everything they own".
	if not bool(p.get("no_local_props", false)):
		_mi(chest, _cyl(0.13, 0.11, 0.42, 12), _m(Color("#8a6a44"), "leather", 0.7), Vector3(0, 0.02, -0.24), Vector3(8, 0, 0))
		_mi(chest, _sphere(0.12, 0.1, 10), wrap, Vector3(0, 0.25, -0.25))
		var staff := _mi(_j(body, "r_wrist"), _cyl(0.018, 0.022, 1.8, 6), wood, Vector3(0, -0.06, 0.03))
		staff.rotation_degrees = Vector3(-75, 0, 0)


static func _merged(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate(true)
	for k in b:
		if out.get(k) is Dictionary and b[k] is Dictionary:
			out[k] = _merged(out[k], b[k])
		else:
			out[k] = b[k]
	return out
