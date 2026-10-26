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
var nameplate_range := 0.0     ## metres: the name floats over them when the target is this close
var command := { "go_to": Vector3.INF, "face": Vector3.INF, "sprint": false, "crouch": false }

var perception: Perception
var locomotion
var nav: TownNav               ## where paths come from (null = cannot walk anywhere)
var target: Node3D             ## who the senses watch (the player)
var target_armed: Callable     ## -> bool; is the target holding a weapon out
var target_crouched: Callable  ## -> bool

var dead := false
var faction := ""              ## from the profile; bolts from the same faction do no harm
var last_hit_by: Node          ## who shot us last (null = unknown)

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
var _label: Label3D
var _nameplate: Label3D
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
		look_body = kit.build(str(soldier.get("archetype", "remnant_trooper")))
		look_body.name = "Look"
		add_child(look_body)
		joints = look_body.get_meta("joints")
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
	_speech.position.y = 2.35       # above the nameplate (2.05)
	_speech.pixel_size = 0.005
	_speech.font_size = 40
	_speech.outline_size = 10
	_speech.modulate = Color(1.0, 0.93, 0.78)
	_speech.visible = false
	add_child(_speech)
	_build_sounds()
	_nameplate = Label3D.new()
	_nameplate.name = "Nameplate"
	_nameplate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_nameplate.position.y = 2.05
	_nameplate.pixel_size = 0.0028
	_nameplate.outline_size = 8
	_nameplate.modulate = Color(0.96, 0.92, 0.84)
	_nameplate.visible = false
	add_child(_nameplate)


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
	if _nameplate != null:
		_nameplate.text = display_name
	return display_name


## True when the floating name is up: named, alive, and the target within range.
func nameplate_shown() -> bool:
	return _nameplate != null and _nameplate.visible


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
	NoiseEvents.emit(origin, float(weapon_cfg.get("noise_radius", 50.0)), "shot_guard")
	return true


## Advance the weapon without firing (cooldowns, reloads).
func hold_fire(dt: float) -> void:
	if weapon_actor != null and weapon_actor.weapon != null:
		weapon_actor.weapon.start_firing(dt, false)


func reloading() -> bool:
	return weapon_actor != null and weapon_actor.weapon != null and weapon_actor.weapon.get("_reloading") == true


## A line over the guard's head for a few seconds (barks; the HUD may also show it).
func say(text: String, seconds: float = 2.6, shout: bool = false) -> void:
	if _speech == null:
		return
	_speech.text = text
	_speech.visible = text != ""
	_speech_left = seconds
	if text == "":
		return
	# Under the words, helmet-radio chatter (no speech engine: the line is on screen).
	var v: Dictionary = sound_cfg().get("voice", {})
	var list: Array = v.get("shout" if shout else "calm", [])
	if list.is_empty():
		return
	var path := str(list[_rng_sfx.randi() % list.size()])
	if ResourceLoader.exists(path):
		play_sfx("voice", load(path), float(v.get("shout_db" if shout else "volume_db", -4.0)))


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
	var move := _walk(delta)
	_turn(delta, move)
	var dir := NpcLocomotion.world_to_command(move, -rotation.y)
	set_command(dir, bool(command.sprint), bool(command.crouch), false)
	super._physics_process(delta)
	if _last_pos != Vector3.INF:
		walked_m += NpcLocomotion._flat(global_position - _last_pos).length()
	_last_pos = global_position
	_animate(delta, move)
	_tick_steps()
	_debug_line()
	_update_nameplate()


func _walk(dt: float) -> Vector3:
	var goal: Vector3 = command.go_to
	if goal == Vector3.INF:
		if locomotion.has_path():
			locomotion.clear()
		return Vector3.ZERO
	if nav == null or not nav.is_ready:
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


