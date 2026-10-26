extends SceneTree
## M9 walk trace (headless). Builds the town, teleports the bot player to the
## start of each route, and walks every waypoint with real physics. Writes
## test_results/town_walk_trace.txt for tests/test_town_walk.gut.gd.
##
## Run: godot --headless --fixed-fps 60 --path . -s res://scenes/town_walk_trace.gd

const OUT := "res://test_results/town_walk_trace.txt"
const REACH := 0.75            # meters: close enough to a waypoint
const STUCK_WINDOW := 180      # physics frames (3 s at 60 fps)
const STUCK_MIN_MOVE := 0.5    # meters moved within the window, or we are stuck
const FALL_Y := -10.0

var _demo
var _layout
var _route_ids := ["spawn_to_cantina", "cantina_to_gate", "gate_to_cantina", "backgap_to_cantina"]
var _route_i := -1
var _points: Array = []
var _wp := 0
var _frames_in_route := 0
var _timeout := 0
var _hist: Array = []          # recent positions for stuck detection
var _frame := 0
var _warmup := 10
var _lines := PackedStringArray()
var _worst_ms := 0.0
var _last_usec := 0
var _failed := false
var _done := false             # guards against writing the file twice


func _initialize() -> void:
	_demo = load("res://scenes/town_demo.gd").new()
	_set_if_present(_demo, "use_look", false)   # keep the trace fast and unchanged
	get_root().add_child(_demo)
	_layout = _demo.town
	_lines.append("# town_walk_trace v1")
	_lines.append("# frame route wp x y z state")


func _set_if_present(obj: Object, prop: String, value) -> void:
	for p in obj.get_property_list():
		if p.name == prop:
			obj.set(prop, value)
			return


func _physics_process(_delta: float) -> bool:
	if _done:
		return true
	_frame += 1
	var now := Time.get_ticks_usec()
	if _last_usec > 0:
		_worst_ms = maxf(_worst_ms, (now - _last_usec) / 1000.0)
	_last_usec = now
	if _frame < _warmup:
		return false
	if _route_i == -1 or _wp >= _points.size():
		if _route_i >= 0:
			_lines.append("ROUTE_DONE %s frames=%d" % [_route_ids[_route_i], _frames_in_route])
		_route_i += 1
		if _route_i >= _route_ids.size():
			_finish()
			return true
		_start_route(_route_ids[_route_i])

	var p: CharacterBody3D = _demo._player
	_frames_in_route += 1

	# Steering toward the current waypoint (2D).
	var target: Vector3 = _points[_wp]
	var to := Vector3(target.x - p.global_position.x, 0.0, target.z - p.global_position.z)
	if to.length() < REACH:
		_lines.append("WP_REACHED %s %d" % [_route_ids[_route_i], _wp])
		_wp += 1
		return false
	p.rotation.y = 0.0
	var dir := Vector2(to.x, to.z).normalized()
	p.set_command(dir, true, false, false)    # sprint to keep CI fast

	# Logging.
	if _frame % 10 == 0:
		_lines.append("%d %s %d %.2f %.2f %.2f OK" % [_frame, _route_ids[_route_i], _wp,
			p.global_position.x, p.global_position.y, p.global_position.z])

	# Failure checks.
	_hist.append(p.global_position)
	if _hist.size() > STUCK_WINDOW:
		_hist.pop_front()
		if (_hist[0] as Vector3).distance_to(_hist[-1]) < STUCK_MIN_MOVE:
			_fail("STUCK", p.global_position)
	if p.global_position.y < FALL_Y:
		_fail("FELL", p.global_position)
	if _frames_in_route > _timeout:
		_fail("TIMEOUT", p.global_position)
	return false


func _start_route(id: String) -> void:
	_points = _layout.route_points_3d(id)
	var start: Vector3 = _points[0]
	# The spawn route starts in the pit: use the spawn marker's height there.
	var start_y: float = _layout.spawn_pos().y if id == "spawn_to_cantina" else 0.0
	var p: CharacterBody3D = _demo._player
	p.global_position = Vector3(start.x, start_y + 0.05, start.z)
	p.velocity = Vector3.ZERO
	p.controller.velocity = Vector3.ZERO
	_wp = 1
	_frames_in_route = 0
	_hist.clear()
	# Generous timeout: time to walk the route at walk speed, doubled, plus 10 s.
	_timeout = int((_layout.route_length(id) / 4.0 * 2.0 + 10.0) * 60.0)
	_lines.append("ROUTE_START %s len=%.1f" % [id, _layout.route_length(id)])


func _fail(kind: String, pos: Vector3) -> void:
	if _done:
		return
	_lines.append("FAIL %s route=%s wp=%d pos=%.2f,%.2f,%.2f" % [kind, _route_ids[_route_i], _wp, pos.x, pos.y, pos.z])
	_failed = true
	_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	_lines.append("SUMMARY boxes=%d markers=%d worst_ms=%.2f failed=%s" % [
		_demo.built_boxes, _demo.built_markers, _worst_ms, str(_failed)])
	if not DirAccess.dir_exists_absolute("res://test_results"):
		DirAccess.make_dir_recursive_absolute("res://test_results")
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(_lines) + "\n")
	f.close()
	print("TOWNTRACE wrote ", OUT, " failed=", _failed)
	quit(1 if _failed else 0)
