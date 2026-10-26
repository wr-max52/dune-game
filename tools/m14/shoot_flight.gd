extends SceneTree
## Review renders for M14: the ship lifting out of the pit, flying over the town,
## the desert and its landmarks, the sky going dark on the climb, and a landing in
## the dunes. Saves PNGs to test_results/m14/.
##
## Needs a real renderer: ./tools/m14/shoot_flight.sh [shots=a,b] (SIZE=1280x720)
## A bot flies the real ship (ShipPilot + AtmoFlight); each shot sets the ship's
## state, lets the scene settle, and saves the frame from the chase camera.

const OUT := "res://test_results/m14"

var demo
var pilot: ShipPilot
var _shots: Array = []
var _i := -1
var _wait := 0
var _frame := 0
var _only: Array = []
var _cmd: Dictionary = {}          ## held external command for flight shots
var _cam_fixed := false
var _cam_xf := Transform3D()


func _initialize() -> void:
	WorldState.reset()
	GameFlow.reset()
	GameFlow.change_scene = func(_p: String) -> void: pass    # never leave for space here
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shots="):
			_only = a.substr(6).split(",")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	demo = load("res://scenes/town_demo.gd").new()
	demo.preset = "golden"
	demo.with_bar = false
	get_root().add_child(demo)
	_shots = [
		["parked_board", _parked],
		["liftoff", _liftoff],
		["over_town", _fly.bind(Vector3(30, 140, 60), Vector3(-0.5, -0.25, -0.83), 0.5, 40)],
		["low_desert", _fly.bind(Vector3(500, 60, 900), Vector3(0.25, -0.05, 0.97), 0.7, 40)],
		["mesa_pass", _fly.bind(Vector3(1150, 130, 700), Vector3(0.3, 0.02, 0.95), 0.7, 40)],
		["climb_3km", _fly.bind(Vector3(0, 3000, 0), Vector3(0.0, 0.6, -0.8), 1.0, 40)],
		["edge_7km", _fly.bind(Vector3(0, 7000, 0), Vector3(0.0, 0.3, -0.95), 1.0, 40)],
		["looking_down_6km", _look_down],
		["landed_dunes", _landed],
	]
	if not _only.is_empty():
		_shots = _shots.filter(func(s): return _only.has(s[0]))


func _physics_process(_d: float) -> bool:
	if pilot != null and not _cmd.is_empty():
		pilot.set_external_command(_cmd)
	return false


func _process(_d: float) -> bool:
	_frame += 1
	if _frame < 30:
		return false
	if pilot == null:
		pilot = demo.pilot
	if _cam_fixed:
		demo._rig.set_override(_cam_xf, 65.0)
		demo._rig._override_blend = 1.0
	if _wait > 0:
		_wait -= 1
		if _wait == 0:
			var name: String = _shots[_i][0]
			var path := ProjectSettings.globalize_path(OUT + "/" + name + ".png")
			get_root().get_texture().get_image().save_png(path)
			print("SHOT ", name, " -> ", path)
		return false
	_i += 1
	if _i >= _shots.size():
		print("SHOOT M14: done")
		return true
	_cmd = {}
	_cam_fixed = false
	demo._rig._override_blend = 1.0 if pilot.piloting else 0.0
	var wait = _shots[_i][1].call()
	_wait = int(wait) if wait != null else 40
	return false


func _seat() -> void:
	if not pilot.piloting:
		demo._player.global_position = demo.town.spawn_pos() + Vector3(0, 0.05, 0)
		pilot.atmo.park(pilot.home, pilot.home_yaw)
		pilot.board()


func _fixed(eye: Vector3, at: Vector3) -> void:
	_cam_fixed = true
	_cam_xf = Transform3D(Basis(), eye).looking_at(at, Vector3.UP)


## Standing beside the parked ship, the board prompt up.
func _parked() -> int:
	var p = demo._player
	p.global_position = demo.town.spawn_pos() + Vector3(0, 0.05, 0)
	p.controller.body_pos = p.global_position
	demo._rig.rig.yaw = -2.6
	demo._rig.rig.pitch = 0.05
	demo._rig.set_first_person(false)
	return 40


## Half way up out of the pit, from the pit rim.
func _liftoff() -> int:
	_seat()
	_cmd = { "throttle": 0.0 }
	pilot.takeoff()
	_fixed(Vector3(24, 4.0, 20), pilot.home + Vector3(0, 6, 0))
	return 70


## Put the ship at `at` flying along `dir` at `throttle`; let the chase camera settle.
func _fly(at: Vector3, dir: Vector3, throttle: float, frames: int) -> int:
	_seat()
	pilot.atmo.place_flying(at, dir.normalized(), pilot.atmo.flight.cruise_speed(throttle), throttle)
	pilot.chase._primed = false
	_cmd = { "throttle": throttle }
	return frames


func _look_down() -> int:
	_fly(Vector3(400, 6000, 1400), Vector3(-0.1, -0.85, -0.5), 0.6, 2)
	_cmd = { "throttle": 0.6 }
	return 4


## Landed in the dunes, seen from the ground nearby.
func _landed() -> int:
	_seat()
	var at := Vector3(640, 0, 520)
	pilot.atmo.park(at, 0.6)
	pilot._set_hull(true)
	_cmd = { "throttle": 0.0 }
	var s: Vector3 = pilot.atmo.position()
	var eye := s + Vector3(16, 0, 12)
	eye.y = pilot.ground.ground_at(eye.x, eye.z) + 4.0
	_fixed(eye, s + Vector3(0, 0.5, 0))
	return 30
