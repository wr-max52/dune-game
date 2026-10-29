class_name NpcBody
extends "res://src/systems/player/character_body.gd"
## An NPC on foot: the player's own body node (CharacterController + collision
## capsule + move_and_slide) with a look, Health, Perception and path following
## bolted on. Same rule as the starfighters: an AI and a human move through one
## implementation, so a guard can never walk faster, climb higher or clip through
## something the player cannot.
##
## The fighter pattern: a brain (next push) writes `command`, this node carries it
## out. Until there is a brain, a body with no orders holds its post and faces
## the way it was placed, while its senses run and its head follows what it sees.
##
##   command.go_to   Vector3.INF = stay put; else walk there along the navmesh
##   command.face    Vector3.INF = face the way we walk (or the post); else face it
##   command.sprint  run instead of walk
##   command.crouch  crouch
##
## Every number comes from a soldier profile (content/core/soldiers/*.json).

const NpcLocomotion := preload("res://src/systems/ai/npc_locomotion.gd")
const BodyAnimatorT := preload("res://src/systems/anim/body_animator.gd")

signal died
signal hit_by(shooter: Node, amount: float)   ## after the damage lands (not for friendly fire)
signal noticed_target          ## awareness crossed the notice line
signal lost_target             ## noticed cleared again

## Show the floating debug line over every NPC (town_demo toggles it on F4).
static var show_debug := false

var profile: Dictionary = {}
var soldier_id := ""
var post_id := ""              ## the marker this NPC was placed at
var display_name := ""         ## issue #15: "Corporal Varo Kesh" (assign_name); "" until named
var nameplate_range := 0.0     ## metres from the profile's naming block; unused since issue #65 (no floating names)
var command := { "go_to": Vector3.INF, "face": Vector3.INF, "sprint": false, "crouch": false }

var perception: Perception
var locomotion
var nav: TownNav               ## where paths come from (null = cannot walk anywhere)
var target: Node3D             ## who the senses watch (the player)
var target_armed: Callable     ## -> bool; is the target holding a weapon out
var target_crouched: Callable  ## -> bool
## Issue #55: a garrison trooper also watches the target's speeder or ship while
## it is a threat in town (the vehicle's hostile_in_town()). Townsfolk do not.
var sees_vehicles := false
## Issue #96: a desert pack walks open ground with no navmesh: straight at its
## goal, along the ground (the ball's up), instead of standing still.
var free_walk := false

var dead := false
var faction := ""              ## from the profile; bolts from the same faction do no harm
var last_hit_by: Node          ## who shot us last (null = unknown)
var damage_usec := -1000000000         ## Time.get_ticks_usec() of the last accepted hit (hit markers read it)
## Issue #65: set by brief() from the brain: true while this NPC is fighting. With
## "has taken damage" it decides whether the health bar shows.
var hostile := false

## M15: the rifle. A brain sets aim_point and calls fire_at(); the body owns the
## weapon state (ammo, rate, reload) and spawns real bolts.
const WeaponActorT := preload("res://src/systems/combat/weapon_actor.gd")
var weapon_actor
var weapon_cfg: Dictionary = {}
var bolt_parent: Node3D        ## where bolts live (the scene root)
var aim_point := Vector3.INF   ## where the rifle points (INF = at ease)
var shots_fired := 0
var _speech: Label3D

## M15: what it sounds like (content/look/npc_sounds.json). Counts are for traces.
const SOUNDS_PATH := "res://content/look/npc_sounds.json"
static var _sound_cfg: Dictionary = {}
var sounds_played: Dictionary = {}     ## "rifle" | "voice" | "hurt" | "death" -> count
var steps_playing := false
var _sfx: Dictionary = {}              ## key -> AudioStreamPlayer3D
var _rng_sfx := RandomNumberGenerator.new()
var _speech_left := 0.0
var facing := 0.0              ## radians, rotation.y the body is turning toward
var post_pos := Vector3.ZERO
var post_facing := 0.0
var turn_rate := deg_to_rad(260.0)

## Look (null in the greybox: a plain capsule mesh stands in).
var kit: CharacterKit
var look_body: Node3D
var joints: Dictionary = {}
var anim = BodyAnimatorT.new()
## Issue #87: the rifle rests low across the body until there is something to aim
## at, comes up before the first shot and goes back down a moment after.
var carry := WeaponCarry.new()
var _rifle_aim_xf := Transform3D()     ## the rifle where CharacterKit's "rifle" pose shoulders it

## Numbers the traces and tests read.
var walked_m := 0.0
var repaths := 0
var path_failures := 0
var stuck_events := 0
var rays_cast := 0
var last_path_ok := true

