class_name ClubTextures
extends RefCounted
## Issue #261: the surfaces the clubs are dressed in, painted in code so nothing has
## to be downloaded or generated elsewhere: wood planks, a checker dance floor, a
## patterned rug, velvet, tufted leather, brushed metal, speaker cloth and panelled
## walls. Each is an albedo and a normal map (Image.bump_map_to_normal_map from the
## same height), on a StandardMaterial3D that maps it world triplanar, so a box or a
## cylinder of any size takes it without UVs and two props side by side line up.
##
## Images are made once a session (they take a few ms each at TEX px) and shared by
## every material that uses them; materials are cached by their arguments.

const TEX := 256

static var _images := {}        ## key -> [albedo ImageTexture, normal ImageTexture]
static var _mats := {}          ## key -> StandardMaterial3D


## Dark warm planks, `width` metres each (the texture repeats every 4 planks).
static func wood(tint := Color("#5a3a24"), width := 0.18, roughness := 0.62) -> StandardMaterial3D:
	return _mat("wood_%s_%s" % [tint.to_html(), width], func(): return _paint_wood(tint), 1.0 / (width * 4.0), roughness, 0.0, 0.6)


## Black and cream squares `size` metres across with a thin grout.
static func checker(a := Color("#1a1716"), b := Color("#d8cbb0"), size := 0.6) -> StandardMaterial3D:
	return _mat("checker_%s_%s_%s" % [a.to_html(), b.to_html(), size], func(): return _paint_checker(a, b), 1.0 / (size * 2.0), 0.35, 0.0, 0.5)


## A deco rug: a field, a border and a diamond lattice, `repeat` metres a tile.
static func rug(field := Color("#5a1e22"), line := Color("#c9a058"), repeat := 1.2) -> StandardMaterial3D:
	return _mat("rug_%s_%s_%s" % [field.to_html(), line.to_html(), repeat], func(): return _paint_rug(field, line), 1.0 / repeat, 0.95, 0.0, 0.3)


## Deep velvet: a fine nap with a soft sheen.
static func velvet(tint := Color("#6a1a24")) -> StandardMaterial3D:
	var m := _mat("velvet_" + tint.to_html(), func(): return _paint_velvet(tint), 3.0, 0.85, 0.0, 0.4)
	m.rim_enabled = true
	m.rim = 0.35
	m.rim_tint = 0.6
	return m


## Button-tufted leather, `cell` metres between buttons.
static func leather(tint := Color("#3a1e16"), cell := 0.22) -> StandardMaterial3D:
	return _mat("leather_%s_%s" % [tint.to_html(), cell], func(): return _paint_leather(tint), 1.0 / (cell * 4.0), 0.45, 0.0, 1.2)


## Brushed metal: fine streaks along X.
static func brushed(tint := Color("#8a8c90"), metallic := 0.85) -> StandardMaterial3D:
	return _mat("brushed_%s_%s" % [tint.to_html(), metallic], func(): return _paint_brushed(tint), 2.0, 0.32, metallic, 0.2)


## Speaker cloth: a dark woven grille.
static func grille(tint := Color("#1c1c1e")) -> StandardMaterial3D:
	return _mat("grille_" + tint.to_html(), func(): return _paint_grille(tint), 6.0, 0.9, 0.0, 0.8)


## Panelled wainscot: raised frames `panel` metres wide on a stained board.
static func panels(tint := Color("#4a2e1c"), panel := 1.2) -> StandardMaterial3D:
	return _mat("panels_%s_%s" % [tint.to_html(), panel], func(): return _paint_panels(tint), 1.0 / panel, 0.55, 0.0, 1.0)


## Diamond plate: raised diamonds on steel, for a stage deck.
static func plate(tint := Color("#5a5c62")) -> StandardMaterial3D:
	return _mat("plate_" + tint.to_html(), func(): return _paint_plate(tint), 2.5, 0.38, 0.8, 1.2)


