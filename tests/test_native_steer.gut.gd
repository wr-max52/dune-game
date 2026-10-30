extends GutTest
## Issue #96: the desert packs walk round the boulders and mesas they know about
## (NativeSteer) instead of through them.

const UP := Vector3.UP


## Walk from `a` toward `b` the way a pack member does: ask where to head, step.
func _walk(s: NativeSteer, a: Vector3, b: Vector3, step := 0.5, max_steps := 600) -> Array:
	var at := a
	var path: Array = [at]
	for i in max_steps:
		var to := s.steer(at, b, UP) - at
		to.y = 0.0
		if (b - at).length() < 0.6:
			break
		at += to.normalized() * minf(step, to.length())
		path.append(at)
	return path


func test_a_clear_way_goes_straight_at_the_goal() -> void:
	var s := NativeSteer.new()
	s.add(Vector3(0, 0, 40), 3.0)              # off to the side of the way
	var goal := Vector3(30, 0, 0)
	assert_eq(s.steer(Vector3.ZERO, goal, UP), goal)


func test_a_rock_in_the_way_is_walked_round() -> void:
	var s := NativeSteer.new()
	var rock := Vector3(15, 0, 0.3)
	s.add(rock, 3.0)
	var goal := Vector3(30, 0, 0)
	var head := s.steer(Vector3.ZERO, goal, UP)
	assert_ne(head, goal, "the rock is in the way")
	var path := _walk(s, Vector3.ZERO, goal)
	assert_lt((path[path.size() - 1] as Vector3).distance_to(goal), 0.7, "and it still gets there")
	var closest := INF
	for p in path:
		closest = minf(closest, (p as Vector3).distance_to(rock))
	assert_gt(closest, 3.0 + 0.5, "never into the rock")


func test_two_rocks_one_after_the_other() -> void:
	var s := NativeSteer.new()
	var rocks := [Vector3(12, 0, 0), Vector3(24, 0, 1.0)]
	for r in rocks:
		s.add(r, 2.5)
	var goal := Vector3(36, 0, 0)
	var path := _walk(s, Vector3.ZERO, goal)
	assert_lt((path[path.size() - 1] as Vector3).distance_to(goal), 0.7)
	for r in rocks:
		for p in path:
			assert_gt((p as Vector3).distance_to(r), 2.5, "clear of every rock")


func test_a_mesa_wider_than_a_cell_counts_too() -> void:
	var s := NativeSteer.new()
	var mesa := Vector3(60, 0, 0)
	s.add(mesa, 35.0)
	var path := _walk(s, Vector3.ZERO, Vector3(120, 0, 2), 1.0, 600)
	assert_lt((path[path.size() - 1] as Vector3).distance_to(Vector3(120, 0, 2)), 1.2)
	for p in path:
		assert_gt((p as Vector3).distance_to(mesa), 35.0)


func test_low_boulders_are_stepped_over_and_tall_ones_kept() -> void:
	var g := WorldGround.new()
	g.setup({}, null, null)
	g.add_boulders([
		{ "center": Vector3(10, 0, 0), "up": UP, "radius": 1.5, "height": 0.4 },
		{ "center": Vector3(20, 0, 0), "up": UP, "radius": 1.5, "height": 2.0 },
	])
	var s := NativeSteer.from_ground(g)
	assert_eq(s.count, 1, "only the tall one is in the way")


func test_a_camp_put_on_a_rock_moves_off_it() -> void:
	var s := NativeSteer.new()
	s.add(Vector3(5, 0, 5), 3.0)
	var spot := s.clear_spot(Vector3(5.5, 0, 5), UP)
	assert_false(s.blocked(spot, UP))
	assert_lt(spot.distance_to(Vector3(5, 0, 5)), 6.0, "only as far as it has to")
