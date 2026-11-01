extends RefCounted
## Character controller math (M1).
##
## Pure, deterministic, headless-testable. Given a movement command and a world
## frame it returns the next velocity + pose. No Node3D, so the headless bot in
## M5 can drive the player exactly this way and we can prove movement with a unit
## test. The node (character_body.gd) wires this to a CharacterBody3D + animation.

enum Pose { STAND, CROUCH, JUMP }

# Speeds and accelerations (units/second).
# Issue #133: "sprint" in the command is the run (W held for the player, a
# guard's hurry), kept under its old name so every bot and trace still works.
# "dash" is the player's Shift sprint: faster, and only while dash_allowed
# (the player's stamina says so).
var walk_speed := 4.0
var sprint_speed := 7.0
var dash_speed := 10.0
var dash_allowed := true
var crouch_speed := 2.0
var ground_accel := 30.0
var gravity := 20.0

# Pose heights.
var stand_height := 1.8
var crouch_height := 1.0

# A movement command: direction in the player's local XZ plane (-1..1 each),
# plus sprint / crouch / jump booleans. "jump" is the press (one frame);
# "jump_held" is whether jump is still down (M13: the jetpack reads it).
var command := { "dir": Vector2(0.0, 0.0), "sprint": false, "crouch": false, "jump": false, "jump_held": false, "dash": false }

# M13: extra upward acceleration this frame (a jetpack's thrust), set by the node
# before step(). While it is on, upward speed is capped at max_rise (0 = no cap).
var lift := 0.0
var max_rise := 0.0
# Issue #274: the fastest the body falls, m/s (0 = no cap). Only the player sets it.
var max_fall := 0.0
# A shove on top of the walk (m/s, world XZ): the jetpack's kick as it lights.
# It fades by push_fade m/s every second and ends when you touch the ground.
var push := Vector3.ZERO
var push_fade := 5.0
# A knockback (two blades meeting): the push holds on the ground too, sliding you
# back until it has faded out.
var push_holds := false
var pose := Pose.STAND

## Sprint slide (issue #65). Off by default: guards share this controller and
## must never slide just because their brain says sprint + crouch. Only the
## player's kit turns it on.
var can_slide := false
var slide_boost := 1.35          ## start speed, times sprint_speed
var slide_duration := 0.75      ## seconds until the slide runs out
var slide_decel := 5.0          ## friction, m/s per second
var slide_steer := 1.2          ## rad/s the slide direction may turn toward input
var slide_sound_hint := false   ## true for one step when a slide starts (audio reads it)
var sliding := false
var slide_time := 0.0
var _slide_dir := Vector3.ZERO
var _slide_speed := 0.0
var _prev_crouch := false
## After a slide crouch is "spent": the pose is STAND even though the key is still
## down. The player has to let go and press again to crouch.
var _crouch_spent := false

var on_ground := true
var velocity := Vector3.ZERO
var body_pos := Vector3.ZERO

func set_command(dir: Vector2, sprint: bool, crouch: bool, jump: bool, jump_held: bool = false, dash: bool = false) -> void:
	command.dir = dir
	command.sprint = sprint
	command.crouch = crouch
	command.jump = jump
	command.jump_held = jump_held or jump
	command.dash = dash


## Issue #133: the Shift sprint is on this frame (moving, standing, stamina left).
## The weapons read it to lower the gun and hold the trigger.
func is_dashing() -> bool:
	return bool(command.dash) and dash_allowed and command.dir.length() > 0.1 \
		and not sliding and not crouching()


## True while the crouch pose applies: a slide, or crouch held and not spent.
func crouching() -> bool:
	return sliding or (bool(command.crouch) and not _crouch_spent)


## The room check says there is no space to stand: stay down like a normal crouch.
func force_crouch() -> void:
	_crouch_spent = false
	command.crouch = true


func is_sliding() -> bool:
	return sliding


## 0 at the start of a slide, 1 when it runs out (0 when not sliding).
func slide_progress() -> float:
	return clampf(slide_time / slide_duration, 0.0, 1.0) if sliding else 0.0


