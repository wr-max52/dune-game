class_name NativeSteer
extends RefCounted
## Issue #96: the desert packs walk round the rocks they know about instead of
## through them. There is no navmesh out in the desert, so this is plain steering:
## the known obstacles (WorldGround's boulders tall enough to stop a walker, and
## its columns: mesas, hoodoos, outpost landmarks) go in a coarse grid, and a
## walker heading for a goal asks for the point to head at now: the goal when the
## way is clear, else a point just past the side of the first rock in the way.
## Asked again as it walks, it curves round and on.
##
## Pure (no nodes): the ground's lists in, points out. Unit tested headless
## (tests/test_native_steer.gut.gd).

var cell := 40.0                ## grid cell, metres
var clearance := 1.4            ## kept between a walker's middle and a rock's side
var min_height := 0.8           ## lower boulders are stepped over
var lookahead := 26.0           ## how far ahead a rock counts as "in the way"
var _grid: Dictionary = {}      ## Vector3i -> [{ c, r }]
var _big: Array = []            ## ones wider than a cell (mesas), always checked
var count := 0


## Steering for everything `ground` (a WorldGround) knows is in the way.
static func from_ground(ground) -> NativeSteer:
	var s := NativeSteer.new()
	if ground == null:
		return s
	for b in ground.boulders:
		if float(b.get("height", 0.0)) >= s.min_height:
			s.add(b.center, float(b.radius))
	for c in ground.columns:
		s.add(c.center, float(c.get("radius", 0.0)))
	return s


func add(center: Vector3, radius: float) -> void:
	if radius <= 0.0:
		return
	var o := { "c": center, "r": radius }
	count += 1
	if radius > cell * 0.5:
		_big.append(o)
		return
	var k := _key(center)
	if not _grid.has(k):
		_grid[k] = []
	(_grid[k] as Array).append(o)


func _key(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x / cell), floori(p.y / cell), floori(p.z / cell))


## Every obstacle that may reach within `reach` of `p`.
func near(p: Vector3, reach: float) -> Array:
	var out: Array = _big.duplicate()
	var n := ceili((reach + cell * 0.5) / cell)
	var k := _key(p)
	for x in range(-n, n + 1):
		for y in range(-n, n + 1):
			for z in range(-n, n + 1):
				var list = _grid.get(k + Vector3i(x, y, z))
				if list != null:
					out.append_array(list)
	return out


## Whether `p` stands inside an obstacle (with the clearance).
func blocked(p: Vector3, up: Vector3) -> bool:
	for o in near(p, clearance):
		if _flat(o.c - p, up).length() < float(o.r) + clearance:
			return true
	return false


## `p`, or the nearest spot outside every obstacle (for camps and route points).
func clear_spot(p: Vector3, up: Vector3) -> Vector3:
	for i in 8:
		var pushed := false
		for o in near(p, clearance + 2.0):
			var rel := _flat(p - o.c, up)
			var need := float(o.r) + clearance + 0.5
			if rel.length() < need:
				var away := rel.normalized() if rel.length() > 0.01 else _side(up)
				p = o.c + away * need + up * up.dot(p - o.c)
				pushed = true
		if not pushed:
			break
	return p


## Where to head now on the way from `from` to `goal` on ground whose up is `up`.
func steer(from: Vector3, goal: Vector3, up: Vector3) -> Vector3:
	return _steer(from, goal, up, 2)


func _steer(from: Vector3, goal: Vector3, up: Vector3, depth: int, skip: Dictionary = {}) -> Vector3:
	var to := _flat(goal - from, up)
	var dist := to.length()
	if dist < 0.5 or count == 0:
		return goal
	var dir := to / dist
	var look := minf(lookahead, dist)
	var first := {}
	var first_t := INF
	for o in near(from + dir * look * 0.5, look * 0.5 + clearance):
		if is_same(o, skip):
			continue
		var rel := _flat(o.c - from, up)
		var r := float(o.r) + clearance
		if _flat(o.c - goal, up).length() < r:
			continue                      # the goal is at the rock: go anyway
		var t := rel.dot(dir)
		var lat := rel - dir * t
		if lat.length() >= r or t <= 0.0:
			continue                      # the way misses it, or it is behind
		var edge := t - sqrt(maxf(0.0, r * r - lat.length_squared()))
		if edge > look or edge >= first_t:
			continue
		first_t = edge
		first = { "o": o, "lat": lat }
	if first.is_empty():
		return goal
	var o: Dictionary = first.o
	var lat: Vector3 = first.lat
	var c: Vector3 = o.c
	var r := float(o.r) + clearance
	var rel := _flat(c - from, up)
	var d := rel.length()
	var n := rel / maxf(d, 0.001)                 # toward the rock
	# Along its edge, the way that gets on toward the goal.
	var along := up.cross(n).normalized()
	if along.dot(dir) < 0.0:
		along = -along
	# Go round on the side the way already leans to (straight at it: the right).
	var away := (-lat if lat.length() > 0.05 else _side(up)).slide(n)
	away = away.normalized() if away.length() > 0.01 else along
	var head: Vector3
	if d <= r + 0.05:
		# At its edge already: along it, and out a little if in too close.
		head = from + along * 2.0 - n * maxf(0.0, r - d + 0.1)
	else:
		# Along the line that just touches it (the tangent), a little past.
		var a := asin(clampf(r / d, 0.0, 1.0))
		var td := n * cos(a) + away * sin(a)
		head = from + td * (sqrt(maxf(0.0, d * d - r * r)) + 0.5)
	head += up * up.dot(from - head)
	if depth > 1:
		var next := _steer(from, head, up, depth - 1, o)     # another rock on the way round?
		if next != head:
			return next
	return head


static func _flat(v: Vector3, up: Vector3) -> Vector3:
	return v - up * v.dot(up)


static func _side(up: Vector3) -> Vector3:
	return up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
