class_name BodyAnimator
extends RefCounted
## Procedural animation for the jointed CharacterKit body (M11). Pure math: given
## what the character is doing this frame it returns joint rotations, a pelvis
## height and (for weapons) chest-space hand/weapon targets. No nodes, so the state
## machine and the cycle are unit-tested headless (tests/test_body_animator.gut.gd).
##
## Why procedural and not imported clips: the characters are built from joints by
## CharacterKit (no skinned mesh), and the free CC0 clip libraries ship for a
## humanoid skeleton we do not have. Joint math keeps every character (player,
## bartender, troopers later) on one system, and every number is tunable here.
##
## Conventions (CharacterKit): the model faces +Z, its left is +X. Limbs hang along
## local -Y. Positive X rotation on a hip swings the leg BACK; positive on a knee
## bends the shin back; negative on an elbow bends the forearm forward.

enum State { LOCOMOTION, AIRBORNE, LAND }

## Upper body modes. FREE swings the arms; the rest are driven by weapons.
const UPPER_FREE := "free"
const UPPER_AIM := "aim"            ## a blaster: right hand forward, left hand supports
const UPPER_RIFLE := "rifle"
const UPPER_SWORD := "sword"        ## guard / swing / block come from SwordPoses
const UPPER_HOLSTER := "holster"    ## mid weapon swap: weapon_xf comes from the caller

const PELVIS_Y := 0.97
const WALK_SPEED := 4.0
const SPRINT_SPEED := 7.0

var state := State.LOCOMOTION
var phase := 0.0               ## gait phase, radians
var time := 0.0
var land_left := 0.0
var land_time := 0.18
var smoothing := 14.0          ## per second; higher = snappier joints
var pelvis_y := PELVIS_Y

var _cur: Dictionary = {}      ## joint -> Vector3 degrees (smoothed)
var _last_state := State.LOCOMOTION
var states_seen := {}          ## for tests/traces: every state name entered


## Inputs:
##   speed:       horizontal speed, m/s
##   move_local:  Vector2(x = to the model's left, y = forward), length <= 1
##   grounded:    bool;   vy: vertical velocity
##   crouch / sprint: bool
##   upper:       one of the UPPER_* modes
##   aim_pitch:   radians, + is up (aim modes bend the chest toward it)
##   twist:       degrees of chest yaw the caller adds (sword swings)
## Returns { joints: {name: Vector3 deg}, pelvis_y: float, state: String }
func step(dt: float, inp: Dictionary) -> Dictionary:
	time += dt
	var grounded: bool = inp.get("grounded", true)
	var vy: float = inp.get("vy", 0.0)
	var speed: float = inp.get("speed", 0.0)
	var crouch: bool = inp.get("crouch", false)

	# ---- state machine
	match state:
		State.LOCOMOTION:
			if not grounded:
				state = State.AIRBORNE
		State.AIRBORNE:
			if grounded:
				state = State.LAND
				land_left = land_time
		State.LAND:
			land_left -= dt
			if not grounded:
				state = State.AIRBORNE
			elif land_left <= 0.0:
				state = State.LOCOMOTION
	states_seen[state_name()] = true
	if state == State.AIRBORNE:
		states_seen["JUMP" if vy > 0.0 else "FALL"] = true

	# ---- gait phase: one full cycle per stride (two steps)
	var stride := lerpf(1.5, 2.4, clampf((speed - WALK_SPEED) / (SPRINT_SPEED - WALK_SPEED), 0.0, 1.0))
	if crouch:
		stride = 1.0
	if state == State.LOCOMOTION and speed > 0.05:
		phase = fmod(phase + TAU * speed / stride * dt, TAU)

	var target := _target(inp, speed, crouch, vy)
	var k := 1.0 - exp(-smoothing * dt)
	for j in target.joints:
		var v: Vector3 = target.joints[j]
		_cur[j] = (_cur.get(j, v) as Vector3).lerp(v, k)
	pelvis_y = lerpf(pelvis_y, target.pelvis_y, k)
	return { "joints": _cur.duplicate(), "pelvis_y": pelvis_y, "state": state_name() }


func state_name() -> String:
	return ["LOCOMOTION", "AIRBORNE", "LAND"][state]


## Every joint the animator owns, so leftovers from a previous pose never stick.
const JOINTS := ["pelvis", "spine", "chest", "neck", "head",
	"l_shoulder", "r_shoulder", "l_elbow", "r_elbow", "l_wrist", "r_wrist",
	"l_hip", "r_hip", "l_knee", "r_knee", "l_ankle", "r_ankle"]


