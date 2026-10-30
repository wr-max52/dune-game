extends GutTest
## The spatial index in WorldGround.height_above: it must give exactly (==) what
## testing every box, column and boulder gives, wherever the query is, and it must
## notice geometry registered after it was built.

var _old_current: PlanetSphere
var _sp: PlanetSphere
var _g: WorldGround
var _rng := RandomNumberGenerator.new()


func before_each() -> void:
	_old_current = PlanetSphere.current
	_sp = PlanetSphere.new(5000.0)
	_sp.configure_site(Rect2(-200, -200, 400, 400), Rect2(-210, -210, 420, 420), [], 0.0)
	PlanetSphere.current = _sp
	_g = WorldGround.new()
	_g.setup({ "terrain": { "sphere_radius": 5000.0 } }, null, null)
	_rng.seed = 12345
	_populate()


func after_each() -> void:
	PlanetSphere.current = _old_current


## The old algorithm, verbatim (the box frame inverted for every box).
func _brute(g: WorldGround, p: Vector3) -> float:
	var sp := g.sphere()
	var h := sp.height_above_ground(p)
	var wreck_up := g.up_at(p)
	for b in g.boxes:
		if b.has("wreck_finish"):
			h = minf(h, WorldGround.box_height_below(b, p, wreck_up))
			continue
		var lp: Vector3 = WorldGround.box_xf(b).affine_inverse() * p
		var mn: Vector3 = b.min
		var mx: Vector3 = b.max
		if lp.x < mn.x or lp.x > mx.x or lp.z < mn.z or lp.z > mx.z:
			continue
		var top := WorldGround.box_top(b, lp.x, lp.z)
		if top <= lp.y + 0.5:
			h = minf(h, lp.y - top)
	for c in g.columns:
		var up: Vector3 = c.get("up", Vector3.UP)
		var rel: Vector3 = p - (c.center as Vector3)
		var along := rel.dot(up)
		if (rel - up * along).length() > float(c.radius):
			continue
		var top: float = c.get("h", float(c.top) - (c.center as Vector3).y)
		if top <= along + 0.5:
			h = minf(h, along - top)
	for bd in g.boulders:
		var bu: Vector3 = bd.up
		var rel: Vector3 = p - (bd.center as Vector3)
		if rel.length_squared() > pow(float(bd.radius) * WorldGround.RAMP_SPREAD + float(bd.height) + 50.0, 2.0):
			continue
		var along := rel.dot(bu)
		var bt := WorldGround.boulder_top(bd, (rel - bu * along).length())
		if bt > -INF and bt <= along + 0.5:
			h = minf(h, along - bt)
	return h


func _map_pt(range_m: float) -> Vector2:
	return Vector2(_rng.randf_range(-range_m, range_m), _rng.randf_range(-range_m, range_m))


func _random_boulders(n: int, range_m: float) -> Array:
	var out: Array = []
	for i in n:
		var m := _map_pt(range_m)
		var base := _sp.surface_at(m.x, m.y)
		out.append({ "center": base, "up": _sp.up_at(base), "radius": _rng.randf_range(1.0, 7.0),
			"height": _rng.randf_range(0.8, 9.0) })
	return out


func _populate() -> void:
	# Plain world-space boxes in the town: floors, roofs, ramps (all four sides).
	var rises := ["", "+x", "-x", "+z", "-z", ""]
	for i in 80:
		var c := Vector3(_rng.randf_range(-150, 150), 0.0, _rng.randf_range(-150, 150))
		var s := Vector3(_rng.randf_range(2, 30), _rng.randf_range(1, 18), _rng.randf_range(2, 30))
		_g.add_box("t%d" % i, "solid", Vector3(c.x - s.x * 0.5, -0.2, c.z - s.z * 0.5),
			Vector3(c.x + s.x * 0.5, s.y, c.z + s.z * 0.5), rises[i % rises.size()])
	# A big floor (so there is something in the always-tested list).
	_g.add_box("floor", "floor", Vector3(-180, -0.2, -180), Vector3(180, 0.0, 180))
	# Leaning boxes out on the ball: some tilted further, some with a stretched Y axis.
	for i in 260:
		var m := _map_pt(2400.0)
		var base := _sp.surface_at(m.x, m.y)
		var up := _sp.up_at(base)
		var basis := PlanetSphere.tilt_to(up) * Basis(Vector3.UP, _rng.randf_range(0, TAU))
		if i % 5 == 0:
			basis = basis * Basis(Vector3.RIGHT, deg_to_rad(_rng.randf_range(-35, 35)))
		if i % 7 == 0:
			basis = basis.scaled(Vector3(1.0, _rng.randf_range(0.6, 1.9), 1.0))
		var s := Vector3(_rng.randf_range(1.5, 20), _rng.randf_range(1.0, 14), _rng.randf_range(1.5, 20))
		_g.add_box("o%d" % i, "solid", Vector3(-s.x * 0.5, 0.0, -s.z * 0.5), Vector3(s.x * 0.5, s.y, s.z * 0.5),
			rises[i % rises.size()], true, Transform3D(basis, base))
	# One wreck plate, leaning steeply, flagged after it was added (as StarcruiserWreck does).
	var wb := _sp.surface_at(900.0, -200.0)
	var wbasis := PlanetSphere.tilt_to(_sp.up_at(wb)) * Basis(Vector3.RIGHT, deg_to_rad(-34.0))
	_g.add_box("wreck/plate", "solid", Vector3(-30, -2, -60), Vector3(30, 2, 60), "", false,
		Transform3D(wbasis, wb + _sp.up_at(wb) * 30.0))
	_g.boxes[-1]["wreck_finish"] = "hull"
	_g.boxes[-1]["sand_y"] = 0.0
	# Columns: mesas along the up, and a plain column with no up (flat-world style).
	for i in 20:
		var m := _map_pt(2800.0)
		var base := _sp.surface_at(m.x, m.y)
		var h := _rng.randf_range(10.0, 90.0)
		_g.columns.append({ "id": "mesa%d" % i, "kind": "mesa", "center": base, "radius": _rng.randf_range(8.0, 70.0),
			"up": _sp.up_at(base), "h": h, "top": base.y + h })
	var cb := _sp.surface_at(-400.0, 300.0)
	_g.columns.append({ "id": "plain", "kind": "mesa", "center": cb, "radius": 12.0, "top": cb.y + 25.0 })
	_g.add_boulders(_random_boulders(150, 2600.0))
	# Town-sized rocks too (the cantina street is dense with props).
	_g.add_boulders(_random_boulders(40, 160.0))


