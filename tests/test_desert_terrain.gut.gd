extends GutTest
## The town seated on the desert (DesertTerrain site mode), the collider that
## follows the player, the horizon landforms and the fall guard. The walk itself,
## with real physics, is tests/test_desert_walk.gut.gd.

const TownDemo := preload("res://scenes/town_demo.gd")
const Landforms := preload("res://src/systems/look/desert_landforms.gd")

var _site_terrain: DesertTerrain
var _site: Dictionary


func before_all() -> void:
	var d = TownDemo.new()
	d.with_desert = false
	d.use_look = false
	d.lookdev_mode = true
	add_child(d)
	_site = d.desert_site()
	d.free()
	_site_terrain = DesertTerrain.new()
	_site_terrain.configure_site(_site.floor, _site.walls, _site.sunken, 0.0)


func after_all() -> void:
	_site_terrain.free()


func after_each() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func test_site_comes_from_town_data() -> void:
	var floor_rect: Rect2 = _site.floor
	assert_eq(floor_rect.position, Vector2(-130, -75), "aprons included (back gap)")
	assert_eq(floor_rect.end, Vector2(160, 75), "aprons included (desert side)")
	assert_eq(_site.walls, Rect2(-100, -75, 200, 150), "walled area = town bounds")
	assert_eq(_site.sunken.size(), 1, "one sunken floor: the pit")
	assert_eq(_site.sunken[0].rect, Rect2(-28, -28, 56, 56), "the round pit's square floor")


func test_sand_meets_the_aprons_and_the_gate_at_floor_level() -> void:
	var t := _site_terrain
	for p in [Vector2(101, 0), Vector2(130, 40), Vector2(159, -70), Vector2(-115, -60), Vector2(-129, -41)]:
		assert_almost_eq(t.height_at(p.x, p.y), 0.0, 0.001, "apron %s is at floor level" % p)
	# Just outside the walls, all round: flat sand at the floor, so walls stand on it.
	for p in [Vector2(0, 76), Vector2(0, -76), Vector2(-101, 20), Vector2(50, 78), Vector2(165, 0)]:
		assert_almost_eq(t.height_at(p.x, p.y), 0.0, 0.05, "outside the wall at %s" % p)


func test_ground_never_pokes_through_the_town() -> void:
	var t := _site_terrain
	var walls: Rect2 = _site.walls
	var worst := -INF
	var x := walls.position.x
	while x <= walls.end.x:
		var z := walls.position.y
		while z <= walls.end.y:
			worst = maxf(worst, t.height_at(x, z))
			worst = maxf(worst, t.ground_at(x, z))
			z += 0.5
		x += 0.5
	assert_lte(worst, 0.0, "inside the walls the ground stays at or under the paving")
	# Away from the wall line it is hidden inside the 0.5 m paving boxes.
	assert_almost_eq(t.height_at(50, -40), -0.12, 0.001, "under the paving")
	assert_gt(t.height_at(50, -40), -0.5, "inside the paving box, not below it")


func test_ground_dips_under_the_pit_for_mesh_and_collider() -> void:
	var t := _site_terrain
	var pit: Rect2 = _site.sunken[0].rect
	# Visual: everything over the pit is under its floor (-6.5 bottom).
	var x := pit.position.x
	while x <= pit.end.x:
		var z := pit.position.y
		while z <= pit.end.y:
			assert_lte(t.height_at(x, z), -6.5, "mesh under the pit floor at %.1f,%.1f" % [x, z])
			z += 1.0
		x += 1.0
	# Collider: every vertex of every cell that touches the pit is under the floor,
	# so the 2 m interpolation never raises an invisible slope inside it.
	var step := 512.0 / 256.0
	var bad := 0
	var cx := floorf(pit.position.x / step) * step - step
	while cx <= pit.end.x + step:
		var cz := floorf(pit.position.y / step) * step - step
		while cz <= pit.end.y + step:
			if t.ground_at(cx, cz) > -6.5:
				bad += 1
			cz += step
		cx += step
	assert_eq(bad, 0, "no collider vertex near the pit is above its floor")


func test_flat_sand_then_real_dunes() -> void:
	var t := _site_terrain
	assert_almost_eq(t.height_at(185, 0), 0.0, 0.6, "packed sand just past the apron")
	var lo := INF
	var hi := -INF
	for i in 200:
		var a := TAU * i / 200.0
		var h := t.height_at(cos(a) * 900.0, sin(a) * 900.0)
		lo = minf(lo, h)
		hi = maxf(hi, h)
	assert_gt(hi - lo, 15.0, "out in the desert there are dunes, not a plane")
	assert_almost_eq(t.height_at(900, 300), t._dunes(900, 300) - t.dune_offset, 0.001,
		"past the blend it is the open dunes")


func test_collider_follows_and_rebuilds_within_budget() -> void:
	var t := DesertTerrain.new()
	t.configure_site(_site.floor, _site.walls, _site.sunken, 0.0)
	t.collider_size = 128.0
	t.collider_cells = 64
	t.recenter_distance = 24.0
	add_child_autofree(t)
	t.build(false)
	var walker := Node3D.new()
	add_child_autofree(walker)
	t.follow(walker)
	assert_eq(t.collider_center, Vector3.ZERO)
	walker.global_position = Vector3(40, 0, 0)
	for i in 400:
		t._physics_process(1.0 / 60.0)
		if t.recenters > 0:
			break
	assert_eq(t.recenters, 1, "re-centred once")
	assert_eq(t.collider_center, Vector3(40, 0, 0), "on the walker, snapped to a cell")
	assert_eq(t.collider_body.position, t.collider_center, "body moved with it")
	assert_lt(t.worst_step_ms, t.rebuild_budget_ms + 3.0, "each frame's share stays near the budget")
	assert_eq(t.snaps, 0, "no synchronous rebuild for a walk")
	# A teleport far past the edge rebuilds at once instead of dropping the player.
	walker.global_position = Vector3(900, 0, 900)
	t._physics_process(1.0 / 60.0)
	assert_eq(t.snaps, 1, "teleport: rebuilt now")
	assert_true(t.collider_covers(900, 900, 10.0), "the ground is under the walker")


