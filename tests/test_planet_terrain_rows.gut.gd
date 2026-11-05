extends GutTest
## Issue #143: the production terrain class across the incremental row-completion
## boundary, and its far chunks. Moved here from tests/regressions/ (issue #545):
## PlanetTerrain now reaches about 200 scripts, so it can only load in the real
## project, never in an isolated copy.


func _terrain(with_mesh: bool) -> PlanetTerrain:
	var t := PlanetTerrain.new()
	t.near_cells = 4
	t.near_step = 1.0
	t.rows_per_frame = 2
	t._with_mesh = with_mesh
	t.collider_body = StaticBody3D.new()
	t.collider_shape = CollisionShape3D.new()
	t.collider_body.add_child(t.collider_shape)
	t.add_child(t.collider_body)
	if with_mesh:
		t.near_mesh = MeshInstance3D.new()
		t.add_child(t.near_mesh)
	add_child(t)
	return t


func _rows(with_mesh: bool) -> void:
	var t := _terrain(with_mesh)
	var center := Vector2(24.0, -12.0)
	t._start("near", center)
	t.set_physics_process(false)
	assert_true(t._jobs.has("near"), "near job starts")
	t._finish_jobs()
	assert_eq(t._jobs.near.row, 2, "first tick builds only the row budget")
	assert_null(t.collider_shape.shape, "partial rows do not publish a collider")
	assert_eq(t.recenters, 0, "partial rows do not count a completed recenter")
	t._start("near", center)
	t.set_physics_process(false)
	assert_eq(t._jobs.near.row, 2, "duplicate request preserves partial row progress")
	t._finish_jobs()
	assert_eq(t._jobs.near.row, 4, "second tick is still incomplete")
	assert_null(t.collider_shape.shape, "last incomplete tick retains old collider")
	t._finish_jobs()
	assert_true(t.collider_shape.shape is HeightMapShape3D, "complete rows publish a heightmap")
	assert_eq(t.collider_shape.shape.map_width, 5, "heightmap includes all cells plus boundary")
	assert_eq(t.collider_shape.shape.map_data.size(), 25, "heightmap includes every height")
	assert_eq(t._near_map, center, "collider commits the requested center")
	assert_eq(t.recenters, 1, "complete rows count exactly one recenter")
	if with_mesh:
		assert_true(t._jobs.has("near") and t._jobs.near.stage == "mesh", "complete collider starts mesh stage")
		var deadline := Time.get_ticks_msec() + 5000
		while not t._jobs.is_empty() and Time.get_ticks_msec() < deadline:
			t._finish_jobs()
			await get_tree().process_frame
		assert_true(t._jobs.is_empty(), "mesh worker completes")
		assert_not_null(t.near_mesh.mesh, "completed worker publishes the mesh")
	else:
		assert_true(t._jobs.is_empty(), "collider-only job finishes without a mesh worker")
	assert_eq(t.recenters, 1, "later ticks do not republish the collider")
	t.free()


func test_rows_collider_only() -> void:
	await _rows(false)


func test_rows_with_mesh() -> void:
	await _rows(true)


func test_far_chunks() -> void:
	var t := PlanetTerrain.new()
	t.far_cells = 4
	t.far_chunks = 1
	for face in 6:
		var chunk: Dictionary = t._far_chunk(face)
		assert_true(chunk.has_all(["arrays", "direction", "angle", "max_radius"]), "far chunk returns mesh and culling metadata")
		assert_eq(chunk.arrays[Mesh.ARRAY_VERTEX].size(), 25, "far chunk includes the full vertex grid")
		assert_true(is_equal_approx(chunk.direction.length(), 1.0), "culling direction is normalized")
		assert_true(chunk.max_radius >= t.sphere.radius, "culling radius encloses the planet")
		assert_true(chunk.angle > 0.0 and chunk.angle < PI, "culling cone is finite and nonempty")
	t.free()
