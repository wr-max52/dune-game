class_name StallTextures
extends RefCounted
## Issue #355: what the traders' stalls are made of: sawn planks, sun-faded canvas
## and painted metal, drawn here once in code (no image files), the way
## CampTextures draws the camps.
##
## Every texture is grey around white and is tinted by the material's colour, so
## one texture serves every colour: a market of twelve stalls in six dyes builds
## three textures, once a run. All three are triplanar in the mesh's own space at
## one tile per metre (canvas: 1.5 m), so a board's grain runs along its own
## length however the stall is turned, and a 4 m counter shows four tiles, not
## one stretched one. LookMaterials.wood / canvas / painted are the way in: they
## run the colour through the town's style first.

const SIZE := 128
const BOARD := 32              ## px: four boards a tile, 25 cm each

static var _mats: Dictionary = {}
static var _tex: Dictionary = {}


## Planks: boards along the grain (V), dark seams between them, a butt joint and
## its nails somewhere up each board, a knot or two, each board a shade apart.
static func planks(color: Color, roughness: float = 0.85) -> StandardMaterial3D:
	var key := "planks_%s_%s" % [color.to_html(), roughness]
	if _mats.has(key):
		return _mats[key]
	var t: Array = _planks_tex()
	var m := _triplanar(color, t[0], t[1], 1.0)
	m.roughness = roughness
	_mats[key] = m
	return m


## Canvas for canopies and drapes: a loose weave, two wide stripes a shade lighter
## (where the sun bleached it), slubs, and stains. Two-sided and backlit like
## LookMaterials.cloth, so a canopy still glows its own dye with the sun behind it.
static func canvas(color: Color) -> StandardMaterial3D:
	var key := "canvas_" + color.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := _triplanar(color, _canvas_tex(), null, 1.0 / 1.5)
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.backlight_enabled = true
	m.backlight = color.lightened(0.2)
	_mats[key] = m
	return m


## Painted metal: half-metre panels with seams and rivets, paint chipped to the
## lighter metal under it, scratches, and grime.
static func painted(color: Color, roughness: float = 0.6, metallic: float = 0.4) -> StandardMaterial3D:
	var key := "painted_%s_%s_%s" % [color.to_html(), roughness, metallic]
	if _mats.has(key):
		return _mats[key]
	var t: Array = _metal_tex()
	var m := _triplanar(color, t[0], t[1], 1.0)
	m.roughness = roughness
	m.metallic = metallic
	_mats[key] = m
	return m


# ------------------------------------------------------------------ textures