var _repath_s := 1.5
var _repath_move := 1.5
var _repath_clock := 0.0
var _path_goal := Vector3.INF
var _last_pos := Vector3.INF
var _los_clear := false
var _was_noticed := false
var _flinch := 0.0
var _fall_t := 0.0
var _last_damage := 0.0
## Issue #25: the body falls as a ragdoll (null in the greybox, which still tips over).
var ragdoll: Ragdoll
var dropped_weapon: RigidBody3D
var _label: Label3D
var _bar_bg: MeshInstance3D     ## issue #65: the enemy health bar (dark back, red fill)
var _bar_fill: MeshInstance3D
var _bar_fill_frac := 1.0
var _shape: CollisionShape3D


## `materials` null = greybox (capsule mesh, no CharacterKit).
func setup(soldier: Dictionary, at: Vector3, yaw: float, materials: LookMaterials = null) -> void:
	profile = soldier
	soldier_id = str(soldier.get("id", ""))
	name = "Npc_" + (post_id if post_id != "" else soldier_id)
	position = at + Vector3(0, 0.05, 0)
	post_pos = at
	post_facing = yaw
	facing = yaw
	rotation.y = yaw
	controller.walk_speed = float(soldier.get("walk_speed", 3.2))
	controller.sprint_speed = float(soldier.get("sprint_speed", 6.2))
	turn_rate = deg_to_rad(float(soldier.get("turn_rate_deg", 260.0)))
	faction = str(soldier.get("faction", ""))
	# Health is the player body's (character_body.gd); guards do not regenerate.
	max_health = int(soldier.get("hp", 60))
	health = HealthT.new(max_health)
	regen_per_s = 0.0
	weapon_cfg = _weapon_config(soldier.get("weapon", {}))
	weapon_actor = WeaponActorT.new()
	weapon_actor.set_weapon(weapon_cfg)
	weapon_actor.configure_bolt = func(b):
		b.shooter = self
		b.sweep = true
		b.stylize = true
		b.color = Color.html(str(weapon_cfg.get("bolt_color", "#ff3a24")))
	perception = Perception.new(soldier.get("perception", {}))
	var navc: Dictionary = soldier.get("nav", {})
	locomotion = NpcLocomotion.new(navc)
	_repath_s = float(navc.get("repath_s", 1.5))
	_repath_move = float(navc.get("repath_move", 1.5))
	if materials != null:
		kit = CharacterKit.new(materials, -1000.0)
		look_body = kit.build(str(soldier.get("archetype", "remnant_trooper")), "", soldier.get("outfit", {}))
		# Issue #96: a smaller body (a desert pack's children) from the same model.
		if soldier.has("look_scale"):
			look_body.scale *= float(soldier.look_scale)
		look_body.name = "Look"
		add_child(look_body)
		joints = look_body.get_meta("joints")
		if look_body.has_meta("weapon"):
			_rifle_aim_xf = (look_body.get_meta("weapon") as Node3D).transform
	else:
		var mesh := CapsuleMesh.new()
		mesh.radius = 0.35
		mesh.height = 1.8
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.90, 0.90, 0.90)
		mesh.material = mat
		var mi := MeshInstance3D.new()
		mi.name = "Look"
		mi.mesh = mesh
		mi.position.y = 0.9
		add_child(mi)
	_label = Label3D.new()
	_label.name = "Debug"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = 2.65        # the F4 line, above the speech
	_label.pixel_size = 0.004
	_label.no_depth_test = true
	_label.visible = false
	add_child(_label)
	_speech = Label3D.new()
	_speech.name = "Speech"
	_speech.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_speech.position.y = 2.35       # above the health bar (2.05)
	_speech.pixel_size = 0.005
	_speech.font_size = 40
	_speech.outline_size = 10
	_speech.modulate = Color(1.0, 0.93, 0.78)
	_speech.visible = false
	add_child(_speech)
	_build_sounds()
	_build_health_bar()


static func sound_cfg() -> Dictionary:
	if _sound_cfg.is_empty():
		_sound_cfg = CharacterKit._read_json(SOUNDS_PATH)
	return _sound_cfg


func _player3d(key: String, stream_path: String, c: Dictionary) -> AudioStreamPlayer3D:
	var a := AudioStreamPlayer3D.new()
	a.name = "Sfx_" + key
	if stream_path != "" and ResourceLoader.exists(stream_path):
		a.stream = load(stream_path)
	a.volume_db = float(c.get("volume_db", 0.0))
	a.unit_size = float(c.get("unit_size", 6.0))
	a.max_distance = float(c.get("max_distance", 60.0))
	a.position.y = 1.4
	a.bus = Sound.SFX_BUS
	add_child(a)
	_sfx[key] = a
	return a


