class_name LookMaterials
extends RefCounted
## Material constructors that follow the palette in docs/ART_DIRECTION.md.
## One shared noise texture feeds every shader, so they all agree on scale.

const ROCK := preload("res://src/systems/look/shaders/rock.gdshader")
const PLASTER := preload("res://src/systems/look/shaders/plaster.gdshader")
const HULL := preload("res://src/systems/look/shaders/hull.gdshader")

const CLOTH_TEAL := Color("#1f7a78")
const CLOTH_MADDER := Color("#a8322a")
const CLOTH_SAFFRON := Color("#d99a2b")
const CLOTH_SAND := Color("#c9a77c")
const REMNANT_OXBLOOD := Color("#6b1e1e")

var noise: Texture2D
var _cache := {}


func _init(noise_tex: Texture2D = null) -> void:
	noise = noise_tex if noise_tex != null else LookEnvironment.make_noise_texture(512, 7, 0.012)


func _shader(shader: Shader, key: String, params: Dictionary) -> ShaderMaterial:
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("noise_tex", noise)
	for k in params:
		m.set_shader_parameter(k, params[k])
	_cache[key] = m
	return m


func rock(ground_y: float = 0.0, strata_scale: float = 0.35) -> ShaderMaterial:
	return _shader(ROCK, "rock_%s_%s" % [ground_y, strata_scale],
		{ "ground_y": ground_y, "strata_scale": strata_scale })


func plaster(ground_y: float = 8.0, band_y: float = -1000.0, band: Color = CLOTH_TEAL, tint: Color = Color("#d8c2a0")) -> ShaderMaterial:
	return _shader(PLASTER, "plaster_%s_%s_%s_%s" % [ground_y, band_y, band.to_html(), tint.to_html()],
		{ "ground_y": ground_y, "band_y": band_y, "band_color": band, "plaster": tint })


func paving(tile: float = 2.4) -> ShaderMaterial:
	return _shader(PLASTER, "paving_%s" % tile,
		{ "ground_y": 0.0, "dirt_height": 0.0, "tile_size": tile, "plaster": Color("#c4a882") })


func hull(sand_y: float = 2.0, panel: float = 4.0, marking_y: float = -1000.0) -> ShaderMaterial:
	return _shader(HULL, "hull_%s_%s_%s" % [sand_y, panel, marking_y],
		{ "sand_y": sand_y, "panel_size": panel, "marking_y": marking_y })


func cloth(color: Color) -> StandardMaterial3D:
	var key := "cloth_" + color.to_html()
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Backlit cloth glows with its own dye colour: the Journey trick.
	m.backlight_enabled = true
	m.backlight = color.lightened(0.2)
	_cache[key] = m
	return m


func flat(color: Color, roughness: float = 0.9, metallic: float = 0.0) -> StandardMaterial3D:
	var key := "flat_%s_%s_%s" % [color.to_html(), roughness, metallic]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	_cache[key] = m
	return m


func glow(color: Color) -> StandardMaterial3D:
	# Not cached: LookEnvironment drives each glow's energy with the lamps.
	var m := StandardMaterial3D.new()
	m.albedo_color = color.darkened(0.6)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 0.15
	return m
