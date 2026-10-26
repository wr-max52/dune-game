class_name PlayerKit
extends Node
## Puts a body and hands on the M1 player (M11): the animated smuggler avatar, the
## hand weapons, footsteps, and the hooks between them and the camera rig. The
## movement node (character_body.gd) and the camera math stay exactly as M1 built
## them; this node only reads them every frame.

const BodyAnimator := preload("res://src/systems/anim/body_animator.gd")
const LOOK_PATH := "res://content/look/hand_weapons.json"

var player: CharacterBody3D
var rig_node: Node3D
var avatar: PlayerAvatar
var weapons: PlayerWeapons
var _steps: AudioStreamPlayer
var _land: AudioStreamPlayer
var _jump: AudioStreamPlayer
var _hurt_flash: ColorRect
var _hurt_left := 0.0


## Build and attach. `bolts_into` is where bolts live (the scene root).
static func attach(p: CharacterBody3D, rig: Node3D, bolts_into: Node3D, mats: LookMaterials = null) -> PlayerKit:
	var k := PlayerKit.new()
	k.name = "PlayerKit"
	k.player = p
	k.rig_node = rig
	k.avatar = PlayerAvatar.new(mats)
	p.add_child(k.avatar)
	k.weapons = PlayerWeapons.new()
	k.add_child(k.weapons)
	k.weapons.setup(p, k.avatar, rig, bolts_into)
	p.add_child(k)
	return k


func _ready() -> void:
	if rig_node != null and rig_node.has_signal("view_changed"):
		rig_node.view_changed.connect(_on_view_changed)
		_on_view_changed(rig_node.rig.is_first_person())
	var sounds: Dictionary = CharacterKit._read_json(LOOK_PATH).get("sounds", {})
	_steps = _player_for(str(sounds.get("step", "")), -14.0)
	if _steps != null and _steps.stream is AudioStreamOggVorbis:
		(_steps.stream as AudioStreamOggVorbis).loop = true
	_land = _player_for(str(sounds.get("land", "")), -10.0)
	_jump = _player_for(str(sounds.get("jump", "")), -14.0)
	player.landed.connect(func(): if _land: _land.play())
	player.jumped.connect(func(): if _jump: _jump.play())
	player.hurt.connect(_on_hurt)
	var layer := CanvasLayer.new()
	layer.layer = 3
	add_child(layer)
	_hurt_flash = ColorRect.new()
	_hurt_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hurt_flash.color = Color(0.6, 0.85, 1.0, 0.0)
	_hurt_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hurt_flash)


func _player_for(path: String, db: float) -> AudioStreamPlayer:
	if path == "" or not ResourceLoader.exists(path):
		return null
	var a := AudioStreamPlayer.new()
	a.stream = load(path)
	a.volume_db = db
	add_child(a)
	return a


func _on_view_changed(first_person: bool) -> void:
	avatar.set_first_person(first_person)


func _on_hurt(_amount: float) -> void:
	_hurt_left = 0.25
	if rig_node != null:
		rig_node.shake(0.4)


func _physics_process(dt: float) -> void:
	if player == null:
		return
	var rig = rig_node.rig if rig_node != null else null
	var ctl = player.controller
	avatar.animate(dt, {
		"velocity": player.velocity,
		"grounded": player.is_on_floor(),
		"crouch": bool(ctl.command.crouch),
		"sprint": bool(ctl.command.sprint),
		"cam_yaw": rig.yaw if rig != null else player.rotation.y,
		"aim_pitch": rig.pitch if rig != null else 0.0,
		"upper": weapons.upper_mode(),
	})
	var moving := player.is_on_floor() and Vector2(player.velocity.x, player.velocity.z).length() > 0.6
	if _steps != null:
		if moving and not _steps.playing:
			_steps.play()
		elif not moving and _steps.playing:
			_steps.stop()
		_steps.pitch_scale = clampf(Vector2(player.velocity.x, player.velocity.z).length() / 4.0, 0.8, 1.5)
	_hurt_left = maxf(0.0, _hurt_left - dt)
	_hurt_flash.color.a = _hurt_left * 1.2
