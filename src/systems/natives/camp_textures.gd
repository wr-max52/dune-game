class_name CampTextures
extends RefCounted
## Issue #96: the materials a native camp is made of, with small textures drawn
## here once (no image files): stitched hide, woven rugs, rough rock, wood grain,
## packed earth, clay, and the painted metal of scavenged canisters. Each is cached
## by its colours, so every camp on a planet shares them.
##
## Hide, rugs, wood, clay and metal map by UV (each wall panel and rug is one
## quad, so a hide panel shows its seams at its edges); rock and earth are
## triplanar, so they read the same on any shape.

const SIZE := 128

static var _mats: Dictionary = {}
static var _tex: Dictionary = {}


## Two-sided hide: sun-bleached and mottled, darker stitched seams down both sides,
## a patch or two sewn on. Takes no shadows on itself (thin two-sided cloth stripes
## with shadow acne otherwise).
static func hide(color: Color) -> StandardMaterial3D:
	var key := "hide_" + color.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.albedo_texture = _hide_tex()
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	m.backlight_enabled = true
	m.backlight = color.darkened(0.1)
	_mats[key] = m
	return m


## A woven rug: bands and a row of diamonds in `accent` on `color`.
static func rug(color: Color, accent: Color) -> StandardMaterial3D:
	var key := "rug_%s_%s" % [color.to_html(), accent.to_html()]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = _rug_tex(color, accent)
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m


static func rock(color: Color) -> StandardMaterial3D:
	return _triplanar("rock_" + color.to_html(), color, _speckle_tex(11, 0.09), _bump_tex(11, 0.09, 5.0), 0.45)


static func earth(color: Color) -> StandardMaterial3D:
	return _triplanar("earth_" + color.to_html(), color, _speckle_tex(23, 0.05), _bump_tex(23, 0.05, 2.0), 0.6)


## Wood: grain along V (a log's or a pole's length).
static func wood(color: Color) -> StandardMaterial3D:
	var key := "wood_" + color.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.albedo_texture = _grain_tex()
	m.roughness = 0.95
	_mats[key] = m
	return m


static func clay(color: Color) -> StandardMaterial3D:
	return _triplanar("clay_" + color.to_html(), color, _speckle_tex(31, 0.04), null, 1.2)


## Scavenged metal: chipped paint in `color` with a `band` stripe round it (V from
## 0.55 to 0.7 of a cylinder's height), scratches, and rust creeping up from the
## bottom.
static func canister(color: Color, band: Color) -> StandardMaterial3D:
	var key := "can_%s_%s" % [color.to_html(), band.to_html()]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = _can_tex(color, band)
	m.metallic = 0.45
	m.roughness = 0.6
	m.roughness_texture = _speckle_tex(41, 0.12)
	_mats[key] = m
	return m


# ------------------------------------------------------------------ textures

static func _triplanar(key: String, color: Color, albedo: Texture2D, normal: Texture2D, scale: float) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.albedo_texture = albedo
	m.roughness = 1.0
	m.uv1_triplanar = true
	m.uv1_world_triplanar = false
	m.uv1_scale = Vector3.ONE * scale
	if normal != null:
		m.normal_enabled = true
		m.normal_texture = normal
		m.normal_scale = 0.8
	_mats[key] = m
	return m


static func _noise(seed_value: int, freq: float, octaves: int = 4) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	n.frequency = freq
	return n


static func _done(key: String, img: Image) -> ImageTexture:
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_tex[key] = t
	return t


## Grey mottling around white (multiplies a material's colour), seamless.
static func _speckle_tex(seed_value: int, freq: float) -> ImageTexture:
	var key := "speckle_%d_%s" % [seed_value, freq]
	if _tex.has(key):
		return _tex[key]
	var img := _noise(seed_value, freq, 5).get_seamless_image(SIZE, SIZE)
	img.convert(Image.FORMAT_RGB8)
	var fine := _noise(seed_value + 1, freq * 6.0, 2)
	for y in SIZE:
		for x in SIZE:
			var v := img.get_pixel(x, y).r
			var f := fine.get_noise_2d(x, y) * 0.5 + 0.5
			var g := clampf(0.62 + v * 0.3 + f * 0.16, 0.0, 1.0)
			img.set_pixel(x, y, Color(g, g, g))
	return _done(key, img)


static func _bump_tex(seed_value: int, freq: float, strength: float) -> ImageTexture:
	var key := "bump_%d_%s_%s" % [seed_value, freq, strength]
	if _tex.has(key):
		return _tex[key]
	var img := _noise(seed_value + 7, freq * 2.0, 5).get_seamless_image(SIZE, SIZE)
	img.convert(Image.FORMAT_RGB8)
	img.bump_map_to_normal_map(strength)
	return _done(key, img)