func _sense(dt: float) -> void:
	var tpos := Vector3.INF
	# A player in a ship's seat is not someone on foot to watch.
	if target != null and is_instance_valid(target) and target.is_inside_tree() \
			and target.get("piloting") != true:
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
		"target_speed": Vector2(target.velocity.x, target.velocity.z).length() if tpos != Vector3.INF and "velocity" in target else 0.0,
	})
	if perception.noticed and not _was_noticed:
		noticed_target.emit()
	elif _was_noticed and not perception.noticed:
		lost_target.emit()
	_was_noticed = perception.noticed


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
	while n != null:
		if n == target:
			return true
		n = n.get_parent()
	return false


func target_chest_height() -> float:
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
	apply_damage(amount)
	hit_by.emit(shooter, amount)


## Bolts and blades call this (bolt.gd looks for apply_damage).
func apply_damage(amount: float) -> void:
	if dead:
		return
	hits_taken += 1
	_flinch = 1.0
	hurt.emit(amount)
	health.apply_damage(amount)
	if not dead:
		play_sfx("hurt")


func _on_death() -> void:
	dead = true
	stop()
	velocity = Vector3.ZERO
	# Out of the way: bolts, rays and the player pass through the body.
	collision_layer = 0
	collision_mask = 1          # still rests on the floor
	if _shape != null:
		_shape.set_deferred("disabled", true)
	play_sfx("death")
	var st: AudioStreamPlayer3D = _sfx.get("steps")
	if st != null:
		st.stop()
	died.emit()


func _fall(dt: float) -> void:
	_fall_t = minf(1.0, _fall_t + dt * 2.5)
	var look := get_node_or_null("Look") as Node3D
	if look != null:
		var k := _fall_t * _fall_t
		look.rotation.x = -PI * 0.5 * k
		look.position.y = (0.9 if kit == null else 0.0) * (1.0 - k) + 0.25 * k
	_debug_line()
	_update_nameplate()


# ------------------------------------------------------------------ look

func _animate(dt: float, move: Vector3) -> void:
	_flinch = maxf(0.0, _flinch - dt * 4.0)
	if kit == null or look_body == null:
		return
	var flat := Vector3(velocity.x, 0, velocity.z)
	var speed := flat.length()
	var local := Basis(Vector3.UP, rotation.y).inverse() * flat
	var move_local := Vector2(local.x, local.z) / maxf(speed, 0.001) if speed > 0.05 else Vector2(0, 1)
	var out: Dictionary = anim.step(dt, {
		"speed": speed, "move_local": move_local, "grounded": is_on_floor(), "vy": velocity.y,
		"crouch": bool(command.crouch), "sprint": bool(command.sprint), "upper": BodyAnimatorT.UPPER_RIFLE,
		"aim_pitch": _aim_pitch(),
	})
	for jn in out.joints:
		if joints.has(jn):
			(joints[jn] as Node3D).rotation_degrees = out.joints[jn]
	(joints.pelvis as Node3D).position.y = out.pelvis_y
	if _flinch > 0.0:
		(joints.chest as Node3D).rotation_degrees.x -= 14.0 * _flinch
	# Hands back on the rifle (CharacterKit put it in the chest at the "rifle" pose).
	if look_body.has_meta("weapon"):
		var w: Node3D = look_body.get_meta("weapon")
		var grips: Dictionary = w.get_meta("grips", {})
		if grips.has("r"):
			kit.reach(look_body, "r", w.transform * (grips.r as Vector3), Vector3(-0.5, -0.7, -0.5))
		if grips.has("l"):
			kit.reach(look_body, "l", w.transform * (grips.l as Vector3), Vector3(0.6, -0.7, -0.4))
	# Head follows what the senses have: the target while seen, else straight ahead.
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
func _update_nameplate() -> void:
	if _nameplate == null:
		return
	var show := display_name != "" and not dead and not show_debug and target != null \
		and nameplate_range > 0.0 and is_instance_valid(target) \
		and global_position.distance_to(target.global_position) <= nameplate_range
	_nameplate.visible = show


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
