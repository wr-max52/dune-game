extends GutTest
## Guard senses (Perception, pure): the view cone, the awareness meter, noticing
## and forgetting, crouching and weapons, hearing shots, and the ray throttle.
## The live version, with real rays against the town, is in tests/test_npc_trace.

const CoreScript := preload("res://src/systems/dataload/core_content.gd")
const DT := 1.0 / 60.0

var cfg: Dictionary


func before_each() -> void:
	NoiseEvents.reset()
	var cc = CoreScript.new()
	cc.load_from()
	cfg = cc.get_soldier("gate_guard").get("perception", {})


## A guard at the origin looking down +Z.
func _eye() -> Perception:
	return Perception.new(cfg)


func _tick(p: Perception, seconds: float, target: Vector3, extra: Dictionary = {}) -> void:
	for i in int(seconds * 60.0):
		var s := { "self_pos": Vector3.ZERO, "forward": Vector3(0, 0, 1), "target_pos": target, "los_clear": true }
		s.merge(extra, true)
		p.update(DT, s)


func test_profile_numbers_are_loaded() -> void:
	var p := _eye()
	assert_eq(p.sight_range, float(cfg.sight_range))
	assert_eq(p.fov_deg, float(cfg.fov_deg))
	assert_gt(p.sight_range, 10.0, "a guard sees across the street")


func test_view_cone() -> void:
	var p := _eye()
	var fwd := Vector3(0, 0, 1)
	assert_true(p.cone_check(Vector3.ZERO, fwd, Vector3(0, 0, 15)), "straight ahead")
	assert_true(p.cone_check(Vector3.ZERO, fwd, Vector3(10, 0, 10)), "45 degrees off is inside a 120 degree cone")
	assert_false(p.cone_check(Vector3.ZERO, fwd, Vector3(12, 0, 0)), "90 degrees off is outside")
	assert_false(p.cone_check(Vector3.ZERO, fwd, Vector3(0, 0, -10)), "behind")
	assert_true(p.cone_check(Vector3.ZERO, fwd, Vector3(0, 0, -2)), "right behind is felt (close range)")
	assert_false(p.cone_check(Vector3.ZERO, fwd, Vector3(0, 0, p.sight_range + 1.0)), "past sight range")


func test_crouching_shrinks_the_range() -> void:
	var p := _eye()
	var at := Vector3(0, 0, p.sight_range * 0.8)
	assert_true(p.cone_check(Vector3.ZERO, Vector3(0, 0, 1), at, false), "seen standing")
	assert_false(p.cone_check(Vector3.ZERO, Vector3(0, 0, 1), at, true), "missed crouched at the same spot")


func test_awareness_builds_then_notices() -> void:
	var p := _eye()
	_tick(p, 0.2, Vector3(0, 0, 15))
	assert_true(p.visible)
	assert_between(p.awareness, 0.01, 0.99, "partly aware after a glimpse")
	assert_false(p.noticed, "a glimpse is not enough")
	_tick(p, 2.0, Vector3(0, 0, 15))
	assert_true(p.noticed, "noticed after a clear look")
	assert_eq(p.last_seen_pos, Vector3(0, 0, 15))


func test_closer_is_noticed_faster() -> void:
	var near := _eye()
	var far := _eye()
	var t_near := _time_to_notice(near, Vector3(0, 0, 5), {})
	var t_far := _time_to_notice(far, Vector3(0, 0, 28), {})
	assert_gt(t_far, t_near, "far (%.2f s) takes longer than near (%.2f s)" % [t_far, t_near])


func test_a_weapon_is_noticed_faster() -> void:
	var calm := _time_to_notice(_eye(), Vector3(0, 0, 20), {})
	var armed_p := _eye()
	var armed := _time_to_notice(armed_p, Vector3(0, 0, 20), { "armed": true })
	assert_lt(armed, calm, "armed %.2f s vs unarmed %.2f s" % [armed, calm])
	assert_true(armed_p.saw_weapon)


