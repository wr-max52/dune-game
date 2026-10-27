extends SceneTree
## Prints a rigged model's meshes, bounds, bones and material settings.
##   godot --headless --path . -s res://tools/look/probe_model.gd -- path=res://assets/characters/smuggler/smuggler.glb

func _init() -> void:
	var path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("path="):
			path = a.substr(5)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(path), state) != OK:
		push_error("probe: cannot read " + path)
		quit(1)
		return
	var scene := doc.generate_scene(state)
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var m := mi.mesh
		print("mesh %s  aabb %s  surfaces %d" % [mi.name, m.get_aabb(), m.get_surface_count()])
		for s in m.get_surface_count():
			var mat := m.surface_get_material(s)
			if mat is BaseMaterial3D:
				var b := mat as BaseMaterial3D
				print("  surf %d metallic %.2f rough %.2f mtex %s rtex %s" % [s, b.metallic, b.roughness, b.metallic_texture != null, b.roughness_texture != null])
	for sk: Skeleton3D in scene.find_children("*", "Skeleton3D", true, false):
		var names := []
		for b in sk.get_bone_count():
			names.append("%s@%.2f" % [sk.get_bone_name(b), sk.get_bone_global_rest(b).origin.y])
		print("bones ", names)
	scene.free()
	quit()
