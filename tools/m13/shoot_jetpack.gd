extends SceneTree
## Review renders for M13: the jetpack lying at the top of the pit ramp, worn on
## the player's back, lit in flight, the view from the top of a climb, and the
## gear trader's prompt. Saves PNGs to test_results/m13/.
##
## Needs a real renderer: ./tools/m13/shoot_jetpack.sh [shots=a,b] (SIZE=1280x720)

const OUT := "res://test_results/m13"

var demo
var gear: GearController
var rig_node
var player
var _shots: Array = []
var _i := -1
var _wait := 0
var _frame := 0
var _only: Array = []
var _hold := false               ## keep jump held (flight shots)
var _jump_pending := false       ## press jump on the next physics frame
var _chase := Vector3.ZERO       ## camera offset that follows the player (0 = fixed)
var _chase_look := Vector3(0, 1.1, 0)


func _initialize() -> void:
	WorldState.reset()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shots="):
			_only = a.substr(6).split(",")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	Disclaimers.launch_shown = true     # the launch notice would cover every shot
	demo = load("res://scenes/town_demo.gd").new()
	demo.preset = "golden"
	demo.with_bar = false
	get_root().add_child(demo)
	_shots = [
		["pickup_on_ramp", _pickup_view],
		["worn_back", _worn.bind(200.0, 3.0)],
		["worn_side", _worn.bind(100.0, 2.6)],
		["takeoff", _flight.bind(24, Vector3(2.2, 0.3, 5.0))],
		["flying", _flight.bind(80, Vector3(3.0, -1.2, 6.5))],
		["flames_close", _flight.bind(40, Vector3(1.4, -0.2, 2.6))],
		["top_of_climb", _top_of_climb],
		["trader", _trader],
	]
	if not _only.is_empty():
		_shots = _shots.filter(func(s): return _only.has(s[0]))


func _physics_process(_d: float) -> bool:
	if player != null and _hold:
		player.set_command(Vector2.ZERO, false, false, _jump_pending, true)
		_jump_pending = false
	return false


func _process(_d: float) -> bool:
	_frame += 1
	if _frame < 20:
		return false
	if player == null:
		gear = demo.gear
		rig_node = demo._rig
		player = demo._player
	if _chase != Vector3.ZERO:
		var at: Vector3 = player.global_position + _chase_look
		_cut(at + _chase, at)
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
		print("SHOOT M13: done")
		return true
	_hold = false
	_chase = Vector3.ZERO
	var wait = _shots[_i][1].call()
	_wait = int(wait) if wait != null else 40
	return false


func _cut(eye: Vector3, at: Vector3) -> void:
	rig_node.set_override(Transform3D(Basis(), eye).looking_at(at, Vector3.UP))
	rig_node._override_blend = 1.0


func _place(pos: Vector3, yaw: float) -> void:
	player.clear_external_command()
	player.set_command(Vector2.ZERO, false, false, false)
	player.global_position = pos + Vector3(0, 0.05, 0)
	player.velocity = Vector3.ZERO
	player.controller.velocity = Vector3.ZERO
	player.controller.body_pos = player.global_position
	rig_node.rig.yaw = yaw
	rig_node.rig.pitch = 0.0
	rig_node.set_first_person(false)      # the body (and the pack) are drawn in third person
	if demo.player_kit != null:
		demo.player_kit.avatar.facing_yaw = yaw


func _wear() -> void:
	if not WorldState.inventory.has("jetpack"):
		gear.focus = { "kind": "pickup", "node": gear.pickup_node("pit_jetpack") }
		gear.interact()


## The pack at the top of the pit ramp, with the player coming up the ramp.
func _pickup_view() -> int:
	var spot: Vector3 = gear.pickup_node("pit_jetpack").base
	_place(Vector3(14, -1.5, 18.5), PI * 0.5)
	_cut(spot + Vector3(-4.6, 1.5, 3.6), spot + Vector3(1.0, 0.7, -0.6))
	return 50


## The pack on the back. `deg` is the camera's angle around the player
## (180 = straight behind), `dist` metres.
func _worn(deg: float, dist: float) -> int:
	_wear()
	_place(Vector3(40, 0, 10), 0.0)
	var a := deg_to_rad(deg)
	var at: Vector3 = player.global_position + Vector3(0, 1.3, 0)
	_cut(at + Vector3(sin(a), 0.15, cos(a)) * dist, at)
	return 45


## Jump and hold: shoot `frames` into the climb with a following camera.
func _flight(frames: int, offset: Vector3) -> int:
	_wear()
	_place(Vector3(40, 0, 10), PI)
	player.jetpack.refill()
	_jump_pending = true
	_hold = true
	_chase = offset
	return frames


## The view from the top of a full climb, from the player's own camera.
func _top_of_climb() -> int:
	_wear()
	_place(Vector3(30, 0, 4), -PI * 0.5)
	rig_node.clear_override()
	rig_node._override_blend = 0.0
	rig_node.rig.pitch = -0.45
	player.jetpack.refill()
	_jump_pending = true
	_hold = true
	return 125


## At the market stall: the sell prompt is on screen.
func _trader() -> int:
	_wear()
	var v: Dictionary = gear.content.get_vendor("gear_trader")
	var stall: Vector3 = demo.town.marker_pos(str(v.marker))
	_place(Vector3(stall.x + 0.6, 0, -28.2), PI)
	var at: Vector3 = Vector3(stall.x, 1.2, stall.z)
	_cut(Vector3(stall.x + 3.2, 2.0, -24.5), at)
	return 45
