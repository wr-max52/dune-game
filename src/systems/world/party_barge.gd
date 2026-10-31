class_name PartyBarge
extends AnimatableBody3D
## Issue #269: a planet's party barge. A big sail barge floating over the sand that
## is one long party: a band on the top deck playing the planet's cantina club
## music, a crowd dancing on every deck (steerage too), and an ugly boss who runs
## it like a king. Buy it from him or beat him and it is yours: take the helm and
## drive it like a speeder, only slowly, and the party never stops.
##
## A planet component, like the beast and the natives: a planet has one only if
## its file has a "barge" block (content/core/planets/<id>.json); the numbers
## every barge shares are content/core/barges/party_barge.json, and the block may
## override any of them. PlanetGen passes it through; the town scene builds it as
## a late stage (with_barge).
##
## Three decks, all walkable (box colliders, so what you see is what you stand on):
##   top       open deck: band stage at the bow, the boss's dais, a bar, masts and
##             sails, an awning, string lights, the helm at the stern; a gangplank
##             runs from the stern down to the sand
##   lower     the lounge, down a ramp from the top deck (port side)
##   steerage  the hold, down a second ramp (starboard): crates, hammocks, lamps
##
## The body is an AnimatableBody3D moved here in _physics_process, so whoever
## stands on a deck rides along. Its people are look-only, children of the body,
## so they ride along too and dance whatever it does. Facing -Z is the bow; local
## y = 0 is the sand under its middle.

signal taken_over(how: String)
signal helm_taken
signal helm_left

const DATA := "res://content/core/barges/party_barge.json"
const BodyAnimatorT := preload("res://src/systems/anim/body_animator.gd")
const LAYER_ENEMIES := 1 << 3

var demo                              ## town_demo.gd
var ground: WorldGround
var player: CharacterBody3D
var planet_id := ""
var cfg: Dictionary = {}
var barge_name := "the party barge"
var boss_name := "the boss"
var owned := false
var driving := false
var speed := 0.0
var heading := Vector3.FORWARD        ## along the ground: where the bow points
var home := Vector3.ZERO
var travelled := 0.0
var boss_hp := 400.0
var party_frames := 0                 ## frames the crowd and band were animated (traces)
var people: Array = []                ## { node, body, deck, kind, off, yaw }
var band: Array = []
var boss: Node3D
var helm_spot := Vector3.ZERO         ## local: where you stand to steer
var _ground := Vector3.ZERO           ## the sand point under the middle
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _mats: Dictionary = {}
var _L := 40.0
var _W := 12.0
var _y := [1.8, 5.2, 8.6]             ## floor tops: steerage, lower, top
var _boss_hit: StaticBody3D
var _boss_home := Vector3.ZERO
var _prompt: Label
var _music: ClubMusic
var _throttle := 0.0
var _steer := 0.0
var external := {}                    ## a trace's command: { throttle, steer }


static func defaults() -> Dictionary:
	var f := FileAccess.open(DATA, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f != null else null
	return d if d is Dictionary else {}


## The planet's barge (a built planet, PlanetGen.build): the defaults with its
## "barge" block laid over (one level deep for the dictionaries), or {} if none.
static func config(planet: Dictionary) -> Dictionary:
	var own: Dictionary = planet.get("barge", {})
	if own.is_empty():
		return {}
	var c := defaults()
	for k in own:
		if own[k] is Dictionary and c.get(k) is Dictionary:
			var d: Dictionary = (c[k] as Dictionary).duplicate(true)
			d.merge(own[k], true)
			c[k] = d
		else:
			c[k] = own[k]
	return c


static func lives_on(planet: Dictionary) -> bool:
	return not config(planet).is_empty()


static func owned_flag(id: String) -> String:
	return "barge_owned_" + id


static func is_owned(id: String) -> bool:
	return WorldState.has_flag(owned_flag(id))


func setup(town_demo, world_ground: WorldGround, planet: Dictionary) -> void:
	demo = town_demo
	ground = world_ground
	player = demo._player
	planet_id = str(planet.get("id", ""))
	cfg = config(planet)
	barge_name = str(cfg.get("name", "the party barge"))
	boss_name = str(cfg.get("boss", {}).get("name", "the boss"))
	boss_hp = float(cfg.get("boss", {}).get("hp", 400))
	owned = is_owned(planet_id)
	_L = float(cfg.get("length", 40.0))
	_W = float(cfg.get("width", 12.0))
	var h := float(cfg.get("hover_m", 1.2))
	var gap := float(cfg.get("deck_gap", 3.4))
	_y = [h + 0.6, h + 0.6 + gap, h + 0.6 + gap * 2.0]
	_rng.seed = 269
	name = "PartyBarge"
	sync_to_physics = true
	process_physics_priority = -1          # moves before the player, who rides it


func _ready() -> void:
	var hm: Array = cfg.get("home", [0, 0])
	home = _surface(Vector2(float(hm[0]), float(hm[1])))
	_ground = home
	heading = _flat(Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)), home).normalized()
	_place()
	_build_hull()
	_build_top()
	_build_below()
	_build_people()
	_build_prompt()
	var club := str(demo.planet.get("cfg", {}).get("club", Sound.lib().cfg.get("club", {}).get("default", ""))) \
		if demo.get("planet") is Dictionary else ""
	club = str(cfg.get("club", club))
	if club != "" and player != null:
		_music = ClubMusic.new().setup_follow(club, self, _L * 0.5, player)
		_music.inside_fn = func(p: Vector3) -> bool: return deck_of(p) != ""
		add_child(_music)


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


