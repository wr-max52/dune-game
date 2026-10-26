extends GutTest
## Path following on foot (npc_locomotion.gd, pure), driven through the player's
## own CharacterController on flat ground, so the test feels the same momentum a
## guard does: it follows corners, arrives, does not circle a tight corner at a
## run, notices when it is pinned, and maps world directions to the controller.

const NpcLocomotion := preload("res://src/systems/ai/npc_locomotion.gd")
const CharacterController := preload("res://src/systems/player/character_controller.gd")
const DT := 1.0 / 60.0


## Walk a controller along `path`. Returns { arrived, seconds, pos, loco, stuck }.
func _drive(path: Array, sprint: bool, seconds: float, nav: Dictionary = {}, block: Callable = Callable(), v0: Vector3 = Vector3.ZERO) -> Dictionary:
	var loco = NpcLocomotion.new(nav)
	loco.set_path(path)
	var c := CharacterController.new()
	c.walk_speed = 3.2
	c.sprint_speed = 6.2
	c.body_pos = path[0]
	c.velocity = v0
	var yaw := 0.7      # any facing: movement must not depend on it
	var stuck := 0
	for i in int(seconds * 60.0):
		var out: Dictionary = loco.update(DT, c.body_pos, Vector2(c.velocity.x, c.velocity.z).length())
		if out.stuck:
			stuck += 1
		if out.arrived:
			return { "arrived": true, "seconds": i * DT, "pos": c.body_pos, "loco": loco, "stuck": stuck }
		var dir: Vector2 = NpcLocomotion.world_to_command((out.move as Vector3) * float(out.speed), yaw)
		c.set_command(dir, sprint, false, false)
		c.step(DT, yaw, 0.0)
		if block.is_valid():
			c.body_pos = block.call(c.body_pos)
	return { "arrived": false, "seconds": seconds, "pos": c.body_pos, "loco": loco, "stuck": stuck }


func test_world_to_command_inverts_the_controller() -> void:
	for yaw in [0.0, 0.5, 1.6, -2.4, PI]:
		for w in [Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-0.6, 0, 0.8)]:
			var c := CharacterController.new()
			c.set_command(NpcLocomotion.world_to_command(w, yaw), false, false, false)
			c.velocity = Vector3.ZERO
			for i in 120:
				c.step(DT, yaw, 0.0)
			var got := Vector3(c.velocity.x, 0, c.velocity.z).normalized()
			assert_almost_eq(got.dot(w.normalized()), 1.0, 0.001, "yaw %.1f moves along %s" % [yaw, str(w)])


func test_follows_corners_and_arrives() -> void:
	var path := [Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 0, 8), Vector3(2, 0, 8)]
	var r := _drive(path, false, 20.0)
	assert_true(r.arrived, "arrived")
	assert_lt((r.pos as Vector3).distance_to(Vector3(2, 0, 8)), 0.7, "at the end")
	# 26 m at 3.2 m/s is about 8 s; allow for easing in and out.
	assert_lt(r.seconds, 11.0, "no dawdling (%.1f s)" % r.seconds)


func test_running_takes_a_tight_corner_without_circling() -> void:
	# A hairpin with short legs, at a run: the case that used to orbit a corner.
	var path := [Vector3(0, 0, 0), Vector3(6, 0, 0), Vector3(6, 0, 1.2), Vector3(0, 0, 1.2), Vector3(0, 0, 2.4), Vector3(6, 0, 2.4)]
	var r := _drive(path, true, 15.0)
	assert_true(r.arrived, "arrived at a run (stopped at %s)" % str(r.pos))


func test_circling_a_corner_counts_as_stuck() -> void:
	# What the npc trace caught on the pit ramp (slope + wall contact, which a flat
	# simulation does not reproduce): a running body circling a corner it keeps
	# overshooting. It moves plenty, so a "did it move" check never fires; the
	# check is progress along the path, so it is caught and the corner is skipped.
	var loco = NpcLocomotion.new({ "stuck_s": 1.0, "corner_lead_s": 0.0 })
	loco.set_path([Vector3(-5, 0, 0), Vector3(0, 0, 0), Vector3(0, 0, 10)])
	var stuck := false
	for i in 180:
		var a := i * DT * 5.0
		var pos := Vector3(cos(a), 0, sin(a)) * 1.2     # 1.2 m circles round the corner
		if loco.update(DT, pos, 6.0).stuck:
			stuck = true
	assert_true(stuck, "orbiting is reported as stuck")
	assert_eq(loco.index, 2, "and the corner it circled is given up")


func test_momentum_takes_corners_earlier() -> void:
	var loco = NpcLocomotion.new({ "waypoint_reach": 0.5, "corner_lead_s": 0.3 })
	loco.set_path([Vector3.ZERO, Vector3(10, 0, 0), Vector3(10, 0, 10)])
	loco.update(DT, Vector3(8.8, 0, 0), 0.0)
	assert_eq(loco.index, 1, "walking: 1.2 m short of the corner is not there yet")
	loco.update(DT, Vector3(8.8, 0, 0), 6.0)
	assert_eq(loco.index, 2, "running at 6 m/s: the corner is taken 1.8 m early")


func test_slows_into_the_end() -> void:
	var loco = NpcLocomotion.new({ "slow_radius": 2.0, "arrive_radius": 0.6 })
	loco.set_path([Vector3.ZERO, Vector3(10, 0, 0)])
	assert_eq(float(loco.update(DT, Vector3(1, 0, 0)).speed), 1.0, "full speed far out")
	assert_lt(float(loco.update(DT, Vector3(9, 0, 0)).speed), 1.0, "easing off near the end")


func test_pinned_body_is_reported_stuck_and_skips_the_corner() -> void:
	var path := [Vector3(0, 0, 0), Vector3(5, 0, 0), Vector3(5, 0, 5)]
	# An invisible wall at x = 2: the body can never get past it.
	var wall := func(p: Vector3) -> Vector3: return Vector3(minf(p.x, 2.0), p.y, p.z)
	var r := _drive(path, false, 5.0, { "stuck_s": 1.0 }, wall)
	assert_false(r.arrived)
	assert_gt(int(r.stuck), 0, "reported stuck")
	assert_gt(int(r.loco.index), 1, "gave up on the corner it was fighting")


func test_remaining_distance() -> void:
	var loco = NpcLocomotion.new()
	loco.set_path([Vector3.ZERO, Vector3(3, 0, 0), Vector3(3, 0, 4)])
	assert_almost_eq(loco.remaining(Vector3.ZERO), 7.0, 0.001)
	loco.clear()
	assert_eq(loco.remaining(Vector3.ZERO), 0.0)
	assert_false(loco.has_path())


func test_empty_path_is_already_there() -> void:
	var loco = NpcLocomotion.new()
	loco.set_path([])
	var out: Dictionary = loco.update(DT, Vector3.ZERO)
	assert_true(out.arrived)
	assert_eq(out.move, Vector3.ZERO)


func test_turning_takes_the_short_way() -> void:
	var a := NpcLocomotion.approach_angle(3.0, -3.0, 0.1)
	assert_gt(a, 3.0, "from +3 to -3 rad goes up through PI, not down through 0")
	assert_eq(NpcLocomotion.approach_angle(0.0, 0.05, 0.1), 0.05, "snaps when within a step")
	assert_almost_eq(NpcLocomotion.facing_toward(Vector3.ZERO, Vector3(0, 0, 5)), 0.0, 0.0001, "+Z is yaw 0")
	assert_almost_eq(NpcLocomotion.facing_toward(Vector3.ZERO, Vector3(5, 0, 0)), PI * 0.5, 0.0001)
