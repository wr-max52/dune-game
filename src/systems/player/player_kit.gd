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
var _jet: AudioStreamPlayer        ## issue #16: the jetpack's roar while it burns
var _hurt_flash: ColorRect
var _hurt_left := 0.0
## Issue #25: while the player is downed, the avatar falls as a ragdoll.
var ragdoll: Ragdoll
var _hidden_weapon: Node3D


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
	_jet = Sound.loop("jet_loop", self)
	if _jet != null:
		player.jet_started.connect(_jet.play)
		player.jet_stopped.connect(_jet.stop)
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
	a.bus = Sound.SFX_BUS
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
	if _ragdolled(dt):
		_hurt_left = maxf(0.0, _hurt_left - dt)
		_hurt_flash.color.a = _hurt_left * 1.2
		if _steps != null and _steps.playing:
			_steps.stop()
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


## Downed: the avatar goes limp (away from the last hit) and the weapon in hand is
## put away; getting up puts every joint back. True while the ragdoll owns the body.
func _ragdolled(dt: float) -> bool:
	var down: bool = player.get("is_downed") == true
	if not down:
		if ragdoll != null:
			ragdoll.stop()
			ragdoll = null
			if _hidden_weapon != null and is_instance_valid(_hidden_weapon):
				_hidden_weapon.visible = true
			_hidden_weapon = null
		return false
	if ragdoll == null:
		if not player.is_inside_tree():
			return false
		var cfg := Ragdoll.load_config()
		var kick := Ragdoll.kick_for(player.global_position, player.last_hit_from, player.last_hit_amount, cfg)
		ragdoll = Ragdoll.new(avatar.joints, cfg)
		ragdoll.start(player.velocity, kick, player.get_world_3d().direct_space_state, [player.get_rid()])
		var w := avatar.weapon_node(avatar.current)
		if w != null and avatar.drawn > 0.5 and w.visible:
			_hidden_weapon = w
			w.visible = false
	var moving := not ragdoll.asleep
	ragdoll.step(dt)
	if moving and avatar.skin != null:
		avatar.skin.sync(avatar.body)
	return true