func _ground_at(at: Vector3) -> Vector3:
	return ground.surface_below(at + _up(at) * 8.0) if ground != null else Vector3(at.x, 0.0, at.z)


func _place() -> void:
	var u := _up(_ground)
	heading = _flat(heading, _ground).normalized()
	global_transform = Transform3D(Basis.looking_at(heading, u), _ground)


## Which deck a world point is on ("top", "lower", "steerage"), or "" off the barge.
func deck_of(p: Vector3) -> String:
	var l := global_transform.affine_inverse() * p
	if absf(l.x) > _W * 0.5 or absf(l.z) > _L * 0.5:
		return ""
	if l.y < _y[0] - 0.6 or l.y > _y[2] + 4.0:
		return ""
	if l.y >= _y[2] - 0.6:
		return "top"
	if l.y >= _y[1] - 0.6:
		return "lower"
	return "steerage"


## Whether the player is on board (any deck, or the gangplank).
func aboard(p: Vector3) -> bool:
	if deck_of(p) != "":
		return true
	var l := global_transform.affine_inverse() * p
	return absf(l.x) < 2.5 and l.z > _L * 0.5 and l.z < _L * 0.5 + 24.0 and l.y > -2.0 and l.y < _y[2] + 3.0


# ------------------------------------------------------------------ building blocks

func _mat(key: String, emissive := false) -> StandardMaterial3D:
	var id := key + ("*" if emissive else "")
	if _mats.has(id):
		return _mats[id]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(str(cfg.get("colors", {}).get(key, key if key.begins_with("#") else "#888888")))
	m.roughness = 0.85
	if emissive:
		m.emission_enabled = true
		m.emission = m.albedo_color
		m.emission_energy_multiplier = 2.5
	_mats[id] = m
	return m


