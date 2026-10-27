extends RefCounted
## The cantina's stair tower and the lookout room on top (town art pass 2).
##
## Two boxes in port_town.json describe it: a `spiral` box (the round tower: wall
## with a door, a centre column, a helical ramp you walk up) and a `lookout` box
## (the round room on top: floor with the stairwell open, a parapet, window posts,
## a roof). This file turns them into triangles. The gameplay layer collides with
## exactly these triangles and the decor draws the same ones, so what you see is
## what you stand on. Everything is world space.
##
## The ramp is a slope, not steps: the player's capsule only rolls over about
## 0.12 m, so a helix at `rise` metres per turn is how a body climbs.

const DOOR_H := 2.4           ## door gap height in the tower wall
const DOOR_HALF := 0.32       ## door gap half angle (radians)
const RAMP_T := 0.25          ## ramp slab thickness
const FLOOR_T := 0.3          ## lookout floor thickness
const ROOM_H := 2.5           ## lookout: floor to roof underside
const PARAPET_H := 1.1
const OPEN_SPAN := 0.75       ## of a turn: the stairwell left open under the room floor
const SEG_PER_TURN := 36


## Everything the builders need, from the spiral box.
static func info(tower: Dictionary) -> Dictionary:
	var mn := Vector3(float(tower.min[0]), float(tower.min[1]), float(tower.min[2]))
	var mx := Vector3(float(tower.max[0]), float(tower.max[1]), float(tower.max[2]))
	var r := minf(mx.x - mn.x, mx.z - mn.z) * 0.5
	var rise := float(tower.get("rise", 3.0))
	var h := mx.y - mn.y
	var door_th: float = { "+x": 0.0, "+z": PI * 0.5, "-x": PI, "-z": -PI * 0.5 }.get(str(tower.get("door", "-z")), -PI * 0.5)
	var th0 := door_th + 0.5
	return {
		"c": Vector3((mn.x + mx.x) * 0.5, mn.y, (mn.z + mx.z) * 0.5),
		"r": r, "ri": r - float(tower.get("wall", 0.35)), "rc": float(tower.get("core", 0.55)),
		"h": h, "rise": rise, "door_th": door_th, "th0": th0, "th_end": th0 + TAU * h / rise,
	}


## A point on the ramp's walking surface: radius r, angle th (unwrapped, from th0).
static func ramp_point(t: Dictionary, r: float, th: float) -> Vector3:
	var y := float(t.rise) * (th - float(t.th0)) / TAU
	return t.c + Vector3(cos(th) * r, y, sin(th) * r)


## Points up the middle of the ramp, every `step` radians: the walk the trace takes.
static func ramp_walk(t: Dictionary, step: float = PI / 6.0) -> Array:
	var out: Array = []
	var r := (float(t.rc) + float(t.ri)) * 0.5
	var th := float(t.th0) + 0.3
	while th < float(t.th_end):
		out.append(ramp_point(t, r, th))
		th += step
	return out


# ---------------------------------------------------------------- the tower

