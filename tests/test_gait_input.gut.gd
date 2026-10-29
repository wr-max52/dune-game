extends GutTest
## Issue #133: tap to walk a few steps, hold to run, Shift to sprint.

const GaitInput := preload("res://src/systems/player/gait_input.gd")
const DT := 1.0 / 60.0
const FWD := Vector2(0, 1)

var g


func before_each() -> void:
	g = GaitInput.new()


func _run(frames: int, dir: Vector2, shift: bool = false) -> Dictionary:
	var out := {}
	for i in frames:
		out = g.update(DT, dir, shift)
	return out


func test_a_tap_walks_four_steps_then_stops() -> void:
	# 4 steps x 1.05 m at 4 m/s = 1.05 s (and 4.2 / 4 = 1.05 again from distance).
	assert_almost_eq(g.burst_s(), 1.05, 0.001)
	_run(6, FWD)                          # a 0.1 s tap
	var walking := _run(30, Vector2.ZERO)   # 0.6 s after release
	assert_eq(walking.dir, FWD, "still walking after the key is up")
	assert_false(walking.run)
	var stopped := _run(30, Vector2.ZERO)   # 1.1 s from the press
	assert_eq(stopped.dir, Vector2.ZERO, "four steps, then stop")


func test_tapping_again_keeps_walking() -> void:
	for i in 4:
		_run(6, FWD)
		var mid := _run(36, Vector2.ZERO)  # 0.7 s between taps
		assert_eq(mid.dir, FWD, "tap %d still walking" % i)


func test_holding_runs_after_the_hold_time() -> void:
	var early := _run(20, FWD)            # 0.33 s
	assert_false(early.run, "a short press is still a walk")
	var held := _run(10, FWD)             # 0.5 s
	assert_true(held.run, "held past 0.4 s: run")
	assert_false(held.dash)


func test_letting_go_of_a_run_stops_at_once() -> void:
	_run(40, FWD)
	var after: Dictionary = g.update(DT, Vector2.ZERO, false)
	assert_eq(after.dir, Vector2.ZERO, "no walk-out after a run")


func test_shift_sprints_straight_away() -> void:
	var out: Dictionary = g.update(DT, FWD, true)
	assert_true(out.dash)
	assert_true(out.run, "falls back to the run when out of stamina")
	var after: Dictionary = g.update(DT, Vector2.ZERO, true)
	assert_eq(after.dir, Vector2.ZERO, "a sprint does not walk on")


func test_shift_alone_does_not_move() -> void:
	var out := _run(10, Vector2.ZERO, true)
	assert_eq(out.dir, Vector2.ZERO)
	assert_false(out.dash)


func test_reset_drops_the_walk_owed() -> void:
	_run(6, FWD)
	g.reset()
	assert_eq(g.update(DT, Vector2.ZERO, false).dir, Vector2.ZERO)
