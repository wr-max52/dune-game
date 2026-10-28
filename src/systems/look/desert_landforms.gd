class_name DesertLandforms
extends Node3D
## Mesas, hoodoos and boulders on the desert around the playable town, so the sand
## outside the gate leads somewhere and the horizon is not empty. Same recipes as
## the beauty corner's `_build_landforms` (the beauty corner is the art reference
## and is not edited, so this is a copy driven by content/look/desert_landforms.json).
##
## Mesas and hoodoos are solid (the player can walk up to them). Boulders are one
## MultiMesh to draw, and (issue #93) each also has its own convex collider, so you
## can stand on them; `boulders` lists them for WorldGround, where the low ones are
## ramps for a speeder and the tall ones stop it.

const DATA_PATH := "res://content/look/desert_landforms.json"

var data: Dictionary = {}
var solid_count := 0          ## bodies added (read by tests)
var boulder_count := 0
var boulder_spots := PackedVector3Array()   ## where they went (the renderer may not say)
## { center: Vector3 (on the ground), up, radius, height } for WorldGround.add_boulders.
var boulders: Array = []


static func load_data(path: String = DATA_PATH) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("DesertLandforms: cannot open %s" % path)
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


## Issue #64: more places to keep clear, [Vector2 centre, radius] each (the
## Remnant's desert outposts: the world's landmarks with a "clear" radius).
var clear_circles: Array = []


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
		if _hits(clear, m[0], m[1], r) or _in_circles(m[0], m[1], r):
			continue
		noise.frequency = 0.9 / r
		var base := _cyl(r * 0.8, r, h, 40)
		base.rings = 14
		var mesh := LookMeshKit.rock(base, noise, 0.18, 28.0 / h, float(m[0]) * 0.01, 0.35)
		var g := _ground(terrain, m[0], m[1])
		var gy := _ground_h(terrain, g, m[0], m[1])
		var mi := _add(mesh, mats.rock(gy, 0.11), g, h * 0.42, Vector3(0, rng.randf_range(0, 360), 0))
		if solid:
			_solid(mi)

	# Hoodoos in the middle distance: the layer between the town and the horizon.
	for hd in data.get("hoodoos", []):
		var r: float = hd[2]
		var h: float = hd[3]
		if _hits(clear, hd[0], hd[1], r) or _in_circles(hd[0], hd[1], r):
			continue
		noise.frequency = 1.4 / r
		var base := _cyl(r * 0.55, r, h, 16)
		base.rings = 10
		var g := _ground(terrain, hd[0], hd[1])
		var gy := _ground_h(terrain, g, hd[0], hd[1])
		var mat := mats.rock(gy, 0.35)
		var col := _add(LookMeshKit.rock(base, noise, 0.28, 3.0, float(hd[0]), 0.4), mat, g, h * 0.45)
		var cap := SphereMesh.new()
		cap.radius = r * 0.9
		cap.height = r * 0.8
		cap.radial_segments = 12
		cap.rings = 6
		_add(LookMeshKit.rock(cap, noise, 0.3, 0.0, float(hd[1])), mat, g, h * 0.95,
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
		if _hits(clear, x, z, s * 2.0) or _in_circles(x, z, s * 2.0):
			continue
		var g := _ground(terrain, x, z)
		xforms.append(Transform3D(g.basis * basis, g.origin + g.basis.y * (-s * 0.25)))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = LookMeshKit.rock(boulder_src, noise, 0.4, 0.0, 3.0)
	if solid:
		_solid_boulders(mm.mesh, xforms)
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
	if terrain is PlanetTerrain:
		_on_ball((terrain as PlanetTerrain).sphere)


## The rock shader's ground height on the ball is metres above the bare ball.
static func _ground_h(terrain: DesertTerrain, g: Transform3D, x: float, z: float) -> float:
	if terrain is PlanetTerrain:
		return (terrain as PlanetTerrain).sphere.altitude(g.origin)
	return terrain.height_at(x, z)


## Every rock material here: strata and dusk follow the ball (issue #77).
func rock_materials() -> Array:
	var out: Array = []
	for n in find_children("*", "GeometryInstance3D", true, false):
		var m = (n as GeometryInstance3D).material_override
		if m is ShaderMaterial and not out.has(m):
			out.append(m)
	return out


func _on_ball(sp: PlanetSphere) -> void:
	for m in rock_materials():
		m.set_shader_parameter("planet_center", sp.center)
		m.set_shader_parameter("planet_radius", sp.radius)
		m.set_shader_parameter("dusk_strength", 0.35)


static func _hits(r: Rect2, x: float, z: float, radius: float) -> bool:
	return r.grow(radius).has_point(Vector2(x, z))


func _in_circles(x: float, z: float, radius: float) -> bool:
	for c in clear_circles:
		if (c[0] as Vector2).distance_to(Vector2(x, z)) < float(c[1]) + radius:
			return true
	return false


func _cyl(top: float, bottom: float, h: float, seg: int) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


## Where a landform at map (x, z) stands: the ground there, y along its up. On the
## home planet's ball (issue #77) that leans with the ground; on a flat desert it is
## just the height at x, z.
static func _ground(terrain: DesertTerrain, x: float, z: float) -> Transform3D:
	if terrain is PlanetTerrain:
		var sp: PlanetSphere = (terrain as PlanetTerrain).sphere
		var at := sp.surface_at(x, z)
		return Transform3D(PlanetSphere.tilt_to(sp.up_at(at)), at)
	return Transform3D(Basis.IDENTITY, Vector3(x, terrain.height_at(x, z), z))


## `up` metres above the ground frame g, turned by rot_deg within it.
func _add(mesh: Mesh, mat: Material, g: Transform3D, up: float, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = Transform3D(g.basis * Basis.from_euler(rot_deg * PI / 180.0), g.origin + g.basis.y * up)
	add_child(mi)
	return mi


## One static body per boulder: a convex hull of the very rock mesh drawn there (its
## points put through that boulder's transform), so what you stand on is what you see.
func _solid_boulders(mesh: Mesh, xforms: Array[Transform3D]) -> void:
	var pts := PackedVector3Array()
	var seen := {}
	for v in (mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
		var key := v.snapped(Vector3.ONE * 0.01)
		if not seen.has(key):
			seen[key] = true
			pts.append(v)
	var root := StaticBody3D.new()
	root.name = "BoulderColliders"
	add_child(root)
	for xf in xforms:
		var hull := PackedVector3Array()
		hull.resize(pts.size())
		var top := 0.0
		var rad := 0.0
		for i in pts.size():
			var w: Vector3 = xf.basis * pts[i]
			hull[i] = w
			top = maxf(top, w.dot(xf.basis.y.normalized()))
			rad = maxf(rad, (w - xf.basis.y.normalized() * w.dot(xf.basis.y.normalized())).length())
		var shape := ConvexPolygonShape3D.new()
		shape.points = hull
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = xf.origin
		root.add_child(cs)
		# Up: the ground's (the transform also leans and turns the rock a little).
		var up := Vector3.UP
		if PlanetSphere.current != null:
			up = PlanetSphere.current.up_at(xf.origin)
		# Measured from the rock's origin, a little under the sand; the ground under
		# it counts wherever it is higher.
		boulders.append({ "center": xf.origin, "up": up, "radius": rad * 0.85, "height": top })


func _solid(mi: MeshInstance3D) -> void:
	mi.create_trimesh_collision()
	solid_count += 1
