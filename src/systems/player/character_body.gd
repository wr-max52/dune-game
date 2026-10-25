extends CharacterBody3D
## Player character node (M1).
##
## Two ways to drive it:
##   - Human: a real key/gamepad. When no command was pushed this frame, the node
##     reads input actions and steps the controller from them.
##   - Bot / demo: call set_command(...) to push a movement command for this frame.
##     That makes the command authoritative -- the input reader is skipped so the
##     bot is never clobbered by "no input". M5's bot uses exactly this path, so
##     human and bot share one movement implementation.

const CharacterController := preload("res://src/systems/player/character_controller.gd")

signal pose_changed(pose: int)

@export var move_actions := PackedStringArray(["move_forward", "move_back", "move_left", "move_right"])
@export var jump_action := "jump"
@export var sprint_action := "sprint_mod"
@export var crouch_action := "crouch_act"

var controller := CharacterController.new()
var use_external_command := false


func set_command(dir: Vector2, sprint: bool, crouch: bool, jump: bool) -> void:
	controller.set_command(dir, sprint, crouch, jump)
	use_external_command = true


func clear_external_command() -> void:
	use_external_command = false


func _physics_process(delta: float) -> void:
	var yaw: float = -rotation.y
	if not use_external_command:
		var dir_in := Vector2(
			Input.get_axis(move_actions[2], move_actions[3]),
			-Input.get_axis(move_actions[0], move_actions[1])
		)
		controller.set_command(
			dir_in,
			Input.is_action_pressed(sprint_action),
			Input.is_action_just_pressed(crouch_action),
			Input.is_action_just_pressed(jump_action)
		)
	controller.step(delta, yaw, 0.0)

	velocity = controller.velocity
	global_position = controller.body_pos
	move_and_slide()
	pose_changed.emit(controller.pose)