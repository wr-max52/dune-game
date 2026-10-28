class_name BoardJolt
extends RefCounted
## Issue #87: the little show a vehicle puts on when you climb in. It sinks under
## your weight, the engine catches and it lifts a hand's width with a shudder,
## then settles back onto its hover (a speeder) or its gear (a ship). Pure math:
## start() on boarding, step() each frame, add the result to the visual only (the
## physics body never moves). Tested in tests/test_board_jolt.gut.gd.

var duration := 1.1
var size := 1.0               ## scales the sink, the lift and the shake (a ship is heavier)
var t := -1.0                 ## seconds since boarding; < 0 = idle


func _init(p_size := 1.0, p_duration := 1.1) -> void:
	size = p_size
	duration = p_duration


func start() -> void:
	t = 0.0


func active() -> bool:
	return t >= 0.0 and t < duration


## Returns the offset to add this frame: a Transform3D in the vehicle's own space
## (identity when idle).
func step(dt: float) -> Transform3D:
	if not active():
		t = -1.0
		return Transform3D.IDENTITY
	t += dt
	if t >= duration:
		return Transform3D.IDENTITY
	var u := t / duration
	var sink := -0.06 * exp(-pow((t - 0.08) / 0.06, 2.0))
	var lift := 0.15 * smoothstep(0.12, 0.42, t) * (1.0 - smoothstep(0.5, duration, t))
	var env := smoothstep(0.05, 0.15, t) * (1.0 - u) * (1.0 - u)
	var y := size * (sink + lift + 0.012 * env * sin(t * 47.0))
	var roll := 0.03 * env * sin(t * 31.0)
	var pitch := 0.022 * env * sin(t * 23.0 + 1.0)
	return Transform3D(Basis.from_euler(Vector3(pitch, 0.0, roll)), Vector3(0.0, y, 0.0))
