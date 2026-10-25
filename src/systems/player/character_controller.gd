extends RefCounted
## Character controller math (M1).
##
## Pure, deterministic, headless-testable. Given a movement command and a world
## frame it returns the next velocity + pose. No Node3D, so the headless bot in
## M5 can drive the player exactly this way and we can prove movement with a unit
## test. The node (character_body.gd) wires this to a CharacterBody3D + animation.

enum Pose { STAND, CROUCH, JUMP }

# Speeds and accelerations (units/second).
var walk_speed := 4.0
var sprint_speed := 7.0
var crouch_speed := 2.0
var ground_accel := 30.0
var gravity := 20.0

# Pose heights.
var stand_height := 1.8
var crouch_height := 1.0

# A movement command: direction in the player's local XZ plane (-1..1 each),
# plus sprint / crouch / jump booleans.
var command := { "dir": Vector2(0.0, 0.0), "sprint": false, "crouch": false, "jump": false }
var pose := Pose.STAND
var on_ground := true
var velocity := Vector3.ZERO
var body_pos := Vector3.ZERO

func set_command(dir: Vector2, sprint: bool, crouch: bool, jump: bool) -> void:
	command.dir = dir
	command.sprint = sprint
	command.crouch = crouch
	command.jump = jump


func current_speed() -> float:
	match pose:
		Pose.CROUCH:
			return crouch_speed
		Pose.STAND:
			return sprint_speed if command.sprint else walk_speed
	return walk_speed


## Integrate one frame. delta is seconds. yaw is the player's facing angle so we
## can turn the input. Gravity + jump are handled; a flat world is assumed here
## (ground at y=0), which the scene layer overrides via a "ground_y" hint.
func step(delta: float, yaw: float, ground_y: float = 0.0) -> void:
	var want := current_speed()
	# Map local input (x = strafe, y = forward) into world XZ using the yaw.
	var sin_y := sin(yaw)
	var cos_y := cos(yaw)
	var world_dir := Vector3(
		command.dir.x * cos_y - command.dir.y * sin_y,
		0.0,
		command.dir.x * sin_y + command.dir.y * cos_y
	)
	var target_vel := world_dir * want
	# Move current horizontal velocity toward the target (accel, not instant snap).
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	horiz = horiz.lerp(target_vel, minf(1.0, delta * ground_accel / maxf(current_speed(), 0.001)))
	velocity.x = horiz.x
	velocity.z = horiz.z

	# Vertical.
	if on_ground and command.jump:
		velocity.y = sqrt(2.0 * gravity * 0.6)
		on_ground = false
		pose = Pose.JUMP
	elif not on_ground:
		velocity.y -= gravity * delta

	# Ground contact.
	if body_pos.y + velocity.y * delta <= ground_y:
		velocity.y = 0.0
		body_pos.y = ground_y
		on_ground = true
		pose = Pose.CROUCH if command.crouch else Pose.STAND
	else:
		body_pos.y += velocity.y * delta

	# Horizontal move.
	body_pos.x += velocity.x * delta
	body_pos.z += velocity.z * delta

	# Pose bookkeeping when grounded and not jumping.
	if on_ground and pose != Pose.JUMP:
		pose = Pose.CROUCH if command.crouch else Pose.STAND


func body_height() -> float:
	return crouch_height if pose == Pose.CROUCH else stand_height
