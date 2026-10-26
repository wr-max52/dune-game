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
	"ramp":     Color(0.70, 0.70, 0.70),
	"overhead": Color(0.45, 0.42, 0.38),
	"roof":     Color(0.55, 0.50, 0.42),
}


## Build one static box. `center` and `size` are in meters. `basis` lets ramps tilt.
static func make_box(id: String, center: Vector3, size: Vector3, color: Color,
		basis: Basis = Basis.IDENTITY) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = id
	body.transform = Transform3D(basis, center)

	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	body.add_child(mi)

	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	return body


## Convert a JSON box (min/max arrays) into center + size.
static func center_size(box: Dictionary) -> Array:
	var mn := Vector3(float(box.min[0]), float(box.min[1]), float(box.min[2]))
	var mx := Vector3(float(box.max[0]), float(box.max[1]), float(box.max[2]))
	return [(mn + mx) * 0.5, mx - mn]
