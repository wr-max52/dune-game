extends RefCounted
## Greybox builder (M9). Turns one box description into a StaticBody3D with a
## BoxMesh and a matching BoxShape3D. Pure helper: no state.

## Colors per box kind. Greybox only; the art pass replaces these.
const KIND_COLORS := {
	"floor":    Color(0.82, 0.74, 0.58),
	"wall":     Color(0.45, 0.42, 0.38),
	"solid":    Color(0.78, 0.69, 0.52),
	"cover":    Color(0.85, 0.60, 0.35),
	"counter":  Color(0.60, 0.33, 0.18),
	"ship":     Color(0.48, 0.55, 0.70),
	"pad":      Color(0.40, 0.38, 0.36),
	"ramp":     Color(0.70, 0.70, 0.70),
	"overhead": Color(0.45, 0.42, 0.38),
	"roof":     Color(0.55, 0.50, 0.42),
	"spiral":   Color(0.55, 0.50, 0.42),
	"lookout":  Color(0.55, 0.50, 0.42),
	"bowl":     Color(0.45, 0.42, 0.38),
}


## Build one static box. `center` and `size` are in meters. `basis` lets ramps tilt.
## `round` builds an upright cylinder inside the box instead (round huts, towers):
## its radius is half the smaller footprint side, so it never leaves the box.
static func make_box(id: String, center: Vector3, size: Vector3, color: Color,
		basis: Basis = Basis.IDENTITY, round: bool = false) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = id
	body.transform = Transform3D(basis, center)

	var mesh: PrimitiveMesh
	var shape: Shape3D
	if round:
		var r := minf(size.x, size.z) * 0.5
		var cm := CylinderMesh.new()
		cm.top_radius = r
		cm.bottom_radius = r
		cm.height = size.y
		mesh = cm
		var cs := CylinderShape3D.new()
		cs.radius = r
		cs.height = size.y
		shape = cs
	else:
		var bm := BoxMesh.new()
		bm.size = size
		mesh = bm
		var bs := BoxShape3D.new()
		bs.size = size
		shape = bs
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	body.add_child(mi)

	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	return body


## A static body that collides with exactly `mesh`'s triangles (the stair tower,
## the lookout room). Same node layout as make_box: "Mesh" then the shape.
static func make_trimesh(id: String, mesh: ArrayMesh, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = id
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	mi.material_override = null
	mesh.surface_set_material(0, mat)
	body.add_child(mi)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(mesh.get_faces())
	shape.backface_collision = true
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	return body


## Convert a JSON box (min/max arrays) into center + size.
static func center_size(box: Dictionary) -> Array:
	var mn := Vector3(float(box.min[0]), float(box.min[1]), float(box.min[2]))
	var mx := Vector3(float(box.max[0]), float(box.max[1]), float(box.max[2]))
	return [(mn + mx) * 0.5, mx - mn]
