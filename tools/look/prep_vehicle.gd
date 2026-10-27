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
##           wider), max_height } }
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