func _build_sounds() -> void:
	_rng_sfx.seed = hash(name)
	var cfg := sound_cfg()
	for key in ["rifle", "hurt", "death"]:
		var c: Dictionary = cfg.get(key, {})
		_player3d(key, str(c.get("stream", "")), c)
	var st: Dictionary = cfg.get("steps", {})
	var steps := _player3d("steps", "", st)
	steps.position.y = 0.1
	var sp := str(st.get("stream", ""))
	if sp != "" and ResourceLoader.exists(sp):
		var stream = (load(sp) as AudioStream).duplicate()
		if stream is AudioStreamOggVorbis:
			stream.loop = true
		steps.stream = stream
	_player3d("voice", "", cfg.get("voice", {}))


## Play a one-shot: the stream is set, a pitch picked from the config's range.
func play_sfx(key: String, stream: AudioStream = null, volume_db := INF) -> void:
	var a: AudioStreamPlayer3D = _sfx.get(key)
	if a == null:
		return
	if stream != null:
		a.stream = stream
	if a.stream == null:
		return
	var c: Dictionary = sound_cfg().get(key, {})
	var pr: Array = c.get("pitch", [1.0, 1.0])
	a.pitch_scale = _rng_sfx.randf_range(float(pr[0]), float(pr[1]))
	if volume_db != INF:
		a.volume_db = volume_db
	if a.is_inside_tree():
		a.play()
	sounds_played[key] = int(sounds_played.get(key, 0)) + 1


## Footsteps loop while walking or running on the ground; quieter crouched.
func _tick_steps() -> void:
	var a: AudioStreamPlayer3D = _sfx.get("steps")
	if a == null or a.stream == null:
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	var on := not dead and is_on_floor() and speed > 0.6
	var c: Dictionary = sound_cfg().get("steps", {})
	a.volume_db = float(c.get("crouch_db", -18.0)) if bool(command.crouch) else float(c.get("volume_db", -8.0))
	a.pitch_scale = clampf(speed / 3.2, 0.8, 1.5)
	if on and not a.playing and a.is_inside_tree():
		a.play()
	elif not on and a.playing:
		a.stop()
	steps_playing = on


## The profile's weapon block over the base weapon's data (content/core/weapons).
static func _weapon_config(w: Dictionary) -> Dictionary:
	var cfg: Dictionary = {}
	var base := str(w.get("base", ""))
	if base != "":
		var cc := preload("res://src/systems/dataload/core_content.gd").new()
		cc.load_from()
		cfg = cc.get_weapon(base).duplicate()
	for k in w:
		cfg[k] = w[k]
	return cfg


## Give this NPC its name, from the soldier profile's "naming" block (NameHooks,
## issue #15). `key` is stable for this NPC ("npc:port_town/trooper_gate_n"), so
## the same post always has the same person, across scenes and saves. Call after
## setup(), as soon as it spawns.
func assign_name(key: String) -> String:
	var naming: Dictionary = profile.get("naming", {})
	display_name = NameHooks.person(naming, key)
	nameplate_range = float(naming.get("nameplate_range", 0.0))
	return display_name


## Issue #65: names no longer float over heads (enemies show a health bar). The
## name is still data (debug line F4, dialogue, briefings). Always false; kept so
## callers and the names trace keep one place to ask.
func nameplate_shown() -> bool:
	return false


func _ready() -> void:
	super._ready()          # builds the capsule and a fresh Health(max_health)
	health.on_death.connect(_on_death)
	for c in get_children():
		if c is CollisionShape3D:
			_shape = c
	_last_pos = global_position
	if weapon_actor != null:
		weapon_actor.bolt_parent = bolt_parent if bolt_parent != null else get_parent() as Node3D


# ------------------------------------------------------------------ orders

func go_to(point: Vector3, sprint: bool = false) -> void:
	command.go_to = point
	command.sprint = sprint


func stop() -> void:
	command.go_to = Vector3.INF
	locomotion.clear()
	_path_goal = Vector3.INF


func face_point(point: Vector3) -> void:
	command.face = point


func clear_face() -> void:
	command.face = Vector3.INF


func is_moving() -> bool:
	return locomotion.has_path()


func arrived() -> bool:
	if free_walk and (nav == null or not nav.is_ready) and command.go_to != Vector3.INF:
		var d: Vector3 = tilt.inverse() * (command.go_to - global_position)
		return Vector2(d.x, d.z).length() < 1.0
	return command.go_to == Vector3.INF or (locomotion.arrived and _path_goal != Vector3.INF \
		and NpcLocomotion._flat(global_position - _path_goal).length() <= locomotion.arrive_radius + 0.25)


