class_name PlanetBeast
extends StaticBody3D
## A planet's beast (issue #220's purple blob, made the beast): a big purple blob
## that rolls about the desert. Every planet may have one, named in its own file
## (content/core/planets/<id>.json, a "beast" block: name, home, what the locals
## say of it); the numbers every beast shares are content/core/hazards/beast.json,
## and the planet's block may override any of them.
##
##   wander   it has nowhere to be: its heading drifts at random and its pace
##            changes now and then, with no pull toward or away from the town; only
##            a loose leash round its own home spot turns it back if it strays
##   touch    dead on the spot, whatever your health (on foot, or a speeder into it)
##   hurt     it has hp (1000) and takes bolts and blades like anything else. Hurt
##            by the player, it chases them, faster than a run, until they are
##            chase_give_up_m (1 km) away or dead, then goes back to wandering
##   dead     it sinks into a puddle and stays dead: WorldState flag
##            beast_slain_<planet id>, so it is not built again and the locals know
##
## Now and then it farts: a sound, a puff and a squash.
##
## It rides the ground (WorldGround: the home planet's ball), moved here rather
## than by physics. Its ball is solid to bolts and blades (layer 4, "enemies") but
## nothing collides with it: touching it is what kills.

signal killed_player
signal farted
signal provoked
signal gave_up
signal slain

const DATA := "res://content/core/hazards/beast.json"
const LAYER_ENEMIES := 1 << 3

var demo                              ## town_demo.gd
var ground: WorldGround
var player: CharacterBody3D
var planet_id := ""
var cfg: Dictionary = {}              ## the species defaults with the planet's block laid over
var beast_name := "the beast"
var radius := 3.6
var hp := 1000.0
var max_hp := 1000.0
var dead := false
var chasing := false
var home := Vector3.ZERO
var heading := Vector3.FORWARD        ## along the ground
var speed := 2.0
var kills := 0
var farts := 0
var hits_taken := 0
var travelled := 0.0                  ## metres rolled (traces)
var _rng := RandomNumberGenerator.new()
var _ball: Node3D                     ## the rolling, wobbling body
var _mat: StandardMaterial3D
var _shape: CollisionShape3D
var _speed_left := 0.0
var _fart_left := 10.0
var _squash := 0.0
var _t := 0.0
var _wake_left := -1.0
var _sfx: AudioStreamPlayer3D


static func defaults() -> Dictionary:
	var f := FileAccess.open(DATA, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f != null else null
	return d if d is Dictionary else {}


## The planet's beast (a built planet, PlanetGen.build): the defaults with its
## "beast" block laid over, or {} if it has none.
static func config(planet: Dictionary) -> Dictionary:
	var own: Dictionary = planet.get("beast", {})
	if own.is_empty():
		return {}
	var c := defaults()
	for k in own:
		if k == "lines" and c.get("lines") is Dictionary:
			var l: Dictionary = (c.lines as Dictionary).duplicate()
			l.merge(own.lines, true)
			c.lines = l
		else:
			c[k] = own[k]
	return c


static func slain_flag(id: String) -> String:
	return "beast_slain_" + id


static func is_slain(id: String) -> bool:
	return WorldState.has_flag(slain_flag(id))


## Whether the planet has a beast still alive to build.
static func lives_on(planet: Dictionary) -> bool:
	return not config(planet).is_empty() and not is_slain(str(planet.get("id", "")))


## What the locals say of the planet's beast (its "lore", or "lore_slain" once it
## is dead), [] if it has none.
static func lore(planet: Dictionary) -> Array:
	var c := config(planet)
	if c.is_empty():
		return []
	var key := "lore_slain" if is_slain(str(planet.get("id", ""))) else "lore"
	return c.get(key, c.get("lore", []))


## One line for an AI character's briefing: the beast, by name, and what is said of it.
static func brief(planet: Dictionary) -> String:
	var c := config(planet)
	if c.is_empty():
		return ""
	var nm := str(c.get("name", "the beast"))
	var said := " ".join(PackedStringArray(lore(planet)))
	if is_slain(str(planet.get("id", ""))):
		return "THIS PLANET'S BEAST: %s, a huge purple blob that rolled about the desert and killed anyone it touched. Word is someone killed it. What people say: %s" % [nm, said]
	return "THIS PLANET'S BEAST: %s, a huge purple blob that rolls about the desert. Anyone it touches dies; hurt it and it chases you a long way. Everyone here knows of it. What people say: %s" % [nm, said]


func setup(town_demo, world_ground: WorldGround, planet: Dictionary) -> void:
	demo = town_demo
	ground = world_ground
	player = demo._player
	planet_id = str(planet.get("id", ""))
	cfg = config(planet)
	beast_name = str(cfg.get("name", cfg.get("label", "the beast")))
	radius = float(cfg.get("radius", 3.6))
	max_hp = float(cfg.get("hp", 1000))
	hp = max_hp
	_rng.seed = 220
	name = "PlanetBeast"
	collision_layer = LAYER_ENEMIES
	collision_mask = 0


func _ready() -> void:
	var h: Array = cfg.get("home", [520, 720])
	home = _surface(Vector2(float(h[0]), float(h[1])))
	heading = _flat(Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)), home).normalized()
	_new_pace()
	_fart_left = _range("fart_every_s", 9.0, 26.0)
	_build_look()
	_shape = CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = radius
	_shape.shape = sph
	add_child(_shape)
	_place(home)
	var path := str(cfg.get("fart_sound", ""))
	_sfx = AudioStreamPlayer3D.new()
	if path != "" and ResourceLoader.exists(path):
		_sfx.stream = load(path)
	_sfx.unit_size = 16.0
	_sfx.max_distance = 220.0
	add_child(_sfx)


