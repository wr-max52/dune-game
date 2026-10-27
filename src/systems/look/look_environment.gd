class_name LookEnvironment
extends Node3D
## Sky, sun, fog and post-processing for a time-of-day preset from
## content/look/time_of_day.json. Add it to a scene, then call apply("golden").
## Materials that need the sun direction register with track_material().
## apply_hour(h) blends between presets by the "hours" keys in the same file
## (the F11 demo settings' time-of-day slider).

const PRESETS_PATH := "res://content/look/time_of_day.json"
const SKY_SHADER := preload("res://src/systems/look/shaders/desert_sky.gdshader")

var presets: Dictionary = {}
var default_preset := "golden"
var current := ""                    ## the preset applied, or the nearest one to `hour`
var hours: Array = []                ## [{ hour, preset }] ascending, from the json
var hour := -1.0                     ## last apply_hour(), -1 after a plain apply()
var sun: DirectionalLight3D
var world_env: WorldEnvironment
var env: Environment
var sky_mat: ShaderMaterial
var sun_dir := Vector3(0, 0.15, -1)
var lamp_level := 0.0
var _tracked: Array[ShaderMaterial] = []
var _lamps: Array[Light3D] = []
var _lamp_mats: Array[StandardMaterial3D] = []


static func load_presets(path: String = PRESETS_PATH) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("LookEnvironment: cannot open %s" % path)
		return {}
	var data = JSON.parse_string(f.get_as_text())
	return data if data is Dictionary else {}


## One shared seamless noise texture. Made synchronously from an Image so the
## first rendered frame already has it (NoiseTexture2D generates on a thread).
static func make_noise_texture(size: int = 512, seed_value: int = 7, freq: float = 0.012) -> ImageTexture:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 4
	n.frequency = freq
	var img := n.get_seamless_image(size, size)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func direction(azimuth_deg: float, elevation_deg: float) -> Vector3:
	var az := deg_to_rad(azimuth_deg)
	var el := deg_to_rad(elevation_deg)
	return Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el)).normalized()


func _init() -> void:
	name = "LookEnvironment"
	var data := load_presets()
	presets = data.get("presets", {})
	default_preset = data.get("default", "golden")
	hours = data.get("hours", [])

	sky_mat = ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	sky_mat.set_shader_parameter("cloud_noise", make_noise_texture(512, 11, 0.02))
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_hdr_threshold = 1.0
	env.ssao_radius = 1.6
	env.ssao_intensity = 1.6
	env.ssil_radius = 6.0
	env.sdfgi_use_occlusion = true
	env.sdfgi_cascades = 6
	env.sdfgi_min_cell_size = 0.4
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.volumetric_fog_sky_affect = 0.0
	env.volumetric_fog_gi_inject = 0.6
	env.adjustment_enabled = true
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	add_child(sun)


func track_material(m: ShaderMaterial) -> void:
	_tracked.append(m)
	m.set_shader_parameter("sun_dir", sun_dir)


func track_lamp(light: Light3D, glow_mat: StandardMaterial3D = null) -> void:
	_lamps.append(light)
	if glow_mat != null:
		_lamp_mats.append(glow_mat)
	_apply_lamps()


## Emissive surfaces (windows, lamp bulbs) that brighten when the preset turns lamps on.
func track_glow(m: StandardMaterial3D) -> void:
	_lamp_mats.append(m)
	_apply_lamps()


func apply(preset_id: String = "") -> void:
	if preset_id == "":
		preset_id = default_preset
	if not presets.has(preset_id):
		push_error("LookEnvironment: unknown preset '%s'" % preset_id)
		return
	current = preset_id
	hour = -1.0
	_apply_values(presets[preset_id])


## A time of day in hours (0..24), blended between the two presets keyed around
## it. `current` becomes whichever of those two is nearer.
func apply_hour(h: float) -> void:
	var k := keys_at_hour(h)
	if k.is_empty():
		return
	hour = h
	current = str(k.a) if float(k.t) < 0.5 else str(k.b)
	_apply_values(blend(presets[k.a], presets[k.b], float(k.t)))


## The two presets around hour `h` and how far from the first: { a, b, t }.
func keys_at_hour(h: float) -> Dictionary:
	var keys: Array = hours.filter(func(e): return presets.has(str(e.get("preset", ""))))
	if keys.is_empty():
		return {}
	var first: Dictionary = keys[0]
	if h <= float(first.hour):
		return { "a": str(first.preset), "b": str(first.preset), "t": 0.0 }
	for i in range(1, keys.size()):
		var lo: Dictionary = keys[i - 1]
		var hi: Dictionary = keys[i]
		if h <= float(hi.hour):
			var span := maxf(0.001, float(hi.hour) - float(lo.hour))
			return { "a": str(lo.preset), "b": str(hi.preset), "t": (h - float(lo.hour)) / span }
	var last: Dictionary = keys[keys.size() - 1]
	return { "a": str(last.preset), "b": str(last.preset), "t": 0.0 }


## The hour key of a preset (its first), so a preset button can move the slider.
func hour_of(preset_id: String) -> float:
	for e in hours:
		if str(e.get("preset", "")) == preset_id:
			return float(e.hour)
	return -1.0


