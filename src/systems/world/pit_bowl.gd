extends RefCounted
## The round landing pit (town art pass 2). One `bowl` box in port_town.json: its
## min/max is the square the street leaves open; this file makes it round. A
## vertical wall at radius r (half the box's width) from the pit floor up to the
## street, and the street filled in between that circle and the square, open
## where each ramp named in `gaps` runs out. The gameplay layer collides with
## these triangles and the decor draws the same ones.

const SEG := 96


static func info(b: Dictionary, town = null) -> Dictionary:
	var mn := Vector3(float(b.min[0]), float(b.min[1]), float(b.min[2]))
	var mx := Vector3(float(b.max[0]), float(b.max[1]), float(b.max[2]))
	var c := Vector3((mn.x + mx.x) * 0.5, 0, (mn.z + mx.z) * 0.5)
	var gaps: Array = []          ## [centre angle, half angle]
	if town != null:
		for id in b.get("gaps", []):
			var g: Dictionary = town.get_box(str(id))
			if g.is_empty():
				continue
			var gc := Vector3((float(g.min[0]) + float(g.max[0])) * 0.5, 0, (float(g.min[2]) + float(g.max[2])) * 0.5) - c
			var along_x := str(g.get("rise_toward", "+x")).ends_with("x")
			var half_w := (float(g.max[2]) - float(g.min[2])) * 0.5 if along_x else (float(g.max[0]) - float(g.min[0])) * 0.5
			var r := (mx.x - mn.x) * 0.5
			gaps.append([atan2(gc.z, gc.x), asin(clampf(half_w / r, 0.0, 1.0))])
	return { "c": c, "r": (mx.x - mn.x) * 0.5, "half": Vector2((mx.x - mn.x) * 0.5, (mx.z - mn.z) * 0.5),
		"y0": mn.y, "y1": mx.y, "gaps": gaps }


static func in_gap(t: Dictionary, th: float) -> bool:
	for g in t.gaps:
		if absf(wrapf(th - float(g[0]), -PI, PI)) < float(g[1]):
			return true
	return false


## "wall" (inside face of the round wall) and "fill" (the street round the circle).
static func parts(b: Dictionary, town = null) -> Dictionary:
	var t := info(b, town)
	var c: Vector3 = t.c
	var r: float = t.r
	var half: Vector2 = t.half
	var y0: float = t.y0
	var y1: float = t.y1
	var wall := _st()
	var fill := _st()
	for i in SEG:
		var a := TAU * i / SEG
		var b2 := TAU * (i + 1) / SEG
		var da := Vector3(cos(a), 0, sin(a))
		var db := Vector3(cos(b2), 0, sin(b2))
		var mid := (a + b2) * 0.5
		if not in_gap(t, mid):
			LookMeshKit.add_quad(wall, c + da * r + Vector3(0, y0, 0), c + db * r + Vector3(0, y0, 0),
				c + db * r + Vector3(0, y1, 0), c + da * r + Vector3(0, y1, 0), -(da + db).normalized())
		# Street between the circle and the square: out along each ray to the square's edge.
		var sa := da * minf(half.x / maxf(absf(da.x), 0.0001), half.y / maxf(absf(da.z), 0.0001))
		var sb := db * minf(half.x / maxf(absf(db.x), 0.0001), half.y / maxf(absf(db.z), 0.0001))
		LookMeshKit.add_quad(fill, c + da * r + Vector3(0, y1, 0), c + db * r + Vector3(0, y1, 0),
			c + sb + Vector3(0, y1, 0), c + sa + Vector3(0, y1, 0), Vector3.UP)
	return { "wall": _done(wall), "fill": _done(fill) }


static func _st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	return st


static func _done(st: SurfaceTool) -> ArrayMesh:
	st.generate_normals()
	return st.commit()