func forward() -> Vector3:
	return Vector3(sin(rotation.y), 0.0, cos(rotation.y))


func eye_position() -> Vector3:
	var h: float = perception.eye_height
	if bool(command.crouch):
		h = float(profile.get("perception", {}).get("eye_height_crouched", 0.95))
	return global_position + Vector3(0, h, 0)


## Where a bolt leaves the rifle: forward of the chest, toward the aim.
func muzzle_position() -> Vector3:
	var chest := eye_position() - Vector3(0, 0.25, 0)
	var to := (aim_point - chest) if aim_point != Vector3.INF else forward()
	to.y = clampf(to.y, -2.0, 2.0)
	return chest + to.normalized() * 0.75 + Vector3(0, 0.0, 0)


## Pull the trigger this frame at `point` (the brain calls it while firing). The
## weapon decides whether a bolt actually leaves (rate, ammo, reload). True on a shot.
func fire_at(point: Vector3, dt: float) -> bool:
	if dead or weapon_actor == null:
		return false
	aim_point = point
	var before: int = weapon_actor.shots_fired
	var origin := muzzle_position()
	if weapon_actor.bolt_parent == null:
		weapon_actor.bolt_parent = get_parent() as Node3D
	weapon_actor.fire_at(point, origin, dt, true)
	if weapon_actor.shots_fired == before:
		return false
	shots_fired += 1
	play_sfx("rifle")
	Sound.battle()           # issue #16: NPCs only ever shoot at the player
	NoiseEvents.emit(origin, float(weapon_cfg.get("noise_radius", 50.0)), "shot_guard")
	return true


## Advance the weapon without firing (cooldowns, reloads).
func hold_fire(dt: float) -> void:
	if weapon_actor != null and weapon_actor.weapon != null:
		weapon_actor.weapon.start_firing(dt, false)


func reloading() -> bool:
	return weapon_actor != null and weapon_actor.weapon != null and weapon_actor.weapon.get("_reloading") == true


# ------------------------------------------------------------------ the brain (M15)

## The fighter pattern, the half before update(): what this body knows, written
## into its GuardBrain. `at` / `vel` are the target's feet and velocity (INF when
## there is nobody to fight). A calm brain turns toward footsteps or a shot it
## just heard. Garrison and Townsfolk both run their bodies through this.
func brief(b: GuardBrain, at: Vector3, vel: Vector3) -> void:
	b.pos = global_position
	b.facing = rotation.y
	b.hp_frac = float(health.hp) / maxf(1.0, float(max_health))
	hostile = b.state == GuardBrain.State.COMBAT
	b.arrived = arrived()
	b.visible = perception.visible
	b.target_pos = at
	b.target_vel = vel
	b.target_chest = target_chest_height()
	b.last_seen = perception.last_seen_pos
	b.heard_pos = perception.heard_pos
	b.reloading = reloading()
	if perception.heard and not perception.visible:
		b.investigate(perception.heard_pos)


## The half after update(): the brain's outputs onto the body (walk, face, crouch,
## aim, fire). Cover and barks stay with the director.
func carry_out(b: GuardBrain, dt: float) -> void:
	if b.go_to == Vector3.INF:
		if command.go_to != Vector3.INF:
			stop()
	else:
		go_to(b.go_to, b.sprint)
	command.sprint = b.sprint
	command.crouch = b.crouch
	if b.face != Vector3.INF:
		face_point(b.face)
	else:
		clear_face()
	aim_point = b.aim
	# Issue #87: the rifle has to come up before a bolt leaves it.
	if b.fire and b.aim != Vector3.INF and carry.on_target():
		if fire_at(b.aim, dt):
			b.on_shot()
	else:
		hold_fire(dt)


## A line over the guard's head for a few seconds (barks; the HUD may also show it).
func say(text: String, seconds: float = 2.6, shout: bool = false) -> void:
	if _speech == null:
		return
	_speech.text = text
	_speech.visible = text != ""
	_speech_left = seconds
	if text.strip_edges() == "":
		return
	var stable_id := post_id if post_id != "" else display_name
	if stable_id == "":
		stable_id = soldier_id
	var voice_profile := NpcVoice.profile_for_npc(stable_id, profile)
	var mood := str(profile.get("voice_mood", ""))
	if mood == "":
		mood = "angry" if hostile else ("wary" if faction == "imperial_remnant" else "warm")
	NpcVoice.speak(text, voice_profile, mood, self, shout)