## #269 cleanup: rusty hull plating: riveted steel plates, two to a `plate`-metre
## tile, rust blooming out of the seams and running down in streaks.
static func rust(tint := Color("#5a5450"), plate := 3.2) -> StandardMaterial3D:
	return _mat("rust_%s_%s" % [tint.to_html(), plate], func(): return _paint_rust(tint), 1.0 / plate, 0.82, 0.45, 1.1)


## #269 cleanup: a solar panel: navy cells `cell` metres across in a dark frame,
## the lines between them glowing `line` (emission from the same tile).
static func solar(line := Color("#3aa8ff"), cell := 0.5, energy := 1.4) -> StandardMaterial3D:
	var key := "solar_%s_%s_%s" % [line.to_html(), cell, energy]
	if _mats.has(key):
		return _mats[key]
	var m := _mat("solar_base_%s" % cell, func(): return _paint_solar(), 1.0 / (cell * 4.0), 0.5, 0.15, 0.6).duplicate() as StandardMaterial3D
	if not _images.has("solar_glow"):
		var g := _paint_solar_glow()
		g.generate_mipmaps()
		_images["solar_glow"] = ImageTexture.create_from_image(g)
	m.emission_enabled = true
	m.emission_texture = _images["solar_glow"]
	m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY     # only the lines glow
	m.emission = line
	m.emission_energy_multiplier = energy
	_mats[key] = m
	return m


## #269 cleanup: the same material mapped in the mesh's own space instead of the
## world's, for things that move (the barge): world triplanar slides the pattern
## across a moving hull. Cached per material.
static func local(m: StandardMaterial3D) -> StandardMaterial3D:
	var key := "local_%d" % m.get_instance_id()
	if _mats.has(key):
		return _mats[key]
	var l := m.duplicate() as StandardMaterial3D
	l.uv1_world_triplanar = false
	_mats[key] = l
	return l


