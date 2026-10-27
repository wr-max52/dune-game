extends SceneTree
## Renders a review sheet of character parts: one column per cell, a front row over a
## back row, on a plain studio backdrop under a warm key light. Used to review the
## character parts library (issue #48) before it goes into the game.
##
##   ./tools/look/shoot_sheet.sh sheet=tools/look/sheets/player_parts.json
##
## Sheet JSON:
##   title: drawn nowhere, kept for the reader
##   out:   res:// path of the PNG
##   cells: [ { label, model, show: [mesh names] (empty = all),
##              textures: { mesh name: res:// png } (swap the albedo),
##              material: { metallic, roughness, specular } (flat values, textures dropped),
##              paint: { mesh name: [low y, high y, "#rrggbb", radius] } recolours one
##                height band of the mesh within `radius` of the vertical axis (x = z = 0)
##                and keeps its texture's shading (a design change drawn onto a
##                reference, like a face wrap that leaves the hat brim alone),
##              scale: size against the others (1 = as modelled) } ]
##   crops: res:// folder. Instead of a sheet, write each cell's front, side and back
##          views as <folder>/<cell name>_<view>.png on a plain grey backdrop under
##          neutral light, no labels, no ground: reference images for Hyper3D. Each
##          cell is shot alone at 1024 x 1024, framed on its visible meshes.

const CELL_W := 420
const ROW_H := 860
const SPACING := 1.25
const VIEW_H := 2.6          ## metres the camera shows top to bottom

var _cells: Array = []
var _out := ""
var _cam: Camera3D
var _models: Array = []
var _crops := ""


func _init() -> void:
	var path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("sheet="):
			path = a.substr(6)
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://" + path.trim_prefix("res://")))
	_cells = cfg.cells
	_out = ProjectSettings.globalize_path(str(cfg.get("out", "")))
	_crops = ProjectSettings.globalize_path(str(cfg.get("crops", "")))
	var size := Vector2i(CELL_W * _cells.size(), ROW_H) if _crops == "" else Vector2i(1024, 1024)
	DisplayServer.window_set_size(size)
	root.size = size
	_stage()
	for i in _cells.size():
		_place(i, _cells[i])
	_shoot.call_deferred()


func _stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#b9ab98") if _crops == "" else Color("#d8d8d8")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#6e7fa6") if _crops == "" else Color("#c8c8c8")
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_color = Color("#ffc48a") if _crops == "" else Color.WHITE
	key.light_energy = 2.2
	key.shadow_enabled = true
	key.rotation_degrees = Vector3(-35, -35, 0)
	root.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color("#9fb0d6")
	fill.light_energy = 0.6
	fill.rotation_degrees = Vector3(-15, 150, 0)
	root.add_child(fill)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("#c9955a")
	gm.roughness = 1.0
	ground.material_override = gm
	if _crops == "":
		root.add_child(ground)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = VIEW_H
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	var mid := (_cells.size() - 1) * SPACING * 0.5
	_cam.position = Vector3(mid, VIEW_H * 0.5 - 0.12, 10.0)
	root.add_child(_cam)
	_cam.make_current()


func _place(i: int, cell: Dictionary) -> void:
	var holder := Node3D.new()
	holder.position = Vector3(i * SPACING, 0, 0)
	root.add_child(holder)
	var low := INF
	var scenes: Array = []
	for layer: Dictionary in cell.get("layers", [cell]):
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(ProjectSettings.globalize_path(str(layer.model)), state) != OK:
			push_error("sheet: cannot read " + str(layer.model))
			continue
		var scene := doc.generate_scene(state) as Node3D
		holder.add_child(scene)
		scenes.append(scene)
		low = minf(low, _dress(scene, layer, cell))
	var k := float(cell.get("scale", 1.0))
	for scene: Node3D in scenes:
		scene.scale = Vector3.ONE * k
		scene.position.y = -low * k
	_models.append(holder)
	var label := Label3D.new()
	label.text = str(cell.get("label", ""))
	label.font_size = 40
	label.outline_size = 10
	label.pixel_size = 0.0025
	label.width = 440
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.position = Vector3(i * SPACING, VIEW_H - 0.22, 1.0)
	if _crops == "":
		root.add_child(label)