func speaking() -> String:
	return _speech.text if _speech != null and _speech.visible else ""


# ------------------------------------------------------------------ per frame

func _physics_process(delta: float) -> void:
	if dead:
		_fall(delta)
		return
	_sense(delta)
	if _speech_left > 0.0:
		_speech_left -= delta
		if _speech_left <= 0.0:
			_speech.visible = false
	carry.step(delta, aim_point != Vector3.INF)
	var move := _walk(delta)
	_turn(delta, move)
	var dir := NpcLocomotion.world_to_command(move, -rotation.y)
	set_command(dir, bool(command.sprint), bool(command.crouch), false)
	super._physics_process(delta)
	_stand_on_ground()
	if _last_pos != Vector3.INF:
		walked_m += NpcLocomotion._flat(global_position - _last_pos).length()
	_last_pos = global_position
	_animate_lod(delta, move)
	_tick_steps()
	_debug_line()
	_update_health_bar()


## Render smoothing: draw the look at the body's origin between the last two physics
## ticks (the body steps at 60 Hz; the screen may not). Position only: the facing is
## set in physics and the look's basis is the ground tilt. Skipped headless, when
## hidden, when dead (the ragdoll owns the look) and out beyond ANIM_FAR.
func _process(_delta: float) -> void:
	if look_body == null or not is_instance_valid(look_body) or not smoothing_active():
		return
	if _look_rest == Vector3.INF:
		_look_rest = look_body.position
	if dead or _anim_dist > ANIM_FAR or not is_visible_in_tree():
		if look_body.position != _look_rest:
			look_body.position = _look_rest
		return
	look_body.position = _look_rest + local_offset(global_basis, render_origin(), global_position)


func _walk(dt: float) -> Vector3:
	var goal: Vector3 = command.go_to
	if goal == Vector3.INF:
		if locomotion.has_path():
			locomotion.clear()
		return Vector3.ZERO
	if nav == null or not nav.is_ready:
		if free_walk:
			return _free_walk(goal)
		return Vector3.ZERO
	_repath_clock -= dt
	var goal_moved := _path_goal == Vector3.INF or goal.distance_to(_path_goal) > _repath_move
	if goal_moved or (locomotion.has_path() and _repath_clock <= 0.0):
		_repath(goal)
	var out: Dictionary = locomotion.update(dt, global_position, Vector2(velocity.x, velocity.z).length())
	if out.stuck:
		stuck_events += 1
		_repath(goal)
	return (out.move as Vector3) * float(out.speed)


## Issue #96: straight at `goal` across open ground, in the body's own (tilted)
## frame, so it walks along the ball like the player does.
func _free_walk(goal: Vector3) -> Vector3:
	var d := goal - global_position
	var local := tilt.inverse() * d
	local.y = 0.0
	if local.length() < 0.8:
		return Vector3.ZERO
	return local.normalized() * clampf(local.length() / 2.0, 0.35, 1.0)


func _repath(goal: Vector3) -> void:
	var p := nav.path(global_position, goal)
	repaths += 1
	_repath_clock = _repath_s
	_path_goal = goal
	last_path_ok = p.size() >= 2 and NpcLocomotion._flat(p[p.size() - 1] - goal).length() < 1.5
	if p.size() < 2:
		path_failures += 1
		locomotion.clear()
		return
	if not last_path_ok:
		path_failures += 1      # walk as close as the mesh allows, but say so
	locomotion.set_path(p)


## Issue #77: on the home planet's ball the body turns only by its facing (yaw),
## so stand the look along the ground's up (the body's tilt) or, far round the
## curve, it walks along lying down.
func _stand_on_ground() -> void:
	if look_body == null or not is_instance_valid(look_body):
		return
	var yaw := Basis(Vector3.UP, rotation.y)
	look_body.basis = Basis.IDENTITY if tilt == Basis.IDENTITY else yaw.inverse() * tilt * yaw


func _turn(dt: float, move: Vector3) -> void:
	var want := facing
	if command.face != Vector3.INF:
		want = NpcLocomotion.facing_toward(global_position, command.face)
	elif move.length() > 0.05:
		want = atan2(move.x, move.z)
	elif command.go_to == Vector3.INF:
		want = post_facing if global_position.distance_to(post_pos) < 1.5 else facing
	facing = NpcLocomotion.approach_angle(rotation.y, want, turn_rate * dt)
	rotation.y = facing


var _was_crouched := false


