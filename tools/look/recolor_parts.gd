extends SceneTree
## Writes the colour variants of a split character's texture (the locals). All parts
## share one texture, so every colour fits every part, and the game picks one per
## part (content/look/characters.json, model.parts).
##
##   godot --headless --path . -s res://tools/look/recolor_parts.gd -- id=local
##
## Reads "recolor" from content/look/character_models.json:
##   colors: { name: "#rrggbb" }   the cloth colour the variant should read as
##   out:    res:// path with %s for the colour name
## Only cloth is recoloured: texels light enough and not too saturated (the sand
## linen). Dark texels (black goggle lenses, belt, gloves, boots) stay as they are.
## Shading is kept: a texel keeps its brightness relative to the mean cloth colour.
## A new colour is one line in the config and a rerun.

const CFG_PATH := "res://content/look/character_models.json"
## Cloth mask: brightness ramps in between these values; saturation must stay under MAX_SAT.
const V_LO := 0.32
const V_HI := 0.45
const MAX_SAT := 0.6


func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var id := str(args.get("id", "local"))
	var all: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CFG_PATH))
	var cfg: Dictionary = all.get(id, {})
	if not cfg.has("recolor"):
		push_error("recolor: no recolor config for '%s'" % id)
		quit(1)
		return
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(str(cfg.out)), state) != OK:
		push_error("recolor: cannot read " + str(cfg.out) + " (run prep_character.gd first)")
		quit(1)
		return
	var scene := doc.generate_scene(state)
	var src: Image = null
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		var mat := (mi as MeshInstance3D).mesh.surface_get_material(0)
		if mat is BaseMaterial3D and (mat as BaseMaterial3D).albedo_texture != null:
			src = (mat as BaseMaterial3D).albedo_texture.get_image()
			break
	scene.free()
	if src == null:
		push_error("recolor: no albedo texture")
		quit(1)
		return
	src.decompress()
	src.convert(Image.FORMAT_RGBA8)
	var ref := _cloth_mean(src)
	print("recolor: %dx%d, mean cloth %s" % [src.get_width(), src.get_height(), ref.to_html(false)])
	var colors: Dictionary = cfg.recolor.colors
	for name in colors:
		var img := _recolor(src, ref, Color(str(colors[name])))
		var out := ProjectSettings.globalize_path(str(cfg.recolor.out) % name)
		DirAccess.make_dir_recursive_absolute(out.get_base_dir())
		img.save_png(out)
		print("recolor: wrote ", out)
	quit()


static func _mask(c: Color) -> float:
	if c.s > MAX_SAT:
		return 0.0
	return smoothstep(V_LO, V_HI, c.v)


static func _cloth_mean(img: Image) -> Color:
	var sum := Vector3.ZERO
	var n := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var c := img.get_pixel(x, y)
			if _mask(c) >= 1.0:
				sum += Vector3(c.r, c.g, c.b)
				n += 1
	sum /= maxf(n, 1)
	return Color(sum.x, sum.y, sum.z)


static func _recolor(src: Image, ref: Color, to: Color) -> Image:
	var img := src.duplicate() as Image
	var ref_l := maxf(ref.get_luminance(), 0.001)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var m := _mask(c)
			if m <= 0.0:
				continue
			var k := c.get_luminance() / ref_l
			var r := Color(to.r * k, to.g * k, to.b * k, c.a).clamp()
			img.set_pixel(x, y, c.lerp(r, m))
	return img
