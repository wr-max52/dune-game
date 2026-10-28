extends GutTest
## Issue #77: the home planet is a whole ball. The math (PlanetSphere), the sand
## on it (PlanetTerrain: the collider under you is the mesh you see) and a body
## standing on it with real physics far round the curve.

const TownDemo := preload("res://scenes/town_demo.gd")
const Body := preload("res://src/systems/player/character_body.gd")

var _site: Dictionary


func before_all() -> void:
	var d = TownDemo.new()
	d.with_desert = false
	d.use_look = false
	d.lookdev_mode = true
	add_child(d)
	_site = d.desert_site()
	d.free()


func after_each() -> void:
	PlanetSphere.current = null


func _sphere() -> PlanetSphere:
	var s := PlanetSphere.new(5000.0)
	s.configure_site(_site.floor, _site.walls, _site.sunken, 0.0)
	return s


func _terrain() -> PlanetTerrain:
	var t := PlanetTerrain.new()
	t.set_radius(5000.0)
	t.configure_site(_site.floor, _site.walls, _site.sunken, 0.0)
	t.threaded = false
	t.near_cells = 64
	t.collider_cells = 64
	t.collider_size = 64.0
	t.recenter_distance = 16.0
	return t


func test_map_coordinates_round_trip() -> void:
	var s := _sphere()
	for m in [Vector2(0, 0), Vector2(120, -40), Vector2(2600, -1900), Vector2(-9000, 4000), Vector2(14000, 0)]:
		var back := s.world_to_map(s.surface_at(m.x, m.y))
		assert_almost_eq(back.x, m.x, 0.05, "map %s round trips" % m)
		assert_almost_eq(back.y, m.y, 0.05)
	assert_almost_eq(s.map_dir(PI * 5000.0 * 0.5, 0).y, 0.0, 0.0001, "a quarter of the way round is the equator")


func test_town_is_flat_and_the_pit_still_dips() -> void:
	var s := _sphere()
	assert_almost_eq(s.height_at(50, -40), -0.12, 0.001, "under the paving, as on the flat desert")
	assert_almost_eq(s.height_at(130, 40), 0.0, 0.01, "apron at floor level")
	assert_lte(s.height_at(0, 0), -6.5, "under the pit floor")
	assert_eq(s.up_at(Vector3(120, 0, 60)), Vector3.UP, "up is straight up in town")


func test_sand_goes_all_the_way_round() -> void:
	var s := _sphere()
	var lo := INF
	var hi := -INF
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 400:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		var e := s.elevation(dir)
		assert_true(is_finite(e), "ground everywhere")
		lo = minf(lo, e)
		hi = maxf(hi, e)
	assert_gt(hi - lo, 20.0, "dunes on every side, not a smooth ball")
	assert_lt(hi - lo, 120.0, "and no spikes")
	var far_side := s.elevation(Vector3.DOWN)
	assert_true(is_finite(far_side), "even straight through the planet from the port")
	assert_lt(absf(far_side), 60.0, "and it is dunes there, not the town's plateau")
	assert_almost_eq(s.dir_map(Vector3.DOWN).length(), PI * 5000.0, 0.01, "the far pole is half way round")


func test_up_turns_with_the_ball() -> void:
	var s := _sphere()
	var p := s.surface_at(2500, 0)
	var up := s.up_at(p)
	assert_almost_eq(up.angle_to((p - s.center).normalized()), 0.0, 0.001, "radial out in the desert")
	assert_almost_eq(rad_to_deg(up.angle_to(Vector3.UP)), rad_to_deg(2500.0 / 5000.0), 0.1, "half a radian round")
	var t := PlanetSphere.tilt_to(up)
	assert_true((t * Vector3.UP).is_equal_approx(up), "tilt takes world up to local up")


func test_collider_matches_the_ground_it_was_built_from() -> void:
	var t := _terrain()
	add_child_autofree(t)
	t.build(false)
	t.snap_to(t.sphere.surface_at(1800, 900))
	assert_true(t.collider_covers(t.sphere.surface_at(1800, 900).x, t.sphere.surface_at(1800, 900).z, 4.0))
	# Every collider vertex lies on the ground the sphere says is there.
	var shape := t.collider_shape.shape as HeightMapShape3D
	var xf := t.collider_shape.global_transform
	var n := shape.map_width
	var worst := 0.0
	for j in range(0, n, 7):
		for i in range(0, n, 7):
			var local := Vector3(i - (n - 1) * 0.5, shape.map_data[j * n + i], j - (n - 1) * 0.5)
			worst = maxf(worst, absf(t.sphere.height_above_ground(xf * local)))
	assert_lt(worst, 0.005, "collider and ground agree to within 5 mm")


func test_collider_follows_round_the_curve() -> void:
	var t := _terrain()
	add_child_autofree(t)
	t.build(false)
	var walker := Node3D.new()
	add_child_autofree(walker)
	t.follow(walker)
	walker.global_position = t.sphere.surface_at(20, 0) + Vector3.UP
	t._physics_process(1.0 / 60.0)
	assert_eq(t.recenters, 1, "moved past the re-centre distance: rebuilt")
	walker.global_position = t.sphere.surface_at(6000, 2000)
	t._physics_process(1.0 / 60.0)
	assert_eq(t.snaps, 1, "teleported round the ball: rebuilt at once")
	var p := walker.global_position
	assert_true(t.collider_covers(p.x, p.z, 8.0), "ground under the walker far round the ball")


func test_a_body_stands_on_the_far_dunes() -> void:
	var t := _terrain()
	add_child_autofree(t)
	t.build(false)
	PlanetSphere.current = t.sphere
	var body := Body.new()
	body.use_external_command = true
	var start := t.sphere.surface_at(3000, -1000)
	var up := t.sphere.up_at(start)
	body.position = start + up * 1.5
	add_child_autofree(body)
	t.follow(body)
	t.snap_to(body.position)
	for i in 90:
		await wait_physics_frames(1)
	assert_true(body.is_on_floor(), "landed on the sand 3 km round the curve")
	assert_almost_eq(t.sphere.height_above_ground(body.global_position), 0.0, 0.15, "on the dunes, not in them")
	assert_almost_eq(body.up_direction.angle_to(up), 0.0, 0.01, "standing along the ground's up")
	# Walk forward for a second: it stays on the ground.
	body.set_command(Vector2(0, 1), false, false, false)
	for i in 60:
		await wait_physics_frames(1)
	assert_gt(body.global_position.distance_to(start), 3.0, "it walked")
	assert_almost_eq(t.sphere.height_above_ground(body.global_position), 0.0, 0.25, "still on the sand")
