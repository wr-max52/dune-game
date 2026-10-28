extends SceneTree
## Renders review stills of ships and speeders (issue #43): each vehicle alone, framed
## on its own bounds, from a few fixed angles under the golden-hour key light.
##
##   godot --path . -s res://tools/look/shoot_vehicles.gd -- sheet=tools/look/sheets/vehicles.json
##
## Sheet JSON:
##   out:   res:// path of the PNG: one row per cell, one column per view
##   crops: res:// folder. Instead of a sheet, write each cell's views as
##          <folder>/<cell name>_<view>.png, 1024 x 1024 on a plain grey backdrop
##          under neutral light: reference images for Hyper3D.
##   views: [ "front34", "side", "rear34", "top", "front", "back" ] (default: the first four)
##   cells: [ { name, label, and one of:
##              ship_look: a look id in content/look/ships.json (built by ShipKit),
##              speeder:   a vehicle id in content/core/vehicles (built by SpeederNode;
##                         "paint" picks one of its look.paints),
##              model:     a .glb path (loaded as-is),
##              item:      a look id in content/look/items.json (built by ItemKit),
##              droid:     a droid kind (with "variant"), built by DroidKit as in game (issue #25) } ]
## A grey 1.8 m figure stands beside each vehicle on the sheet, for scale.

const CELL := Vector2i(560, 400)
const VIEWS := {
	"front34": Vector3(-35, 20, 0), "side": Vector3(-90, 8, 0), "rear34": Vector3(-145, 18, 0),
	"top": Vector3(0, 80, 0), "front": Vector3(0, 0, 0), "back": Vector3(180, 0, 0),
}

var _cfg: Dictionary
var _crops := ""
var _cam: Camera3D
var _env: Environment


func _init() -> void:
	var path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("sheet="):
			path = a.substr(6)
	_cfg = JSON.parse_string(FileAccess.get_file_as_string("res://" + path.trim_prefix("res://")))
	_crops = ProjectSettings.globalize_path(str(_cfg.get("crops", "")))
	var size := CELL if _crops == "" else Vector2i(1024, 1024)
	DisplayServer.window_set_size(size)
	root.size = size
	_stage()
	_shoot.call_deferred()


func _stage() -> void:
	var crops := _crops != ""
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color("#d8d8d8") if crops else Color("#b9ab98")
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color("#c8c8c8") if crops else Color("#6e7fa6")
	_env.ambient_light_energy = 0.9
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.ssao_enabled = true
	_env.glow_enabled = not crops
	var we := WorldEnvironment.new()
	we.environment = _env
	root.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_color = Color.WHITE if crops else Color("#ffc48a")
	key.light_energy = 2.0
	key.shadow_enabled = true
	key.rotation_degrees = Vector3(-40, -30, 0)
	root.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color("#9fb0d6")
	fill.light_energy = 0.6
	fill.rotation_degrees = Vector3(-15, 150, 0)
	root.add_child(fill)
	if not crops:
		var ground := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(400, 400)
		ground.mesh = pm
		var gm := StandardMaterial3D.new()
		gm.albedo_color = Color("#c9955a")
		gm.roughness = 1.0
		ground.material_override = gm
		root.add_child(ground)
	_cam = Camera3D.new()
	root.add_child(_cam)
	_cam.make_current()


## The vehicle for a cell, resting on y = 0 and centred on x/z.
func _build(cell: Dictionary) -> Node3D:
	var holder := Node3D.new()
	root.add_child(holder)
	var v: Node3D = null
	if cell.has("ship_look"):
		v = ShipKit.new().build(str(cell.ship_look))
	elif cell.has("speeder"):
		# Just its look: the node itself wants a town to ride in.
		var s := SpeederNode.new()
		s.cfg = HoverModel.load_config(str(cell.speeder))
		s.paint = str(cell.get("paint", ""))
		s._build_visual()
		v = s.visual
		s.remove_child(v)
		s.free()
	elif cell.has("item"):
		v = ItemKit.new().build(str(cell.item))
	elif cell.has("droid"):
		var dc := DroidRoster.config()
		var kind := str(cell.droid)
		v = DroidKit.build(kind, DroidRoster.variant_cfg(kind, str(cell.get("variant", ""))), LookMaterials.new(),
			dc.get("kinds", {}).get(kind, {}).get("look", {}))
	elif cell.has("model"):
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(ProjectSettings.globalize_path(str(cell.model)), state) == OK:
			v = doc.generate_scene(state) as Node3D
	if v == null:
		push_error("vehicles: cannot build " + str(cell))
		return holder
	holder.add_child(v)
	var box := _aabb(holder)
	v.position -= Vector3(box.get_center().x, box.position.y, box.get_center().z)
	return holder


func _shoot() -> void:
	var views: Array = _cfg.get("views", ["front34", "side", "rear34", "top"])
	var cells: Array = _cfg.cells
	var sheet: Image = null
	if _crops != "":
		DirAccess.make_dir_recursive_absolute(_crops)
	for r in cells.size():
		var cell: Dictionary = cells[r]
		var holder := _build(cell)
		var figure := _figure() if _crops == "" else null
		var box := _aabb(holder)
		if figure != null:
			figure.position = Vector3(box.end.x + 1.2, 0, box.end.z - 0.5)
		for c in views.size():
			_aim(box, VIEWS[str(views[c])], _crops != "")
			if figure != null:
				figure.visible = str(views[c]) != "top"
			var img := await _grab()
			if _crops != "":
				var p := _crops.path_join("%s_%s.png" % [cell.get("name", str(r)), views[c]])
				img.save_png(p)
				print("vehicles: wrote ", p)
				continue
			if sheet == null:
				sheet = Image.create(CELL.x * views.size(), CELL.y * cells.size(), false, img.get_format())
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(c * CELL.x, r * CELL.y))
		holder.queue_free()
		if figure != null:
			figure.queue_free()
	if sheet != null:
		var out := ProjectSettings.globalize_path(str(_cfg.out))
		DirAccess.make_dir_recursive_absolute(out.get_base_dir())
		sheet.save_png(out)
		print("vehicles: wrote ", out)
	quit()


## Frame the box from yaw/pitch (degrees; yaw 0 looks at the nose, which faces -Z).
## Crops are orthographic so Hyper3D sees true proportions.
func _aim(box: AABB, view: Vector3, ortho: bool) -> void:
	var yaw := deg_to_rad(view.x)
	var pitch := deg_to_rad(view.y)
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	var c := box.get_center()
	var radius := box.size.length() * 0.5
	if ortho:
		_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		_cam.size = radius * 2.1
		_cam.position = c + dir * 100.0
	else:
		_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		_cam.fov = 35.0
		_cam.position = c + dir * radius / tan(deg_to_rad(_cam.fov * 0.5)) * 1.05
	_cam.far = 400.0
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.FORWARD
	_cam.look_at(c, up)


## A plain 1.8 m stand-in person, for scale.
func _figure() -> Node3D:
	var f := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.25
	cap.height = 1.8
	f.mesh = cap
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("#5a5f68")
	f.material_override = m
	var holder := Node3D.new()
	holder.add_child(f)
	f.position.y = 0.9
	root.add_child(holder)
	return holder


static func _aabb(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var b: AABB = (n.global_transform.affine_inverse() * mi.global_transform) * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _grab() -> Image:
	for f in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