## Two preset dictionaries mixed at t: numbers lerp, "#rrggbb" colors lerp,
## anything else (bools) switches at the halfway point.
static func blend(a: Variant, b: Variant, t: float) -> Variant:
	if a is Dictionary and b is Dictionary:
		var out := {}
		for key in a:
			out[key] = blend(a[key], b[key], t) if b.has(key) else a[key]
		return out
	if (a is float or a is int) and (b is float or b is int):
		return lerpf(float(a), float(b), t)
	if a is String and b is String and a.begins_with("#") and b.begins_with("#"):
		return "#" + Color.html(a).lerp(Color.html(b), t).to_html(false)
	return a if t < 0.5 else b


func _apply_values(p: Dictionary) -> void:
	var s: Dictionary = p["sun"]
	var k: Dictionary = p["sky"]
	var fog: Dictionary = p["fog"]
	var vol: Dictionary = p["volumetric"]
	var post: Dictionary = p["post"]

	sun_dir = direction(float(s["azimuth_deg"]), float(s["elevation_deg"]))
	sun.transform.basis = Basis.looking_at(-sun_dir, Vector3.UP if absf(sun_dir.y) < 0.99 else Vector3.FORWARD)
	sun.light_color = Color.html(s["color"])
	sun.light_energy = float(s["energy"])
	sun.light_angular_distance = float(s["angular_size"])
	sun.directional_shadow_max_distance = float(s["shadow_distance"])
	sun.light_volumetric_fog_energy = float(s["fog_energy"])

	sky_mat.set_shader_parameter("sun_dir", sun_dir)
	sky_mat.set_shader_parameter("zenith_color", Color.html(k["zenith"]))
	sky_mat.set_shader_parameter("horizon_color", Color.html(k["horizon"]))
	sky_mat.set_shader_parameter("ground_color", Color.html(k["ground"]))
	sky_mat.set_shader_parameter("sun_glow_color", Color.html(k["sun_glow"]))
	sky_mat.set_shader_parameter("sun_disk_color", Color.html(k["sun_disk"]))
	sky_mat.set_shader_parameter("glow_strength", float(k["glow_strength"]))
	sky_mat.set_shader_parameter("horizon_falloff", float(k["horizon_falloff"]))
	sky_mat.set_shader_parameter("sky_energy", float(k["energy"]))
	sky_mat.set_shader_parameter("cloud_cover", float(k["cloud_cover"]))
	sky_mat.set_shader_parameter("cloud_color", Color.html(k["cloud_color"]))
	sky_mat.set_shader_parameter("cloud_shadow", Color.html(k["cloud_shadow"]))
	sky_mat.set_shader_parameter("planet_dir", direction(float(k["planet_azimuth_deg"]), float(k["planet_elevation_deg"])))
	sky_mat.set_shader_parameter("planet_radius", float(k["planet_radius"]))
	sky_mat.set_shader_parameter("planet_visibility", float(k["planet_visibility"]))
	sky_mat.set_shader_parameter("planet_color_a", Color.html(k["planet_a"]))
	sky_mat.set_shader_parameter("planet_color_b", Color.html(k["planet_b"]))
	sky_mat.set_shader_parameter("ring_color", Color.html(k["ring"]))

	env.ambient_light_energy = float(p["ambient"]["energy"])
	env.fog_enabled = true
	env.fog_density = float(fog["density"])
	env.fog_aerial_perspective = float(fog["aerial"])
	env.fog_sun_scatter = float(fog["sun_scatter"])
	env.fog_light_color = Color.html(fog["color"])
	env.fog_sky_affect = float(fog["sky_affect"])
	env.fog_height = float(fog.get("height", 0.0))
	env.fog_height_density = float(fog.get("height_density", 0.0))

	env.volumetric_fog_enabled = bool(vol["enabled"])
	env.volumetric_fog_density = float(vol["density"])
	env.volumetric_fog_albedo = Color.html(vol["albedo"])
	env.volumetric_fog_anisotropy = float(vol["anisotropy"])
	env.volumetric_fog_length = float(vol["length"])

	env.tonemap_exposure = float(post["exposure"])
	env.tonemap_white = float(post["white"])
	env.glow_intensity = float(post["glow"])
	env.glow_bloom = float(post["glow_bloom"])
	env.adjustment_contrast = float(post["contrast"])
	env.adjustment_saturation = float(post["saturation"])
	env.adjustment_brightness = float(post["brightness"])
	env.ssao_enabled = bool(post["ssao"])
	env.ssil_enabled = bool(post["ssil"])
	env.sdfgi_enabled = bool(post["sdfgi"])

	lamp_level = float(p.get("lamps", 0.0))
	_apply_lamps()
	for m in _tracked:
		m.set_shader_parameter("sun_dir", sun_dir)


func _apply_lamps() -> void:
	for l in _lamps:
		l.visible = lamp_level > 0.01
		l.light_energy = lamp_level * float(l.get_meta("base_energy", 1.0))
	for m in _lamp_mats:
		m.emission_energy_multiplier = 0.15 + lamp_level * 3.0
