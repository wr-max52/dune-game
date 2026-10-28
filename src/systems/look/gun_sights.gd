extends RefCounted
## The sights the hand-gun models lack (issue #65), built from primitives and the
## numbers in hand_weapons.json. All positions are model space (the glb's own
## frame, +Z along the barrel, before the weapon scale), so they are added as
## children of the model node.
##
## Rifle: a scope (tube, ocular and objective bells, two rings, a rail, thin lens
## discs and a lit reticle) whose rear end is the `ads.sight` point. The tube is
## open and the bells are the only thing near the eye, so looking through it shows
## the world with the reticle floating in it.
## Pistol: a front post and a pair of rear blades with a notch between them.

const RETICLE_ENERGY := 3.0


static func add_to(model: Node3D, spec: Dictionary) -> void:
	if spec.get("scope") is Dictionary:
		model.add_child(build_scope(spec.scope))
	if spec.get("sights") is Dictionary:
		model.add_child(build_iron_sights(spec.sights))


static func _v3(a, d := Vector3.ZERO) -> Vector3:
	if a is Array and a.size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return d


static func _metal(c: Color, rough := 0.45) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = 0.5
	m.roughness = rough
	return m


static func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## A tube along +Z (CylinderMesh is along Y: turn it). r_rear / r_front radii.
static func _tube(parent: Node3D, r_rear: float, r_front: float, length: float, z: float, mat: Material, caps := false) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.bottom_radius = r_rear
	c.top_radius = r_front
	c.height = length
	c.radial_segments = 20
	c.rings = 1
	c.cap_top = caps
	c.cap_bottom = caps
	return _mesh(parent, c, mat, Vector3(0, 0, z), Vector3(90, 0, 0))


static func build_scope(s: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Scope"
	root.position = _v3(s.get("pos"), Vector3(0, 0.24, 0))
	var length := float(s.get("length", 0.24))
	var r := float(s.get("radius", 0.024))
	var r_oc := float(s.get("ocular", 0.029))
	var r_ob := float(s.get("objective", 0.034))
	var body := _metal(Color(0.05, 0.05, 0.06))
	var ring := _metal(Color(0.09, 0.09, 0.1), 0.35)
	var bell := 0.045
	# Main tube between the two bells, then the bells flaring to the ends.
	_tube(root, r, r, length - bell * 2.0 + 0.004, 0.0, body)
	_tube(root, r_oc, r, bell, -length * 0.5 + bell * 0.5, body)
	_tube(root, r, r_ob, bell, length * 0.5 - bell * 0.5, body)
	# Rim at the eyepiece, a ring you can see the world through.
	var rim := TorusMesh.new()
	rim.inner_radius = r_oc - 0.003
	rim.outer_radius = r_oc + 0.001
	rim.rings = 20
	rim.ring_segments = 6
	_mesh(root, rim, ring, Vector3(0, 0, -length * 0.5), Vector3(90, 0, 0))
	for z in s.get("rings", [-0.065, 0.075]):
		_tube(root, r * 1.18, r * 1.18, 0.014, float(z), ring)
	# Rail across the model's own optic block so the scope does not float.
	var rail := BoxMesh.new()
	rail.size = Vector3(0.036, 0.014, length * 0.8)
	_mesh(root, rail, ring, Vector3(0, -r - 0.003, 0))
	# Glass: faint, so the front one reads from outside and neither tints the view.
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.4, 0.7, 0.75, 0.1)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.03
	glass.metallic_specular = 1.0
	glass.render_priority = -1
	for g in [[r_ob - 0.003, length * 0.5 - 0.004], [r_oc - 0.004, -length * 0.5 + 0.02]]:
		var d := CylinderMesh.new()
		d.top_radius = g[0]
		d.bottom_radius = g[0]
		d.height = 0.0015
		d.radial_segments = 20
		var lens := _mesh(root, d, glass, Vector3(0, 0, g[1]), Vector3(90, 0, 0))
		lens.name = "Lens"
	root.add_child(_reticle(Color.html(str(s.get("reticle", "#ff2a1a"))), r - 0.003))
	return root


## Thin crosshair with an open centre and a dot, lit and unshaded so it reads on
## any background. Sits in the middle of the tube, facing the eye (+Z normal).
static func _reticle(col: Color, reach: float) -> Node3D:
	var n := Node3D.new()
	n.name = "Reticle"
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = RETICLE_ENERGY
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true            # floats over the view, never hidden by the glass
	m.render_priority = 10
	var t := 0.0006
	var gap := 0.003
	var seg := reach - gap
	for sgn in [-1.0, 1.0]:
		var h := BoxMesh.new()
		h.size = Vector3(seg, t, t)
		_mesh(n, h, m, Vector3(sgn * (gap + seg * 0.5), 0, 0))
		var v := BoxMesh.new()
		v.size = Vector3(t, seg, t)
		_mesh(n, v, m, Vector3(0, sgn * (gap + seg * 0.5), 0))
	var dot := BoxMesh.new()
	dot.size = Vector3(t * 1.6, t * 1.6, t)
	_mesh(n, dot, m, Vector3.ZERO)
	return n


static func build_iron_sights(s: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "IronSights"
	var mat := _metal(Color(0.04, 0.04, 0.045), 0.5)
	if s.get("front") is Dictionary:
		var f: Dictionary = s.front
		var b := BoxMesh.new()
		b.size = _v3(f.get("size"), Vector3(0.0035, 0.016, 0.005))
		_mesh(root, b, mat, _v3(f.get("pos")))
	if s.get("rear") is Dictionary:
		var r: Dictionary = s.rear
		var sz := _v3(r.get("size"), Vector3(0.004, 0.015, 0.006))
		var at := _v3(r.get("pos"))
		var off := float(r.get("gap", 0.007)) * 0.5 + sz.x * 0.5
		for sgn in [-1.0, 1.0]:
			var b := BoxMesh.new()
			b.size = sz
			_mesh(root, b, mat, at + Vector3(sgn * off, 0, 0))
	return root