## A box: seen, and (solid) stood on / walked into. Local space.
func _box(size: Vector3, at: Vector3, mat: Material, solid := true, rot := Basis.IDENTITY, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.transform = Transform3D(rot, at)
	(parent if parent != null else self).add_child(mi)
	if solid:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		cs.transform = Transform3D(rot, at)
		add_child(cs)
	return mi


func _cyl(r: float, h: float, at: Vector3, mat: Material, solid := false, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 12
	mi.mesh = cm
	mi.material_override = mat
	mi.position = at
	(parent if parent != null else self).add_child(mi)
	if solid:
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = r
		sh.height = h
		cs.shape = sh
		cs.position = at
		add_child(cs)
	return mi


func _ball(r: float, at: Vector3, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 10
	sm.rings = 6
	mi.mesh = sm
	mi.material_override = mat
	mi.position = at
	(parent if parent != null else self).add_child(mi)
	return mi


## A floor slab (top surface at y) over the inside of the hull, with a stairwell hole.
func _floor(y: float, hole: Rect2, mat: Material) -> void:
	var x0 := -_W * 0.5 + 0.4
	var x1 := _W * 0.5 - 0.4
	var z0 := -_L * 0.5 + 0.4
	var z1 := _L * 0.5 - 0.4
	var t := 0.3
	var rects: Array = []
	if hole.size == Vector2.ZERO:
		rects.append(Rect2(x0, z0, x1 - x0, z1 - z0))
	else:
		var hx0 := hole.position.x
		var hx1 := hole.end.x
		var hz0 := hole.position.y
		var hz1 := hole.end.y
		rects.append(Rect2(x0, z0, hx0 - x0, z1 - z0))
		rects.append(Rect2(hx1, z0, x1 - hx1, z1 - z0))
		rects.append(Rect2(hx0, z0, hx1 - hx0, hz0 - z0))
		rects.append(Rect2(hx0, hz1, hx1 - hx0, z1 - hz1))
	for r in rects:
		if r.size.x > 0.01 and r.size.y > 0.01:
			_box(Vector3(r.size.x, t, r.size.y), Vector3(r.get_center().x, y - t * 0.5, r.get_center().y), mat)


## A walkable ramp from a (top) to b (bottom), w wide; its top face runs through both.
func _ramp(a: Vector3, b: Vector3, w: float, mat: Material) -> void:
	var d := b - a
	var along := d.normalized()
	var side := Vector3.UP.cross(along).normalized()
	if side.length() < 0.5:
		side = Vector3.RIGHT
	var n := along.cross(side).normalized()
	if n.y < 0.0:
		n = -n
	var t := 0.3
	var basis := Basis(side, n, -along)
	_box(Vector3(w, t, d.length() + 0.4), (a + b) * 0.5 - n * t * 0.5, mat, true, basis)


# ------------------------------------------------------------------ the hull

const HOLE_TOP := Rect2(-5.6, -6.0, 2.4, 9.0)      ## top deck -> lower (port), x, z
const HOLE_LOWER := Rect2(3.2, 4.0, 2.4, 9.0)      ## lower -> steerage (starboard)


func _build_hull() -> void:
	var hull := _mat("hull")
	var deck := _mat("deck")
	var trim := _mat("trim")
	var h := float(cfg.get("hover_m", 1.2))
	var top := float(_y[2])
	var wall_h := top + 1.1 - h
	# Bottom (the steerage floor), sides, bow and stern.
	_box(Vector3(_W, _y[0] - h, _L), Vector3(0, (h + _y[0]) * 0.5, 0), hull)
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.4, wall_h, _L), Vector3(sx * (_W * 0.5 - 0.2), h + wall_h * 0.5, 0), hull)
		_box(Vector3(0.5, 0.25, _L + 0.2), Vector3(sx * (_W * 0.5 - 0.2), top + 1.15, 0), trim, false)   # gunwale
		_box(Vector3(0.8, 0.5, _L * 0.9), Vector3(sx * (_W * 0.3), h - 0.6, 0), trim, false)              # skids
	_box(Vector3(_W, wall_h, 0.4), Vector3(0, h + wall_h * 0.5, -_L * 0.5 + 0.2), hull)
	# The stern: solid up to the top deck, bulwark either side of the gangplank.
	_box(Vector3(_W, top - h, 0.4), Vector3(0, (h + top) * 0.5, _L * 0.5 - 0.2), hull)
	for sx in [-1.0, 1.0]:
		_box(Vector3(_W * 0.5 - 1.6, 1.1, 0.4), Vector3(sx * (_W * 0.25 + 0.8), top + 0.55, _L * 0.5 - 0.2), hull)
	# The bow: a pointed prow (look only) and a figurehead lamp.
	_box(Vector3(_W * 0.72, wall_h * 0.8, _W * 0.72), Vector3(0, h + wall_h * 0.45, -_L * 0.5 - 0.6), hull, false,
		Basis(Vector3.UP, PI * 0.25))
	_ball(0.5, Vector3(0, top + 1.6, -_L * 0.5 - 2.6), _mat("lamp", true))
	# Decks.
	_floor(_y[1], HOLE_LOWER, deck)
	_floor(top, HOLE_TOP, deck)
	# Stairs: top -> lower down the port side, lower -> steerage down the starboard.
	var cx := HOLE_TOP.get_center().x
	_ramp(Vector3(cx, top, HOLE_TOP.position.y), Vector3(cx, _y[1], HOLE_TOP.end.y), HOLE_TOP.size.x - 0.2, deck)
	cx = HOLE_LOWER.get_center().x
	_ramp(Vector3(cx, _y[1], HOLE_LOWER.position.y), Vector3(cx, _y[0], HOLE_LOWER.end.y), HOLE_LOWER.size.x - 0.2, _mat("steerage"))
	# Gangplank: stern to the sand (its foot sinks a little into it).
	_ramp(Vector3(0, top, _L * 0.5 - 0.3), Vector3(0, -1.0, _L * 0.5 + 22.0), 3.0, deck)
	for sx in [-1.0, 1.0]:
		for i in 6:
			var f := float(i) / 5.0
			var p := Vector3(sx * 1.6, lerpf(top, -1.0, f) + 0.5, lerpf(_L * 0.5, _L * 0.5 + 22.0, f))
			_cyl(0.06, 1.0, p, trim)
	# Railings round the stairwell on the top deck (so nobody steps in by mistake).
	_box(Vector3(0.1, 1.0, HOLE_TOP.size.y), Vector3(HOLE_TOP.end.x + 0.05, top + 0.5, HOLE_TOP.get_center().y), trim)
	_box(Vector3(HOLE_TOP.size.x, 1.0, 0.1), Vector3(HOLE_TOP.get_center().x, top + 0.5, HOLE_TOP.end.y + 0.05), trim)
	_box(Vector3(0.1, 1.0, HOLE_LOWER.size.y), Vector3(HOLE_LOWER.position.x - 0.05, _y[1] + 0.5, HOLE_LOWER.get_center().y), trim)
	_box(Vector3(HOLE_LOWER.size.x, 1.0, 0.1), Vector3(HOLE_LOWER.get_center().x, _y[1] + 0.5, HOLE_LOWER.end.y + 0.05), trim)


func _build_top() -> void:
	var top := float(_y[2])
	var trim := _mat("trim")
	var gold := _mat("gold")
	# Masts and sails (striped), the awning over the dance floor, string lights.
	for mz in [-9.0, 6.0]:
		_cyl(0.35, 16.0, Vector3(0, top + 8.0, mz), trim, true)
		_box(Vector3(_W * 0.95, 0.25, 0.25), Vector3(0, top + 14.5, mz), trim, false)
		_box(Vector3(_W * 0.85, 9.0, 0.08), Vector3(0, top + 9.5, mz - 0.3), _mat("sail"), false)
		_box(Vector3(_W * 0.85, 1.0, 0.1), Vector3(0, top + 7.5, mz - 0.3), _mat("sail_stripe"), false)
		_box(Vector3(_W * 0.85, 1.0, 0.1), Vector3(0, top + 11.5, mz - 0.3), _mat("sail_stripe"), false)
	for i in 8:
		var z := lerpf(-8.0, 4.0, float(i) / 7.0)
		_box(Vector3(_W * 0.9, 0.06, 1.5), Vector3(0, top + 4.2, z), _mat("awning" if i % 2 == 0 else "awning_stripe"), false)
	for sx in [-1.0, 1.0]:
		for z in [-8.5, 4.5]:
			_cyl(0.08, 4.2, Vector3(sx * _W * 0.44, top + 2.1, z), gold)
	var bulb := _mat("lamp", true)
	for sx in [-1.0, 1.0]:
		for i in 18:
			_ball(0.09, Vector3(sx * (_W * 0.5 - 0.2), top + 1.45 + 0.25 * sin(i * 1.3), lerpf(-_L * 0.5 + 1.0, _L * 0.5 - 1.0, i / 17.0)), bulb)
	# The band's stage at the bow (low enough to step up), with a back wall.
	_box(Vector3(_W - 1.0, 0.1, 6.0), Vector3(0, top + 0.05, -_L * 0.5 + 4.0), gold)
	_box(Vector3(_W - 1.0, 3.0, 0.2), Vector3(0, top + 1.5, -_L * 0.5 + 1.0), _mat("sail_stripe"), false)
	# Drums and a keyboard on the stage.
	_cyl(0.45, 0.6, Vector3(-3.0, top + 0.4, -_L * 0.5 + 2.6), _mat("sail_stripe"))
	_cyl(0.3, 0.45, Vector3(-2.2, top + 0.6, -_L * 0.5 + 3.1), gold)
	_box(Vector3(1.4, 0.15, 0.5), Vector3(2.8, top + 1.0, -_L * 0.5 + 3.2), trim, false)
	# The bar (starboard) with bottles.
	_box(Vector3(1.0, 1.1, 6.0), Vector3(_W * 0.5 - 1.2, top + 0.55, -1.0), trim)
	for i in 9:
		_cyl(0.06, 0.3, Vector3(_W * 0.5 - 1.2, top + 1.25, -3.6 + i * 0.65), _mat("#5aa070" if i % 3 else "#a8322a"))
	# The boss's dais and lounger, facing the stern.
	_boss_home = Vector3(0, top + 0.12, 10.5)
	_box(Vector3(4.0, 0.12, 3.0), Vector3(0, top + 0.06, 10.5), gold)
	_box(Vector3(3.2, 0.6, 1.6), Vector3(0, top + 0.42, 11.3), _mat("sail_stripe"), false)
	_box(Vector3(3.2, 1.6, 0.3), Vector3(0, top + 0.9, 9.4), _mat("sail_stripe"), false)
	# The helm: a wheel on a post near the stern, starboard.
	helm_spot = Vector3(3.6, top + 0.05, 16.8)
	_cyl(0.15, 1.1, Vector3(3.6, top + 0.55, 15.9), trim)
	var wheel := _cyl(0.55, 0.08, Vector3(3.6, top + 1.2, 16.0), gold)
	wheel.rotation.x = PI * 0.5
	wheel.name = "Wheel"


func _build_below() -> void:
	# The lounge: tables, a rug, lamps. Steerage: crates, hammocks, low lamps.
	for i in 4:
		_cyl(0.6, 0.08, Vector3(-1.5 + (i % 2) * 3.0, _y[1] + 0.8, -12.0 + (i / 2) * 5.0), _mat("trim"))
		_cyl(0.1, 0.8, Vector3(-1.5 + (i % 2) * 3.0, _y[1] + 0.4, -12.0 + (i / 2) * 5.0), _mat("trim"))
	_box(Vector3(5.0, 0.03, 8.0), Vector3(0, _y[1] + 0.02, 10.0), _mat("sail_stripe"), false)
	for i in 6:
		_box(Vector3(1.2, 1.0, 1.2), Vector3(-4.6, _y[0] + 0.5, -16.0 + i * 1.6), _mat("steerage"))
	for i in 4:
		var hm := _box(Vector3(0.9, 0.08, 2.4), Vector3(-3.0 + i * 1.6, _y[1] - 1.0, -6.0), _mat("sail"), false)
		hm.rotation.z = 0.08 * (i % 2 * 2 - 1)
	if demo != null and bool(demo.get("use_look")):
		for at in [Vector3(0, _y[1] + 2.6, -8.0), Vector3(0, _y[1] + 2.6, 8.0), Vector3(0, _y[0] + 2.6, -8.0), Vector3(0, _y[0] + 2.6, 6.0),
				Vector3(0, _y[2] + 3.8, -2.0), Vector3(0, _y[2] + 3.0, -_L * 0.5 + 4.0)]:
			var l := OmniLight3D.new()
			l.light_color = Color(str(cfg.get("colors", {}).get("lamp", "#ffb860")))
			l.light_energy = 2.0
			l.omni_range = 11.0
			l.position = at
			add_child(l)
			_ball(0.18, at + Vector3(0, 0.3, 0), _mat("lamp", true))


# ------------------------------------------------------------------ the people

func _build_people() -> void:
	var crowd: Dictionary = cfg.get("crowd", {})
	var looks: Array = cfg.get("crowd_looks", ["local"])
	var top := float(_y[2])
	# Top deck: the dance floor between the stage and the boss.
	for i in int(crowd.get("top", 12)):
		_add_person(looks[i % looks.size()], _free_spot("top"), "top", "dancer")
	for i in int(crowd.get("lower", 7)):
		_add_person(looks[(i + 1) % looks.size()], _free_spot("lower"), "lower", "dancer")
	for i in int(crowd.get("steerage", 9)):
		_add_person(looks[(i + 2) % looks.size()], _free_spot("steerage"), "steerage", "dancer")
	# The band, on the stage, facing aft.
	var n := int(cfg.get("band_size", 4))
	for i in n:
		var x := lerpf(-3.6, 3.6, float(i) / maxf(1.0, n - 1.0))
		var p := _add_person("local", Vector3(x, top + 0.1, -_L * 0.5 + 3.8), "top", "band", 0.0)
		band.append(p)
		_instrument(p, i)
	# Guards either side of the dais (they groove too).
	for i in int(cfg.get("guards", 2)):
		_add_person("desert_guard", _boss_home + Vector3((i * 2 - 1) * 2.6, 0, -0.5), "top", "guard", 0.0)
	_build_boss()


## A clear spot on a deck (local), away from the stairwells, masts, bar and dais.
func _free_spot(deck: String) -> Vector3:
	var y: float = _y[2] if deck == "top" else (_y[1] if deck == "lower" else _y[0])
	for tries in 40:
		var x := _rng.randf_range(-_W * 0.5 + 1.2, _W * 0.5 - 1.4)
		var z := _rng.randf_range(-_L * 0.5 + 2.0, _L * 0.5 - 2.0)
		var ok := true
		match deck:
			"top":
				z = _rng.randf_range(-12.5, 7.0)
				ok = not HOLE_TOP.grow(0.8).has_point(Vector2(x, z)) and x < _W * 0.5 - 2.2 \
					and Vector2(x, z).distance_to(Vector2(0, -9)) > 1.2 and Vector2(x, z).distance_to(Vector2(0, 6)) > 1.2
			"lower":
				ok = not HOLE_LOWER.grow(0.8).has_point(Vector2(x, z)) and not Rect2(-6, -6.5, 3.6, 11.0).has_point(Vector2(x, z))
			_:
				ok = not Rect2(2.4, 11.0, 4.0, 8.0).has_point(Vector2(x, z)) and x > -3.6
		if ok:
			return Vector3(x, y, z)
	return Vector3(0, y, 0)


func _add_person(look: String, at: Vector3, deck: String, kind: String, yaw := INF) -> Dictionary:
	var holder := Node3D.new()
	holder.name = "%s_%d" % [kind, people.size()]
	holder.position = at
	holder.rotation.y = _rng.randf() * TAU if yaw == INF else yaw
	add_child(holder)
	var body: Node3D = null
	if demo != null and bool(demo.get("use_look")) and demo.has_method("_kit"):
		body = demo._kit().build(look, "idle")
		holder.add_child(body)
	else:
		body = Node3D.new()                 # headless: a stand-in that still moves
		body.name = "Stand"
		holder.add_child(body)
	var p := { "node": holder, "body": body, "deck": deck, "kind": kind, "off": _rng.randf() * 30.0,
		"yaw": holder.rotation.y, "beat": 0.0 }
	people.append(p)
	return p


func _joint(body: Node3D, jn: String) -> Node3D:
	var j = body.get_meta("joints", {}) if body.has_meta("joints") else {}
	return j.get(jn) if j is Dictionary else null


func _instrument(p: Dictionary, i: int) -> void:
	var body: Node3D = p.body
	var chest := _joint(body, "chest")
	var at: Node3D = chest if chest != null else body
	var gold := _mat("gold")
	match i % 4:
		0:     # a horn
			var horn := _cyl(0.05, 0.6, Vector3(0.05, -0.05, 0.35), gold, false, at)
			horn.rotation.x = PI * 0.4
			_cyl(0.14, 0.12, Vector3(0.05, -0.28, 0.6), gold, false, at).rotation.x = PI * 0.4
		1:     # a long-necked lute
			var lute := _box(Vector3(0.35, 0.12, 0.45), Vector3(0.0, -0.2, 0.25), _mat("trim"), false, Basis(Vector3.FORWARD, 0.6), at)
			lute.name = "Lute"
			_box(Vector3(0.05, 0.05, 0.7), Vector3(-0.3, 0.05, 0.25), _mat("trim"), false, Basis(Vector3.FORWARD, 0.6), at)
		2:     # hand drums, on the deck in front
			_cyl(0.22, 0.7, Vector3(0, 0.35, 0.55), _mat("sail_stripe"), false, p.node)
		3:     # pipes
			for k in 4:
				_cyl(0.025, 0.25 + k * 0.06, Vector3(-0.06 + k * 0.04, 0.0, 0.32), gold, false, at)


## The boss: big, wide and ugly, warts and all, on his dais.
func _build_boss() -> void:
	var p := _add_person("cantina_owner", _boss_home, "top", "boss", 0.0)
	boss = p.node
	var body: Node3D = p.body
	body.scale *= Vector3(2.0, 1.25, 2.0)
	var head := _joint(body, "head")
	var chest := _joint(body, "chest")
	var wart := _mat("#6f7a4a")
	if chest != null:
		var belly := _ball(0.32, Vector3(0, -0.22, 0.14), _mat("#7a5a3a"), chest)
		belly.scale = Vector3(1.15, 0.95, 1.0)
	if head != null:
		for k in 6:
			_ball(0.03 + 0.02 * (k % 3), Vector3(_rng.randf_range(-0.1, 0.1), _rng.randf_range(0.0, 0.16), _rng.randf_range(0.02, 0.12)), wart, head)
		_ball(0.07, Vector3(0, 0.02, 0.13), _mat("#8a6a4a"), head)     # a big nose
	# Bolts and blades find him; he is the only one on board who can be hurt.
	_boss_hit = BossHit.new()
	_boss_hit.barge = self
	_boss_hit.collision_layer = LAYER_ENEMIES
	_boss_hit.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.9
	cap.height = 2.6
	cs.shape = cap
	cs.position = Vector3(0, 1.3, 0)
	_boss_hit.add_child(cs)
	boss.add_child(_boss_hit)
	if owned:
		_boss_below()


class BossHit:
	extends StaticBody3D
	var barge

	func apply_damage(amount: float) -> void:
		barge.hurt_boss(amount)

	func apply_damage_from(amount: float, _shooter: Node) -> void:
		barge.hurt_boss(amount)

	func apply_blade_hit(amount: float, _dir: Vector3) -> void:
		barge.hurt_boss(amount)


## The party never stops: everyone dances (the cantina's dance loop), the band
## grooves over its instruments, the boss bounces with laughter. Near the barge only.
func _animate(dt: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	if player.global_position.distance_to(global_position) > float(cfg.get("anim_m", 160.0)):
		return
	party_frames += 1
	for p in people:
		var body: Node3D = p.body
		var t: float = _t + float(p.off)
		p.beat = t
		if not body.has_meta("joints"):
			body.position.y = 0.08 * absf(sin(t * 4.2))       # headless stand-in
			body.rotation.y = 0.3 * sin(t * 1.3)
			continue
		var joints: Dictionary = body.get_meta("joints")
		if p.kind == "dancer":
			var pose: Dictionary = BodyAnimatorT.dance_pose(t)
			for jn in pose.joints:
				if joints.has(jn):
					(joints[jn] as Node3D).rotation_degrees = pose.joints[jn]
			if joints.has("pelvis"):
				(joints.pelvis as Node3D).position.y = float(pose.pelvis_y)
				(joints.pelvis as Node3D).position.x = float(pose.pelvis_x)
			body.rotation.y = float(pose.yaw)
		else:
			# Band, guards and the boss: a nod, a sway and a bounce on the beat.
			var b := t * TAU * 2.0
			var k := 1.6 if p.kind == "boss" else 1.0
			if joints.has("head"):
				(joints.head as Node3D).rotation_degrees = Vector3(10.0 * sin(b) * k, 8.0 * sin(b * 0.5), 0)
			if joints.has("chest"):
				(joints.chest as Node3D).rotation_degrees = Vector3(4.0 * sin(b) * k, 12.0 * sin(b * 0.25), 6.0 * sin(b * 0.5))
			if joints.has("pelvis"):
				(joints.pelvis as Node3D).position.y = BodyAnimatorT.PELVIS_Y - 0.04 * absf(sin(b * 0.5)) * k
			if joints.has("l_knee"):
				(joints.l_knee as Node3D).rotation_degrees.x = 10.0 * absf(sin(b * 0.5))
			if joints.has("r_knee"):
				(joints.r_knee as Node3D).rotation_degrees.x = 10.0 * absf(sin(b * 0.5 + PI * 0.5))
			if p.kind == "band" and joints.has("r_elbow"):
				(joints.r_elbow as Node3D).rotation_degrees = Vector3(-70.0 - 20.0 * sin(b), 0, 0)
				if joints.has("l_elbow"):
					(joints.l_elbow as Node3D).rotation_degrees = Vector3(-80.0 + 15.0 * sin(b + 1.0), 0, 0)
		for s in body.get_meta("skins", []):
			s.sync(body)


# ------------------------------------------------------------------ taking it over

func hurt_boss(amount: float) -> void:
	if owned or amount <= 0.0:
		return
	var was := boss_hp
	boss_hp -= amount
	if was >= float(cfg.get("boss", {}).get("hp", 400)):
		_toast(line("boss_hurt"))
	if boss_hp <= 0.0:
		_take_over("beaten")


## Buy it: the boss's price in credits. False if you can't afford it.
func buy() -> bool:
	if owned:
		return false
	var price := int(cfg.get("boss", {}).get("price", 1500))
	if WorldState.credits < price:
		return false
	WorldState.credits -= price
	_take_over("bought")
	return true


func _take_over(how: String) -> void:
	owned = true
	WorldState.set_flag(owned_flag(planet_id))
	WorldState.log_event("Took %s from %s." % [barge_name, boss_name])
	_toast(line("bought" if how == "bought" else "boss_beaten"))
	_boss_below()
	taken_over.emit(how)


## The old boss goes below to the lounge and keeps on partying.
func _boss_below() -> void:
	if boss == null:
		return
	boss.position = Vector3(-1.0, _y[1], -2.0)
	if _boss_hit != null:
		_boss_hit.collision_layer = 0
	for p in people:
		if p.node == boss:
			p.deck = "lower"


func line(key: String) -> String:
	var v = cfg.get("lines", {}).get(key, "")
	if v is Array:
		v = v[_rng.randi() % v.size()] if not (v as Array).is_empty() else ""
	return str(v).replace("{name}", barge_name).replace("{boss}", boss_name) \
		.replace("{price}", str(int(cfg.get("boss", {}).get("price", 1500))))


func _toast(text: String) -> void:
	var gear = demo.get("gear") if demo != null else null
	if text != "" and gear != null and gear.hud != null:
		gear.hud.toast(text, 5.0)


# ------------------------------------------------------------------ helm

func near_boss() -> bool:
	if owned or boss == null or player == null:
		return false
	return player.global_position.distance_to(boss.global_position) <= float(cfg.get("boss", {}).get("reach_m", 4.5))


func near_helm() -> bool:
	return player != null and player.global_position.distance_to(to_global(helm_spot)) <= 2.2


## Take the helm (yours only). The player stands at the wheel and rides along.
func take_helm() -> bool:
	if not owned or driving or player == null:
		return false
	driving = true
	player.locked = true
	_pin_player()
	_toast(line("at_helm"))
	helm_taken.emit()
	return true


func leave_helm() -> void:
	if not driving:
		return
	driving = false
	external = {}
	player.locked = false
	_toast(line("let_go"))
	helm_left.emit()


func _pin_player() -> void:
	var at := to_global(helm_spot) + _up(global_position) * 0.05
	player.global_position = at
	player.velocity = Vector3.ZERO
	if "controller" in player and player.controller != null:
		player.controller.velocity = Vector3.ZERO
		player.controller.body_pos = at


# ------------------------------------------------------------------ frame

func _physics_process(dt: float) -> void:
	_t += dt
	_read_input()
	_move(dt)
	_animate(dt)


func _read_input() -> void:
	if player == null or not is_instance_valid(player):
		return
	var e := InputMap.has_action("interact") and Input.is_action_just_pressed("interact")
	var text := ""
	var gear = demo.get("gear") if demo != null else null
	var gear_busy: bool = gear != null and not (gear.focus as Dictionary).is_empty()
	if driving:
		if e:
			leave_helm()
		elif external.is_empty():
			_throttle = _axis("move_back", "move_forward")
			_steer = _axis("move_left", "move_right")
	elif not player.locked and not bool(player.get("piloting")) and not gear_busy:
		if near_helm():
			text = line("helm_prompt")
			if e:
				if owned:
					take_helm()
				else:
					_toast(line("helm_locked"))
		elif near_boss():
			var can_buy := WorldState.credits >= int(cfg.get("boss", {}).get("price", 1500))
			text = line("buy_prompt" if can_buy else "talk_prompt")
			if e:
				if can_buy:
					buy()
				else:
					_toast(line("talk"))
	if not external.is_empty():
		_throttle = float(external.get("throttle", 0.0))
		_steer = float(external.get("steer", 0.0))
	if _prompt != null:
		_prompt.text = text
		_prompt.visible = text != ""


func _axis(neg: String, pos: String) -> float:
	var a := 0.0
	if InputMap.has_action(pos) and Input.is_action_pressed(pos):
		a += 1.0
	if InputMap.has_action(neg) and Input.is_action_pressed(neg):
		a -= 1.0
	return a


## Driven: slow and heavy, like a speeder that weighs a town. Not driven and not
## yours: it drifts about its home, no pull toward or away from town, and stops
## while you are on board. Yours and parked: it stays put.
func _move(dt: float) -> void:
	var d: Dictionary = cfg.get("drive", {})
	var up := _up(_ground)
	if driving:
		var target := _throttle * (float(d.get("max_speed", 4.5)) if _throttle >= 0.0 else float(d.get("reverse_speed", 1.5)))
		var rate := float(d.get("accel", 0.6)) if signf(target) == signf(speed) or is_zero_approx(speed) else float(d.get("brake", 1.2))
		speed = move_toward(speed, target, rate * dt)
		var grip := clampf(absf(speed) / 1.5, 0.35, 1.0)
		heading = heading.rotated(up, -_steer * float(d.get("turn_rate", 0.22)) * grip * dt * (1.0 if speed >= 0.0 else -1.0))
	elif owned or (player != null and aboard(player.global_position)):
		speed = move_toward(speed, 0.0, float(d.get("brake", 1.2)) * dt)
	else:
		speed = move_toward(speed, float(cfg.get("drift_speed", 0.7)), 0.2 * dt)
		var jitter := deg_to_rad(float(cfg.get("turn_jitter_deg", 25.0)))
		heading = heading.rotated(up, _rng.randfn() * jitter * sqrt(dt))
		if _ground.distance_to(home) > float(cfg.get("roam_m", 250.0)):
			heading = heading.lerp(_flat(home - _ground, _ground).normalized(), minf(1.0, dt * 0.3))
	if absf(speed) > 0.001:
		var step := heading * speed * dt
		_ground = _ground_at(_ground + step)
		travelled += step.length()
	_place()
	if driving:
		_pin_player()
		var wheel := get_node_or_null("Wheel") as Node3D
		if wheel != null:
			wheel.rotation = Vector3(PI * 0.5, _steer * 0.8, 0)


func _build_prompt() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 4
	add_child(layer)
	_prompt = Label.new()
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.position = Vector2(-300, -170)
	_prompt.size = Vector2(600, 28)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_prompt.add_theme_constant_override("outline_size", 4)
	_prompt.visible = false
	RetroUI.prompt(_prompt)
	layer.add_child(_prompt)
