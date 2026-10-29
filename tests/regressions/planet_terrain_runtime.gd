extends SceneTree
## Issue #143: load the complete production terrain class and exercise both sides
## of the incremental row-completion boundary. No copied methods or stubs.

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)


func terrain(with_mesh: bool) -> PlanetTerrain:
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
	root.add_child(t)
	return t


func test_rows(with_mesh: bool) -> void:
	var t := terrain(with_mesh)
	var center := Vector2(24.0, -12.0)
	t._start("near", center)
	t.set_physics_process(false)
	check(t._jobs.has("near"), "near job starts")
	t._finish_jobs()
	check(t._jobs.near.row == 2, "first tick builds only the row budget")
	check(t.collider_shape.shape == null, "partial rows do not publish a collider")
	check(t.recenters == 0, "partial rows do not count a completed recenter")
	t._start("near", center)
	t.set_physics_process(false)
	check(t._jobs.near.row == 2, "duplicate request preserves partial row progress")
	t._finish_jobs()
	check(t._jobs.near.row == 4, "second tick is still incomplete")
	check(t.collider_shape.shape == null, "last incomplete tick retains old collider")
	t._finish_jobs()
	check(t.collider_shape.shape is HeightMapShape3D, "complete rows publish a heightmap")
	check(t.collider_shape.shape.map_width == 5, "heightmap includes all cells plus boundary")
	check(t.collider_shape.shape.map_data.size() == 25, "heightmap includes every height")
	check(t._near_map == center, "collider commits the requested center")
	check(t.recenters == 1, "complete rows count exactly one recenter")
	if with_mesh:
		check(t._jobs.has("near") and t._jobs.near.stage == "mesh", "complete collider starts mesh stage")
		var deadline := Time.get_ticks_msec() + 5000
		while not t._jobs.is_empty() and Time.get_ticks_msec() < deadline:
			t._finish_jobs()
			await process_frame
		check(t._jobs.is_empty(), "mesh worker completes")
		check(t.near_mesh.mesh != null, "completed worker publishes the mesh")
	else:
		check(t._jobs.is_empty(), "collider-only job finishes without a mesh worker")
	check(t.recenters == 1, "later ticks do not republish the collider")
	t.free()


func test_far_chunks() -> void:
	var t := PlanetTerrain.new()
	t.far_cells = 4
	t.far_chunks = 1
	for face in 6:
		var chunk: Dictionary = t._far_chunk(face)
		check(chunk.has_all(["arrays", "direction", "angle", "max_radius"]), "far chunk returns mesh and culling metadata")
		check(chunk.arrays[Mesh.ARRAY_VERTEX].size() == 25, "far chunk includes the full vertex grid")
		check(is_equal_approx(chunk.direction.length(), 1.0), "culling direction is normalized")
		check(chunk.max_radius >= t.sphere.radius, "culling radius encloses the planet")
		check(chunk.angle > 0.0 and chunk.angle < PI, "culling cone is finite and nonempty")
	t.free()


func _run() -> void:
	print("PlanetTerrain production-script regression")
	await test_rows(false)
	await test_rows(true)
	test_far_chunks()
	print("%d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