static func _hide_tex() -> ImageTexture:
	if _tex.has("hide"):
		return _tex.hide
	var n := _noise(5, 0.03, 4)
	var hair := _noise(6, 0.35, 1)
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 96
	var patches: Array = []
	for k in 2:
		var w := rng.randi_range(22, 40)
		var h := rng.randi_range(18, 34)
		patches.append(Rect2i(rng.randi_range(14, SIZE - 14 - w), rng.randi_range(10, SIZE - 10 - h), w, h))
	for y in SIZE:
		for x in SIZE:
			var v := 0.84 + n.get_noise_2d(x, y) * 0.16 + hair.get_noise_2d(x * 0.3, y * 2.0) * 0.05
			v += 0.06 * (1.0 - float(y) / SIZE)            # bleached towards the top
			var edge := mini(x, SIZE - 1 - x)
			if edge < 3:
				v *= 0.62 + 0.1 * edge                      # the seam
			elif edge == 5 and (y / 3) % 2 == 0:
				v *= 0.7                                    # its stitches
			for r: Rect2i in patches:
				if r.has_point(Vector2i(x, y)):
					v *= 0.88
					var bx := mini(x - r.position.x, r.end.x - 1 - x)
					var by := mini(y - r.position.y, r.end.y - 1 - y)
					if mini(bx, by) == 1 and ((x + y) / 2) % 2 == 0:
						v *= 0.65
			v = clampf(v, 0.0, 1.0)
			img.set_pixel(x, y, Color(v, v * 0.98, v * 0.95))
	return _done("hide", img)


static func _rug_tex(color: Color, accent: Color) -> ImageTexture:
	var key := "rug_%s_%s" % [color.to_html(), accent.to_html()]
	if _tex.has(key):
		return _tex[key]
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var light := color.lightened(0.35)
	for y in SIZE:
		for x in SIZE:
			var c := color
			var by := absi(y - SIZE / 2)
			if y < 6 or y >= SIZE - 6:
				c = accent.darkened(0.2)                  # the borders
			elif y in [10, 11, SIZE - 12, SIZE - 11]:
				c = light
			elif by < 16:
				# A row of diamonds across the middle.
				var dx := absi((x % 32) - 16)
				var d := dx + by
				c = accent if d < 13 else (light if d < 15 else color)
				if d < 5:
					c = color
			elif (by > 26 and by < 30):
				c = accent if (x / 4) % 2 == 0 else light
			# The weave: alternate threads a touch lighter and darker.
			var w := 0.94 if (x + y) % 2 == 0 else 1.04
			img.set_pixel(x, y, Color(c.r * w, c.g * w, c.b * w))
	return _done(key, img)


static func _grain_tex() -> ImageTexture:
	if _tex.has("grain"):
		return _tex.grain
	var n := _noise(13, 0.05, 3)
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	for y in SIZE:
		for x in SIZE:
			var warp := n.get_noise_2d(x * 0.4, y * 0.05) * 9.0
			var ring := sin((x + warp) * 0.9) * 0.5 + 0.5
			var v := 0.7 + ring * 0.22 + n.get_noise_2d(x * 3.0, y * 0.2) * 0.08
			v = clampf(v, 0.0, 1.0)
			img.set_pixel(x, y, Color(v, v, v))
	return _done("grain", img)


static func _can_tex(color: Color, band: Color) -> ImageTexture:
	var key := "can_%s_%s" % [color.to_html(), band.to_html()]
	if _tex.has(key):
		return _tex[key]
	var chip := _noise(17, 0.09, 4)
	var rust_n := _noise(19, 0.05, 4)
	var rust := Color("#6a3a1e")
	var bare := Color("#7c7a74")
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var scratches: Array = []
	for k in 10:
		scratches.append(Vector3(rng.randf_range(0, SIZE), rng.randf_range(0, SIZE), rng.randf_range(-0.5, 0.5)))
	for y in SIZE:
		var v := float(y) / SIZE                          # 0 at the top, 1 at the bottom
		for x in SIZE:
			var c := band if v > 0.3 and v < 0.45 else color
			if (v > 0.08 and v < 0.1) or (v > 0.9 and v < 0.92):
				c = c.darkened(0.35)                      # the rolled rims
			var ch := chip.get_noise_2d(x, y)
			if ch > 0.32:
				c = bare                                  # paint chipped off
			var r := rust_n.get_noise_2d(x, y) * 0.5 + 0.5
			var up := smoothstep(0.55, 1.0, v)
			c = c.lerp(rust, clampf(up * r * 1.6 + (0.6 if ch > 0.42 else 0.0), 0.0, 0.85))
			for s: Vector3 in scratches:
				var dx := float(x) - (s.x + (float(y) - s.y) * s.z)
				if absf(dx) < 0.6 and absf(float(y) - s.y) < 14.0:
					c = c.lightened(0.25)
			img.set_pixel(x, y, c)
	return _done(key, img)
