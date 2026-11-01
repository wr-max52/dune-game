class_name MerchantNPC
extends Node3D
## A merchant who stands at a stall and talks (issue #42: Skrugs). A CharacterKit
## body (any archetype and outfit, all red for Skrugs) with a procedural idle: he
## shifts his weight, follows the player with his head, nods and gestures while
## talking, and tilts his head while thinking. The words come from NpcBrain via the
## TalkSpot; this node only acts them out (act_named, speak_pulse). With no kit (the
## CI greybox) it is a capsule.

const BodyAnimator := preload("res://src/systems/anim/body_animator.gd")

var kit: CharacterKit
var body: Node3D
var joints: Dictionary = {}
var anim := BodyAnimator.new()
var look_at_target: Node3D
var mood_act := "idle"                ## "idle" | "thinking" | "talking"
var move_speed := 0.0                 ## m/s while someone walks him (the general leaving the pit): his legs walk
var _act_left := 0.0
var _talk_energy := 0.0
var _t := 0.0


func _init(character_kit: CharacterKit = null, archetype: String = "local", outfit: Dictionary = {}) -> void:
	kit = character_kit
	if kit != null:
		body = kit.build(archetype, "idle", outfit)
		add_child(body)
		joints = body.get_meta("joints", {})
	else:
		var mi := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.35
		cap.height = 1.8
		mi.mesh = cap
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("#a8322a")
		mi.material_override = m
		mi.position = Vector3(0, 0.9, 0)
		add_child(mi)
		body = mi


## TalkSpot's hook: "idle", "thinking", "talking" (anything else idles).
func act_named(n: String, seconds: float = 0.0) -> void:
	mood_act = n if n in ["thinking", "talking"] else "idle"
	_act_left = seconds


## Pulse while words stream in (drives the nods and gestures).
func speak_pulse() -> void:
	_talk_energy = 1.0
	mood_act = "talking"
	_act_left = 1.2


func _process(dt: float) -> void:
	_t += dt
	if _act_left > 0.0:
		_act_left -= dt
		if _act_left <= 0.0 and mood_act != "thinking":
			mood_act = "idle"
	_talk_energy = maxf(0.0, _talk_energy - dt * 2.5)
	if joints.is_empty():
		return
	var out := anim.step(dt, { "speed": move_speed, "grounded": true, "upper": BodyAnimator.UPPER_HOLSTER })
	for jn in out.joints:
		if joints.has(jn):
			(joints[jn] as Node3D).rotation_degrees = out.joints[jn]
	(joints.pelvis as Node3D).position.y = out.pelvis_y
	_upper()
	if body.has_meta("skin"):
		(body.get_meta("skin") as SkinnedBody).sync(body)


func _upper() -> void:
	var head := joints.get("head") as Node3D
	var neck := joints.get("neck") as Node3D
	var chest := joints.get("chest") as Node3D
	if head == null or neck == null or chest == null:
		return
	match mood_act:
		"thinking":
			head.rotation_degrees.x = -6.0
			head.rotation_degrees.z = 8.0 * sin(_t * 0.8)
		"talking":
			head.rotation_degrees.x = -2.0 + 6.0 * _talk_energy * sin(_t * 8.0)
	if look_at_target != null and is_instance_valid(look_at_target):
		var to := look_at_target.global_position + Vector3(0, 1.5, 0) - head.global_position
		var local := global_basis.inverse() * to
		if local.length() < 9.0:
			var yaw := clampf(rad_to_deg(atan2(local.x, local.z)), -60.0, 60.0)
			neck.rotation_degrees.y = yaw * 0.4
			head.rotation_degrees.y = yaw * 0.6
	if mood_act == "talking" and _talk_energy > 0.2:
		# Big salesman hands.
		kit.reach(body, "r", Vector3(-0.3, -0.02 + 0.1 * sin(_t * 3.2), 0.36 + 0.06 * sin(_t * 2.1)), Vector3(-0.6, -0.5, -0.4))
		kit.reach(body, "l", Vector3(0.3, -0.05 + 0.08 * sin(_t * 2.7 + 1.0), 0.32), Vector3(0.6, -0.5, -0.4))
	chest.rotation_degrees.x += 1.0 * sin(_t * 1.3)
