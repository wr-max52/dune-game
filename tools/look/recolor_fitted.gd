extends SceneTree
## Writes colour variants for each part of a fitted character (tools/look/fit_parts.gd).
## Every part has its own texture, so each part names the colour it swaps.
##
##   godot --headless --path . -s res://tools/look/recolor_fitted.gd -- id=smuggler
##   godot --headless --path . -s res://tools/look/recolor_fitted.gd -- id=smuggler analyze=1
##   godot --headless --path . -s res://tools/look/recolor_fitted.gd -- id=kit only=void
##
## Reads "part_colors" from content/look/character_models.json:
##   out:   res:// path with %s for the part and %s for the colour name
##   parts: { part: { mesh, tol: 0.35, min_l: 0.02, variants: { name: { "#from": "#to", ... } } } }
##   (a swap's "#to" can be ["#to", tol, min_l] to set those for that swap alone: a
##   saturated accent spreads further in chroma than a neutral base, and its dark
##   folds sit under a min_l that keeps a black undersuit out of a grey swap)
## mesh names the mesh whose texture is recoloured (default: the part name). A kit
## outfit's pieces share one texture, so one entry ("player", mesh "player_torso")
## gives every piece of that outfit its variants.
## min_l leaves texels darker than it alone (a black visor on a grey helmet).
## A variant is a list of swaps. A texel is swapped when its chroma (colour divided by
## brightness, so shading does not matter) is within `tol` of a `from`'s; its
## brightness relative to `from` is kept, so folds and stitching survive. Use the same
## variant names on every part so a whole outfit can match. analyze=1 prints each
## part's main colours instead.

const CFG_PATH := "res://content/look/character_models.json"


func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var id := str(args.get("id", "smuggler"))
	var all: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CFG_PATH))
	var cfg: Dictionary = all.get(id, {})
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if not cfg.has("fit") or doc.append_from_file(ProjectSettings.globalize_path(str(cfg.fit.out)), state) != OK:
		push_error("recolor: no fitted model for '%s' (run fit_parts.gd first)" % id)
		quit(1)
		return
	var scene := doc.generate_scene(state)
	var pc: Dictionary = cfg.get("part_colors", {"parts": {}})
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var img := _albedo(mi)
		if img != null and args.has("analyze"):
			_analyze(String(mi.name), img)
	for part in ({} if args.has("analyze") else pc.parts):
		var p: Dictionary = pc.parts[part]
		var mi := scene.find_child(str(p.get("mesh", part)), true, false) as MeshInstance3D
		var img := _albedo(mi) if mi != null else null
		if img == null:
			push_error("recolor: no textured mesh for '%s'" % part)
			continue
		for name in p.variants:
			if args.has("only") and str(name) != str(args.only):
				continue        # one new variant: leave the others' files alone
			var out := ProjectSettings.globalize_path(str(pc.out) % [part, name])
			DirAccess.make_dir_recursive_absolute(out.get_base_dir())
			var v := img
			for from in p.variants[name]:
				var to = p.variants[name][from]
				var tol := float(p.get("tol", 0.35))
				var min_l := float(p.get("min_l", 0.02))
				if to is Array:
					tol = float(to[1])
					min_l = float(to[2]) if to.size() > 2 else min_l
					to = to[0]
				v = _recolor(v, Color(str(from)), Color(str(to)), tol, min_l)
			v.save_png(out)
			print("recolor: wrote ", out)
	scene.free()
	quit()


## The mesh's albedo texture as RGBA8, or null.
static func _albedo(mi: MeshInstance3D) -> Image:
	var mat := mi.mesh.surface_get_material(0)
	if not (mat is BaseMaterial3D) or (mat as BaseMaterial3D).albedo_texture == null:
		return null
	var img := (mat as BaseMaterial3D).albedo_texture.get_image()
	img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


static func _chroma(c: Color) -> Vector3:
	var l := maxf(c.get_luminance(), 0.02)
	return Vector3(c.r, c.g, c.b) / l


static func _recolor(src: Image, from: Color, to: Color, tol: float, min_l: float) -> Image:
	var img := src.duplicate() as Image
	var fc := _chroma(from)
	var fl := maxf(from.get_luminance(), 0.001)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.get_luminance() < min_l:
				continue
			var m := 1.0 - smoothstep(tol * 0.6, tol, _chroma(c).distance_to(fc))
			if m <= 0.0:
				continue
			var k := c.get_luminance() / fl
			img.set_pixel(x, y, c.lerp(Color(to.r * k, to.g * k, to.b * k, c.a).clamp(), m))
	return img


## The eight most common colours (4 bits a channel), with their share of the texture.
static func _analyze(part: String, img: Image) -> void:
	var bins := {}
	var n := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var key := Vector3i(int(c.r * 15.0), int(c.g * 15.0), int(c.b * 15.0))
			var e: Array = bins.get(key, [0, Vector3.ZERO])
			bins[key] = [e[0] + 1, e[1] + Vector3(c.r, c.g, c.b)]
			n += 1
	var keys := bins.keys()
	keys.sort_custom(func(a, b): return bins[a][0] > bins[b][0])
	var line := []
	for key in keys.slice(0, 8):
		var avg: Vector3 = bins[key][1] / bins[key][0]
		line.append("%s %d%%" % [Color(avg.x, avg.y, avg.z).to_html(false), 100 * bins[key][0] / n])
	print("analyze %s: %s" % [part, ", ".join(line)])
