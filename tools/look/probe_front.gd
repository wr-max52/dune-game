extends SceneTree
## Prints where a prepped model's front surface is (the -Z-most vertex near the
## middle, inside a height band), to place droid eyes and muzzles (issue #25).
##   godot --headless --path . -s res://tools/look/probe_front.gd -- path=res://assets/gear/droid_cargo.glb y0=0.65 y1=0.8 [x=0.12]

func _init() -> void:
	var path := ""
	var y0 := -INF
	var y1 := INF
	var half := 0.12
	for a in OS.get_cmdline_user_args():
		if a.begins_with("path="):
			path = a.substr(5)
		elif a.begins_with("y0="):
			y0 = float(a.substr(3))
		elif a.begins_with("y1="):
			y1 = float(a.substr(3))
		elif a.begins_with("x="):
			half = float(a.substr(2))
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	doc.append_from_file(ProjectSettings.globalize_path(path), state)
	var scene := doc.generate_scene(state) as Node3D
	var best := Vector3(0, 0, INF)
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var p: Node = mi
		while p != scene:
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		for v: Vector3 in mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			var w: Vector3 = xf * v
			if w.y >= y0 and w.y <= y1 and absf(w.x) < half and w.z < best.z:
				best = w
	print("front: ", best)
	scene.free()
	quit()