## Emission on top of any of these (a glowing edge, a lit sign), not cached.
static func glow(color: Color, energy := 3.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color.darkened(0.5)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


## Light that adds itself on (a beam of haze, a lens flare), not cached.
static func beam(color: Color, alpha := 0.18) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.proximity_fade_enabled = true
	m.proximity_fade_distance = 0.6
	return m


# ------------------------------------------------------------------ materials

static func _mat(key: String, paint: Callable, scale: float, roughness: float, metallic: float, normal_depth: float) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var texs: Array = _images.get(key, [])
	if texs.is_empty():
		var out: Array = paint.call()          # [albedo Image, height Image]
		var h: Image = out[1]
		h.bump_map_to_normal_map(4.0)
		h.generate_mipmaps()
		(out[0] as Image).generate_mipmaps()
		texs = [ImageTexture.create_from_image(out[0]), ImageTexture.create_from_image(h)]
		_images[key] = texs
	var m := StandardMaterial3D.new()
	m.albedo_texture = texs[0]
	m.normal_enabled = normal_depth > 0.0
	m.normal_texture = texs[1]
	m.normal_scale = normal_depth
	m.roughness = roughness
	m.metallic = metallic
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_triplanar_sharpness = 4.0
	m.uv1_scale = Vector3.ONE * scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats[key] = m
	return m


# ------------------------------------------------------------------ painting
# Each returns [albedo, height], both TEX x TEX and seamless (every pattern repeats
# a whole number of times across the tile, and the noise is sampled tileable).

static func _noise(seed: int, freq: float, octaves := 3) -> Image:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = freq
	n.fractal_octaves = octaves
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	return n.get_seamless_image(TEX, TEX)


static func _pair() -> Array:
	return [Image.create(TEX, TEX, false, Image.FORMAT_RGBA8), Image.create(TEX, TEX, false, Image.FORMAT_RGBA8)]


static func _gray(v: float) -> Color:
	v = clampf(v, 0.0, 1.0)
	return Color(v, v, v)


static func _paint_wood(tint: Color) -> Array:
	var out := _pair()
	var grain := _noise(7, 0.02, 4)
	var fine := _noise(19, 0.12, 2)
	var planks := 4
	var pw := TEX / planks
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var shade: Array = []
	var shift: Array = []
	for i in planks:
		shade.append(rng.randf_range(-0.12, 0.12))
		shift.append(rng.randi_range(0, TEX - 1))
	for y in TEX:
		for x in TEX:
			var p := x / pw
			var u := x % pw
			var g := grain.get_pixel(x, (y + int(shift[p])) % TEX).r
			var f := fine.get_pixel(x, y).r
			var streak := 0.5 + 0.5 * sin((float(u) * 0.55 + g * 5.0) * 1.3)
			var v := 1.0 + float(shade[p]) + (streak - 0.5) * 0.16 + (f - 0.5) * 0.05
			var seam := u < 2 or (y + int(shift[p])) % TEX < 2
			var c := tint * v
			if seam:
				c = tint.darkened(0.6)
			c.a = 1.0
			out[0].set_pixel(x, y, c)
			out[1].set_pixel(x, y, _gray(0.15 if seam else 0.55 + streak * 0.015))
	return out


static func _paint_checker(a: Color, b: Color) -> Array:
	var out := _pair()
	var wear := _noise(3, 0.03, 3)
	var half := TEX / 2
	for y in TEX:
		for x in TEX:
			var on := ((x / half) + (y / half)) % 2 == 0
			var gx := mini(x % half, half - 1 - x % half)
			var gy := mini(y % half, half - 1 - y % half)
			var grout := mini(gx, gy) < 2
			var w := wear.get_pixel(x, y).r
			var c: Color = (a if on else b) * (0.92 + w * 0.16)
			if grout:
				c = Color("#2a2622")
			c.a = 1.0
			out[0].set_pixel(x, y, c)
			out[1].set_pixel(x, y, _gray(0.2 if grout else 0.6))
	return out


static func _paint_rug(field: Color, line: Color) -> Array:
	var out := _pair()
	var nap := _noise(11, 0.25, 2)
	for y in TEX:
		for x in TEX:
			var u := float(x) / TEX
			var v := float(y) / TEX
			# A diamond lattice (two diagonal line sets) and a ring in each cell.
			var d1 := absf(fposmod(u + v, 0.5) - 0.25)
			var d2 := absf(fposmod(u - v, 0.5) - 0.25)
			var lattice := minf(d1, d2) < 0.012
			var cx := fposmod(u, 0.5) - 0.25
			var cy := fposmod(v + 0.25, 0.5) - 0.25
			var ring := absf(sqrt(cx * cx + cy * cy) - 0.08) < 0.01
			var n := nap.get_pixel(x, y).r
			var c := field * (0.85 + n * 0.3)
			if lattice or ring:
				c = line * (0.85 + n * 0.2)
			c.a = 1.0
			out[0].set_pixel(x, y, c)
			out[1].set_pixel(x, y, _gray(0.45 + n * 0.2))
	return out


static func _paint_velvet(tint: Color) -> Array:
	var out := _pair()
	var nap := _noise(23, 0.35, 2)
	var crush := _noise(29, 0.015, 3)
	for y in TEX:
		for x in TEX:
			var n := nap.get_pixel(x, y).r
			var k := crush.get_pixel(x, y).r
			var c := tint * (0.75 + k * 0.45 + n * 0.1)
			c.a = 1.0
			out[0].set_pixel(x, y, c)
			out[1].set_pixel(x, y, _gray(0.4 + n * 0.3))
	return out


static func _paint_leather(tint: Color) -> Array:
	var out := _pair()
	var pores := _noise(31, 0.4, 2)
	var cells := 4
	var cw := float(TEX) / cells
	for y in TEX:
		for x in TEX:
			# Distance to the nearest button on a diamond grid (offset every other row).
			var row := floori(y / cw)
			var ox := cw * 0.5 if row % 2 == 1 else 0.0
			var bx := fposmod(x + ox, cw) - cw * 0.5
			var by := fposmod(float(y), cw) - cw * 0.5
			var d := sqrt(bx * bx + by * by) / (cw * 0.5)
			var dome := clampf(1.0 - d, 0.0, 1.0)
			var pore := pores.get_pixel(x, y).r
			var h := pow(dome, 0.6) * 0.8 + pore * 0.06
			var button := d > 0.9 or d < 0.08
			var c := tint * (0.55 + dome * 0.6 + pore * 0.08)
			if d < 0.08:
				c = tint.darkened(0.7)
			c.a = 1.0
			out[0].set_pixel(x, y, c)
			out[1].set_pixel(x, y, _gray(0.05 if button else h))
	return out


static func _paint_brushed(tint: Color) -> Array:
	var out := _pair()
	var n := FastNoiseLite.new()
	n.seed = 41
	n.frequency = 0.5
	var streaks := Image.create(TEX, TEX, false, Image.FORMAT_RGBA8)
	for y in TEX:
		var row := n.get_noise_1d(y * 3.1) * 0.5 + 0.5
		for x in TEX:
			streaks.set_pixel(x, y, _gray(row))
	var blot := _noise(43, 0.02, 3)
	for y in TEX:
		for x in TEX:
			var s := streaks.get_pixel(x, y).r
			var b := blot.get_pixel(x, y).r
			var c := tint * (0.85 + s * 0.2 + (b - 0.5) * 0.1)
			c.a = 1.0
			out[0].set_pixel(x, y, c)
			out[1].set_pixel(x, y, _gray(0.5 + s * 0.08))
	return out


static func _paint_grille(tint: Color) -> Array:
	var out := _pair()
	var cell := 8
	for y in TEX:
		for x in TEX:
			var u := x % cell - cell * 0.5 + 0.5
			var v := y % cell - cell * 0.5 + 0.5
			var hole := u * u + v * v < 6.0
			var c := tint.darkened(0.7) if hole else tint * 1.15
			c.a = 1.0
			out[0].set_pixel(x, y, c)
			out[1].set_pixel(x, y, _gray(0.1 if hole else 0.6))
	return out


static func _paint_panels(tint: Color) -> Array:
	var out := _pair()
	var grain := _noise(53, 0.03, 4)
	var frame := 18
	var bevel := 6
	for y in TEX:
		for x in TEX:
			var g := grain.get_pixel(x, (y * 3) % TEX).r
			var ex := mini(x, TEX - 1 - x)
			var ey := mini(y, TEX - 1 - y)
			var e := mini(ex, ey)
			var h := 0.7
			var shade := 1.0
			if e < frame:
				h = 0.85
				shade = 1.08
			elif e < frame + bevel:
				var k := float(e - frame) / bevel
				h = lerpf(0.85, 0.45, k)
				shade = 0.8 if ex < ey else 0.95
			else:
				h = 0.5
				shade = 0.92
			if e < 2:
				h = 0.1
				shade = 0.4
			var c := tint * (shade + (g - 0.5) * 0.25)
			c.a = 1.0
			out[0].set_pixel(x, y, c)
			out[1].set_pixel(x, y, _gray(h))
	return out


static func _paint_plate(tint: Color) -> Array:
	var out := _pair()
	var scuff := _noise(61, 0.05, 3)
	var cell := TEX / 8
	for y in TEX:
		for x in TEX:
			var row := y / cell
			var ox := cell / 2 if row % 2 == 1 else 0
			var u := float((x + ox) % cell) / cell - 0.5
			var v := float(y % cell) / cell - 0.5
			# A diamond leaning one way on even rows, the other on odd ones.
			var a := u * 0.7 + v * 0.7 if row % 2 == 0 else u * 0.7 - v * 0.7
			var b := -u * 0.7 + v * 0.7 if row % 2 == 0 else u * 0.7 + v * 0.7
			var on := absf(a) < 0.32 and absf(b) < 0.07
			var w := scuff.get_pixel(x, y).r
			var c := tint * (0.85 + w * 0.25) * (1.25 if on else 1.0)
			c.a = 1.0
			out[0].set_pixel(x, y, c)
			out[1].set_pixel(x, y, _gray(0.85 if on else 0.4))
	return out


## #269 cleanup: steel plates with a seam and a row of rivets round each, rust in
## patches that grow out of the seams, and streaks running down from them.
static func _paint_rust(tint: Color) -> Array:
	var out := _pair()
	var patch := _noise(71, 0.018, 4)
	var pit := _noise(73, 0.15, 2)
	var streak := _noise(79, 0.05, 2)
	var orange := Color("#8a4a22")
	var dark := Color("#4a2a18")
	var plates := 2
	var pw := TEX / plates
	for y in TEX:
		for x in TEX:
			var u := x % pw
			var v := (y + (pw / 2 if (x / pw) % 2 == 1 else 0)) % pw
			var e := mini(mini(u, pw - 1 - u), mini(v, pw - 1 - v))
			var seam := e < 2
			var rivet := e >= 5 and e <= 8 and (u + v) % 14 < 4 and (e == 6 or e == 7)
			var near_seam := clampf(1.0 - float(e) / 40.0, 0.0, 1.0)
			# Streaks: noise squeezed across x and stretched down y, so they run.
			var s := streak.get_pixel((x * 5) % TEX, (y / 3) % TEX).r
			var r := clampf((patch.get_pixel(x, y).r - 0.48) * 4.0 + near_seam * 0.6 + (s - 0.55) * 1.2, 0.0, 1.0)
			var p := pit.get_pixel(x, y).r
			var c := tint * (0.85 + p * 0.3)
			c = c.lerp(orange * (0.8 + p * 0.4), r * 0.85)
			c = c.lerp(dark, clampf(r - 0.6, 0.0, 1.0) * 1.5)
			var h := 0.55 - r * 0.15 * p
			if seam:
				c = c.darkened(0.55)
				h = 0.15
			elif rivet:
				c = c.lightened(0.12)
				h = 0.9
			c.a = 1.0
			out[0].set_pixel(x, y, c)
			out[1].set_pixel(x, y, _gray(h))
	return out


## #269 cleanup: 4 x 4 navy cells a tile, each with a faint crystal grain and two thin
## bus bars, in a dark frame.
static func _paint_solar() -> Array:
	var out := _pair()
	var grain := _noise(83, 0.2, 2)
	var navy := Color("#0e1c3e")
	var cell := TEX / 4
	for y in TEX:
		for x in TEX:
			var u := x % cell
			var v := y % cell
			var e := mini(mini(u, cell - 1 - u), mini(v, cell - 1 - v))
			var g := grain.get_pixel(x, y).r
			var c := navy * (0.85 + g * 0.35)
			var h := 0.6
			if e < 3:
				c = Color("#05080f")
				h = 0.3
			elif u == cell / 3 or u == cell * 2 / 3:
				c = navy.lightened(0.25)
				h = 0.65
			c.a = 1.0
			out[0].set_pixel(x, y, c)
			out[1].set_pixel(x, y, _gray(h))
	return out


## #269 cleanup: the glow of the solar tile: a thin bright line down the middle of
## each gap between cells (thin, so far off it doesn't wash the navy out).
static func _paint_solar_glow() -> Image:
	var img := Image.create(TEX, TEX, false, Image.FORMAT_RGBA8)
	var cell := TEX / 4
	for y in TEX:
		for x in TEX:
			var u := x % cell
			var v := y % cell
			var d := float(mini(mini(u, cell - 1 - u), mini(v, cell - 1 - v)))
			var k := clampf(1.0 - d / 1.5, 0.0, 1.0)
			img.set_pixel(x, y, _gray(k))
	return img