## Points: on the ground, just above and inside things, under the sand, high up.
func _points(n: int) -> Array:
	var items: Array = []
	for b in _g.boxes:
		items.append([WorldGround.box_xf(b) * (((b.min as Vector3) + (b.max as Vector3)) * 0.5),
			((b.max as Vector3) - (b.min as Vector3)).length()])
	for c in _g.columns:
		items.append([c.center, float(c.radius) + 20.0])
	for bd in _g.boulders:
		items.append([bd.center, float(bd.radius) * 2.5 + 5.0])
	var alts := [-6.0, -1.0, -0.4, 0.0, 0.3, 0.8, 2.0, 4.0, 12.0, 40.0, 120.0, 200.0, 800.0, 4000.0]
	var out: Array = []
	for i in n:
		var it: Array = items[_rng.randi() % items.size()]
		var near: Vector3 = it[0] + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) \
			* float(it[1]) * 0.7
		var along := _sp.up_at(near) * float(alts[_rng.randi() % alts.size()])
		if i % 3 == 0:
			out.append(near)                  # inside, or right at, the item
		else:
			var ground := _sp.surface_at(_sp.world_to_map(near).x, _sp.world_to_map(near).y)
			out.append(ground + along)        # standing/hovering over that spot
	for i in n / 8:
		var m := _map_pt(3000.0)
		out.append(_sp.surface_at(m.x, m.y) + _sp.up_at(_sp.surface_at(m.x, m.y)) * float(alts[_rng.randi() % alts.size()]))
	return out


func test_index_equals_the_linear_scan_everywhere() -> void:
	var pts := _points(4000)
	var mismatches := 0
	var changed := 0
	for p in pts:
		var want := _brute(_g, p)
		var got := _g.height_above(p)
		if got != want:
			mismatches += 1
			if mismatches <= 5:
				push_error("mismatch at %s: indexed %s, linear %s" % [p, got, want])
		if want != _sp.height_above_ground(p):
			changed += 1
	assert_eq(mismatches, 0, "indexed height_above is exactly the linear scan's")
	assert_gt(changed, 600, "the points really are touched by boxes, columns and boulders")


func test_surface_below_matches_too() -> void:
	for p in _points(300):
		var want: Vector3 = p - _g.up_at(p) * _brute(_g, p)
		assert_eq(_g.surface_below(p), want)


func test_wide_and_high_queries_match() -> void:
	# Past the grid's comfortable reach: the occupied-cell sphere test, and the plain scan.
	var bad := 0
	for alt in [150.0, 400.0, 1000.0, 1300.0, 3000.0, 4000.0, 9000.0]:
		for i in 60:
			var m := _map_pt(2500.0)
			var base := _sp.surface_at(m.x, m.y)
			var p: Vector3 = base + _sp.up_at(base) * alt
			if _g.height_above(p) != _brute(_g, p):
				bad += 1
	assert_eq(bad, 0)