func _target(inp: Dictionary, speed: float, crouch: bool, vy: float) -> Dictionary:
	var j := {}
	for n in JOINTS:
		j[n] = Vector3.ZERO
	var py := PELVIS_Y
	var s := sin(phase)
	var c := cos(phase)
	var walk01 := clampf(speed / WALK_SPEED, 0.0, 1.0)
	var sprint01 := clampf((speed - WALK_SPEED) / (SPRINT_SPEED - WALK_SPEED), 0.0, 1.0)
	var move: Vector2 = inp.get("move_local", Vector2(0, 1))
	if move.length() < 0.01:
		move = Vector2(0, 1)
	move = move.normalized()
	var fwd := move.y          # cos of the move angle in the body frame
	var side := move.x         # + = toward the model's left

	match state:
		State.LOCOMOTION:
			var hip_a := 30.0 * walk01 + 16.0 * sprint01
			var knee_a := 35.0 * walk01 + 40.0 * sprint01
			# Legs: swing along the move direction (backwards walking reverses it).
			j.l_hip = Vector3(-hip_a * s * fwd, 0, 16.0 * walk01 * s * side + 2.0)
			j.r_hip = Vector3(hip_a * s * fwd, 0, 16.0 * walk01 * s * side - 2.0)
			j.l_knee = Vector3(knee_a * maxf(0.0, c) + 6.0 * walk01, 0, 0)
			j.r_knee = Vector3(knee_a * maxf(0.0, -c) + 6.0 * walk01, 0, 0)
			j.l_ankle = Vector3(-0.35 * j.l_knee.x + 8.0 * walk01 * s * fwd, 0, 0)
			j.r_ankle = Vector3(-0.35 * j.r_knee.x - 8.0 * walk01 * s * fwd, 0, 0)
			# Hips bob twice per stride and counter-twist with the shoulders.
			py = PELVIS_Y - (0.025 + 0.03 * sprint01) * walk01 * s * s
			j.pelvis = Vector3(0, -6.0 * walk01 * s, 0)
			j.chest = Vector3(5.0 * walk01 + 10.0 * sprint01, 8.0 * walk01 * s, 0)
			j.head = Vector3(-4.0 * walk01 - 8.0 * sprint01, -2.0 * walk01 * s, 0)
			# Arms counter-swing; sprinting pumps with bent elbows.
			var arm_a := 22.0 * walk01 + 30.0 * sprint01
			j.l_shoulder = Vector3(arm_a * s, 0, 8.0)
			j.r_shoulder = Vector3(-arm_a * s, 0, -8.0)
			j.l_elbow = Vector3(-14.0 - 14.0 * walk01 - 60.0 * sprint01, 0, 0)
			j.r_elbow = Vector3(-14.0 - 14.0 * walk01 - 60.0 * sprint01, 0, 0)
			# Idle: breathe and settle.
			var idle := 1.0 - walk01
			j.chest.x += idle * 1.5 * sin(time * 1.7)
			j.l_shoulder.z += idle * 0.8 * sin(time * 1.7)
			j.r_shoulder.z -= idle * 0.8 * sin(time * 1.7)
			if crouch:
				j.l_hip.x += -55.0
				j.r_hip.x += -50.0
				j.l_knee.x += 90.0
				j.r_knee.x += 85.0
				j.l_ankle.x += -35.0
				j.r_ankle.x += -35.0
				j.chest.x += 14.0
				py = PELVIS_Y - 0.3
		State.AIRBORNE:
			var rising := vy > 0.0
			j.l_hip = Vector3(-35.0 if rising else -20.0, 0, 4)
			j.r_hip = Vector3(10.0 if rising else -8.0, 0, -4)
			j.l_knee = Vector3(55.0 if rising else 25.0, 0, 0)
			j.r_knee = Vector3(30.0 if rising else 20.0, 0, 0)
			j.l_shoulder = Vector3(-25.0, 0, 30.0)
			j.r_shoulder = Vector3(-15.0, 0, -30.0)
			j.l_elbow = Vector3(-35, 0, 0)
			j.r_elbow = Vector3(-35, 0, 0)
			j.chest = Vector3(8.0, 0, 0)
		State.LAND:
			var dip := clampf(land_left / land_time, 0.0, 1.0)
			j.l_hip = Vector3(-35.0 * dip, 0, 3)
			j.r_hip = Vector3(-30.0 * dip, 0, -3)
			j.l_knee = Vector3(60.0 * dip, 0, 0)
			j.r_knee = Vector3(55.0 * dip, 0, 0)
			j.l_ankle = Vector3(-25.0 * dip, 0, 0)
			j.r_ankle = Vector3(-25.0 * dip, 0, 0)
			j.chest = Vector3(12.0 * dip, 0, 0)
			j.l_shoulder = Vector3(0, 0, 20.0 * dip + 6.0)
			j.r_shoulder = Vector3(0, 0, -20.0 * dip - 6.0)
			py = PELVIS_Y - 0.18 * dip

	# ---- upper body overrides for weapons. Arms are placed by IK afterwards
	# (player_avatar.gd), so here we only shape the torso.
	var upper: String = inp.get("upper", UPPER_FREE)
	var pitch_deg := rad_to_deg(float(inp.get("aim_pitch", 0.0)))
	if upper != UPPER_FREE:
		# Stop the walk's shoulder twist so the weapon stays on the aim line.
		j.pelvis.y *= 0.3
		j.chest.y = 0.0
		j.head.y = 0.0
	match upper:
		UPPER_AIM, UPPER_RIFLE:
			j.chest.x = -pitch_deg * 0.55 + 4.0
			j.head.x = -pitch_deg * 0.35
			j.spine.y = -8.0 if upper == UPPER_AIM else -14.0
		UPPER_SWORD, UPPER_HOLSTER:
			j.chest.x = j.chest.x * 0.5 - pitch_deg * 0.3 + 6.0
			j.head.x = -pitch_deg * 0.3
	j.chest.y += float(inp.get("twist", 0.0))
	return { "joints": j, "pelvis_y": py }
