class_name SpaceTravel
extends Node3D
## Flying to another planet (issue #45). Every neighbour the planet generator
## lists hangs in this planet's sky where its config says ("at", metres from the
## port). A marker on screen names each one and how far it is.
##
## Issue #99: one map, no cutaway. Every planet's scene is the same space shifted
## to its own port (PlanetGen.neighbours), so the sun and the stars agree. A
## planet whose type has a space.handoff (the asteroid) is drawn here as its real
## ball (the same rock, coarse) with its station on top; fly within handoff metres
## of its surface and its own scene takes over on the spot, the ship exactly where
## it was, same heading and speed, nothing faded. Climb more than that far off it
## and its parent's scene takes over the same way. A planet with no handoff is
## still flown into and faded to, as before (GameFlow.travel).
##
## No input of its own: ShipPilot owns the ship. This only watches where it is.

signal travel_started(to: String)

const CAPTURE := 400.0               ## metres outside a body's radius that count as "arrived"
const HYSTERESIS := 300.0            ## issue #99: leaving needs this much more than arriving

var pilot                            ## ShipPilot
var bodies: Array = []               ## { id, name, at, radius, node }
var traveling := ""                  ## the planet a fade is taking us to ("" = none)
var change := true                   ## false: decide but do not change scene (tests)
var _layer: CanvasLayer
var _labels: Dictionary = {}         ## id -> Label
var _sand_bodies: Array = []         ## sand ShaderMaterials of ball neighbours (the sun is tracked)
var self_radius := 0.0               ## issue #99: this planet's ball, and how far up its scene still holds
var self_handoff := 0.0
var handoffs := 0                    ## seamless switches started (traces, tests)


func setup(ship_pilot, neighbours: Array, with_looks: bool) -> void:
	pilot = ship_pilot
	name = "SpaceTravel"
	var me: Dictionary = pilot.demo.planet if pilot != null and "planet" in pilot.demo else {}
	if not me.is_empty():
		self_radius = PlanetGen.ball_radius(me.get("cfg", {}), null) if not me.get("world", {}).get("terrain", {}).has("sphere_radius") \
			else float(me.world.terrain.sphere_radius)
		self_handoff = PlanetGen.handoff_altitude(str(me.get("type", "")))
	for n in neighbours:
		var b := { "id": str(n.id), "at": n.at, "radius": float(n.radius), "type": str(n.type), "node": null,
			"name": PlanetGen.display_name(PlanetGen.build(str(n.id))),
			"offset": n.get("offset", n.at), "child": bool(n.get("child", true)),
			"handoff": PlanetGen.handoff_altitude(str(n.type)) }
		if with_looks:
			b.node = _body(n)
		bodies.append(b)


func _ready() -> void:
	for b in bodies:
		if b.node != null:
			add_child(b.node)
	var look = pilot.demo.get("look") if pilot != null and pilot.get("demo") != null else null
	if look != null:
		for m in _sand_bodies:
			look.track_material(m)     # the sun, so the ball's night side is dusk
	_layer = CanvasLayer.new()
	_layer.layer = 4
	add_child(_layer)
	for b in bodies:
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 16)
		l.add_theme_color_override("font_color", Color("#9fe8ff"))
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		l.add_theme_constant_override("outline_size", 5)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.visible = false
		_layer.add_child(l)
		_labels[b.id] = l


## How far the ship is from a body's surface (metres; < 0 inside its capture).
func distance_to(id: String) -> float:
	for b in bodies:
		if b.id == id:
			return (pilot.atmo.position() as Vector3).distance_to(b.at) - float(b.radius) - CAPTURE
	return INF