func test_high_over_an_item_matches_and_counts_it() -> void:
	# A ship in orbit straight over a roof, a mesa or a boulder (the item's own
	# axis, a little off it, and the gravity up): the line test keeps exactly the
	# items the plain scan finds.
	var bad := 0
	var touched := 0
	var tops: Array = []
	for b in _g.boxes:
		var xf := WorldGround.box_xf(b)
		var mid: Vector3 = ((b.min as Vector3) + (b.max as Vector3)) * 0.5
		tops.append([xf * Vector3(mid.x, (b.max as Vector3).y, mid.z), xf.basis.y.normalized()])
	for c in _g.columns:
		var up: Vector3 = c.get("up", Vector3.UP)
		tops.append([(c.center as Vector3) + up * float(c.get("h", float(c.top) - (c.center as Vector3).y)), up])
	for bd in _g.boulders:
		tops.append([(bd.center as Vector3) + (bd.up as Vector3) * float(bd.height), bd.up])
	for t in tops:
		for alt in [1300.0, 3000.0, 6000.0]:
			for dir in [t[1], _sp.up_at(t[0])]:
				var p: Vector3 = t[0] + (dir as Vector3) * alt + Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1))
				var want := _brute(_g, p)
				if _g.height_above(p) != want:
					bad += 1
				if want != _sp.height_above_ground(p):
					touched += 1
	assert_eq(bad, 0, "high queries straight over items are exactly the linear scan's")
	assert_gt(touched, 200, "the items under those points really count")


func test_high_queries_are_cheap() -> void:
	# Issue: from orbit every item was in the sphere's reach and each query scanned
	# them all (a ship's agl is five queries, every physics step).
	var pts: Array = []
	for i in 200:
		var m := _map_pt(2500.0)
		var base := _sp.surface_at(m.x, m.y)
		pts.append(base + _sp.up_at(base) * _rng.randf_range(1500.0, 6000.0))
	_g.height_above(pts[0])
	var t0 := Time.get_ticks_usec()
	for p in pts:
		_g.height_above(p)
	var indexed := Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	for p in pts:
		_g._height_above_linear(p, _sp.height_above_ground(p))
	var linear := Time.get_ticks_usec() - t0
	assert_lt(float(indexed), float(linear) * 0.5, "indexed %d us vs linear %d us" % [indexed, linear])


func test_far_below_the_ground_nothing_counts() -> void:
	var base := _sp.surface_at(50.0, 50.0)
	var p := base - _sp.up_at(base) * 3.0
	assert_eq(_g.height_above(p), _brute(_g, p))
	assert_lt(_g.height_above(p), -0.5)


func test_a_column_appended_directly_is_noticed() -> void:
	var base := _sp.surface_at(1234.0, 777.0)
	var up := _sp.up_at(base)
	var p := base + up * 60.0
	_g.height_above(p)                      # builds the index
	var before := _g.height_above(p)
	_g.columns.append({ "id": "new_rock", "kind": "rock", "center": base, "radius": 30.0, "up": up, "h": 40.0,
		"top": base.y + 40.0 })
	var after := _g.height_above(p)
	assert_eq(after, _brute(_g, p))
	assert_lt(after, before - 10.0, "the new column is under the point now")
	assert_almost_eq(after, 20.0, 0.5, "standing 60 m up over a 40 m column")


func test_add_boulders_after_a_query_is_noticed() -> void:
	var base := _sp.surface_at(-1500.0, 600.0)
	var up := _sp.up_at(base)
	var p := base + up * 7.0
	var before := _g.height_above(p)
	_g.add_boulders([{ "center": base, "up": up, "radius": 3.0, "height": 6.0 }])
	var after := _g.height_above(p)
	assert_eq(after, _brute(_g, p))
	assert_lt(after, before - 4.0, "a 6 m rock now stands under the point")


func test_a_replaced_array_and_invalidate_index() -> void:
	var base := _sp.surface_at(300.0, 300.0)
	var up := _sp.up_at(base)
	var p := base + up * 30.0
	_g.height_above(p)
	# Same count, different content: only invalidate_index() can know.
	var xf := Transform3D(PlanetSphere.tilt_to(up), base)
	var swapped: Array = _g.boxes.duplicate()
	swapped[5] = { "id": "swapped", "kind": "solid", "min": Vector3(-10, 0, -10), "max": Vector3(10, 22, 10),
		"rise": "", "visual": true, "xf": xf }
	_g.boxes = swapped                         # a new Array instance: noticed by itself
	assert_eq(_g.height_above(p), _brute(_g, p))
	assert_almost_eq(_g.height_above(p), 8.0, 0.5, "the swapped box is a 22 m roof under the point")
	_g.boxes[5].max = Vector3(10, 12, 10)      # geometry edit in place: say so
	_g.invalidate_index()
	assert_eq(_g.height_above(p), _brute(_g, p))
	assert_almost_eq(_g.height_above(p), 18.0, 0.5)


func test_flat_world_path_is_untouched() -> void:
	PlanetSphere.current = null
	var flat := WorldGround.new()
	flat.setup({}, null, null)
	flat.add_box("roof", "solid", Vector3(-5, 0, -5), Vector3(5, 6, 5))
	assert_almost_eq(flat.height_above(Vector3(0, 10, 0)), 4.0, 0.001)
	assert_almost_eq(flat.height_above(Vector3(50, 10, 0)), 10.0, 0.001)
