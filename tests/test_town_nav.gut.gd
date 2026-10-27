extends GutTest
## The town navmesh (town_nav.gd): baked from the box data, with buildings and
## crates cleared (no walkable floor inside a closed box), the watchtower top kept
## (a marker stands on it), settings that round cleanly, and the soldier data the
## town points at actually exists. Pathing with real physics: tests/test_npc_trace.

const TownLayout := preload("res://src/systems/world/town_layout.gd")
const CoreScript := preload("res://src/systems/dataload/core_content.gd")
const PitBowl := preload("res://src/systems/world/pit_bowl.gd")

var town


func before_each() -> void:
	town = TownLayout.new()
	assert_true(town.load_town("port_town"))


func test_every_box_becomes_twelve_triangles() -> void:
	var faces := TownNav.box_faces(town)
	# The round pit is a hollow shell: its own triangles, not a box (a lid).
	var bowl_faces := 0
	for b in town.boxes():
		if str(b.kind) == "bowl":
			for m in PitBowl.parts(b, town).values():
				bowl_faces += (m as ArrayMesh).get_faces().size()
	assert_gt(bowl_faces, 0)
	assert_eq(faces.size(), (town.boxes().size() - 1) * 36 + bowl_faces)


func test_ramps_keep_their_slope() -> void:
	var faces := TownNav.box_faces(town)
	var i := 0
	for b in town.boxes():
		if str(b.id) == "ramp_ne":
			var lo := INF
			var hi := -INF
			for k in 36:
				lo = minf(lo, faces[i + k].y)
				hi = maxf(hi, faces[i + k].y)
			assert_almost_eq(hi, 0.0, 0.05, "the ramp's top reaches the street")
			assert_lt(lo, -5.9, "and its foot is on the pit floor")
		i += 36


func test_obstructions_are_blocking_boxes_except_stood_on() -> void:
	var ids := []
	for b in TownNav.obstruction_boxes(town):
		ids.append(str(b.id))
	assert_true(ids.has("barracks_hall"), "buildings are cleared")
	assert_true(ids.has("stall_n6"), "so are crates and stalls")
	assert_false(ids.has("watchtower"), "the tower top keeps its floor (a post stands there)")
	assert_false(ids.has("ramp_ne"), "ramps are walked on")
	assert_false(ids.has("ground_east"), "floors are walked on")


func test_bounds_hold_every_marker() -> void:
	var bounds := TownNav.town_bounds(town)
	for m in town.markers():
		var p: Vector3 = town.marker_pos(str(m.id))
		assert_true(bounds.grow(0.01).has_point(p + Vector3(0, 0.01, 0)), "%s inside the bake bounds" % m.id)


func test_settings_round_cleanly() -> void:
	var s := TownNav.DEFAULTS
	for k in ["agent_height", "agent_max_climb"]:
		var units := float(s[k]) / float(s.cell_height)
		assert_almost_eq(units, roundf(units), 0.001, "%s is a whole number of cells" % k)
	var r := float(s.agent_radius) / float(s.cell_size)
	assert_almost_eq(r, roundf(r), 0.001, "agent_radius is a whole number of cells")
	assert_lte(float(s.agent_max_climb), 0.12, "no taller than the capsule can actually step")


func test_bake_has_no_floor_inside_buildings() -> void:
	var tn := TownNav.new()
	var nm := tn.make_navmesh(town)
	NavigationServer3D.bake_from_source_geometry_data(nm, TownNav.source_geometry(town))
	tn.free()
	assert_gt(nm.get_polygon_count(), 200, "the town baked")
	var inside := 0
	var hall: Dictionary = town.get_box("barracks_hall")
	for v in nm.vertices:
		if v.y < 1.0 and v.x > float(hall.min[0]) + 1.0 and v.x < float(hall.max[0]) - 1.0 \
				and v.z > float(hall.min[2]) + 1.0 and v.z < float(hall.max[2]) - 1.0:
			inside += 1
	assert_eq(inside, 0, "no walkable ground inside the barracks hall")


func test_soldier_markers_name_real_profiles() -> void:
	var cc = CoreScript.new()
	cc.load_from()
	var live := 0
	for m in town.markers():
		if m.has("soldier"):
			live += 1
			var s: Dictionary = cc.get_soldier(str(m.soldier))
			assert_false(s.is_empty(), "%s names soldier %s" % [m.id, m.soldier])
			assert_true(s.has("perception") and s.has("nav"), "%s's profile has senses and pathing" % m.id)
	assert_eq(live, 14, "the gate guards, the tower sentry, the barracks pair and the nine locals are live")


func test_noise_events() -> void:
	NoiseEvents.reset()
	var a := NoiseEvents.emit(Vector3.ONE, 10.0)
	var b := NoiseEvents.emit(Vector3.ZERO, 20.0, "shot_range")
	assert_eq(b, a + 1)
	assert_eq(NoiseEvents.after(0).size(), 2)
	assert_eq(NoiseEvents.after(a).size(), 1)
	assert_eq(NoiseEvents.after(a)[0].kind, "shot_range")
	for i in 40:
		NoiseEvents.emit(Vector3.ZERO, 1.0)
	assert_eq(NoiseEvents.after(0).size(), NoiseEvents.MAX_EVENTS, "capped")
	NoiseEvents.reset()