func _physics_process(_dt: float) -> void:
	if pilot == null or traveling != "":
		return
	var flying: bool = pilot.piloting and pilot.atmo.state in [AtmoFlight.State.FLYING, AtmoFlight.State.LIFTOFF]
	_update_labels(flying)
	if not flying:
		return
	var pos: Vector3 = pilot.atmo.position()
	for b in bodies:
		if b.child and float(b.handoff) > 0.0:
			# Issue #99: close enough to its ball: its scene, seamlessly.
			if pos.distance_to(b.at) <= float(b.radius) + float(b.handoff):
				handoff(b.id)
				return
		elif not b.child and self_handoff > 0.0:
			# Issue #99: far enough off this ball: the parent's scene, seamlessly.
			if pos.distance_to(Vector3(0, -self_radius, 0)) >= self_radius + self_handoff + HYSTERESIS:
				handoff(b.id)
				return
		elif distance_to(b.id) <= 0.0:
			go(b.id)
			return


## Issue #99: switch to planet `id`'s scene now, with no fade: the ship carries on
## from the same point (in that planet's coordinates), heading, speed and throttle.
func handoff(id: String) -> void:
	var b: Dictionary = {}
	for x in bodies:
		if x.id == id:
			b = x
	if b.is_empty() or traveling != "":
		return
	traveling = id
	handoffs += 1
	if pilot.fight != null:
		pilot.end_fight("left")
	travel_started.emit(id)
	var look = pilot.demo.get("look")
	var extra := {
		"handoff": { "position": pilot.atmo.position() - (b.offset as Vector3), "basis": pilot.atmo.flight.basis,
			"speed": pilot.atmo.speed(), "throttle": pilot._throttle },
		"hour": float(look.hour) if look != null else -1.0,
		"preset": str(look.current) if look != null else "",
	}
	if not change:
		last_handoff = extra
		return
	GameFlow.travel(get_tree() if is_inside_tree() else null, id, pilot.ship_id, str(b.name), extra)


var last_handoff: Dictionary = {}     ## what the last handoff carried (tests, with change = false)


## Leave for planet `id` now (a running space fight is broken off first).
func go(id: String) -> void:
	var b: Dictionary = {}
	for x in bodies:
		if x.id == id:
			b = x
	if b.is_empty():
		return
	traveling = id
	if pilot.fight != null:
		pilot.end_fight("left")
	pilot.hud.toast(GameFlow.label("travel_enter") % str(b.name), 3.0)
	travel_started.emit(id)
	if not change:
		return
	if not is_inside_tree():
		GameFlow.travel(null, id, pilot.ship_id, str(b.name))
		return
	var tw := create_tween()
	tw.tween_method(pilot.hud.set_fade, 0.0, 1.0, float(GameFlow.setting("fade_time", 0.6)))
	tw.tween_callback(func(): GameFlow.travel(get_tree(), id, pilot.ship_id, str(b.name)))


func _update_labels(flying: bool) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	for b in bodies:
		var l: Label = _labels.get(b.id)
		if l == null:
			continue
		if cam == null or not flying or cam.is_position_behind(b.at):
			l.visible = false
			continue
		var d := maxf(0.0, distance_to(b.id) + CAPTURE)
		l.text = GameFlow.label("travel_to") % ["◇ " + str(b.name), "%.1f km" % (d / 1000.0)]
		var sp := cam.unproject_position(b.at)
		l.position = sp + Vector2(14, -10)
		l.visible = true