func _sense(dt: float) -> void:
	# Standing up from cover: the last look was from behind it. Look again now.
	if _was_crouched and not bool(command.crouch):
		perception.force_ray()
	_was_crouched = bool(command.crouch)
	var tpos := Vector3.INF
	# A player in a ship's seat is not someone on foot to watch; a trooper still
	# watches the speeder or ship they are in while it is a threat in town.
	if target != null and is_instance_valid(target) and target.is_inside_tree() \
			and (target.get("piloting") != true or hostile_vehicle() != null):
		tpos = target.global_position
	var crouched: bool = target_crouched.call() if target_crouched.is_valid() else false
	var armed: bool = target_armed.call() if target_armed.is_valid() else false
	perception.cone_update(global_position, forward(), tpos, crouched)
	if perception.wants_ray(dt):
		_los_clear = _ray_clear(tpos)
		rays_cast += 1
	elif not perception.in_cone:
		_los_clear = false
	perception.update(dt, {
		"self_pos": global_position, "forward": forward(), "target_pos": tpos,
		"crouched": crouched, "armed": armed, "los_clear": _los_clear,
		"target_speed": _target_speed() if tpos != Vector3.INF else 0.0,
	})
	if perception.noticed and not _was_noticed:
		noticed_target.emit()
	elif _was_noticed and not perception.noticed:
		lost_target.emit()
	_was_noticed = perception.noticed


## Issue #55: the vehicle the target is in, if this trooper should treat it as a
## threat right now; null otherwise.
func hostile_vehicle() -> Node:
	if not sees_vehicles or target == null or not is_instance_valid(target):
		return null
	var v = target.get("vehicle")
	if v == null or not is_instance_valid(v) or not v.hostile_in_town():
		return null
	return v


func _target_speed() -> float:
	var v := hostile_vehicle()
	var vel: Vector3 = v.threat_velocity() if v != null else (target.velocity if "velocity" in target else Vector3.ZERO)
	return Vector2(vel.x, vel.z).length()


## Eye to the target's chest. Clear if nothing but the target is in the way.
## A crouched target's chest is lower, so waist-high cover really hides it.
func _ray_clear(tpos: Vector3) -> bool:
	if tpos == Vector3.INF or not is_inside_tree():
		return false
	var to := tpos + Vector3(0, target_chest_height(), 0)
	var q := PhysicsRayQueryParameters3D.create(eye_position(), to)
	q.exclude = [get_rid()]
	q.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return true
	var n: Node = hit.collider
	var v := hostile_vehicle()
	var hull: Node = v.hull_body() if v != null else null
	while n != null:
		if n == target or (hull != null and n == hull):
			return true
		n = n.get_parent()
	return false


func target_chest_height() -> float:
	if hostile_vehicle() != null:
		return 0.0                # aim at the hull, not a rider's chest above it
	var crouched: bool = target_crouched.call() if target_crouched.is_valid() else false
	if crouched:
		return float(profile.get("perception", {}).get("target_chest_crouched", 0.75))
	return perception.target_chest


# ------------------------------------------------------------------ damage

## Bolts call this when they know who fired them. Same-faction bolts do nothing
## (guards do not shoot each other); anything else is a real hit.
func apply_damage_from(amount: float, shooter: Node) -> void:
	if dead:
		return
	if shooter is NpcBody and (shooter as NpcBody).faction == faction and faction != "":
		return
	last_hit_by = shooter
	if shooter is Node3D and is_instance_valid(shooter):
		last_hit_from = (shooter as Node3D).global_position
	apply_damage(amount)
	hit_by.emit(shooter, amount)


## Bolts and blades call this (bolt.gd looks for apply_damage).
func apply_damage(amount: float) -> void:
	if dead:
		return
	hits_taken += 1
	damage_usec = Time.get_ticks_usec()
	_last_damage = amount
	_flinch = 1.0
	hurt.emit(amount)
	health.apply_damage(amount)
	if not dead:
		play_sfx("hurt")


func _on_death() -> void:
	dead = true
	stop()
	var was_moving := velocity
	velocity = Vector3.ZERO
	# Out of the way: bolts, rays and the player pass through the body.
	collision_layer = 0
	collision_mask = 1          # still rests on the floor
	if _shape != null:
		_shape.set_deferred("disabled", true)
	play_sfx("death")
	_go_limp(was_moving)
	var st: AudioStreamPlayer3D = _sfx.get("steps")
	if st != null:
		st.stop()
	died.emit()


