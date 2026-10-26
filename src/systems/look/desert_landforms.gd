class_name DesertLandforms
extends Node3D
## Mesas, hoodoos and boulders on the desert around the playable town, so the sand
## outside the gate leads somewhere and the horizon is not empty. Same recipes as
## the beauty corner's `_build_landforms` (the beauty corner is the art reference
## and is not edited, so this is a copy driven by content/look/desert_landforms.json).
##
## Mesas and hoodoos are solid (the player can walk up to them); boulders are one
## MultiMesh with no collision, as in the beauty corner.

const DATA_PATH := "res://content/look/desert_landforms.json"

var data: Dictionary = {}
var solid_count := 0          ## bodies added (read by tests)
var boulder_count := 0
var boulder_spots := PackedVector3Array()   ## where they went (the renderer may not say)


static func load_data(path: String = DATA_PATH) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("DesertLandforms: cannot open %s" % path)
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


## `keep_out` = the town's floor area (xz); nothing is placed on or near it.
func build(terrain: DesertTerrain, mats: LookMaterials, keep_out: Rect2) -> void:
	name = "Landforms"
	data = load_data()
	if data.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(data.get("seed", 4242))
	var margin := float(data.get("keep_out_margin", 25.0))
	var clear := keep_out.grow(margin)
	var solid := bool(data.get("collision", true))
	var noise := FastNoiseLite.new()
	noise.seed = 31
	noise.fractal_octaves = 3

	# Mesas: big, simple, layered by fog. [x, z, radius, height]
	for m in data.get("mesas", []):
		var r: float = m[2]
		var h: float = m[3]
		if _hits(clear, m[0], m[1], r):
			continue
		noise.frequency = 0.9 / r
		var base := _cyl(r * 0.8, r, h, 40)
		base.rings = 14
		var mesh := LookMeshKit.rock(base, noise, 0.18, 28.0 / h, float(m[0]) * 0.01, 0.35)
		var gy := terrain.height_at(m[0], m[1])
		var mi := _add(mesh, mats.rock(gy, 0.11), Vector3(m[0], gy + h * 0.42, m[1]), Vector3(0, rng.randf_range(0, 360), 0))
		if solid:
			_solid(mi)

	# Hoodoos in the middle distance: the layer between the town and the horizon.
	for hd in data.get("hoodoos", []):
		var r: float = hd[2]
		var h: float = hd[3]
		if _hits(clear, hd[0], hd[1], r):
			continue
		noise.frequency = 1.4 / r
		var base := _cyl(r * 0.55, r, h, 16)
		base.rings = 10
		var gy := terrain.height_at(hd[0], hd[1])
		var mat := mats.rock(gy, 0.35)
		var col := _add(LookMeshKit.rock(base, noise, 0.28, 3.0, float(hd[0]), 0.4), mat, Vector3(hd[0], gy + h * 0.45, hd[1]))
		var cap := SphereMesh.new()
		cap.radius = r * 0.9
		cap.height = r * 0.8
		cap.radial_segments = 12
		cap.rings = 6
		_add(LookMeshKit.rock(cap, noise, 0.3, 0.0, float(hd[1])), mat, Vector3(hd[0], gy + h * 0.95, hd[1]),
			Vector3(0, 0, rng.randf_range(-12, 12)))
		if solid:
			_solid(col)

	# Boulders, scattered with a MultiMesh: one draw call for hundreds.
	var b: Dictionary = data.get("boulders", {})
	var want := int(b.get("count", 0))
	if want <= 0:
		return
	var boulder_src := BoxMesh.new()
	boulder_src.size = Vector3(2.0, 1.6, 1.8)
	boulder_src.subdivide_width = 2
	boulder_src.subdivide_height = 2
	boulder_src.subdivide_depth = 2
	noise.frequency = 0.9
	var xforms: Array[Transform3D] = []
	var min_dist := float(b.get("min_dist", 165.0))
	var spread := float(b.get("spread", 1500.0))
	for i in want:
		var ang := rng.randf() * TAU
		var dist := min_dist + pow(rng.randf(), 1.6) * spread
		var x := cos(ang) * dist
		var z := sin(ang) * dist
		var s := rng.randf_range(0.5, 1.0) * (1.0 + pow(rng.randf(), 3.0) * 5.0)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.2), s * rng.randf_range(0.8, 1.3)))
		basis = basis * Basis(Vector3.RIGHT, rng.randf_range(-0.4, 0.4))
		if _hits(clear, x, z, s * 2.0):
			continue
		xforms.append(Transform3D(basis, Vector3(x, terrain.height_at(x, z) - s * 0.25, z)))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = LookMeshKit.rock(boulder_src, noise, 0.4, 0.0, 3.0)
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	boulder_count = xforms.size()
	for x in xforms:
		boulder_spots.append(x.origin)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Boulders"
	mmi.multimesh = mm
	mmi.material_override = mats.rock(0.0, 1.2)
	add_child(mmi)


static func _hits(r: Rect2, x: float, z: float, radius: float) -> bool:
	return r.grow(radius).has_point(Vector2(x, z))


func _cyl(top: float, bottom: float, h: float, seg: int) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


func _add(mesh: Mesh, mat: Material, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	add_child(mi)
	return mi


func _solid(mi: MeshInstance3D) -> void:
	mi.create_trimesh_collision()
	solid_count += 1