func _end_slide() -> void:
	sliding = false
	slide_time = 0.0
	_crouch_spent = bool(command.crouch)
	if pose == Pose.CROUCH:
		pose = Pose.STAND


## Start / run / end the slide for this frame. Returns true when it owns the
## horizontal velocity this frame.
func _tick_slide(delta: float, world_dir: Vector3) -> bool:
	slide_sound_hint = false
	if not bool(command.crouch):
		_crouch_spent = false
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	if not sliding:
		var pressed: bool = bool(command.crouch) and not _prev_crouch
		if can_slide and pressed and on_ground and (bool(command.sprint) or bool(command.dash)) and pose != Pose.JUMP \
				and horiz.length() > walk_speed:
			sliding = true
			slide_time = 0.0
			_slide_dir = horiz.normalized()
			_slide_speed = maxf(horiz.length(), sprint_speed * slide_boost)
			slide_sound_hint = true
		else:
			return false
	slide_time += delta
	if bool(command.jump) or not on_ground or slide_time >= slide_duration or _slide_speed < crouch_speed:
		var jumping: bool = bool(command.jump) and on_ground
		_end_slide()
		return jumping  # a jump out of a slide keeps its speed for this frame
	# Steer a little toward the input, never snap.
	if world_dir.length() > 0.1:
		var ang := _slide_dir.signed_angle_to(world_dir.normalized(), Vector3.UP)
		_slide_dir = _slide_dir.rotated(Vector3.UP, clampf(ang, -slide_steer * delta, slide_steer * delta))
	_slide_speed = maxf(0.0, _slide_speed - slide_decel * delta)
	velocity.x = _slide_dir.x * _slide_speed
	velocity.z = _slide_dir.z * _slide_speed
	return true


func current_speed() -> float:
	match pose:
		Pose.CROUCH:
			return crouch_speed
		Pose.STAND:
			if is_dashing():
				return dash_speed
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
	# Move current horizontal velocity toward the target (accel, not instant snap).
	if not _tick_slide(delta, world_dir):
		want = current_speed()  # a slide that just ended already stands
		var target_vel := world_dir * want
		# The push rides on top: steer the rest, then put the (faded) push back.
		var horiz := Vector3(velocity.x - push.x, 0.0, velocity.z - push.z)
		horiz = horiz.lerp(target_vel, minf(1.0, delta * ground_accel / maxf(want, 0.001)))
		push = push.move_toward(Vector3.ZERO, push_fade * delta)
		velocity.x = horiz.x + push.x
		velocity.z = horiz.z + push.z

	# Vertical.
	if on_ground and command.jump:
		velocity.y = sqrt(2.0 * gravity * 0.6)
		on_ground = false
		pose = Pose.JUMP
	elif not on_ground:
		velocity.y += (lift - gravity) * delta
		if lift > 0.0 and max_rise > 0.0:
			velocity.y = minf(velocity.y, max_rise)
		if max_fall > 0.0:
			velocity.y = maxf(velocity.y, -max_fall)

	# Ground contact.
	if body_pos.y + velocity.y * delta <= ground_y:
		velocity.y = 0.0
		body_pos.y = ground_y
		on_ground = true
		pose = Pose.CROUCH if crouching() else Pose.STAND
	else:
		body_pos.y += velocity.y * delta

	# Horizontal move.
	body_pos.x += velocity.x * delta
	body_pos.z += velocity.z * delta

	if push_holds and push == Vector3.ZERO:
		push_holds = false
	if on_ground and not push_holds:
		push = Vector3.ZERO     # the ground's grip takes over what is left
	# Pose bookkeeping when grounded and not jumping.
	if on_ground and pose != Pose.JUMP:
		pose = Pose.CROUCH if crouching() else Pose.STAND
	_prev_crouch = bool(command.crouch)


func body_height() -> float:
	return crouch_height if pose == Pose.CROUCH else stand_height