func _range(key: String, a: float, b: float) -> float:
	var r: Array = cfg.get(key, [a, b])
	return _rng.randf_range(float(r[0]), float(r[1]))


## A line from the data with its name put in ("" if there is none).
func line(key: String) -> String:
	return str(cfg.get("lines", {}).get(key, "")).replace("{name}", beast_name)


# ------------------------------------------------------------------ ground

func _surface(m: Vector2) -> Vector3:
	var sp := ground.sphere() if ground != null else null
	if sp != null:
		return sp.surface_at(m.x, m.y)
	var hgt := ground.terrain.height_at(m.x, m.y) if ground != null and ground.terrain != null else 0.0
	return Vector3(m.x, hgt, m.y)


func _up(p: Vector3) -> Vector3:
	return ground.up_at(p) if ground != null else Vector3.UP


func _flat(v: Vector3, at: Vector3) -> Vector3:
	var u := _up(at)
	return v - u * v.dot(u)


## The ground point under (about) `at`.
func _ground_at(at: Vector3) -> Vector3:
	return ground.surface_below(at + _up(at) * 6.0) if ground != null else Vector3(at.x, 0.0, at.z)


# ------------------------------------------------------------------ look

## A glossy purple ball with a soft inner glow; it squashes and jiggles.
func _build_look() -> void:
	_ball = Node3D.new()
	_ball.name = "Body"
	add_child(_ball)
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 40
	mesh.rings = 20
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(str(cfg.get("color", "#8a3fc8")))
	_mat.roughness = 0.18
	_mat.metallic = 0.0
	_mat.rim_enabled = true
	_mat.rim = 0.7
	_mat.rim_tint = 0.6
	_mat.emission_enabled = true
	_mat.emission = Color(str(cfg.get("glow", "#c07aff")))
	_mat.emission_energy_multiplier = 0.35
	var mi := MeshInstance3D.new()
	mi.name = "Blob"
	mi.mesh = mesh
	mi.material_override = _mat
	_ball.add_child(mi)
	# A few darker spots so you can see it roll.
	var spot := StandardMaterial3D.new()
	spot.albedo_color = Color(str(cfg.get("color", "#8a3fc8"))).darkened(0.35)
	spot.roughness = 0.3
	for i in 7:
		var s := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = radius * _rng.randf_range(0.12, 0.22)
		sm.height = sm.radius * 0.6
		s.mesh = sm
		s.material_override = spot
		var d := Vector3(_rng.randfn(), _rng.randfn(), _rng.randfn()).normalized()
		s.position = d * radius * 0.97
		s.basis = Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT).rotated(d, 0.0) * Basis(Vector3.RIGHT, PI * 0.5)
		_ball.add_child(s)


# ------------------------------------------------------------------ frame

func _physics_process(dt: float) -> void:
	_t += dt
	_tick_wake(dt)
	if dead:
		return
	_wander(dt)
	_wobble(dt)
	_touch()
	_tick_fart(dt)


