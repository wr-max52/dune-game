extends RefCounted
## Issue #133: turns the player's movement keys into a gait. Pure, so the timing
## is unit-tested headless (tests/test_gait_input.gut.gd).
##
##   tap a move key      walk tap_steps natural steps, then stop
##   tap again           walk tap_steps more from that press (keep tapping to keep walking)
##   hold past hold_s    run (the controller's "sprint", 7 m/s); let go and you stop
##   Shift + move        sprint (the controller's "dash"), straight away
##
## Guards and bots never come through here: they push their commands directly.

const BodyAnimator := preload("res://src/systems/anim/body_animator.gd")

var hold_s := 0.4           ## how long a press must last to count as a hold
var tap_steps := 2
var walk_speed := 4.0
## One step is half the walk animation's stride, so the steps you see are the
## steps you get: 2 x 1.05 m = 2.1 m, which takes 0.525 s at 4 m/s.
var step_length := BodyAnimator.WALK_STRIDE * 0.5

var _was_pressed := false
var _held := 0.0            ## seconds the current press has lasted
var _ran := false           ## this press became a run (or a sprint): no walk-out on release
var _burst_left := 0.0      ## seconds of tap-walk still owed
var _burst_dir := Vector2.ZERO


## Seconds a tap walks for.
func burst_s() -> float:
	return float(tap_steps) * step_length / maxf(walk_speed, 0.001)


## dir: the raw move keys this frame (local, as character_body reads them).
## sprint_key: Shift is down. Returns { dir: Vector2, run: bool, dash: bool }.
func update(dt: float, dir: Vector2, sprint_key: bool) -> Dictionary:
	var pressed := dir.length() > 0.1
	if pressed and not _was_pressed:
		_held = 0.0
		_ran = false
		_burst_left = burst_s()
	_was_pressed = pressed
	_burst_left = maxf(0.0, _burst_left - dt)
	if pressed:
		_held += dt
		_burst_dir = dir
		if sprint_key or _held >= hold_s:
			_ran = true
		return { "dir": dir, "run": _ran, "dash": sprint_key }
	if _burst_left > 0.0 and not _ran:
		return { "dir": _burst_dir, "run": false, "dash": false }
	_burst_left = 0.0
	return { "dir": Vector2.ZERO, "run": false, "dash": false }


## Drop any walk still owed (the body was locked, a cinematic took over).
func reset() -> void:
	_was_pressed = false
	_held = 0.0
	_ran = false
	_burst_left = 0.0
