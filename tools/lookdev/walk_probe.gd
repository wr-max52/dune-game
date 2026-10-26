extends SceneTree
## Probe: can a human walk the beauty corner? Holds real input actions (W, D, a mouse
## turn, W again) and prints where the player went relative to the camera.
## Run: godot --headless --path . -s res://tools/lookdev/walk_probe.gd
const BeautyCorner := preload("res://scenes/lookdev/beauty_corner.gd")
var s
var f := 0
var start := Vector3.ZERO
var phase := ""

func _initialize() -> void:
	s = BeautyCorner.new()
	s.terrain_resolution = 64
	get_root().add_child(s)

func _cam_fwd() -> Vector3:
	var c: Camera3D = s._rig._camera
	var v := -c.global_transform.basis.z
	return Vector3(v.x, 0, v.z).normalized()

func _report(tag: String) -> void:
	var p: Vector3 = s._player.global_position
	var moved := p - start
	var flat := Vector3(moved.x, 0, moved.z)
	var dot := flat.normalized().dot(_cam_fwd()) if flat.length() > 0.05 else 0.0
	print("PROBE %s: pos=%s moved=%.2fm dot(move,camera_forward)=%.2f on_floor=%s cam_current=%s" % [
		tag, p, flat.length(), dot, s._player.is_on_floor(), s._rig._camera.current])

func _physics_process(_d: float) -> bool:
	f += 1
	if f == 30:
		start = s._player.global_position
		print("PROBE spawn: ", start, " camera_fwd=", _cam_fwd(), " third_person=", not s._rig.rig.is_first_person(), " model_visible=", s._player_model.visible)
		Input.action_press("move_forward")
	elif f == 150:
		Input.action_release("move_forward")
		_report("W held 2s")
		start = s._player.global_position
		Input.action_press("move_right")
	elif f == 210:
		Input.action_release("move_right")
		var p: Vector3 = s._player.global_position
		var right := _cam_fwd().cross(Vector3.UP)
		print("PROBE D held 1s: moved=%.2fm dot(move,camera_right)=%.2f" % [(p - start).length(), (p - start).normalized().dot(right)])
		# mouse look: turn 90 degrees, then walk forward again
		var ev := InputEventMouseMotion.new()
		ev.relative = Vector2(-628, 0)
		Input.parse_input_event(ev)
	elif f == 220:
		start = s._player.global_position
		Input.action_press("move_forward")
	elif f == 340:
		Input.action_release("move_forward")
		_report("after mouse turn, W held 2s")
		quit(0)
	return false