## Aimless: the heading drifts at random, the pace changes now and then. Only a
## loose leash round its own home turns it back if it strays very far. Chasing, it
## steers at the player instead, at its chase speed.
func _wander(dt: float) -> void:
	var at := global_position - _up(global_position) * radius
	_speed_left -= dt
	if _speed_left <= 0.0:
		_new_pace()
	if chasing:
		_chase(at, dt)
	else:
		var jitter := deg_to_rad(float(cfg.get("turn_jitter_deg", 70.0)))
		heading = heading.rotated(_up(at), _rng.randfn() * jitter * sqrt(dt))
		if at.distance_to(home) > float(cfg.get("leash_m", 1400.0)):
			heading = heading.lerp(_flat(home - at, at).normalized(), minf(1.0, dt * 0.5))
	heading = _flat(heading, at).normalized()
	var pace := float(cfg.get("chase_speed", 5.5)) if chasing else speed
	var step := heading * pace * dt
	var next := _ground_at(at + step)
	travelled += step.length()
	_place(next)
	# Roll: turn about the axis across its path by the distance over its radius.
	var axis := _up(next).cross(heading).normalized()
	if axis.length() > 0.5 and _ball != null:
		_ball.basis = Basis(axis, step.length() / radius) * _ball.basis
		_ball.basis = _ball.basis.orthonormalized()


## After the player: steer at them; give up once they are far enough away (or dead).
func _chase(at: Vector3, dt: float) -> void:
	if player == null or not is_instance_valid(player) or bool(player.get("is_downed")):
		_calm()
		return
	var to := _flat(player.global_position - at, at)
	if to.length() > float(cfg.get("chase_give_up_m", 1000.0)):
		_calm()
		_toast(line("gave_up"))
		return
	if to.length() > 0.01:
		heading = heading.lerp(to.normalized(), minf(1.0, dt * float(cfg.get("chase_turn", 2.5))))


func _calm() -> void:
	if not chasing:
		return
	chasing = false
	_new_pace()
	gave_up.emit()


func _new_pace() -> void:
	speed = _range("speed", 1.2, 3.4)
	_speed_left = _range("speed_change_s", 3.0, 8.0)


func _place(ground_point: Vector3) -> void:
	var u := _up(ground_point)
	global_position = ground_point + u * radius * (1.0 - 0.12 * _squash)


## Jiggle as it goes, and a squash when it farts (look only).
func _wobble(dt: float) -> void:
	_squash = move_toward(_squash, 0.0, dt * 1.6)
	if _ball == null:
		return
	var w := 0.04 * sin(_t * 3.1) + 0.025 * sin(_t * 5.3 + 1.0)
	var mi := _ball.get_node_or_null("Blob") as Node3D
	var s := Vector3(1.0 + w + 0.12 * _squash, 1.0 - w - 0.18 * _squash, 1.0 + w + 0.12 * _squash)
	# The squash is along the ground's up, whichever way the body has rolled.
	var up_local := _ball.global_basis.inverse() * _up(global_position)
	if mi != null:
		mi.basis = _scale_along(up_local.normalized(), s)


static func _scale_along(up: Vector3, s: Vector3) -> Basis:
	var b := Basis.looking_at(up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized(), up)
	return b * Basis.from_scale(Vector3(s.x, s.y, s.z)) * b.inverse()


# ------------------------------------------------------------------ hurt, dead

## Bolts call this (bolt.gd). Only the player (on foot, or in what they ride)
## sets it chasing; a stray bolt from anyone else just hurts.
func apply_damage_from(amount: float, shooter: Node) -> void:
	_hurt(amount, _is_player(shooter))


## Blades and anything that does not say who: only the player swings a blade here.
func apply_damage(amount: float) -> void:
	_hurt(amount, true)


func apply_blade_hit(amount: float, _dir: Vector3) -> void:
	_hurt(amount, true)


func _is_player(shooter: Node) -> bool:
	if shooter == null or player == null or not is_instance_valid(shooter):
		return shooter == null
	if shooter == player:
		return true
	var v = player.get("vehicle") if bool(player.get("piloting")) else null
	return v is Node and is_instance_valid(v) and (shooter == v or (v as Node).is_ancestor_of(shooter))


func _hurt(amount: float, by_player: bool) -> void:
	if dead or amount <= 0.0:
		return
	hits_taken += 1
	hp -= amount
	_squash = maxf(_squash, 0.5)
	if hp <= 0.0:
		_die()
		return
	if by_player and not chasing:
		chasing = true
		_toast(line("provoked"))
		provoked.emit()


