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
signal hurt(amount: float)          ## something hit the player (bolts, blades)
signal jumped
signal landed
signal jet_started              ## M13: the jetpack lit
signal jet_stopped              ## M13: the jetpack cut out (released or empty)

## M11: while true (talking at the bar, a cutscene) the player stands still and
## ignores movement input. Gravity and collision still run.
var locked := false
## M14: true while the player is in a ship's seat. ShipPilot sets it (and disables
## this node); prompts on foot (the bar, gear) check it so E means "roll" up there.
var piloting := false
var hits_taken := 0
var _was_on_floor := true

@export var move_actions := PackedStringArray(["move_forward", "move_back", "move_left", "move_right"])
@export var jump_action := "jump"
@export var sprint_action := "sprint_mod"
@export var crouch_action := "crouch_act"

var controller := CharacterController.new()
var use_external_command := false

## M13: the attached jetpack (src/systems/player/jetpack.gd), or null. Gear
## (GearController) sets it; this node only feeds it jump-held + grounded and
## hands its thrust to the controller.
var jetpack = null

## Capsule dimensions. The body origin is at the feet (the camera's fpv_offset of
## 1.6 assumes that), so the capsule is lifted by half its height.
@export var capsule_radius := 0.4
@export var capsule_height := 1.8


func _ready() -> void:
	# Without a shape, move_and_slide() collides with nothing and the player walks
	# through walls. Build one unless the scene already supplies it.
	var has_shape := false
	for child in get_children():
		if child is CollisionShape3D:
			has_shape = true
			break
	if not has_shape:
		var shape := CapsuleShape3D.new()
		shape.radius = capsule_radius
		shape.height = capsule_height
		var col := CollisionShape3D.new()
		col.name = "Capsule"
		col.shape = shape
		col.position = Vector3(0.0, capsule_height * 0.5, 0.0)
		add_child(col)
	# Start the pure controller where the node actually is (it used to start at the
	# origin and teleport the player there on frame 1).
	controller.body_pos = global_position


func set_command(dir: Vector2, sprint: bool, crouch: bool, jump: bool, jump_held: bool = false) -> void:
	controller.set_command(dir, sprint, crouch, jump, jump_held)
	use_external_command = true


func clear_external_command() -> void:
	use_external_command = false


func _physics_process(delta: float) -> void:
	var yaw: float = -rotation.y
	if locked:
		controller.set_command(Vector2.ZERO, false, false, false)
	elif not use_external_command:
		var dir_in := Vector2(
			Input.get_axis(move_actions[2], move_actions[3]),
			-Input.get_axis(move_actions[0], move_actions[1])
		)
		controller.set_command(
			dir_in,
			Input.is_action_pressed(sprint_action),
			Input.is_action_pressed(crouch_action),  # held, not one frame
			Input.is_action_just_pressed(jump_action),
			Input.is_action_pressed(jump_action)     # M13: held, for the jetpack
		)

	# Physics is the authority on position and ground contact. The pure controller
	# only decides velocity and pose. Previously the node overwrote global_position
	# with the controller's own integration every frame, which threw away whatever
	# move_and_slide() resolved, so walls and floors never actually stopped anything.
	var grounded := is_on_floor()
	controller.body_pos = global_position
	controller.on_ground = grounded
	if grounded and controller.velocity.y < 0.0:
		controller.velocity.y = 0.0
	_step_jetpack(delta, grounded)
	# A ground height far below the world disables the controller's flat-floor
	# clamp, so landing is decided by collision instead of a hardcoded y = 0.
	controller.step(delta, yaw, -INF)

	velocity = controller.velocity
	move_and_slide()

	# Feed the resolved result back so the next step starts from reality.
	controller.body_pos = global_position
	controller.velocity = velocity
	controller.on_ground = is_on_floor()
	if controller.on_ground and controller.pose == CharacterController.Pose.JUMP:
		controller.pose = CharacterController.Pose.CROUCH if controller.command.crouch else CharacterController.Pose.STAND
	pose_changed.emit(controller.pose)
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor:
		landed.emit()
	elif not on_floor and _was_on_floor and velocity.y > 0.5:
		jumped.emit()
	_was_on_floor = on_floor


## M13: run the jetpack (if one is attached) and hand its thrust to the controller.
func _step_jetpack(delta: float, grounded: bool) -> void:
	if jetpack == null:
		controller.lift = 0.0
		controller.max_rise = 0.0
		return
	var was: bool = jetpack.thrusting
	var held: bool = bool(controller.command.jump_held) and not locked
	controller.lift = jetpack.step(delta, held, grounded)
	controller.max_rise = jetpack.max_rise()
	if jetpack.thrusting and not was:
		jet_started.emit()
	elif was and not jetpack.thrusting:
		jet_stopped.emit()


## Bolts and blades call this (see bolt.gd). The slice has no player death yet:
## hits are reported so the camera and HUD can react.
func apply_damage(amount: float) -> void:
	hits_taken += 1
	hurt.emit(amount)