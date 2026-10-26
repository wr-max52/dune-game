class_name CoverPicker
extends RefCounted
## Where to take cover. Pure and headless-testable: cover spots are generated from
## the town's own boxes (crates, barricades, walls, buildings), and a spot counts
## as cover from a threat only when its box really sits between the spot and the
## threat. Guards claim spots so two never crouch behind the same one.
##
## Replaces squad_coordinator.gd for live guards: that one hands out "nearest
## node" by index and never asks whether the node hides you from anyone.

const MIN_HEIGHT := 1.0      ## a box lower than this hides nothing (a crouched body is ~1.05 m)


## Spots around every box tall enough to hide behind, within `radius` of
## `center`: one every `step` metres along each side, `standoff` metres out.
## Each spot: { pos: Vector3, box: String, rect: [minx, minz, maxx, maxz], height }.
## Spots that would put a body inside another box are dropped.
static func candidates(boxes: Array, center: Vector3, radius: float, standoff: float = 0.95,
		step: float = 1.6, kinds: Array = ["cover", "solid", "wall"]) -> Array:
	var out: Array = []
	var blockers: Array = []
	for b in boxes:
		if str(b.kind) in ["wall", "solid", "cover", "counter", "ship"]:
			blockers.append(b)
	for b in boxes:
		if not (str(b.kind) in kinds):
			continue
		var mnx := float(b.min[0])
		var mnz := float(b.min[2])
		var mxx := float(b.max[0])
		var mxz := float(b.max[2])
		var floor_y := float(b.min[1])
		var height := float(b.max[1]) - floor_y
		if height < MIN_HEIGHT or floor_y > 0.2 or floor_y < -0.2:
			continue                       # too low, or not standing on the street
		if _rect_dist(center.x, center.z, [mnx, mnz, mxx, mxz]) > radius:
			continue
		var sides := [
			[Vector2(mnx, mnz - standoff), Vector2(mxx, mnz - standoff)],
			[Vector2(mnx, mxz + standoff), Vector2(mxx, mxz + standoff)],
			[Vector2(mnx - standoff, mnz), Vector2(mnx - standoff, mxz)],
			[Vector2(mxx + standoff, mnz), Vector2(mxx + standoff, mxz)],
		]
		for sd in sides:
			var a: Vector2 = sd[0]
			var c: Vector2 = sd[1]
			var n := maxi(1, int(a.distance_to(c) / step))
			for i in n + 1:
				var p := a.lerp(c, (float(i) + 0.5) / float(n + 1)) if n > 0 else (a + c) * 0.5
				if Vector2(p.x, p.y).distance_to(Vector2(center.x, center.z)) > radius:
					continue
				if _inside_any(p, blockers, 0.45):
					continue
				out.append({ "pos": Vector3(p.x, 0.0, p.y), "box": str(b.id), "rect": [mnx, mnz, mxx, mxz], "height": height })
	return out


## True if the spot's own box blocks the line from the spot to the threat.
static func covers(spot: Dictionary, threat: Vector3) -> bool:
	var p: Vector3 = spot.pos
	return segment_hits_rect(Vector2(p.x, p.z), Vector2(threat.x, threat.z), spot.rect)


## The best free spot for a guard at `from` against `threat`: it must cover,
## sit between min_d and max_d from the threat, and not be claimed (claimed is a
## list of Vector3 already taken). Nearest to the guard wins, with a nudge toward
## mid range so guards do not all hug the threat. Returns the index, or -1.
static func pick(from: Vector3, threat: Vector3, spots: Array, claimed: Array,
		min_d: float = 6.0, max_d: float = 40.0) -> int:
	var best := -1
	var best_score := INF
	for i in spots.size():
		var s: Dictionary = spots[i]
		var p: Vector3 = s.pos
		var td := Vector2(p.x - threat.x, p.z - threat.z).length()
		if td < min_d or td > max_d:
			continue
		if not covers(s, threat):
			continue
		var taken := false
		for c in claimed:
			if (c as Vector3).distance_to(p) < 1.2:
				taken = true
				break
		if taken:
			continue
		var score := Vector2(p.x - from.x, p.z - from.z).length() + 0.25 * absf(td - 15.0)
		if score < best_score:
			best_score = score
			best = i
	return best


## 2D segment vs axis-aligned rect [minx, minz, maxx, maxz] (Liang-Barsky).
static func segment_hits_rect(a: Vector2, b: Vector2, r: Array) -> bool:
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	var ps := [-d.x, d.x, -d.y, d.y]
	var qs := [a.x - float(r[0]), float(r[2]) - a.x, a.y - float(r[1]), float(r[3]) - a.y]
	for i in 4:
		var pp: float = ps[i]
		var q: float = qs[i]
		if absf(pp) < 1e-9:
			if q < 0.0:
				return false
		else:
			var t := q / pp
			if pp < 0.0:
				t0 = maxf(t0, t)
			else:
				t1 = minf(t1, t)
			if t0 > t1:
				return false
	return true


static func _rect_dist(x: float, z: float, r: Array) -> float:
	var dx := maxf(maxf(float(r[0]) - x, 0.0), x - float(r[2]))
	var dz := maxf(maxf(float(r[1]) - z, 0.0), z - float(r[3]))
	return sqrt(dx * dx + dz * dz)


static func _inside_any(p: Vector2, boxes: Array, margin: float) -> bool:
	for b in boxes:
		if p.x > float(b.min[0]) - margin and p.x < float(b.max[0]) + margin \
				and p.y > float(b.min[2]) - margin and p.y < float(b.max[2]) + margin \
				and float(b.max[1]) > 0.3 and float(b.min[1]) < 1.8:
			return true
	return false