static func _triplanar(color: Color, albedo: Texture2D, normal: Texture2D, scale: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.albedo_texture = albedo
	m.uv1_triplanar = true
	m.uv1_world_triplanar = false
	m.uv1_scale = Vector3.ONE * scale
	if normal != null:
		m.normal_enabled = true
		m.normal_texture = normal
		m.normal_scale = 0.7
	return m


## Seamless fbm noise as an image (red channel 0..1).
static func _noise_img(seed_value: int, freq: float, octaves: int = 4) -> Image:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	n.frequency = freq
	var img := n.get_seamless_image(SIZE, SIZE)
	img.convert(Image.FORMAT_RGB8)
	return img


static func _tex_from(img: Image) -> ImageTexture:
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _normal_from(height: Image, strength: float) -> ImageTexture:
	height.bump_map_to_normal_map(strength)
	return _tex_from(height)


## [albedo, normal]
static func _planks_tex() -> Array:
	if _tex.has("planks"):
		return _tex.planks
	var warp := _noise_img(31, 0.04, 3)
	var fine := _noise_img(32, 0.18, 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 355
	var boards := SIZE / BOARD
	var shade: Array = []
	var joint: Array = []
	var knot: Array = []
	for b in boards:
		shade.append(rng.randf_range(0.86, 1.04))
		joint.append(rng.randi_range(0, SIZE - 1))
		knot.append(Vector2(b * BOARD + rng.randf_range(8, BOARD - 8), rng.randf_range(0, SIZE)) if rng.randf() < 0.6 else Vector2(-99, -99))
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var hgt := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	for y in SIZE:
		for x in SIZE:
			var b := x / BOARD
			var bx := x % BOARD
			var w := warp.get_pixel(x, y).r * 6.0
			# Grain: rings along V, periodic over the tile so it wraps.
			var ring := sin((bx + w) * TAU * 3.0 / BOARD) * 0.5 + 0.5
			var v := (0.74 + ring * 0.14 + (fine.get_pixel(x, y).r - 0.5) * 0.16) * float(shade[b])
			var h := 0.75
			var k: Vector2 = knot[b]
			var kd := Vector2(x - k.x, wrapf(y - k.y, -SIZE * 0.5, SIZE * 0.5) * 0.5).length()   # long along the grain
			if kd < 3.5:
				v *= 0.55 + kd * 0.08
			elif kd < 7.0:
				v *= 0.92
			if bx < 2 or bx >= BOARD - 1:
				v *= 0.45                                  # the seam between boards
				h = 0.0
			var jd := absi(y - int(joint[b]))
			if jd < 1 or jd > SIZE - 2:
				v *= 0.5                                   # the board's butt joint
				h = 0.1
			elif jd == 3 and (bx == 7 or bx == BOARD - 8):
				v *= 0.35                                  # its nails
				h = 0.5
			v = clampf(v, 0.0, 1.0)
			img.set_pixel(x, y, Color(v, v * 0.97, v * 0.93))
			hgt.set_pixel(x, y, Color(h, h, h))
	_tex.planks = [_tex_from(img), _normal_from(hgt, 3.0)]
	return _tex.planks


static func _canvas_tex() -> ImageTexture:
	if _tex.has("canvas"):
		return _tex.canvas
	var stain := _noise_img(41, 0.03, 3)
	var slub := _noise_img(42, 0.3, 1)
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	for y in SIZE:
		for x in SIZE:
			var v := 0.9
			var sx := x % 64
			if sx >= 6 and sx < 22:
				v = 1.0                                    # a bleached stripe
			elif sx == 4 or sx == 23:
				v = 0.78                                   # its stitched edges
			v *= 0.95 if (x + y) % 2 == 0 else 1.03       # the weave
			v *= 0.94 + slub.get_pixel(x / 2, y).r * 0.1  # uneven threads along the warp
			v *= 1.0 - smoothstep(0.65, 0.95, stain.get_pixel(x, y).r) * 0.1    # faint dirt and water marks
			v = clampf(v, 0.0, 1.0)
			img.set_pixel(x, y, Color(v, v, v * 0.97))
	_tex.canvas = _tex_from(img)
	return _tex.canvas


## [albedo, normal]
static func _metal_tex() -> Array:
	if _tex.has("metal"):
		return _tex.metal
	var chip := _noise_img(51, 0.06, 4)
	var grime := _noise_img(52, 0.02, 3)
	var fine := _noise_img(53, 0.4, 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3550
	var scratches: Array = []
	for k in 14:
		scratches.append(Vector3(rng.randf_range(0, SIZE), rng.randf_range(0, SIZE), rng.randf_range(-0.6, 0.6)))
	var panel := SIZE / 2
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var hgt := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	for y in SIZE:
		for x in SIZE:
			var px := x % panel
			var py := y % panel
			var v := 0.86 + (fine.get_pixel(x, y).r - 0.5) * 0.08
			var h := 0.7
			var g := grime.get_pixel(x, y).r
			v *= 1.0 - maxf(g - 0.5, 0.0) * 0.6
			var c := chip.get_pixel(x, y).r
			if c > 0.7:
				v = 1.18 + (c - 0.7) * 0.4                 # bare metal where the paint chipped
				h = 0.6
			elif c > 0.66:
				v *= 0.7                                   # the chip's dark rim
			if px < 1 or py < 1:
				v *= 0.4                                   # the seam between panels
				h = 0.0
			elif (px == 4 or px == panel - 4) and (py == 4 or py == panel - 4 or py == panel / 2):
				v *= 1.25                                  # a rivet head
				h = 1.0
			for s: Vector3 in scratches:
				var dx := float(x) - (s.x + (float(y) - s.y) * s.z)
				if absf(dx) < 0.6 and absf(float(y) - s.y) < 10.0:
					v *= 1.2
			v = clampf(v * 0.85, 0.0, 1.0)               # bare metal ends up near white
			img.set_pixel(x, y, Color(v, v, v))
			hgt.set_pixel(x, y, Color(h, h, h))
	_tex.metal = [_tex_from(img), _normal_from(hgt, 2.0)]
	return _tex.metal
