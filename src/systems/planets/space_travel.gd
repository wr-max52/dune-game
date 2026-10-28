class_name SpaceTravel
extends Node3D
## Flying to another planet (issue #45). Every neighbour the planet generator
## lists hangs in this planet's sky where its config says ("at", metres from the
## port): the asteroid station as a lumpy grey rock, the home planet as a great
## curved world. A marker on screen names each one and how far it is. Fly into
## one (within its radius plus `capture`) and the screen fades: GameFlow.travel
## rebuilds the town scene as that planet, and you arrive in its sky, still flying
## the same ship, above its landing bay.
##
## No input of its own: ShipPilot owns the ship. This only watches where it is.

signal travel_started(to: String)

const CAPTURE := 400.0               ## metres outside a body's radius that count as "arrived"

var pilot                            ## ShipPilot
var bodies: Array = []               ## { id, name, at, radius, node }
var traveling := ""                  ## the planet a fade is taking us to ("" = none)
var change := true                   ## false: decide but do not change scene (tests)
var _layer: CanvasLayer
var _labels: Dictionary = {}         ## id -> Label
var _sand_bodies: Array = []         ## sand ShaderMaterials of ball neighbours (the sun is tracked)


func setup(ship_pilot, neighbours: Array, with_looks: bool) -> void:
	pilot = ship_pilot
	name = "SpaceTravel"
	for n in neighbours:
		var b := { "id": str(n.id), "at": n.at, "radius": float(n.radius), "type": str(n.type), "node": null,
			"name": PlanetGen.display_name(PlanetGen.build(str(n.id))) }
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
	for b in bodies:
		if distance_to(b.id) <= 0.0:
			go(b.id)
			return


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
func _body(n: Dictionary) -> Node3D:
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