## A neighbour as seen from here: a rock for a small body, a planet for a big one.
## Issue #99: a ball type with a handoff (the asteroid) is its real ball and
## station, coarse, so arriving changes only the detail.
func _body(n: Dictionary) -> Node3D:
	if bool(n.get("ball", false)) and bool(n.get("child", false)) and PlanetGen.handoff_altitude(str(n.type)) > 0.0:
		var real := _ball_body(n)
		if real != null:
			return real
	var r := float(n.radius)
	var mi := MeshInstance3D.new()
	mi.name = "Planet_" + str(n.id)
	var noise := FastNoiseLite.new()
	noise.seed = NameEngine.fnv(str(n.id)) % 1000
	noise.frequency = 1.4 / r
	noise.fractal_octaves = 3
	var sphere := SphereMesh.new()
	sphere.radius = r
	sphere.height = r * 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	var rocky := str(n.type) == "asteroid"
	mi.mesh = LookMeshKit.rock(sphere, noise, 0.3 if rocky else 0.012, 0.0, 3.0, 0.85 if rocky else 1.0) if rocky or r < 20000.0 else sphere
	var m := StandardMaterial3D.new()
	m.albedo_color = n.color
	m.albedo_texture = LookEnvironment.make_noise_texture(256, 3, 0.02)
	m.roughness = 0.95
	m.rim_enabled = not rocky
	m.rim = 0.6
	m.rim_tint = 0.4
	mi.material_override = m
	if bool(n.get("ball", false)) and str(n.type) == "sand":
		# Issue #77: the home planet seen from space is the same sand you walk on:
		# its dunes' colours and the dusk side of one real sun.
		var sand := ShaderMaterial.new()
		sand.shader = DesertTerrain.SAND_SHADER
		sand.set_shader_parameter("noise_tex", LookEnvironment.make_noise_texture(256, 3, 0.01))
		sand.set_shader_parameter("planet_center", n.at)
		sand.set_shader_parameter("planet_radius", r)
		sand.set_shader_parameter("glitter", 0.0)
		mi.material_override = sand
		_sand_bodies.append(sand)
	mi.position = n.at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = r
	return mi


## Issue #99: the neighbour's own ball (its AsteroidSphere, seated on its own
## station's footprint) at far detail, in its rock, and its station on top: the
## very shapes its own scene builds, placed at its port's offset here.
func _ball_body(n: Dictionary) -> Node3D:
	var p := PlanetGen.build(str(n.id))
	var tcfg: Dictionary = p.get("type_cfg", {})
	var surf: Dictionary = tcfg.get("surface", {})
	if p.is_empty() or str(tcfg.get("ground", "")) != "ball":
		return null
	var root := Node3D.new()
	root.name = "Planet_" + str(n.id)
	root.position = n.get("offset", n.at)
	var sp := AsteroidSphere.new(float(n.radius), surf)
	var site := site_of(p.town)
	sp.configure_site(site.floor, site.walls, site.sunken, 0.0)
	var pt := PlanetTerrain.new()
	pt.use_sphere(sp)
	pt.rock_look = surf.get("look", {})
	pt.far_chunks = 3
	pt.far_cells = 40
	root.add_child(pt)
	pt.build_far_only(n.at)
	_sand_bodies.append(pt.material)
	if pilot != null and pilot.demo != null and bool(tcfg.get("enclosed", false)):
		var ext := AsteroidWorld.new()
		root.add_child(ext)
		ext.build_exterior(p.town.get("station", {}), pilot.demo._flat_mats())
	return root


## A town's footprint for seating a ball (town_demo.desert_site, from data).
static func site_of(town: Dictionary) -> Dictionary:
	var floor_rect := Rect2()
	var sunken := []
	var first := true
	for b in town.get("boxes", []):
		if str(b.kind) != "floor":
			continue
		var r := Rect2(float(b.min[0]), float(b.min[2]), float(b.max[0]) - float(b.min[0]), float(b.max[2]) - float(b.min[2]))
		if float(b.max[1]) < -0.1:
			sunken.append({ "rect": r, "y": float(b.min[1]) })
			continue
		floor_rect = r if first else floor_rect.merge(r)
		first = false
	var bd: Dictionary = town.get("bounds", {})
	var walls := floor_rect
	if not bd.is_empty():
		walls = Rect2(float(bd.min[0]), float(bd.min[1]), float(bd.max[0]) - float(bd.min[0]), float(bd.max[1]) - float(bd.min[1]))
	return { "floor": floor_rect, "walls": walls, "sunken": sunken }