## It sinks into a purple puddle and stays dead (the flag keeps it from being built
## again, and the locals hear of it).
func _die() -> void:
	hp = 0.0
	dead = true
	chasing = false
	if _shape != null:
		_shape.set_deferred("disabled", true)
	if planet_id != "":
		WorldState.set_flag(slain_flag(planet_id))
	WorldState.log_event("Killed %s, the beast." % beast_name)
	_toast(line("slain"))
	if _ball != null:
		var mi := _ball.get_node_or_null("Blob") as Node3D
		var tw := create_tween().set_parallel(true)
		tw.tween_property(self, "global_position", global_position - _up(global_position) * radius * 0.85, 2.5)
		if mi != null:
			var up_local := (_ball.global_basis.inverse() * _up(global_position)).normalized()
			tw.tween_property(mi, "basis", _scale_along(up_local, Vector3(1.6, 0.15, 1.6)), 2.5)
	slain.emit()


# ------------------------------------------------------------------ touch = death

func _touch() -> void:
	if player == null or not is_instance_valid(player) or bool(player.get("is_downed")):
		return
	var c := global_position
	if bool(player.get("piloting")):
		var v = player.get("vehicle")
		if v is SpeederNode and (v as SpeederNode).model.position.distance_to(c) <= radius + float(cfg.get("speeder_margin", 1.4)):
			(v as SpeederNode).dismount()
			_kill()
		return
	var chest := player.global_position + _up(player.global_position) * 0.9
	if chest.distance_to(c) <= radius + float(cfg.get("kill_margin", 0.35)):
		_kill()


## Dead on the spot. Whoever handles a downed player (the town's garrison) wakes
## them; if nobody does in a few seconds, the beast does it, in the pit.
func _kill() -> void:
	kills += 1
	if "invulnerable_left" in player:
		player.invulnerable_left = 0.0
	player.apply_damage_from(float(player.health.hp) + 9999.0, self)
	_toast(line("killed"))
	_wake_left = 4.0
	_calm()
	killed_player.emit()


func _tick_wake(dt: float) -> void:
	if _wake_left < 0.0:
		return
	if not bool(player.get("is_downed")):
		_wake_left = -1.0
		return
	_wake_left -= dt
	if _wake_left <= 0.0:
		_wake_left = -1.0
		player.global_position = demo.town.spawn_pos() + Vector3(0, 0.05, 0)
		if player.has_method("align_to_ground"):
			player.call("align_to_ground", true)
		player.revive()
		player.locked = false
		_toast(line("woke"))


func _toast(text: String) -> void:
	var gear = demo.get("gear") if demo != null else null
	if text != "" and gear != null and gear.hud != null:
		gear.hud.toast(text, 4.0)


# ------------------------------------------------------------------ farts

func _tick_fart(dt: float) -> void:
	_fart_left -= dt
	if _fart_left <= 0.0:
		fart()


## Pfffrt: a sound, a puff behind it and a squash.
func fart() -> void:
	farts += 1
	_fart_left = _range("fart_every_s", 9.0, 26.0)
	_squash = 1.0
	if _sfx != null and _sfx.stream != null:
		_sfx.pitch_scale = _rng.randf_range(0.8, 1.2)
		_sfx.play()
	if demo != null and bool(demo.get("use_look")):
		_puff()
	farted.emit()


func _puff() -> void:
	var c := Color(str(cfg.get("puff", "#9a8a4a")))
	var base := global_position - heading * radius * 1.05 - _up(global_position) * radius * 0.5
	for i in 6:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.6
		sm.height = 1.2
		sm.radial_segments = 10
		sm.rings = 6
		mi.mesh = sm
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(c.r, c.g, c.b, 0.55)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		demo.add_child(mi)
		var drift := (-heading * _rng.randf_range(0.5, 2.5) + _up(base) * _rng.randf_range(0.3, 1.6)
			+ heading.cross(_up(base)) * _rng.randf_range(-1.2, 1.2))
		mi.global_position = base + drift * 0.3
		var tw := mi.create_tween().set_parallel(true)
		tw.tween_property(mi, "global_position", base + drift * 2.2, 2.2)
		tw.tween_property(mi, "scale", Vector3.ONE * _rng.randf_range(2.5, 4.0), 2.2)
		tw.tween_property(m, "albedo_color:a", 0.0, 2.2)
		tw.chain().tween_callback(mi.queue_free)
