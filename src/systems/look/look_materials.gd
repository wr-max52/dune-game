class_name LookMaterials
extends RefCounted
## Material constructors that follow the palette in docs/ART_DIRECTION.md.
## One shared noise texture feeds every shader, so they all agree on scale.

const ROCK := preload("res://src/systems/look/shaders/rock.gdshader")
const PLASTER := preload("res://src/systems/look/shaders/plaster.gdshader")
const HULL := preload("res://src/systems/look/shaders/hull.gdshader")
const ENERGY_SHIELD := preload("res://src/systems/look/shaders/energy_shield.gdshader")

const CLOTH_TEAL := Color("#1f7a78")
const CLOTH_MADDER := Color("#a8322a")
const CLOTH_SAFFRON := Color("#d99a2b")
const CLOTH_SAND := Color("#c9a77c")
const REMNANT_OXBLOOD := Color("#6b1e1e")

var noise: Texture2D
var _cache := {}
## Issue #45: the town style (TownStyle). Null or identity = the port's own look.
## Set it before the town is dressed: every wall, slab, trim, prop and awning made
## here asks it for its colours and finish.
var style: TownStyle


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
	if _styled():
		if style.metal_walls:
			return _metal_wall(ground_y, style.wall(tint), style.band(band), band_y)
		var p := { "ground_y": ground_y, "band_y": band_y, "band_color": style.band(band), "plaster": style.wall(tint) }
		_finish(p)
		return _shader(PLASTER, "plaster_%s_%s_%s_%s" % [ground_y, band_y, band.to_html(), tint.to_html()], p)
	return _shader(PLASTER, "plaster_%s_%s_%s_%s" % [ground_y, band_y, band.to_html(), tint.to_html()],
		{ "ground_y": ground_y, "band_y": band_y, "band_color": band, "plaster": tint })


func paving(tile: float = 2.4) -> ShaderMaterial:
	if _styled():
		var p := { "ground_y": 0.0, "dirt_height": 0.0, "tile_size": tile, "plaster": style.paving() }
		_finish(p)
		p.metallic_amount = minf(float(p.get("metallic_amount", 0.0)), 0.4)
		return _shader(PLASTER, "paving_%s" % tile, p)
	return _shader(PLASTER, "paving_%s" % tile,
		{ "ground_y": 0.0, "dirt_height": 0.0, "tile_size": tile, "plaster": Color("#c4a882") })


func hull(sand_y: float = 2.0, panel: float = 4.0, marking_y: float = -1000.0) -> ShaderMaterial:
	var p := { "sand_y": sand_y, "panel_size": panel, "marking_y": marking_y }
	if _styled():
		p["metal"] = style.hull_metal(Color(0.20, 0.21, 0.23))
		p["metal_light"] = style.hull_metal_light(Color(0.34, 0.34, 0.35))
		p["sand"] = style.drift_color(Color(0.79, 0.58, 0.35))
		if style.accent != null:
			p["marking"] = style.accent
		if style.metallic >= 0.0:
			p["metal_scale"] = clampf(style.metallic / 0.55, 0.0, 1.8)
		if style.roughness >= 0.0:
			p["rough_add"] = style.roughness - 0.5
	return _shader(HULL, "hull_%s_%s_%s" % [sand_y, panel, marking_y], p)


## Issue #45: a style with metal walls draws plaster walls as panelled metal.
func _metal_wall(ground_y: float, tint: Color, band: Color, band_y: float) -> ShaderMaterial:
	var p := { "sand_y": ground_y + 0.6, "panel_size": 2.4, "marking_y": band_y if band_y > -999.0 else -1000.0,
		"metal": tint.darkened(0.12), "metal_light": tint.lightened(0.18), "marking": band, "sand": style.drift_color(Color(0.79, 0.58, 0.35)),
		"metal_scale": clampf(maxf(style.metallic, 0.0) / 0.55, 0.0, 1.8),
		"rough_add": (style.roughness - 0.5) if style.roughness >= 0.0 else 0.0 }
	return _shader(HULL, "metalwall_%s_%s_%s_%s" % [ground_y, band_y, tint.to_html(), band.to_html()], p)


func _styled() -> bool:
	return style != null and not style.is_identity()


func _finish(p: Dictionary) -> void:
	if style.metallic >= 0.0:
		p["metallic_amount"] = style.metallic
	if style.roughness >= 0.0:
		p["surface_roughness"] = style.roughness
	p["dirt"] = style.dirt_color(Color(0.55, 0.42, 0.32))
	p["sand_drift"] = style.drift_color(Color(0.79, 0.58, 0.35))
	if style.dirt_amount == 0.0:
		p["dirt_height"] = 0.0


func cloth(color: Color) -> StandardMaterial3D:
	if _styled():
		color = style.band(color)
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
	if _styled():
		color = style.prop(color)
		if style.metallic >= 0.0:
			metallic = maxf(metallic, style.metallic * 0.6)
		if style.roughness >= 0.0:
			roughness = lerpf(roughness, style.roughness, 0.5)
	var key := "flat_%s_%s_%s" % [color.to_html(), roughness, metallic]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	_cache[key] = m
	return m


## Issue #355: the stalls' textured planks, canvas and painted metal
## (StallTextures), coloured through the town's style like flat() and cloth().
func wood(color: Color, roughness: float = 0.85) -> StandardMaterial3D:
	if _styled():
		color = style.prop(color)
		if style.roughness >= 0.0:
			roughness = lerpf(roughness, style.roughness, 0.5)
	return StallTextures.planks(color, roughness)


func canvas(color: Color) -> StandardMaterial3D:
	return StallTextures.canvas(style.band(color) if _styled() else color)


func painted(color: Color, roughness: float = 0.6, metallic: float = 0.4) -> StandardMaterial3D:
	if _styled():
		color = style.prop(color)
		if style.metallic >= 0.0:
			metallic = maxf(metallic, style.metallic * 0.6)
		if style.roughness >= 0.0:
			roughness = lerpf(roughness, style.roughness, 0.5)
	return StallTextures.painted(color, roughness, metallic)


## An energy shield on a mesh `size` across (a box, or a disc `size.x` wide): the
## cruiser bay's look, scan lines rolling along `lines` and a rim glowing `rim`
## metres in from each face (0 on an axis = no rim there). Not cached: each is sized.
static func energy_shield(size: Vector3, rim: Vector3, lines := Vector3.UP, disc := false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ENERGY_SHIELD
	m.set_shader_parameter("half_size", size * 0.5)
	m.set_shader_parameter("rim", rim)
	m.set_shader_parameter("line_axis", lines)
	m.set_shader_parameter("disc", disc)
	return m


func glow(color: Color) -> StandardMaterial3D:
	# Not cached: LookEnvironment drives each glow's energy with the lamps.
	var m := StandardMaterial3D.new()
	m.albedo_color = color.darkened(0.6)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 0.15
	return m
