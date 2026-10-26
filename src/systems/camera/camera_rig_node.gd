extends Node3D
## Camera rig node (M1). Owns a live Camera3D and drives it every frame from the
## pure camera_rig math. Toggling FPV<->TPV only recomputes the camera position
## for the SAME yaw/pitch, so aim is preserved.

const CameraRig := preload("res://src/systems/camera/camera_rig.gd")

@export var mouse_sensitivity := 0.0025
@export var toggle_action := "toggle_view"
var rig := CameraRig.new()
var _camera: Camera3D
var _player: Node3D


func _ready() -> void:
	_camera = Camera3D.new()
	_camera.current = true
	add_child(_camera)
	_camera.make_current()


func set_player(player: Node3D) -> void:
	_player = player


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		rig.add_yaw(-event.relative.x * mouse_sensitivity)
		rig.add_pitch(-event.relative.y * mouse_sensitivity)
	if event.is_action_pressed(toggle_action):
		rig.toggle_mode()
		print_verbose("CameraRig: view -> ", "TPV" if not rig.is_first_person() else "FPV")


func _process(_delta: float) -> void:
	if _player != null:
		# Absolute, not relative. rotate_y() re-added the yaw every frame and spun
		# the player forever after any mouse movement. The body reads -rotation.y
		# as its movement yaw, which lines up with the rig's look direction.
		_player.rotation.y = rig.yaw
		if _camera.is_inside_tree():
			_camera.global_transform = rig.camera_transform(_player.global_position)
