extends GutTest
## Issue #77: the home planet is a whole ball. The math (PlanetSphere), the sand
## on it (PlanetTerrain: the collider under you is the mesh you see) and a body
## standing on it with real physics far round the curve.

const TownDemo := preload("res://scenes/town_demo.gd")
const Body := preload("res://src/systems/player/character_body.gd")
const TownLayout := preload("res://src/systems/world/town_layout.gd")
const CoreScript := preload("res://src/systems/dataload/core_content.gd")

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


# ---------------------------------------------------------------- flying on the ball

func _flight() -> AtmoFlight:
	var cc = CoreScript.new()
	cc.load_from()
	var sp := _sphere()
	PlanetSphere.current = sp
	var town := TownLayout.new()
	town.load_town("port_town")
	var g := WorldGround.new()
	g.setup(cc.get_world("port_desert"), town, cc, func(x: float, z: float) -> float: return sp.height_at(x, z))
	g.add_landforms(DesertLandforms.load_data(), _site.floor)
	var a := AtmoFlight.new()
	a.setup(cc.get_ship("interceptor"), g)
	return a


func test_the_ship_ground_is_the_ball() -> void:
	var a := _flight()
	assert_eq(a.ground.sphere(), PlanetSphere.current, "the home planet's world finds its ball")
	assert_eq(a.ground.columns.filter(func(c): return c.has("up")).size(), a.ground.columns.size(),
		"every mesa and hoodoo stands along the ball's up")
	var outpost: Array = a.ground.boxes.filter(func(b): return str(b.id).begins_with("outpost/"))
	assert_gt(outpost.size(), 0)
	var xf := WorldGround.box_xf(outpost[0])
	assert_gt(rad_to_deg(xf.basis.y.angle_to(Vector3.UP)), 30.0, "the outpost 3 km out leans with the ground")


func test_park_lift_fly_and_land_round_the_curve() -> void:
	var a := _flight()
	var sp := PlanetSphere.current
	var at := sp.surface_at(2000, 1200)
	a.park(at, 0.4)
	assert_almost_eq(a.agl(), 0.0, 0.05, "parked on the sand 2.3 km round")
	assert_almost_eq(a.transform().basis.y.angle_to(sp.up_at(at)), 0.0, 0.01, "standing along the ground's up")
	a.takeoff()
	for i in 600:
		a.step(1.0 / 60.0)
	assert_eq(a.state, AtmoFlight.State.FLYING)
	assert_almost_eq(a.agl(), a.p("liftoff_height", 18.0), 1.0, "lifted straight up along up, to its hover height")
	# Hover at zero throttle: it stays at its height above the ground round the curve.
	var alt := a.altitude()
	for i in 120:
		a.set_command(0, 0, 0, 0, false)
		a.step(1.0 / 60.0)
	assert_almost_eq(a.altitude(), alt, 0.5, "hovering holds its height")
	assert_true(a.can_land())
	a.land()
	for i in 900:
		a.step(1.0 / 60.0)
		if a.state == AtmoFlight.State.PARKED:
			break
	assert_eq(a.state, AtmoFlight.State.PARKED, "landed out there")
	assert_almost_eq(a.agl(), 0.0, 0.05, "on the sand, not in it")


func test_flying_round_the_planet_never_leaves_it() -> void:
	var a := _flight()
	var sp := PlanetSphere.current
	var start := sp.surface_at(0, 1500)
	var up := sp.up_at(start)
	a.place_flying(start + up * 300.0, Vector3(1, 0, 0) - up * up.x, 120.0, 0.6)
	var low := INF
	var high := -INF
	for i in 60 * 40:
		# Keep the nose level with the ground below as the ball turns under it.
		var u := a.up()
		var f: Vector3 = a.flight.forward()
		var pitch := clampf(-f.dot(u) * 4.0, -1.0, 1.0)
		a.set_command(pitch, 0, 0, 0.6, false)
		a.step(1.0 / 60.0)
		if a.state != AtmoFlight.State.FLYING:
			break
		low = minf(low, a.altitude())
		high = maxf(high, a.altitude())
	assert_eq(a.state, AtmoFlight.State.FLYING, "still flying after 40 s")
	assert_gt(sp.world_to_map(a.position()).length(), 3000.0, "a good way round")
	assert_gt(low, 100.0, "never hit the ground")
	assert_lt(high, 900.0, "nor flew off into space: level flight follows the curve")


func test_crashing_into_a_leaning_mesa() -> void:
	var a := _flight()
	var mesa: Dictionary = a.ground.columns.filter(func(c): return str(c.id) == "mesa_1500_1700")[0]
	var up: Vector3 = mesa.up
	var mid: Vector3 = (mesa.center as Vector3) + up * float(mesa.h) * 0.5
	var side := up.cross(Vector3.RIGHT).normalized()
	a.place_flying(mid + side * (float(mesa.radius) + 80.0), -side, 120.0, 1.0)
	var ev := []
	for i in 120:
		a.set_command(0, 0, 0, 1.0, false)
		ev.append_array(a.step(1.0 / 60.0))
		if a.state == AtmoFlight.State.CRASHED:
			break
	assert_eq(a.state, AtmoFlight.State.CRASHED, "flew into its side")
	assert_eq(a.last_hit, "mesa_1500_1700")


func test_a_speeder_drives_straight_round_the_curve() -> void:
	var a := _flight()
	var sp := PlanetSphere.current
	var m := HoverModel.new(HoverModel.load_config(), a.ground)
	var at := sp.surface_at(1200, 2600)
	m.place(at, 1.0)
	assert_almost_eq(m.height_over_ground(), 0.0, 0.01, "riding at hover height, 2.9 km round")
	var start_dir := m.forward()
	var lows := 0
	for i in 60 * 30:
		m.set_command(1.0, 0.0, false)
		m.step(1.0 / 60.0)
		if m.height_over_ground() < -0.3:
			lows += 1
	var gone := sp.world_to_map(m.position).distance_to(Vector2(1200, 2600))
	assert_gt(gone, 800.0, "drove most of a kilometre in 30 s")
	assert_eq(lows, 0, "never sank into the sand")
	assert_almost_eq(m.forward().dot(sp.up_at(m.position)), 0.0, 0.001, "nose stays along the ground")
	# Straight round a ball is a great circle: the heading turned with the ground
	# and nowhere else (the plane of travel holds).
	var plane := (at - sp.center).cross(start_dir).normalized()
	assert_almost_eq((m.position - sp.center).normalized().dot(plane), 0.0, 0.02, "drove straight, no drift")


func test_the_town_always_has_ground_wherever_the_player_is() -> void:
	var t := _terrain()
	add_child_autofree(t)
	t.build(false)
	PlanetSphere.current = t.sphere
	var walker := Node3D.new()
	add_child_autofree(walker)
	t.follow(walker)
	walker.global_position = t.sphere.surface_at(1500, 0)
	t.snap_to(walker.global_position)          # the player far away in the desert
	var body := Body.new()
	body.use_external_command = true
	body.position = Vector3(-161, 1.0, -60)    # someone at the speeder post
	add_child_autofree(body)
	for i in 60:
		await wait_physics_frames(1)
	assert_true(body.is_on_floor(), "standing on the town's own collider")
	assert_almost_eq(body.global_position.y, t.height_at(-161, -60), 0.1, "on the sand there, not below it")