## Part name -> ArrayMesh: "ramp", "core", "wall".
static func tower_parts(tower: Dictionary) -> Dictionary:
	var t := info(tower)
	var c: Vector3 = t.c
	var ri: float = t.ri
	var rc: float = t.rc
	var h: float = t.h
	# Ramp: a helical slab from the door round to the top.
	var ramp := _st()
	var n := int(ceil((float(t.th_end) - float(t.th0)) / TAU * SEG_PER_TURN))
	for i in n:
		var a := lerpf(t.th0, t.th_end, float(i) / n)
		var b := lerpf(t.th0, t.th_end, float(i + 1) / n)
		var ia := ramp_point(t, rc, a)
		var oa := ramp_point(t, ri, a)
		var ib := ramp_point(t, rc, b)
		var ob := ramp_point(t, ri, b)
		var dn := Vector3(0, -RAMP_T, 0)
		var out := Vector3(cos((a + b) * 0.5), 0, sin((a + b) * 0.5))
		LookMeshKit.add_quad(ramp, ia, oa, ob, ib, Vector3.UP)
		LookMeshKit.add_quad(ramp, ia + dn, oa + dn, ob + dn, ib + dn, Vector3.DOWN)
		LookMeshKit.add_quad(ramp, oa, ob, ob + dn, oa + dn, out)
		LookMeshKit.add_quad(ramp, ia, ib, ib + dn, ia + dn, -out)
	for end in [[t.th0, -1.0], [t.th_end, 1.0]]:
		var th: float = end[0]
		var side := Vector3(-sin(th), 0, cos(th)) * float(end[1])
		var i0 := ramp_point(t, rc, th)
		var o0 := ramp_point(t, ri, th)
		LookMeshKit.add_quad(ramp, i0, o0, o0 + Vector3(0, -RAMP_T, 0), i0 + Vector3(0, -RAMP_T, 0), side)
	# Core column.
	var core := _st()
	_band(core, 0.0, rc, c.y, c.y + h, 0.0, TAU, 16, c)
	# Wall, with the door cut out at the bottom. It stops under the lookout floor.
	var wall := _st()
	var top := c.y + h - FLOOR_T
	var seg := 48
	for i in seg:
		var a := TAU * i / seg + float(t.door_th) + PI     # seam opposite the door
		var b := TAU * (i + 1) / seg + float(t.door_th) + PI
		var mid := wrapf((a + b) * 0.5 - float(t.door_th), -PI, PI)
		var in_gap := absf(mid) < DOOR_HALF
		_band(wall, ri, float(t.r), c.y + (DOOR_H if in_gap else 0.0), top, a, b, 1, c, false)
		if in_gap:
			_band(wall, ri, float(t.r), c.y + DOOR_H - 0.01, c.y + DOOR_H, a, b, 1, c, true, false)
		# Jambs where the gap starts and ends.
		var next_mid := wrapf(b + PI / seg - float(t.door_th), -PI, PI)
		if in_gap != (absf(next_mid) < DOOR_HALF):
			var d := Vector3(cos(b), 0, sin(b))
			var side := Vector3(-sin(b), 0, cos(b)) * (1.0 if in_gap else -1.0)
			LookMeshKit.add_quad(wall, c + d * ri, c + d * float(t.r), c + d * float(t.r) + Vector3(0, DOOR_H, 0), c + d * ri + Vector3(0, DOOR_H, 0), side)
	return { "ramp": _done(ramp), "core": _done(core), "wall": _done(wall) }


# ---------------------------------------------------------------- the lookout

## Part name -> ArrayMesh: "floor", "parapet", "posts", "pillar", "roof".
static func lookout_parts(room: Dictionary, tower: Dictionary) -> Dictionary:
	var t := info(tower)
	var c: Vector3 = t.c
	var rr := minf(float(room.max[0]) - float(room.min[0]), float(room.max[2]) - float(room.min[2])) * 0.5
	var fy := float(room.min[1])          # floor top: the ramp arrives here
	var cy := Vector3(c.x, 0, c.z)
	# Floor: a full ring outside the stairwell, and one quarter over it where the ramp lands.
	var fl := _st()
	_band(fl, float(t.ri), rr, fy - FLOOR_T, fy, 0.0, TAU, 40, cy)
	var land0 := float(t.th_end)
	_band(fl, float(t.rc), float(t.ri), fy - FLOOR_T, fy, land0, land0 + TAU * (1.0 - OPEN_SPAN), 10, cy, true, true, true)
	var parapet := _st()
	_band(parapet, rr - 0.3, rr, fy, fy + PARAPET_H, 0.0, TAU, 40, cy)
	# Window posts between the parapet and the roof: the room is open to the town.
	var posts := _st()
	for i in 8:
		var a := TAU * (i + 0.5) / 8.0
		var p := cy + Vector3(cos(a), 0, sin(a)) * (rr - 0.15)
		_box(posts, Vector3(p.x, fy + PARAPET_H, p.z), Vector3(p.x, fy + ROOM_H, p.z), 0.14, a)
	var pillar := _st()
	_band(pillar, 0.0, float(t.rc), fy, fy + ROOM_H, 0.0, TAU, 16, cy)
	var roof := _st()
	_band(roof, 0.0, rr + 0.35, fy + ROOM_H, fy + ROOM_H + 0.3, 0.0, TAU, 40, cy)
	return { "floor": _done(fl), "parapet": _done(parapet), "posts": _done(posts), "pillar": _done(pillar), "roof": _done(roof) }


