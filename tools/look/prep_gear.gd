extends SceneTree
## Turns a raw Hyper3D gear or droid model (issue #25) into a game model: turned,
## scaled to metres, placed on its origin, its textures shrunk and (optionally)
## washed toward grey so the game can tint it, written as a .glb.
##
##   godot --headless --path . -s res://tools/look/prep_gear.gd -- id=rifle
##   godot --headless --path . -s res://tools/look/prep_gear.gd            # every entry
##
## Reads content/look/gear_models.json:
##   { id: { source, out,
##           rot_deg   [x, y, z] turns the raw model into the game's axes,
##           size      metres along `axis` ("x", "y" or "z") after turning; axis "box"
##                     squeezes it into a 1 m cube instead (cargo cases),
##           origin    "center" (the middle of the bounds), "ground" (bottom centre) or
##                     "back" (centred, its +Z face at 0: a pack worn on the back),
##           desaturate 0..1: wash the colour texture toward grey (for tinting),
##           max_texture  pixels: textures larger than this are halved until they fit,
##           cut       { bones: [...], bone_prefix, boxes: [[x0, y0, z0, x1, y1, z1], ...],
##                     keep_near: [x, y, z, r] }: drop the triangles mostly skinned
##                     to one of `bones` or a bone starting with `bone_prefix` whose
##                     centre is in a box (any box if none) and not within r of
##                     keep_near (game axes, metres): a prop fused into a hand } }
## Hand weapons point their muzzle along +Z; droids face -Z and stand on y = 0.

const CFG_PATH := "res://content/look/gear_models.json"


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
		push_error("prep_gear: cannot read " + str(c.source))
		return
	var model := doc.generate_scene(state) as Node3D
	var root := Node3D.new()
	root.name = id.to_pascal_case()
	var turn := Node3D.new()
	turn.name = "Model"
	root.add_child(turn)
	turn.add_child(model)
	var r: Array = c.get("rot_deg", [0, 0, 0])
	turn.rotation_degrees = Vector3(float(r[0]), float(r[1]), float(r[2]))
	var box := _aabb(root)
	var axis := str(c.get("axis", "z"))
	var along := box.size.x if axis == "x" else (box.size.y if axis == "y" else box.size.z)
	turn.scale = Vector3.ONE * (float(c.get("size", 1.0)) / maxf(along, 0.001))
	if axis == "box":
		# A unit cube on every axis (the game stretches it to each item's size). Scaled
		# in the raw model's own axes, so turns of 90 degrees keep it a cube.
		turn.scale = Vector3.ONE
		model.scale = Vector3.ONE / _aabb(model).size.max(Vector3.ONE * 0.001)
	box = _aabb(root)
	if str(c.get("origin", "center")) == "ground":
		turn.position = -Vector3(box.get_center().x, box.position.y, box.get_center().z)
	elif str(c.get("origin", "center")) == "back":
		turn.position = -Vector3(box.get_center().x, box.get_center().y, box.end.z)
	else:
		turn.position = -box.get_center()
	box = _aabb(root)
	if c.has("cut"):
		_cut(root, c.cut)
	_textures(root, int(c.get("max_texture", 1024)), float(c.get("desaturate", 0.0)))
	_own(root, root)
	var out_doc := GLTFDocument.new()
	var out_state := GLTFState.new()
	out_doc.append_from_scene(root, out_state)
	var out := ProjectSettings.globalize_path(str(c.out))
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	if out_doc.write_to_filesystem(out_state, out) != OK:
		push_error("prep_gear: cannot write " + out)
		return
	var tris := 0
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			tris += mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size() / 3
	print("prep_gear: %s  bounds %s .. %s (x y z, metres), %d triangles -> %s" % [
		id, box.position, box.end, tris, out])
	root.free()


## Drop triangles (see `cut` above). Skinned meshes keep their skin; only the index
## list changes, so the vertices stay put for the rig.
func _cut(root: Node3D, cut: Dictionary) -> void:
	var bones: Array = cut.get("bones", [])
	var prefix := str(cut.get("bone_prefix", ""))
	var keep_near: Array = cut.get("keep_near", [])     ## [x, y, z, r]: never cut inside
	var boxes: Array = []
	for b in cut.get("boxes", []):
		boxes.append(AABB(Vector3(b[0], b[1], b[2]), Vector3(b[3] - b[0], b[4] - b[1], b[5] - b[2])))
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var sk := mi.get_node_or_null(mi.skeleton) as Skeleton3D if mi.skin != null else null
		var xf := Transform3D.IDENTITY
		var p: Node = mi
		while p != root:
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		var out := ArrayMesh.new()
		var dropped := 0
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var bw: PackedInt32Array = arr[Mesh.ARRAY_BONES] if arr[Mesh.ARRAY_BONES] != null else PackedInt32Array()
			var ww: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS] if arr[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
			var per := bw.size() / maxi(verts.size(), 1)
			var keep := PackedInt32Array()
			for t in range(0, idx.size(), 3):
				var tri := [idx[t], idx[t + 1], idx[t + 2]]
				var centre := (xf * verts[tri[0]] + xf * verts[tri[1]] + xf * verts[tri[2]]) / 3.0
				var in_box := boxes.is_empty()
				for b: AABB in boxes:
					if b.has_point(centre):
						in_box = true
				if keep_near.size() == 4 and centre.distance_to(Vector3(keep_near[0], keep_near[1], keep_near[2])) < float(keep_near[3]):
					in_box = false
				var on_bone := bones.is_empty() and prefix == ""
				if not on_bone and per > 0 and sk != null:
					for v in tri:
						var best := 0
						for k in per:
							if ww[v * per + k] > ww[v * per + best]:
								best = k
						var bn := sk.get_bone_name(bw[v * per + best])
						if bones.has(bn) or (prefix != "" and bn.begins_with(prefix)):
							on_bone = true
				if in_box and on_bone:
					dropped += 1
				else:
					keep.append_array(PackedInt32Array(tri))
			arr[Mesh.ARRAY_INDEX] = keep
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, mi.mesh.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
			out.surface_set_material(s, mi.mesh.surface_get_material(s))
		mi.mesh = out
		print("prep_gear: cut %d triangles from %s" % [dropped, mi.name])


## Shrink every texture to max_px and wash the colour ones toward grey.
func _textures(root: Node, max_px: int, desat: float) -> void:
	var done := {}
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if m == null:
				continue
			for slot in [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_NORMAL,
					BaseMaterial3D.TEXTURE_ORM, BaseMaterial3D.TEXTURE_METALLIC,
					BaseMaterial3D.TEXTURE_ROUGHNESS, BaseMaterial3D.TEXTURE_EMISSION]:
				var t := m.get_texture(slot)
				if t == null:
					continue
				var key := str(t.get_rid())
				if done.has(key):
					m.set_texture(slot, done[key])
					continue
				var img := t.get_image()
				if img == null:
					continue
				if img.is_compressed():
					img.decompress()
				while img.get_width() > max_px or img.get_height() > max_px:
					img.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_LANCZOS)
				if slot == BaseMaterial3D.TEXTURE_ALBEDO and desat > 0.0:
					_desaturate(img, desat)
				var nt := ImageTexture.create_from_image(img)
				done[key] = nt
				m.set_texture(slot, nt)


static func _desaturate(img: Image, k: float) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var col := img.get_pixel(x, y)
			var l := col.get_luminance()
			img.set_pixel(x, y, Color(lerpf(col.r, l, k), lerpf(col.g, l, k), lerpf(col.b, l, k), col.a))


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