## Shows the layer's meshes and applies its texture and material swaps. Returns the
## lowest point of the model (all meshes, so layers from one skeleton line up).
func _dress(scene: Node3D, layer: Dictionary, cell: Dictionary) -> float:
	var show: Array = layer.get("show", [])
	var tex: Dictionary = layer.get("textures", {})
	var mc: Dictionary = layer.get("material", cell.get("material", {}))
	var paint: Dictionary = layer.get("paint", {})
	var low := INF
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		mi.visible = show.is_empty() or show.has(String(mi.name))
		if paint.has(String(mi.name)):
			mi.material_override = _painted(mi.mesh.surface_get_material(0), paint[mi.name])
		var mat := mi.mesh.surface_get_material(0)
		if mat is BaseMaterial3D and (tex.has(String(mi.name)) or not mc.is_empty()):
			var m := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
			if tex.has(String(mi.name)):
				m.albedo_texture = ImageTexture.create_from_image(Image.load_from_file(ProjectSettings.globalize_path(str(tex[mi.name]))))
			if mc.has("metallic"):
				m.metallic_texture = null
				m.metallic = float(mc.metallic)
			if mc.has("roughness"):
				m.roughness_texture = null
				m.roughness = float(mc.roughness)
			if mc.has("specular"):
				m.metallic_specular = float(mc.specular)
			mi.set_surface_override_material(0, m)
		low = minf(low, mi.mesh.get_aabb().position.y)
	return low


## The mesh's own texture, with one height band recoloured: the band takes the
## colour, shaded by the texture's brightness so folds survive.
static func _painted(base: Material, p: Array) -> ShaderMaterial:
	var col := Color(str(p[2]))
	var sh := Shader.new()
	sh.code = """shader_type spatial;
uniform sampler2D tex : source_color;
uniform vec3 col : source_color;
uniform float lo;
uniform float hi;
uniform float radius;
varying vec3 p;
void vertex() { p = VERTEX; }
void fragment() {
	vec3 c = texture(tex, UV).rgb;
	if (p.y > lo && p.y < hi && length(p.xz) < radius) {
		float l = dot(c, vec3(0.299, 0.587, 0.114));
		c = col * clamp(l / 0.35, 0.55, 1.3);
	}
	ALBEDO = c;
	ROUGHNESS = 0.9;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("tex", (base as BaseMaterial3D).albedo_texture if base is BaseMaterial3D else null)
	m.set_shader_parameter("col", col)
	m.set_shader_parameter("lo", float(p[0]))
	m.set_shader_parameter("hi", float(p[1]))
	m.set_shader_parameter("radius", float(p[3]) if p.size() > 3 else 1e9)
	return m


func _shoot() -> void:
	if _crops != "":
		await _shoot_crops()
		quit()
		return
	var front := await _grab()
	for h: Node3D in _models:
		h.rotation_degrees.y = 180.0
	var back := await _grab()
	var sheet := Image.create(front.get_width(), front.get_height() * 2, false, front.get_format())
	sheet.blit_rect(front, Rect2i(Vector2i.ZERO, front.get_size()), Vector2i.ZERO)
	sheet.blit_rect(back, Rect2i(Vector2i.ZERO, back.get_size()), Vector2i(0, front.get_height()))
	DirAccess.make_dir_recursive_absolute(_out.get_base_dir())
	sheet.save_png(_out)
	print("sheet: wrote ", _out)
	quit()


func _shoot_crops() -> void:
	DirAccess.make_dir_recursive_absolute(_crops)
	for h: Node3D in _models:
		h.visible = false
	for i in _cells.size():
		var h: Node3D = _models[i]
		h.visible = true
		var box := _visible_aabb(h)
		var side := maxf(box.size.y, maxf(box.size.x, box.size.z)) * 1.12
		_cam.size = side
		_cam.position = Vector3(h.position.x, box.get_center().y, 10.0)
		for view: Array in [["front", 0.0], ["side", 90.0], ["back", 180.0]]:
			h.rotation_degrees.y = view[1]
			var path := _crops.path_join("%s_%s.png" % [_cells[i].get("name", str(i)), view[0]])
			(await _grab()).save_png(path)
			print("sheet: wrote ", path)
		h.visible = false


## Bounds of the visible meshes under a cell (rest pose), in the cell's space.
static func _visible_aabb(h: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in h.find_children("*", "MeshInstance3D", true, false):
		if not mi.visible:
			continue
		var b: AABB = (h.global_transform.affine_inverse() * mi.global_transform) * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _grab() -> Image:
	for f in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