## Issue #25: let the look fall as a ragdoll, pushed away from whoever hit us last,
## and throw the rifle out of its hands.
func _go_limp(was_moving: Vector3) -> void:
	if look_body == null or joints.is_empty() or not is_inside_tree():
		return
	var cfg := Ragdoll.load_config()
	var kick := Ragdoll.kick_for(global_position, last_hit_from, _last_damage, cfg)
	ragdoll = Ragdoll.new(joints, cfg)
	ragdoll.start(was_moving, kick, get_world_3d().direct_space_state, [get_rid()])
	if look_body.has_meta("weapon"):
		var w: Node3D = look_body.get_meta("weapon")
		look_body.remove_meta("weapon")
		dropped_weapon = Ragdoll.drop(w, get_parent() as Node3D, was_moving + kick * 0.6, cfg)


func _fall(dt: float) -> void:
	if ragdoll != null:
		var moving := not ragdoll.asleep
		ragdoll.step(dt)
		if moving and look_body.has_meta("skin"):
			(look_body.get_meta("skin") as SkinnedBody).sync(look_body)
		_debug_line()
		_update_health_bar()
		return
	_fall_t = minf(1.0, _fall_t + dt * 2.5)
	var look := get_node_or_null("Look") as Node3D
	if look != null:
		var k := _fall_t * _fall_t
		look.rotation.x = -PI * 0.5 * k
		look.position.y = (0.9 if kit == null else 0.0) * (1.0 - k) + 0.25 * k
	_debug_line()
	_update_health_bar()


# ------------------------------------------------------------------ look

## Animation level of detail: a rigged body is the most expensive thing an NPC
## does each frame, and nobody sees a trooper across town (or from a ship 8 km
## up). Full rate near the player, a quarter rate past anim_near, none past
## anim_far. Gameplay (movement, senses, firing) always runs at full rate.
const ANIM_NEAR := 40.0
const ANIM_FAR := 150.0
var anim_frames := 0           ## how many times the body was actually posed (tests)
var _anim_acc := 0.0
var _anim_tick := 0
var _anim_dist := 0.0          ## distance to the target at the last tick (render smoothing LOD)
var _look_rest := Vector3.INF  ## look_body's rest position, noted before the first offset


func _animate_lod(dt: float, move: Vector3) -> void:
	if bool(profile.get("dance_loop", false)):
		_anim_dist = 0.0
		_animate(dt, move)
		anim_frames += 1
		return
	var d := 0.0
	if target != null and is_instance_valid(target):
		d = global_position.distance_to(target.global_position)
	_anim_dist = d
	if d > ANIM_FAR:
		_anim_acc = 0.0
		return
	_anim_acc += dt
	_anim_tick += 1
	if d > ANIM_NEAR and _anim_tick % 4 != 0:
		return
	_animate(_anim_acc, move)
	_anim_acc = 0.0
	anim_frames += 1


func _animate(dt: float, move: Vector3) -> void:
	_flinch = maxf(0.0, _flinch - dt * 4.0)
	if kit == null or look_body == null:
		return
	var v := tilt.inverse() * velocity      # in the ground's frame (issue #77)
	var flat := Vector3(v.x, 0, v.z)
	var speed := flat.length()
	var local := Basis(Vector3.UP, rotation.y).inverse() * flat
	var move_local := Vector2(local.x, local.z) / maxf(speed, 0.001) if speed > 0.05 else Vector2(0, 1)
	var out: Dictionary = anim.step(dt, {
		"speed": speed, "move_local": move_local, "grounded": is_on_floor(), "vy": v.y,
		"crouch": bool(command.crouch), "sprint": bool(command.sprint), "upper": BodyAnimatorT.UPPER_RIFLE,
		"aim_pitch": _aim_pitch(), "ready": carry.eased(),
		"dance": bool(profile.get("dance_loop", false)),
	})
	if bool(profile.get("dance_loop", false)):
		rotation.y = post_facing + float(out.get("dance_yaw", 0.0))
	for jn in out.joints:
		if joints.has(jn):
			(joints[jn] as Node3D).rotation_degrees = out.joints[jn]
	(joints.pelvis as Node3D).position.y = out.pelvis_y
	(joints.pelvis as Node3D).position.x = out.pelvis_x
	if _flinch > 0.0:
		(joints.chest as Node3D).rotation_degrees.x -= 14.0 * _flinch
	# Hands back on the rifle: shouldered at CharacterKit's "rifle" pose when aiming,
	# slung low across the body at rest (issue #87).
	if look_body.has_meta("weapon"):
		var w: Node3D = look_body.get_meta("weapon")
		var grips: Dictionary = w.get_meta("grips", {})
		var kind := str(w.get_meta("carry", "rifle"))      # issue #76: the marked officer's pistol
		w.transform = WeaponCarry.blend(WeaponCarry.rest_xf(kind, grips.get("r", Vector3.ZERO)), _rifle_aim_xf, carry.eased())
		if grips.has("r"):
			kit.reach(look_body, "r", w.transform * (grips.r as Vector3), Vector3(-0.5, -0.7, -0.5))
		if grips.has("l"):
			kit.reach(look_body, "l", w.transform * (grips.l as Vector3), Vector3(0.6, -0.7, -0.4))
	# Head follows what the senses have: the target while seen, else straight ahead.
	if not bool(profile.get("dance_loop", false)):
		var look_at := Vector3.INF
		if perception.visible:
			look_at = target.global_position + Vector3(0, 1.5, 0)
		elif perception.heard and perception.heard_pos != Vector3.INF:
			look_at = perception.heard_pos
		var yaw := 0.0
		if look_at != Vector3.INF:
			var l := global_basis.inverse() * (look_at - eye_position())
			yaw = clampf(rad_to_deg(atan2(l.x, l.z)), -70.0, 70.0)
		(joints.neck as Node3D).rotation_degrees.y = yaw * 0.4
		(joints.head as Node3D).rotation_degrees.y = yaw * 0.6
	# A rigged model (SkinnedBody, characters.json "model") follows the joints only
	# when told to, after they have moved this frame.
	if look_body.has_meta("skin"):
		(look_body.get_meta("skin") as SkinnedBody).sync(look_body)


