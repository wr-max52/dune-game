extends Node3D
## M1 demo scene. Builds a greybox port floor + a few cover boxes, spawns the
## player with the camera rig, and (for the recording) auto-pilots the player in
## a loop, toggling FPV<->TPV. This gives a playable clip without a hand-authored
## .tscn and without a human. A human driving with WASD works the same way because
## the player shares the exact movement path.

const Greybox := preload("res://src/systems/world/greybox.gd")
const CharacterBody := preload("res://src/systems/player/character_body.gd")
const CameraRigNode := preload("res://src/systems/camera/camera_rig_node.gd")
const CharacterController := preload("res://src/systems/player/character_controller.gd")

var _player: Node
var _rig: Node
var _t := 0.0
var _toggle_every := 3.0
var _auto := true  # on in the recording; a human could set it false

func _ready() -> void:
	_add_floor()
	_add_cover(Vector3(-6, 1, -6), Vector3(3, 2, 3))
	_add_cover(Vector3(6, 1, 4), Vector3(3, 2, 3))
	_add_cover(Vector3(8, 1, -8), Vector3(4, 2, 4))

	_player = CharacterBody.new()
	_player.position = Vector3(0, 0.9, 0)
	add_child(_player)

	_rig = CameraRigNode.new()
	add_child(_rig)
	_rig.set_player(_player as Node3D)

	# Light so the recorded frame is visible.
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	add_child(light)


func _add_floor() -> void:
	add_child(Greybox.make_box("Floor", Vector3(0, -0.25, 0), Vector3(40, 0.5, 40),
		Greybox.KIND_COLORS.floor))


func _add_cover(pos: Vector3, size: Vector3) -> void:
	add_child(Greybox.make_box("Cover", pos, size, Greybox.KIND_COLORS.cover))


func _process(delta: float) -> void:
	if _auto:
		_auto_pilot(delta)


func _auto_pilot(delta: float) -> void:
	## Circle the player around the origin and toggle the camera every few seconds.
	_t += delta
	if fmod(_t, _toggle_every) < delta and _t > 0.1:
		_rig.rig.toggle_mode()
		print("DEMO: view now ", "TPV" if not _rig.rig.is_first_person() else "FPV",
			" yaw=", _rig.rig.yaw)
	# Walk in a circle, occasionally sprint and jump.
	var ang := _t * 0.6
	var dir := Vector2(cos(ang), sin(ang))
	var sprint := fmod(_t, 6.0) < 3.0
	var jump := fmod(_t, 4.0) < delta and fmod(_t, 4.0) >= 0.0
	_player.set_command(dir, sprint, false, jump)
