extends SceneTree
## Turns a raw Hyper3D vehicle (issue #43) into a game model: turned to face -Z,
## scaled to its length in metres, centred on its middle, written as a .glb that
## ShipKit (a ship look's "scene") or SpeederNode (a vehicle look's "scene") loads.
##
##   godot --headless --path . -s res://tools/look/prep_vehicle.gd -- id=interceptor
##   godot --headless --path . -s res://tools/look/prep_vehicle.gd            # every entry
##
## Reads content/look/vehicle_models.json:
##   { id: { source, out, yaw_deg (turns the raw model so its nose faces -Z),
##           length (metres, nose to tail), max_span (metres; shrinks it further if
##           wider), max_height, paint ({ body, trim, glow, glow_energy,
##           metallic, roughness }: a paint job on the albedo, a lit core and
##           the finish; see _paint) } }
## Hyper3D models come out about 2 units long, facing any way; the numbers here are
## the only fix-up, so a re-generation is one source path and one yaw.

const CFG_PATH := "res://content/look/vehicle_models.json"


func _init() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("id="):
			only = a.substr(3)
	var all: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CFG_PATH))
	for id in all:
		if not (all[id] is Dictionary and all[id].has("source")) or (only != "" and id != only):
			continue
		_prep(id, all[id])
	quit()


func _prep(id: String, c: Dictionary) -> void:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(str(c.source)), state) != OK:
		push_error("prep_vehicle: cannot read " + str(c.source))
		return
	var model := doc.generate_scene(state) as Node3D
	var root := Node3D.new()
	root.name = id.to_pascal_case()
	var turn := Node3D.new()
	turn.name = "Model"
	root.add_child(turn)
	turn.add_child(model)
	turn.rotation.y = deg_to_rad(float(c.get("yaw_deg", 0.0)))
	var box := _aabb(root)
	var k := float(c.length) / maxf(box.size.z, 0.001)
	if c.has("max_span"):
		k = minf(k, float(c.max_span) / maxf(box.size.x, 0.001))
	if c.has("max_height"):
		k = minf(k, float(c.max_height) / maxf(box.size.y, 0.001))
	turn.scale = Vector3.ONE * k
	box = _aabb(root)
	turn.position = -box.get_center()
	box = _aabb(root)
	if c.has("paint"):
		_paint(root, c.paint)
	_own(root, root)
	var out_doc := GLTFDocument.new()
	var out_state := GLTFState.new()
	out_doc.append_from_scene(root, out_state)
	var out := ProjectSettings.globalize_path(str(c.out))
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	if out_doc.write_to_filesystem(out_state, out) != OK:
		push_error("prep_vehicle: cannot write " + out)
		return
	var tris := 0
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			tris += mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size() / 3
	print("prep_vehicle: %s  %.2f x %.2f x %.2f m (span x height x length), %d triangles -> %s" % [
		id, box.size.x, box.size.y, box.size.z, tris, out])
	root.free()


## Issue #82: one Hyper3D model, several paint jobs. The albedo's light panels
## take `body`, its mid greys (pads, frame, trim) take `trim`, near-black (glass,
## underside) stays as it is. The blue plasma core is lit by an emission map made
## from its own pixels, recoloured to `glow` when there is one; glow_energy 0
## leaves the blue unlit (the Lanner's blue bands are paint, not a core). `bands` [trim from,
## trim to, body from, body to] moves the luminance split, and `refs` [body, trim] the
## luminance each colour is matched at, for a darker albedo (the frigate's: mostly
## 0.2 to 0.3, all of it "trim" on the defaults). `metallic` / `roughness` replace the
## model's own finish (Hyper3D's de-lit textures come out chalky: the Lanner's were
## metallic 0.01, roughness 0.86).
static func _paint(root: Node, paint: Dictionary) -> void:
	var body := Color(str(paint.get("body", "#0000")))      # alpha 0 = leave it
	var trim := Color(str(paint.get("trim", "#0000")))
	var glow := Color(str(paint.get("glow", "#0000")))
	var bands: Array = paint.get("bands", [0.08, 0.2, 0.32, 0.5])
	var refs: Array = paint.get("refs", [0.8, 0.28])
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if mat == null or mat.albedo_texture == null:
				continue
			var img := mat.albedo_texture.get_image()
			if img.is_compressed():
				img.decompress()
			img.convert(Image.FORMAT_RGBA8)
			var em := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGB8)
			for y in img.get_height():
				for x in img.get_width():
					var c := img.get_pixel(x, y)
					if c.s > 0.35 and c.v > 0.3 and c.h > 0.5 and c.h < 0.72:
						var g := Color.from_hsv(glow.h, glow.s, c.v) if glow.a > 0.0 else c
						img.set_pixel(x, y, g)
						em.set_pixel(x, y, g)
						continue
					var l := c.get_luminance()
					var out := c
					var wb := smoothstep(float(bands[2]), float(bands[3]), l) if body.a > 0.0 else 0.0
					var wt := smoothstep(float(bands[0]), float(bands[1]), l) * (1.0 - wb) if trim.a > 0.0 else 0.0
					if wb > 0.0:
						out = out.lerp(body * clampf(l / float(refs[0]), 0.6, 1.15), wb)
					if wt > 0.0:
						out = out.lerp(trim * clampf(l / float(refs[1]), 0.45, 1.3), wt)
					out.a = c.a
					img.set_pixel(x, y, out)
			mat = mat.duplicate() as BaseMaterial3D
			mat.albedo_texture = ImageTexture.create_from_image(img)
			if float(paint.get("glow_energy", 3.0)) > 0.0:
				mat.emission_enabled = true
				mat.emission = Color.WHITE
				mat.emission_texture = ImageTexture.create_from_image(em)
				mat.emission_energy_multiplier = float(paint.get("glow_energy", 3.0))
			if paint.has("metallic"):
				mat.metallic_texture = null
				mat.metallic = float(paint.metallic)
			if paint.has("roughness"):
				mat.roughness_texture = null
				mat.roughness = float(paint.roughness)
			mi.mesh.surface_set_material(s, mat)


static func _own(n: Node, owner: Node) -> void:
	for ch in n.get_children():
		ch.owner = owner
		_own(ch, owner)


static func _aabb(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var p: Node = mi
		while p != n:
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		var b: AABB = xf * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