## Radians up (+) or down toward the aim point, for the chest bend.
func _aim_pitch() -> float:
	if aim_point == Vector3.INF:
		return -0.25
	var to := aim_point - eye_position()
	return atan2(to.y, Vector2(to.x, to.z).length())
## Issue #65: a billboarded bar over enemies. Enemy = fighting right now (hostile,
## from the brain) or hurt (it only loses hp to the player; same-faction fire is
## ignored). Calm and unhurt townsfolk and guards show nothing. Hidden when dead
## or farther than HEALTH_BAR_RANGE.
const HEALTH_BAR_RANGE := 40.0
const BAR_W := 0.7
const BAR_H := 0.07

func _build_health_bar() -> void:
	_bar_bg = _bar_quad(Color(0.05, 0.04, 0.04), 0)
	_bar_fill = _bar_quad(Color(0.9, 0.18, 0.1), 1)
	_bar_bg.name = "HealthBarBack"
	_bar_fill.name = "HealthBarFill"
	for q in [_bar_bg, _bar_fill]:
		q.position.y = 2.05
		q.visible = false
		add_child(q)


## Unshaded billboard quad. Drawn through walls off (depth tested), fill on top of back.
func _bar_quad(col: Color, priority: int) -> MeshInstance3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = col
	m.render_priority = priority
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var q := QuadMesh.new()
	q.size = Vector2(BAR_W, BAR_H)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func health_bar_fill() -> float:
	return clampf(float(health.hp) / maxf(1.0, float(health.max_hp)), 0.0, 1.0)


func health_bar_shown() -> bool:
	return _bar_bg != null and _bar_bg.visible


func _update_health_bar() -> void:
	if _bar_bg == null:
		return
	var hurt: bool = health.hp < health.max_hp
	var near: bool = target != null and is_instance_valid(target) \
		and global_position.distance_to(target.global_position) <= HEALTH_BAR_RANGE
	var show: bool = not dead and (hostile or hurt) and near
	_bar_bg.visible = show
	_bar_fill.visible = show
	if not show:
		return
	var f := health_bar_fill()
	if is_equal_approx(f, _bar_fill_frac):
		return
	_bar_fill_frac = f
	# Shrink the fill toward the left edge: size follows hp, centre shifts to keep
	# the left edge fixed. Billboarding works in view space, so the offset rotates with it.
	var fm := _bar_fill.mesh as QuadMesh
	fm.size = Vector2(maxf(0.0001, BAR_W * f), BAR_H * 0.7)
	fm.center_offset = Vector3(-BAR_W * (1.0 - f) * 0.5, 0.0, 0.002)


func debug_text() -> String:
	var who := ("%s (%s)" % [display_name, post_id]) if display_name != "" else post_id
	if dead:
		return "%s  DEAD" % who
	var p := perception
	var goal := "post" if command.go_to == Vector3.INF else ("walk" if is_moving() else "there")
	return "%s  hp %d  %s\nsee %s  aware %.2f%s%s" % [
		who, health.hp, goal, "yes" if p.visible else ("cone" if p.in_cone else "no"),
		p.awareness, "  NOTICED" if p.noticed else "", "  heard " + p.heard_kind if p.since_heard < 2.0 else ""]


func _debug_line() -> void:
	if _label == null:
		return
	_label.visible = show_debug
	if show_debug:
		_label.text = debug_text()