func test_blocked_line_of_sight_is_not_seen() -> void:
	var p := _eye()
	_tick(p, 3.0, Vector3(0, 0, 10), { "los_clear": false })
	assert_true(p.in_cone, "in the cone")
	assert_false(p.visible, "but behind something")
	assert_eq(p.awareness, 0.0)
	assert_false(p.noticed)


func test_forgets_after_a_while_out_of_sight() -> void:
	var p := _eye()
	_tick(p, 2.0, Vector3(0, 0, 10))
	assert_true(p.noticed)
	_tick(p, p.forget_s * 0.5, Vector3(0, 0, -40))
	assert_true(p.noticed, "still remembers shortly after")
	_tick(p, p.forget_s + 1.0, Vector3(0, 0, -40))
	assert_false(p.noticed, "forgotten after forget_s out of sight")
	assert_eq(p.last_seen_pos, Vector3(0, 0, 10), "but keeps where it last saw them")


func test_no_target_sees_nothing() -> void:
	var p := _eye()
	_tick(p, 1.0, Vector3.INF)
	assert_false(p.in_cone)
	assert_false(p.visible)


func test_hearing_a_shot_in_range() -> void:
	var p := _eye()
	NoiseEvents.emit(Vector3(30, 0, 0), 45.0, "shot")
	_tick(p, DT, Vector3.INF)
	assert_true(p.heard, "a shot 30 m off is heard, behind or not")
	assert_eq(p.heard_pos, Vector3(30, 0, 0))
	assert_eq(p.heard_kind, "shot")
	assert_almost_eq(p.awareness, p.heard_awareness, 0.001, "alert, not certain")
	assert_false(p.noticed, "hearing a shot does not reveal the shooter")
	assert_eq(p.last_seen_pos, Vector3.INF)


func test_out_of_earshot_and_heard_once() -> void:
	var p := _eye()
	NoiseEvents.emit(Vector3(80, 0, 0), 45.0, "shot")
	_tick(p, DT, Vector3.INF)
	assert_false(p.heard, "too far")
	NoiseEvents.emit(Vector3(10, 0, 0), 45.0, "shot")
	_tick(p, DT, Vector3.INF)
	assert_true(p.heard)
	_tick(p, DT, Vector3.INF)
	assert_false(p.heard, "the same shot is not heard twice")


func test_a_quiet_noise_carries_less() -> void:
	var p := _eye()
	NoiseEvents.emit(Vector3(20, 0, 0), 10.0, "shot")
	_tick(p, DT, Vector3.INF)
	assert_false(p.heard, "a noise only carries its own radius")


func test_old_noises_are_not_heard_by_a_new_guard() -> void:
	NoiseEvents.emit(Vector3(5, 0, 0), 45.0, "shot")
	var p := _eye()
	_tick(p, DT, Vector3.INF)
	assert_false(p.heard, "a guard spawned after the shot did not hear it")


func test_rays_are_throttled_and_only_in_the_cone() -> void:
	var p := _eye()
	var rays := 0
	for i in 60:
		p.cone_update(Vector3.ZERO, Vector3(0, 0, 1), Vector3(0, 0, 10), false)
		if p.wants_ray(DT):
			rays += 1
	assert_between(rays, int(p.ray_hz) - 1, int(p.ray_hz) + 1, "about ray_hz rays a second (%d)" % rays)
	rays = 0
	for i in 60:
		p.cone_update(Vector3.ZERO, Vector3(0, 0, 1), Vector3(0, 0, -20), false)
		if p.wants_ray(DT):
			rays += 1
	assert_eq(rays, 0, "no rays for a target outside the cone")


func _time_to_notice(p: Perception, at: Vector3, extra: Dictionary) -> float:
	for i in 600:
		var s := { "self_pos": Vector3.ZERO, "forward": Vector3(0, 0, 1), "target_pos": at, "los_clear": true }
		s.merge(extra, true)
		p.update(DT, s)
		if p.noticed:
			return (i + 1) * DT
	return INF
