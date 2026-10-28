class_name DustWind
extends Node3D
## Wind you can see in the desert (issue #93): grains of sand flying downwind (each
## particle is two or three small separate dots strung along its path) and slow
## soft puffs, round the camera, coming and going in gusts. GPU particles, so it costs the
## CPU nothing; the sand shader adds the matching sheets on the ground itself.
## Follows the drawing camera and, on the home planet's ball, lies along its
## ground (the wind blows along the surface wherever you are). The town's
## altitude detail tiers hide it ("weather") once you fly up.
##
## Numbers: content/look/world.json "dust".

const LOOK_PATH := "res://content/look/world.json"

var cfg: Dictionary = {}
var wind := Vector2(0.8, 0.6)        ## the sand shader's wind_dir (map / ground plane)
var streaks: GPUParticles3D
var puffs: GPUParticles3D
var gust := 1.0                      ## 0..1, how hard it is blowing right now (read by tests)
var _t := 0.0
var _gusts := FastNoiseLite.new()


func _ready() -> void:
	name = "DustWind"
	cfg = ItemKit._read_json(LOOK_PATH).get("dust", {})
	streaks = _layer("Streaks", cfg.get("streaks", {}), true)
	puffs = _layer("Puffs", cfg.get("puffs", {}), false)
	_gusts.seed = 17
	_gusts.frequency = float(cfg.get("gust_rate", 0.12))


## The wind blows along this ground-plane direction (as the sand shader's wind_dir).
func set_wind(dir: Vector2) -> void:
	wind = dir.normalized()


func _process(dt: float) -> void:
	# Gusts: the dust comes in waves, a lull then a blow, never quite still.
	_t += dt
	gust = smoothstep(-0.35, 0.55, _gusts.get_noise_1d(_t))
	var lull := float(cfg.get("lull", 0.12))
	streaks.amount_ratio = lerpf(lull, 1.0, gust)
	puffs.amount_ratio = lerpf(lull, 1.0, smoothstep(-0.35, 0.55, _gusts.get_noise_1d(_t - 1.5)))
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	var at := cam.global_position
	var tilt := PlanetSphere.current.tilt_at(at) if PlanetSphere.current != null else Basis.IDENTITY
	# Stay on the camera, standing along its ground; the wind turns with it.
	global_transform = Transform3D(tilt * Basis.looking_at(Vector3(wind.x, 0.0, wind.y), Vector3.UP), at)


func _layer(n: String, c: Dictionary, streak: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = n
	p.amount = int(c.get("amount", 600 if streak else 60))
	p.lifetime = float(c.get("lifetime", 1.6 if streak else 5.0))
	p.preprocess = p.lifetime
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-80, -20, -80), Vector3(160, 40, 160))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if streak:
		p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	var m := ParticleProcessMaterial.new()
	var box := float(c.get("box", 45.0 if streak else 70.0))
	var h := float(c.get("height", 2.5 if streak else 6.0))
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(box, h * 0.5, box)
	# The node looks downwind, so local -Z is the wind; it blows along the ground.
	m.direction = Vector3(0, 0, -1)
	m.spread = float(c.get("spread", 6.0 if streak else 25.0))
	m.initial_velocity_min = float(c.get("speed_min", 9.0 if streak else 2.0))
	m.initial_velocity_max = float(c.get("speed_max", 15.0 if streak else 4.5))
	m.gravity = Vector3.ZERO
	m.scale_min = float(c.get("scale_min", 0.6))
	m.scale_max = float(c.get("scale_max", 1.4))
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.add_point(0.25, Color(1, 1, 1, 1))
	fade.add_point(0.75, Color(1, 1, 1, 1))
	fade.set_color(fade.get_point_count() - 1, Color(1, 1, 1, 0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	m.color_ramp = ramp
	p.process_material = m
	p.position = Vector3(0, h * 0.5, 0)
	var quad := QuadMesh.new()
	quad.size = Vector2(float(c.get("width", 0.05 if streak else 6.0)), float(c.get("length", 1.6 if streak else 4.0)))
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(str(c.get("color", "#e8cfa4")))
	mat.albedo_color.a = float(c.get("alpha", 0.35 if streak else 0.12))
	mat.albedo_texture = _dots() if streak else _soft(false)
	if not streak:
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.disable_receive_shadows = true
	quad.material = mat
	p.draw_pass_1 = quad
	add_child(p)
	return p


## Grains: three small soft dots strung along the quad's length (the middle one
## fainter, so many read as two), with clear gaps between them.
static func _dots() -> Texture2D:
	var w := 16
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var dots := [[0.15, 0.40, 1.0], [0.52, 0.62, 0.55], [0.86, 0.45, 0.9]]   # [along, across, strength]
	for d in dots:
		var cy := float(d[0]) * h
		var cx := float(d[1]) * w
		for y in h:
			for x in w:
				var r := Vector2((x + 0.5 - cx) / 4.0, (y + 0.5 - cy) / 4.0).length()
				var a := clampf(1.0 - r, 0.0, 1.0) * float(d[2])
				if a > img.get_pixel(x, y).a:
					img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


## A soft blob (puffs), so nothing reads as a square.
static func _soft(streak: bool) -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 64
	t.height = 64
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0) if streak else Vector2(1.0, 0.5)
	return t