func test_collider_data_matches_ground() -> void:
	var t := DesertTerrain.new()
	t.configure_site(_site.floor, _site.walls, _site.sunken, 0.0)
	t.collider_size = 64.0
	t.collider_cells = 32
	add_child_autofree(t)
	t.build(false)
	var shape := t.collider_shape.shape as HeightMapShape3D
	var step := 2.0
	# Row 0 col 0 is the (-32, -32) corner; heights are stored in cell units.
	assert_almost_eq(shape.map_data[0] * step, t.ground_at(-32, -32), 0.001)
	assert_almost_eq(shape.map_data[33 * 16 + 16] * step, t.ground_at(0, 0), 0.001, "centre")


func test_town_demo_builds_the_desert() -> void:
	var d = TownDemo.new()
	d.use_look = false
	d.lookdev_mode = true
	add_child_autofree(d)
	assert_not_null(d.terrain, "desert on by default")
	assert_not_null(d.terrain.collider_body, "greybox gets the collider")
	assert_eq(d.terrain.get_node_or_null("Mesh"), null, "but no mesh (nothing draws in CI)")
	assert_eq(d.view_far(), 20000.0, "the home planet: the whole ball")
	var off = TownDemo.new()
	off.use_look = false
	off.lookdev_mode = true
	off.with_desert = false
	add_child_autofree(off)
	assert_null(off.terrain, "with_desert = false is the old town")
	assert_eq(off.view_far(), 4000.0)


func test_look_hides_the_aprons_and_raises_landforms() -> void:
	var d = TownDemo.new()
	d.lookdev_mode = true
	d.terrain_resolution = 120          # fast; the layout is what is under test
	add_child_autofree(d)
	# Issue #77: the home planet is a ball; its sand is three layers, the nearest first.
	assert_true(d.terrain is PlanetTerrain, "the port's world is a sphere")
	assert_not_null(d.terrain.get_node_or_null("Near"), "look: the sand under the player")
	assert_not_null(d.terrain.get_node_or_null("Mid"), "look: the sand round the camera")
	assert_eq(d.terrain.get_node("Far").get_child_count(), 6 * d.terrain.far_chunks * d.terrain.far_chunks, "the whole ball")
	for id in ["desert_apron", "backgap_apron"]:
		var body: Node = d.get_node("Town/" + id)
		assert_false((body.get_node("Mesh") as MeshInstance3D).visible, "%s hidden: the sand shows" % id)
		assert_true(body is StaticBody3D, "%s still solid" % id)
	assert_true((d.get_node("Town/ground_east/Mesh") as MeshInstance3D).visible, "paving stays")
	assert_not_null(d.landforms)
	assert_gt(d.landforms.solid_count, 8, "mesas and hoodoos are solid")
	assert_gt(d.landforms.boulder_count, 100)
	var keep: Rect2 = d.desert_site().floor.grow(float(d.landforms.data.keep_out_margin))
	for c in d.landforms.get_children():
		if c is MeshInstance3D:
			assert_false(keep.has_point(Vector2(c.position.x, c.position.z)), "%s clear of the town" % c.name)
	var mm: MultiMesh = (d.landforms.get_node("Boulders") as MultiMeshInstance3D).multimesh
	assert_eq(mm.instance_count, d.landforms.boulder_count)
	var inside := 0
	for o in d.landforms.boulder_spots:
		if keep.has_point(Vector2(o.x, o.z)):
			inside += 1
	assert_eq(inside, 0, "no boulders in or near the town")


func test_mesas_have_broad_caps_and_eroded_shelves() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 31
	noise.fractal_octaves = 3
	var mesh := Landforms._mesa_mesh(100.0, 200.0, noise, 4.0)
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var base_radius := 0.0
	var cap_radius := 0.0
	for v in verts:
		var radial := Vector2(v.x, v.z).length()
		if v.y < -60.0:
			base_radius = maxf(base_radius, radial)
		if v.y > 60.0:
			cap_radius = maxf(cap_radius, radial)
	assert_gt(base_radius, cap_radius * 1.35, "the cliff narrows to a distinct broad plateau")
	assert_lte(base_radius, 90.0, "the visible cliff stays inside its existing world-ground column")
	assert_gt(verts.size(), 64 * 10 * 6, "the stepped silhouette has enough geometry to read")


func test_fall_guard_uses_the_ground() -> void:
	var d = TownDemo.new()
	d.use_look = false
	add_child_autofree(d)
	var g: GearController = d.gear
	assert_true(g.ground_at.is_valid(), "the town hands the terrain to the gear")
	# Out in the desert the threshold follows the dunes, not the town's lowest floor.
	var out_far := Vector3(800, 0, 200)
	assert_almost_eq(g.floor_below(out_far), d.terrain.ground_at(800, 200), 0.001)
	# Over the pit the pit floor still counts (the terrain dips below it).
	assert_almost_eq(g.floor_below(Vector3(0, 0, 0)), minf(d.terrain.ground_at(0, 0), -6.5), 0.001)
	var off = TownDemo.new()
	off.use_look = false
	off.with_desert = false
	add_child_autofree(off)
	assert_false(off.gear.ground_at.is_valid())
	assert_eq(off.gear.floor_below(out_far), off.gear.lowest_floor, "no terrain: old rule")
