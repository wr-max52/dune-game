class_name DroidKit
extends RefCounted
## Droid looks. Issue #25: each kind's "look" in content/core/droids/droids.json
## names a Hyper3D model (assets/gear/, prepped by tools/look/prep_gear.gd), tinted
## by the variant's body colour, with glowing eyes and a muzzle placed from data.
## Without a model (or if it is missing) the issue #51 primitives stand in.
##
## Every look is a Node3D whose origin sits on the ground, facing -Z, with:
##   "Model"  the part that tips over (a wreck lies down) or spins
##   "Eye*"   glowing meshes (brightness shows whether it is awake)
##   "Muzzle" where bolts leave (assassin only)

static func build(kind: String, variant: Dictionary, mats: LookMaterials, look: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = "Droid_" + kind
	var model := Node3D.new()
	model.name = "Model"
	root.add_child(model)
	var body := Color(str(variant.get("body", "#808080")))
	var trim := Color(str(variant.get("trim", "#404040")))
	var eye := Color(str(variant.get("eye", "#4ad0ff")))
	if _from_model(model, look, body, eye, mats):
		root.set_meta("source", "model")
		return root
	root.set_meta("source", "kit")
	match kind:
		"floating":
			_floating(model, body, trim, eye, mats)
		"cargo":
			_cargo(model, body, trim, eye, mats)
		"assassin":
			_assassin(model, body, trim, eye, mats)
	return root


## The kind's model, tinted toward the body colour (look.tint: 0 = as generated,
## 1 = full body colour), with an "Eye" per look.eyes entry and a "Muzzle" at
## look.muzzle. False when there is no model to load.
static func _from_model(model: Node3D, look: Dictionary, body: Color, eye: Color, mats: LookMaterials) -> bool:
	var path := str(look.get("model", ""))
	if path == "" or not ResourceLoader.exists(path):
		return false
	var scene = load(path)
	if not (scene is PackedScene):
		return false
	var n: Node3D = (scene as PackedScene).instantiate()
	model.add_child(n)
	var k := float(look.get("tint", 0.8))
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if src == null:
				continue
			var m := src.duplicate() as BaseMaterial3D
			m.albedo_color = Color.WHITE.lerp(body, k)
			mi.set_surface_override_material(s, m)
	var r := float(look.get("eye_radius", 0.04))
	var i := 0
	for e in look.get("eyes", []):
		_mesh(model, _ball(r), mats.glow(eye), Vector3(float(e[0]), float(e[1]), float(e[2])), Vector3.ZERO, "Eye" if i == 0 else "Eye%d" % (i + 1))
		i += 1
	if look.has("muzzle"):
		var mz := Node3D.new()
		mz.name = "Muzzle"
		var a: Array = look.muzzle
		mz.position = Vector3(float(a[0]), float(a[1]), float(a[2]))
		model.add_child(mz)
	return true


## All the glowing eyes under a look.
static func eyes(root: Node) -> Array:
	var out := []
	for c in root.find_children("Eye*", "MeshInstance3D", true, false):
		out.append(c)
	return out


static func set_awake(root: Node, awake: bool) -> void:
	for e in eyes(root):
		var m := (e as MeshInstance3D).material_override as StandardMaterial3D
		if m != null:
			m.emission_energy_multiplier = 4.0 if awake else 0.15


static func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot_deg := Vector3.ZERO, nm := "") -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.rotation_degrees = rot_deg
	if nm != "":
		m.name = nm
	parent.add_child(m)
	return m


static func _box(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	return b


static func _ball(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	return s


static func _rod(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 8
	return c


## A hovering ball with a band and one eye (the range remote's shape).
static func _floating(m: Node3D, body: Color, trim: Color, eye: Color, mats: LookMaterials) -> void:
	_mesh(m, _ball(0.25), mats.flat(body, 0.45, 0.7))
	var tor := TorusMesh.new()
	tor.inner_radius = 0.24
	tor.outer_radius = 0.3
	_mesh(m, tor, mats.flat(trim, 0.4, 0.8))
	_mesh(m, _ball(0.07), mats.glow(eye), Vector3(0, 0, -0.22), Vector3.ZERO, "Eye")


## A small box on four wheels with a lid seam and one eye.
static func _cargo(m: Node3D, body: Color, trim: Color, eye: Color, mats: LookMaterials) -> void:
	var b := mats.flat(body, 0.7, 0.3)
	var t := mats.flat(trim, 0.6, 0.5)
	_mesh(m, _box(0.6, 0.48, 0.7), b, Vector3(0, 0.42, 0))
	_mesh(m, _box(0.64, 0.05, 0.74), t, Vector3(0, 0.67, 0))
	_mesh(m, _box(0.5, 0.18, 0.04), t, Vector3(0, 0.45, -0.36))
	for x in [-0.32, 0.32]:
		for z in [-0.24, 0.24]:
			_mesh(m, _rod(0.12, 0.08), t, Vector3(x, 0.12, z), Vector3(0, 0, 90), "Wheel")
	_mesh(m, _ball(0.05), mats.glow(eye), Vector3(0, 0.58, -0.36), Vector3.ZERO, "Eye")


## Tall, thin and skeletal: rod limbs, a ribbed narrow chest, a skull with two eyes,
## and a pistol in the right hand.
static func _assassin(m: Node3D, body: Color, trim: Color, eye: Color, mats: LookMaterials) -> void:
	var b := mats.flat(body, 0.5, 0.6)
	var t := mats.flat(trim, 0.5, 0.7)
	for x in [-0.12, 0.12]:
		_mesh(m, _rod(0.035, 0.6), b, Vector3(x, 0.3, 0))          # shin
		_mesh(m, _ball(0.05), t, Vector3(x, 0.6, 0))               # knee
		_mesh(m, _rod(0.04, 0.55), b, Vector3(x, 0.88, 0))         # thigh
		_mesh(m, _box(0.08, 0.04, 0.2), t, Vector3(x, 0.02, -0.05))  # foot
	_mesh(m, _box(0.3, 0.08, 0.14), t, Vector3(0, 1.17, 0))        # pelvis
	_mesh(m, _rod(0.035, 0.42), b, Vector3(0, 1.4, 0))             # spine
	for i in 4:
		_mesh(m, _box(0.32 - i * 0.03, 0.035, 0.16), b, Vector3(0, 1.48 + i * 0.08, 0))  # ribs
	_mesh(m, _box(0.5, 0.06, 0.12), t, Vector3(0, 1.82, 0))        # shoulders
	_mesh(m, _rod(0.025, 0.14), b, Vector3(0, 1.9, 0))             # neck
	_mesh(m, _box(0.18, 0.24, 0.22), b, Vector3(0, 2.08, 0), Vector3.ZERO, "Head")
	for x in [-0.045, 0.045]:
		_mesh(m, _ball(0.025), mats.glow(eye), Vector3(x, 2.1, -0.115), Vector3.ZERO, "Eye")
	# Left arm hangs; the right one is raised to aim the pistol forward.
	_mesh(m, _rod(0.03, 0.75), b, Vector3(-0.27, 1.45, 0))
	var arm := Node3D.new()
	arm.name = "GunArm"
	arm.position = Vector3(0.27, 1.8, 0)
	m.add_child(arm)
	_mesh(arm, _rod(0.03, 0.62), b, Vector3(0, 0, -0.31), Vector3(90, 0, 0))
	_mesh(arm, _box(0.05, 0.12, 0.26), t, Vector3(0, 0.02, -0.68))  # pistol
	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0, 0.04, -0.84)
	arm.add_child(muzzle)