# ---------------------------------------------------------------- helpers

## Every triangle of the parts, for a ConcavePolygonShape3D.
static func faces(parts: Dictionary) -> PackedVector3Array:
	var out := PackedVector3Array()
	for k in parts:
		out.append_array((parts[k] as ArrayMesh).get_faces())
	return out


## All parts as one mesh (the greybox stand-in).
static func merged(parts: Dictionary) -> ArrayMesh:
	var st := _st()
	for k in parts:
		st.append_from(parts[k], 0, Transform3D.IDENTITY)
	return st.commit()


static func _st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	return st


static func _done(st: SurfaceTool) -> ArrayMesh:
	st.generate_normals()
	return st.commit()


## A ring (or disk, r0 = 0) sector around centre c's vertical axis, y0..y1.
static func _band(st: SurfaceTool, r0: float, r1: float, y0: float, y1: float, a0: float, a1: float,
		seg: int, c: Vector3, caps: bool = true, sides: bool = true, ends: bool = false) -> void:
	var cc := Vector3(c.x, 0, c.z)
	for i in seg:
		var a := lerpf(a0, a1, float(i) / seg)
		var b := lerpf(a0, a1, float(i + 1) / seg)
		var da := Vector3(cos(a), 0, sin(a))
		var db := Vector3(cos(b), 0, sin(b))
		var out := (da + db).normalized()
		var p := func(d: Vector3, r: float, y: float) -> Vector3: return cc + d * r + Vector3(0, y, 0)
		if sides:
			LookMeshKit.add_quad(st, p.call(da, r1, y0), p.call(db, r1, y0), p.call(db, r1, y1), p.call(da, r1, y1), out)
			if r0 > 0.0:
				LookMeshKit.add_quad(st, p.call(da, r0, y0), p.call(db, r0, y0), p.call(db, r0, y1), p.call(da, r0, y1), -out)
		if caps:
			LookMeshKit.add_quad(st, p.call(da, r0, y1), p.call(db, r0, y1), p.call(db, r1, y1), p.call(da, r1, y1), Vector3.UP)
			LookMeshKit.add_quad(st, p.call(da, r0, y0), p.call(db, r0, y0), p.call(db, r1, y0), p.call(da, r1, y0), Vector3.DOWN)
	if ends:
		for e in [[a0, -1.0], [a1, 1.0]]:
			var th: float = e[0]
			var d := Vector3(cos(th), 0, sin(th))
			var side := Vector3(-sin(th), 0, cos(th)) * float(e[1])
			LookMeshKit.add_quad(st, cc + d * r0 + Vector3(0, y0, 0), cc + d * r1 + Vector3(0, y0, 0), cc + d * r1 + Vector3(0, y1, 0), cc + d * r0 + Vector3(0, y1, 0), side)


## An upright square post of half-width w from a to b, turned by yaw.
static func _box(st: SurfaceTool, a: Vector3, b: Vector3, w: float, yaw: float) -> void:
	var u := Vector3(cos(yaw), 0, sin(yaw)) * w
	var v := Vector3(-sin(yaw), 0, cos(yaw)) * w
	var corners := [u + v, -u + v, -u - v, u - v]
	for i in 4:
		var p: Vector3 = corners[i]
		var q: Vector3 = corners[(i + 1) % 4]
		LookMeshKit.add_quad(st, a + p, a + q, b + q, b + p, (p + q).normalized())
	LookMeshKit.add_quad(st, b + corners[0], b + corners[1], b + corners[2], b + corners[3], Vector3.UP)
