class_name TownStyle
extends RefCounted
## The town style kit (issue #45). One spec -- a preset ("metallic", "snowy",
## "pastel", "desert") or plain words ("red matte metal", "pale blue glossy ceramic
## with gold trim") -- restyles a whole town: LookMaterials asks this for every
## wall, paving slab, metal trim, prop and awning it makes, so no building has to
## know. Vocabulary: content/look/town_styles.json.
##
## "desert" (and "") is the port's own look: is_identity() and nothing changes.

const DATA_PATH := "res://content/look/town_styles.json"

static var _data: Dictionary = {}

var spec := ""
var main = null                 ## Color or null: the walls
var accent = null               ## Color or null: trims and painted bands
var palette: Array = []         ## Colors: each building (and band) one of these
var metallic := -1.0            ## < 0: keep each material's own
var roughness := -1.0
var metal_walls := false        ## walls drawn as metal (hull shader), not plaster
var snow := false
var dirt = null                 ## Color or null
var dirt_amount := -1.0
var unknown: PackedStringArray = []


static func data() -> Dictionary:
	if _data.is_empty():
		_data = TownGen._read(DATA_PATH)
	return _data


static func parse(text: String) -> TownStyle:
	var s := TownStyle.new()
	s.spec = text.strip_edges().to_lower()
	s._apply_words(s.spec, 0)
	return s


func is_identity() -> bool:
	return main == null and accent == null and palette.is_empty() and metallic < 0.0 and roughness < 0.0 \
		and not snow and dirt == null and not metal_walls


func _apply_words(text: String, depth: int) -> void:
	var d := data()
	var presets: Dictionary = d.get("presets", {})
	var colors: Dictionary = d.get("colors", {})
	var shades: Dictionary = d.get("shades", {})
	var finishes: Dictionary = d.get("finishes", {})
	var materials: Dictionary = d.get("materials", {})
	var accent_words: Array = d.get("accent_words", [])
	var words := text.replace(",", " ").replace("-", " ").split(" ", false)
	var pending_shade := {}
	var next_is_accent := false
	var metal_mul := 1.0
	for w in words:
		if presets.has(w) and depth == 0:
			var p: Dictionary = presets[w]
			_apply_words(str(p.get("words", "")), depth + 1)
			if p.has("accent"):
				accent = _color(str(p.accent))
			if bool(p.get("snow", false)):
				snow = true
			for c in p.get("palette", []):
				palette.append(_color(str(c)))
			continue
		if accent_words.has(w):
			next_is_accent = true
			continue
		if shades.has(w) and not colors.has(w):
			pending_shade = shades[w]
			continue
		if colors.has(w) and not (materials.has(w) and main != null):
			var c := _shade(_color(w), pending_shade)
			pending_shade = {}
			if main == null and not next_is_accent:
				main = c
			else:
				accent = c
			next_is_accent = false
			if not materials.has(w):
				continue
		if finishes.has(w):
			var f: Dictionary = finishes[w]
			if f.has("roughness"):
				roughness = float(f.roughness)
			if f.has("metallic_mul"):
				metal_mul = float(f.metallic_mul)
			if f.has("dirt"):
				dirt_amount = float(f.dirt)
			if f.has("dirt_color"):
				dirt = Color(str(f.dirt_color))
			if bool(f.get("snow", false)):
				snow = true
			continue
		if materials.has(w):
			var m: Dictionary = materials[w]
			metallic = float(m.get("metallic", metallic))
			if roughness < 0.0:
				roughness = float(m.get("roughness", roughness))
			metal_walls = metal_walls or bool(m.get("metal_walls", false))
			continue
		if not colors.has(w):
			unknown.append(w)
	# A shade with no colour after it ("pastel plaster") shades the whole palette.
	if not pending_shade.is_empty() and main == null and palette.is_empty():
		main = _shade(Color("#d8c2a0"), pending_shade)
	if metallic >= 0.0:
		metallic = clampf(metallic * metal_mul, 0.0, 1.0)


static func _color(name: String) -> Color:
	var c: Dictionary = data().get("colors", {})
	return Color(str(c.get(name, "#808080")))


static func _shade(c: Color, sh: Dictionary) -> Color:
	if sh.is_empty():
		return c
	var out := c
	if sh.has("lighten"):
		out = out.lightened(float(sh.lighten))
	if sh.has("darken"):
		out = out.darkened(float(sh.darken))
	if sh.has("desaturate"):
		out = Color.from_hsv(out.h, out.s * (1.0 - float(sh.desaturate)), out.v)
	if sh.has("saturate"):
		out = Color.from_hsv(out.h, minf(1.0, out.s * (1.0 + float(sh.saturate))), out.v)
	return out


# ------------------------------------------------------------------ for LookMaterials

## A wall's plaster tint. Huts keep a little of their own tint so a street is not
## one flat colour; a palette gives each building one of its colours.
func wall(tint: Color) -> Color:
	if not palette.is_empty():
		return palette[_pick(tint, palette.size())]
	if main != null:
		return (main as Color).lerp(tint, 0.18)
	if snow:
		return tint.lerp(Color("#f2f4f6"), 0.75)
	return tint


## A painted band or awning colour.
func band(c: Color) -> Color:
	if not palette.is_empty():
		return (palette[_pick(c, palette.size(), 3)] as Color).darkened(0.12)
	if accent != null:
		return (accent as Color).lerp(c, 0.12)
	return c


func paving() -> Color:
	if snow:
		return Color(str(data().get("snow", {}).get("paving", "#dfe6ee")))
	if main != null:
		return (main as Color).darkened(0.25).lerp(Color("#c4a882"), 0.25)
	if not palette.is_empty():
		return Color("#e6dccc")
	return Color("#c4a882")


func dirt_color(fallback: Color) -> Color:
	if snow:
		return Color(str(data().get("snow", {}).get("dirt", "#e8eef5")))
	if dirt != null:
		return dirt
	return fallback


func drift_color(fallback: Color) -> Color:
	if snow:
		return Color(str(data().get("snow", {}).get("drift", "#f4f7fb")))
	return fallback


## A prop's flat colour, pulled toward the style's.
func prop(c: Color) -> Color:
	if not palette.is_empty():
		return c.lerp(palette[_pick(c, palette.size(), 5)], 0.4)
	if main != null:
		return c.lerp(main, 0.45)
	if snow:
		return c.lerp(Color("#e8eef5"), 0.25)
	return c


## Hull metal (trims, bay posts, bridges): the style's colour when it is a metal.
func hull_metal(fallback: Color) -> Color:
	if metal_walls and main != null:
		return (main as Color).darkened(0.12)
	if accent != null and metal_walls:
		return (accent as Color).darkened(0.6)
	return fallback


func hull_metal_light(fallback: Color) -> Color:
	if metal_walls and main != null:
		return (main as Color).lightened(0.18)
	return fallback


static func _pick(c: Color, n: int, salt: int = 0) -> int:
	return absi(hash(c.to_html(false)) + salt * 7) % n
