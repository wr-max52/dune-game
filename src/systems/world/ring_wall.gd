extends RefCounted
## A round wall (issue #237). One `ring` box in a town layout: its min/max is the
## square round the circle (outer radius = half its width, centred in it), from
## min.y to max.y, `thickness` metres thick, cut open at each of its `gaps`
## ({ "deg": centre angle, "half": half the opening in metres }; 0 deg is +X, the
## front gate, and +deg turns toward +Z). The wall is a ring of straight pieces,
## each a box no longer than `piece` metres, so it reads as round. Hollow: the
## whole town sits inside its box. The gameplay layer collides with the pieces,
## the decor draws them and the validator (V9) keeps markers and routes off them.
## Any layout can use it: the round port's town wall, a round building's body.

const PIECE := 6.0             ## default longest piece, metres along the wall


## Centre, radii, height and gaps (as [centre angle, half angle] in radians).
static func info(b: Dictionary) -> Dictionary:
	var mn := Vector3(float(b.min[0]), float(b.min[1]), float(b.min[2]))
	var mx := Vector3(float(b.max[0]), float(b.max[1]), float(b.max[2]))
	var r := (mx.x - mn.x) * 0.5
	var t := clampf(float(b.get("thickness", 2.0)), 0.1, r)
	var rm := r - t * 0.5
	var gaps: Array = []
	for g in b.get("gaps", []):
		gaps.append([deg_to_rad(float(g.get("deg", 0.0))), asin(clampf(float(g.get("half", 1.0)) / rm, 0.0, 1.0))])
	return { "c": Vector3((mn.x + mx.x) * 0.5, 0, (mn.z + mx.z) * 0.5), "r": r, "ri": r - t, "rm": rm, "t": t,
		"y0": mn.y, "y1": mx.y, "gaps": gaps, "piece": float(b.get("piece", PIECE)) }


static func in_gap(t: Dictionary, th: float) -> bool:
	for g in t.gaps:
		if absf(wrapf(th - float(g[0]), -PI, PI)) < float(g[1]):
			return true
	return false


## The wall's pieces: [{ "center": Vector3, "size": Vector3, "basis": Basis }].
## Each runs along the chord between its two end angles at the middle radius,
## a little longer so neighbours meet on the outside face too.
static func pieces(b: Dictionary) -> Array:
	var t := info(b)
	var out: Array = []
	for span in _spans(t):
		var a0: float = span[0]
		var a1: float = span[1]
		var n := maxi(1, ceili((a1 - a0) * float(t.rm) / float(t.piece)))
		for i in n:
			var p0 := a0 + (a1 - a0) * i / n
			var p1 := a0 + (a1 - a0) * (i + 1) / n
			var mid := (p0 + p1) * 0.5
			var chord := 2.0 * float(t.rm) * sin((p1 - p0) * 0.5)
			var dir := Vector3(cos(mid), 0, sin(mid))
			var along := Vector3(-dir.z, 0, dir.x)
			var basis := Basis(along, Vector3.UP, -dir)       # local x along the wall, local z across it
			var over := float(t.t) * tan((p1 - p0) * 0.5)      # meet on the outer face
			out.append({
				"center": t.c + dir * float(t.rm) * cos((p1 - p0) * 0.5) + Vector3(0, (float(t.y0) + float(t.y1)) * 0.5, 0),
				"size": Vector3(chord + over, float(t.y1) - float(t.y0), float(t.t)),
				"basis": basis,
			})
	return out


## Solid arcs [a0, a1] (radians, a0 < a1) between the gaps, round the whole circle.
static func _spans(t: Dictionary) -> Array:
	var cuts: Array = []
	for g in t.gaps:
		cuts.append([float(g[0]) - float(g[1]), float(g[0]) + float(g[1])])
	if cuts.is_empty():
		return [[0.0, TAU]]
	cuts.sort_custom(func(a, b): return wrapf(a[0], 0.0, TAU) < wrapf(b[0], 0.0, TAU))
	var out: Array = []
	for i in cuts.size():
		var start: float = cuts[i][1]
		var nxt: Array = cuts[(i + 1) % cuts.size()]
		var stop: float = nxt[0]
		while stop <= start:
			stop += TAU
		out.append([start, stop])
	return out


## 2D distance from (x, z) to the nearest piece's footprint (INF when the point is
## nowhere near the wall's band, so callers can skip the per-piece test).
static func distance(b: Dictionary, x: float, z: float, ps: Array = [], t: Dictionary = {}) -> float:
	if t.is_empty():
		t = info(b)
	if ps.is_empty():
		ps = pieces(b)
	var d := Vector2(x - t.c.x, z - t.c.z).length()
	if d < float(t.ri) - 3.0 or d > float(t.r) + 3.0:
		return INF
	var best := INF
	for p in ps:
		var bs: Basis = p.basis
		var pc: Vector3 = p.center
		var sz: Vector3 = p.size
		var rel := Vector3(x - pc.x, 0, z - pc.z)
		var lx := absf(rel.dot(bs.x)) - sz.x * 0.5
		var lz := absf(rel.dot(bs.z)) - sz.z * 0.5
		best = minf(best, Vector2(maxf(lx, 0.0), maxf(lz, 0.0)).length())
	return best


## Every piece as triangles, in world space (the nav bake and the mesh). Each
## triangle is wound clockwise seen from outside its piece (Godot's front face).
static func faces(b: Dictionary) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in pieces(b):
		out.append_array(_piece_faces(p))
	return out


static func _piece_faces(p: Dictionary) -> PackedVector3Array:
	var out := PackedVector3Array()
	var xf := Transform3D(p.basis, p.center)
	var h: Vector3 = p.size * 0.5
	var c := []
	for i in 8:
		c.append(xf * Vector3(h.x * (1 if i & 1 else -1), h.y * (1 if i & 2 else -1), h.z * (1 if i & 4 else -1)))
	for q in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
		var quad: Vector3 = (c[q[0]] + c[q[1]] + c[q[2]] + c[q[3]]) * 0.25
		var outward: Vector3 = quad - (p.center as Vector3)
		for tri in [[q[0], q[1], q[2]], [q[0], q[2], q[3]]]:
			var a: Vector3 = c[tri[0]]
			var b2: Vector3 = c[tri[1]]
			var d: Vector3 = c[tri[2]]
			if (b2 - a).cross(d - a).dot(outward) > 0.0:
				out.append_array(PackedVector3Array([a, d, b2]))
			else:
				out.append_array(PackedVector3Array([a, b2, d]))
	return out


## The gameplay body: one mesh of every piece, and a box shape per piece.
static func make_body(b: Dictionary, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = str(b.id)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var f := faces(b)
	for i in range(0, f.size(), 3):
		var n := (f[i + 2] - f[i]).cross(f[i + 1] - f[i]).normalized()     # outward (clockwise front)
		for k in 3:
			st.set_normal(n)
			st.add_vertex(f[i + k])
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	body.add_child(mi)
	for p in pieces(b):
		var shape := BoxShape3D.new()
		shape.size = p.size
		var col := CollisionShape3D.new()
		col.shape = shape
		col.transform = Transform3D(p.basis, p.center)
		body.add_child(col)
	return body
