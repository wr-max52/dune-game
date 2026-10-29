extends Node3D
## Look-dev "beauty corner": one finished-looking slice of the port edge, the desert,
## and the fallen empire's wreck on the horizon. It is the visual target for the
## whole game (docs/ART_DIRECTION.md). Everything is built from code and data, so
## the local agent can change it without the editor.
##
## Run it in the editor (F6) to walk around, or shoot it with tools/lookdev/shoot.sh.

const CharacterBody := preload("res://src/systems/player/character_body.gd")
const CameraRigNode := preload("res://src/systems/camera/camera_rig_node.gd")
const SHOTS_PATH := "res://content/look/shots.json"

@export var preset := ""                ## "" = the default preset in time_of_day.json
@export var lookdev_mode := false       ## true: fixed review cameras, no player
@export var terrain_resolution := 400   ## lower it for fast headless tests

var look: LookEnvironment
var terrain: DesertTerrain
var mats: LookMaterials
var camera: Camera3D
var shots: Dictionary = {}
var wreck_anchor := Vector3.ZERO
var _smoke_mat: StandardMaterial3D
var _smoke_mats: Array[StandardMaterial3D] = []
var _rng := RandomNumberGenerator.new()
var _player: Node3D
var _rig: Node


func _ready() -> void:
	_rng.seed = 4242
	look = LookEnvironment.new()
	add_child(look)
	terrain = DesertTerrain.new()
	terrain.resolution = terrain_resolution
	add_child(terrain)
	terrain.build()
	mats = LookMaterials.new()

	_build_port()
	_build_wreck()
	_build_megaring()
	_build_landforms()
	_build_smoke()
	_build_characters()

	shots = _load_shots()
	set_preset(preset)

	if lookdev_mode:
		camera = Camera3D.new()
		camera.name = "ShotCamera"
		camera.far = 12000.0
		add_child(camera)
		camera.current = true
		show_shot("hero_vista")
	else:
		_spawn_player()


# ---------------------------------------------------------------- presets + shots

func set_preset(id: String) -> void:
	look.apply(id)
	preset = look.current
	var p: Dictionary = look.presets.get(preset, {})
	if p.has("smoke"):
		for m in _smoke_mats:
			var c := Color.html(p["smoke"])
			c.a = float(m.get_meta("alpha", 0.8))
			m.albedo_color = c


func _load_shots() -> Dictionary:
	var f := FileAccess.open(SHOTS_PATH, FileAccess.READ)
	if f == null:
		return {}
	var data = JSON.parse_string(f.get_as_text())
	return data.get("shots", {}) if data is Dictionary else {}


func shot_ids() -> Array:
	return shots.keys()


func show_shot(id: String) -> bool:
	if camera == null or not shots.has(id):
		return false
	var s: Dictionary = shots[id]
	var pos := Vector3(s["pos"][0], s["pos"][1], s["pos"][2])
	if s.has("height_above_ground"):
		pos.y = terrain.height_at(pos.x, pos.z) + float(s["height_above_ground"])
	var target := Vector3(s["target"][0], s["target"][1], s["target"][2])
	camera.fov = float(s.get("fov", 65.0))
	camera.global_position = pos
	camera.look_at(target, Vector3.UP)
	return true


# ---------------------------------------------------------------- helpers

func _add(mesh: Mesh, mat: Material, pos: Vector3, parent: Node3D,
		rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scl
	parent.add_child(mi)
	return mi


func _frustum(w: float, d: float, h: float, lean: float) -> ArrayMesh:
	return LookMeshKit.frustum(w, d, h, lean)


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _cyl(top: float, bottom: float, h: float, seg: int = 24) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


func _solid(mi: MeshInstance3D) -> void:
	mi.create_trimesh_collision()


## A cylinder collider standing on `pos`, for a dome cap over a round house.
func _cyl_solid(parent: Node3D, pos: Vector3, r: float, h: float) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = r
	shape.height = h
	cs.shape = shape
	cs.transform = Transform3D(Basis.IDENTITY, pos)
	body.add_child(cs)
	parent.add_child(body)


# ---------------------------------------------------------------- the port

const FLOOR_Y := 8.0
const WALL_R := 148.0


func _build_port() -> void:
	var port := Node3D.new()
	port.name = "Port"
	add_child(port)

	# Paving disk and its collider.
	var pave := _add(_cyl(WALL_R + 1.5, WALL_R + 1.5, 1.0, 96),
		mats.paving(1.6), Vector3(0, FLOOR_Y - 0.5, 0), port)
	pave.name = "Paving"
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = WALL_R + 1.5
	shape.height = 1.0
	col.shape = shape
	body.position = Vector3(0, FLOOR_Y - 0.5, 0)
	body.add_child(col)
	port.add_child(body)

	# Rock plinth: the cliff the port stands on.
	var plinth_noise := FastNoiseLite.new()
	plinth_noise.seed = 12
	plinth_noise.frequency = 0.006
	plinth_noise.fractal_octaves = 3
	var plinth := _cyl(WALL_R + 8.0, WALL_R + 46.0, 74.0, 72)
	plinth.rings = 14
	var cliff_mat := mats.rock(-30.0, 0.3)
	_add(LookMeshKit.rock(plinth, plinth_noise, 0.07, 0.42, 1.0), cliff_mat, Vector3(0, 4.0 - 37.0, 0), port)
	# Irregular rock masses around the plinth so the cliff is not a perfect drum.
	var rn := FastNoiseLite.new()
	rn.seed = 44
	rn.fractal_octaves = 3
	for i in 22:
		var a := TAU * i / 22.0 + _rng.randf_range(-0.08, 0.08)
		var rr := _rng.randf_range(18.0, 36.0)
		var hh := _rng.randf_range(30.0, 66.0)
		rn.frequency = 1.3 / rr
		var m := _cyl(rr * 0.82, rr, hh, 18)
		m.rings = 12
		var dist := WALL_R + 12.0 + rr * 0.45
		_add(LookMeshKit.rock(m, rn, 0.22, 0.5, float(i) * 7.0, 0.18), cliff_mat,
			Vector3(cos(a) * dist, 2.0 - hh * 0.5 - _rng.randf_range(2.0, 12.0), sin(a) * dist), port, Vector3(0, _rng.randf_range(0, 360), 0))
	_build_wall(port)
	_build_breach_rubble(port)
	_build_lane(port)
	_build_spire(port, Vector3(-22, FLOOR_Y, -112))
	_build_landing_bay(port, Vector3(48, FLOOR_Y, -40))
	_build_hero_foreground(port)


const BREACH_A := PI * 1.5 + 0.03
const BREACH_HALF := 0.075


func _build_breach_rubble(port: Node3D) -> void:
	var mat := mats.plaster(FLOOR_Y, -1000.0, LookMaterials.CLOTH_TEAL, Color("#d6bf9a"))
	var chunk_noise := FastNoiseLite.new()
	chunk_noise.seed = 8
	chunk_noise.frequency = 0.9
	var chunk_src := BoxMesh.new()
	chunk_src.size = Vector3(1.6, 0.8, 1.0)
	chunk_src.subdivide_width = 2
	chunk_src.subdivide_height = 1
	chunk_src.subdivide_depth = 2
	var chunks: Array[ArrayMesh] = []
	for k in 4:
		chunks.append(LookMeshKit.rock(chunk_src, chunk_noise, 0.35, 0.0, k * 13.0))
	for i in 26:
		var a := BREACH_A + _rng.randf_range(-BREACH_HALF, BREACH_HALF) * (1.3 if i < 10 else 0.95)
		var r := WALL_R + _rng.randf_range(-3.0, 2.5)
		var s := _rng.randf_range(0.25, 1.1) * (1.6 if i < 5 else 1.0)
		_add(chunks[i % chunks.size()], mat, Vector3(cos(a) * r, FLOOR_Y + s * 0.2, sin(a) * r), port,
			Vector3(_rng.randf_range(-25, 25), _rng.randf_range(0, 180), _rng.randf_range(-25, 25)), Vector3.ONE * s)
	# Broken parapet ends, and a scorch mark on the paving.
	for side in [-1.0, 1.0]:
		var a: float = BREACH_A + side * (BREACH_HALF + 0.004)
		_add(_box(Vector3(1.8, 1.0, 2.6)), mat, Vector3(cos(a) * (WALL_R + 1.5), FLOOR_Y + 0.9, sin(a) * (WALL_R + 1.5)), port,
			Vector3(0, -rad_to_deg(a), side * 18.0))
	# Soft scorch decal fanning back from the breach.
	var grad := Gradient.new()
	grad.set_color(0, Color(0.1, 0.08, 0.07, 0.8))
	grad.set_color(1, Color(0.1, 0.08, 0.07, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var decal := Decal.new()
	decal.texture_albedo = tex
	decal.size = Vector3(22.0, 4.0, 14.0)
	decal.position = Vector3(cos(BREACH_A) * (WALL_R - 5.0), FLOOR_Y, sin(BREACH_A) * (WALL_R - 5.0))
	decal.albedo_mix = 0.75
	port.add_child(decal)


func _build_wall(port: Node3D) -> void:
	var wall_mat := mats.plaster(2.0, 5.2, LookMaterials.REMNANT_OXBLOOD.darkened(0.1), Color("#cdb38f"))
	var gates: Array[float] = [0.0, PI * 0.5, PI]   # east, south (behind), west; never across the hero view
	var gap := 0.07
	var arcs := []
	for i in gates.size():
		var a0: float = gates[i] + gap
		var a1: float = (gates[i + 1] if i + 1 < gates.size() else gates[0] + TAU) - gap
		arcs.append([a0, a1])
	for arc in arcs:
		var a0: float = arc[0]
		var a1: float = arc[1]
		var seg := int((a1 - a0) * 60.0)
		_solid(_add(LookMeshKit.ring_segment(WALL_R, WALL_R + 5.0, -8.0, FLOOR_Y + 0.2, a0, a1, seg), wall_mat, Vector3.ZERO, port))
		# Parapet, with a breach where the hero view looks out (the wall was hit days ago).
		var parapet_mat := mats.plaster(FLOOR_Y, -1000.0, LookMaterials.CLOTH_TEAL, Color("#d6bf9a"))
		var pieces := [[a0, a1]]
		if a0 < BREACH_A and a1 > BREACH_A:
			pieces = [[a0, BREACH_A - BREACH_HALF], [BREACH_A + BREACH_HALF, a1]]
		for pc in pieces:
			var p0: float = pc[0]
			var p1: float = pc[1]
			_solid(_add(LookMeshKit.ring_segment(WALL_R + 0.6, WALL_R + 2.4, FLOOR_Y + 0.2, FLOOR_Y + 1.35, p0, p1, int((p1 - p0) * 60.0) + 1),
				parapet_mat, Vector3.ZERO, port))
		# Buttresses give the long wall rhythm and scale.
		var a := a0 + 0.06
		while a < a1 - 0.04:
			var p := Vector3(cos(a), 0, sin(a)) * (WALL_R + 6.0)
			_add(_box(Vector3(4.5, 15.0, 3.2)), wall_mat, p + Vector3(0, 0.0, 0), port, Vector3(0, -rad_to_deg(a), 0))
			a += 0.105
	# Round bastions at the gates and between them.
	for i in 6:
		var a: float = i * TAU / 6.0 + (gap * 2.2 if i % 2 == 0 else -gap * 2.2)
		if absf(wrapf(a - (-PI * 0.5), -PI, PI)) < 0.25:
			continue   # keep the hero view open
		var p := Vector3(cos(a), 0, sin(a)) * (WALL_R + 3.0)
		_solid(_add(_cyl(7.5, 8.5, 26.0, 28), wall_mat, p + Vector3(0, 3.0, 0), port))
		_add(LookMeshKit.ring_segment(6.6, 8.2, 16.0, 17.2, 0.0, TAU, 28),
			mats.plaster(FLOOR_Y), p, port)
		_banner(port, p + Vector3(0, 15.5, 0) + Vector3(cos(a), 0, sin(a)) * 8.6, a, 3.2, 9.0, LookMaterials.CLOTH_MADDER)


func _banner(parent: Node3D, top: Vector3, facing: float, w: float, h: float, color: Color) -> void:
	var m := _add(LookMeshKit.cloth(w, h, 0.5), mats.cloth(color), top, parent)
	m.rotation.y = -facing + PI * 0.5


func _dome_house(parent: Node3D, pos: Vector3, r: float, h: float, yaw: float, band: Color) -> void:
	var house := Node3D.new()
	house.position = pos
	house.rotation.y = yaw
	parent.add_child(house)
	var mat := mats.plaster(FLOOR_Y, FLOOR_Y + h - 0.6, band)
	h += 2.5
	_solid(_add(_cyl(r, r * 1.04, h, 28), mat, Vector3(0, h * 0.5, 0), house))
	_add(LookMeshKit.ring_segment(r - 0.1, r + 0.35, h - 0.1, h + 0.5, 0.0, TAU, 28), mat, Vector3.ZERO, house)
	var dome := SphereMesh.new()
	dome.radius = r * 0.92
	dome.height = r * 0.62
	dome.is_hemisphere = true
	dome.radial_segments = 28
	dome.rings = 10
	_add(dome, mat, Vector3(0, h, 0), house)
	_cyl_solid(house, Vector3(0, h + r * 0.31, 0), r * 0.92, r * 0.62)
	# Door and windows face +X locally (the lane).
	_add(_box(Vector3(1.6, 3.4, 2.6)), mat, Vector3(r - 0.3, 1.7, 0), house)
	_add(_box(Vector3(0.2, 2.6, 1.5)), mats.flat(Color("#241a15")), Vector3(r + 0.45, 1.3, 0), house)
	var win := mats.glow(Color("#ffb46a"))
	look.track_glow(win)
	for z in [-r * 0.5, r * 0.5]:
		_add(_box(Vector3(0.4, 0.8, 0.6)), win, Vector3(r * 0.86, h * 0.62, z), house)
	_lamp(house, Vector3(r + 0.7, 3.0, 1.6))


func _block_house(parent: Node3D, pos: Vector3, size: Vector3, yaw: float, band: Color) -> void:
	var house := Node3D.new()
	house.position = pos
	house.rotation.y = yaw
	parent.add_child(house)
	var mat := mats.plaster(FLOOR_Y, FLOOR_Y + size.y * 0.35, band)
	# Battered (inward-sloping) walls: a four-sided frustum, scaled to the footprint.
	_solid(_add(_frustum(size.x, size.z, size.y, 0.12), mat, Vector3(0, size.y * 0.5, 0), house))
	_add(_box(Vector3(size.x * 0.88 + 0.5, 0.5, size.z * 0.88 + 0.5)), mat, Vector3(0, size.y + 0.25, 0), house)
	if size.y > 10.0:
		# A smaller stepped upper storey.
		_add(_frustum(size.x * 0.5, size.z * 0.55, 3.2, 0.1), mat, Vector3(-size.x * 0.12, size.y + 2.1, 0), house)
	# Salvaged hull plate bolted on: the port is built from the empire's leftovers.
	if _rng.randf() < 0.5:
		_add(_box(Vector3(0.2, minf(size.y * 0.3, 3.0), minf(size.z * 0.25, 3.2))), mats.hull(-50.0, 0.8),
			Vector3(size.x * 0.44 + 0.1, size.y * 0.45, size.z * 0.22), house, Vector3(0, 0, -5.0))
	_add(_box(Vector3(0.2, 2.6, 1.5)), mats.flat(Color("#241a15")), Vector3(size.x * 0.5 + 0.02, 1.3, -size.z * 0.25), house)
	var win := mats.glow(Color("#ffb46a"))
	look.track_glow(win)
	_add(_box(Vector3(0.4, 0.9, 0.7)), win, Vector3(size.x * 0.5, size.y * 0.7, -size.z * 0.25), house)
	# Roof clutter breaks the silhouette.
	_add(_box(Vector3(1.6, 1.0, 1.2)), mats.hull(FLOOR_Y + size.y, 0.8), Vector3(-size.x * 0.2, size.y + 1.0, size.z * 0.2), house)
	_add(_cyl(0.08, 0.08, 4.0, 6), mats.flat(Color("#3b3532"), 0.6, 0.5), Vector3(size.x * 0.3, size.y + 2.5, -size.z * 0.3), house)
	_lamp(house, Vector3(size.x * 0.5 + 0.6, 2.9, -size.z * 0.25 + 1.3))


func _lamp(parent: Node3D, pos: Vector3) -> void:
	var bulb := mats.glow(Color("#ffb46a"))
	look.track_glow(bulb)
	var s := SphereMesh.new()
	s.radius = 0.16
	s.height = 0.32
	_add(s, bulb, pos, parent)
	var l := OmniLight3D.new()
	l.position = pos + Vector3(0.3, 0, 0)
	l.light_color = Color("#ffb46a")
	l.omni_range = 9.0
	l.set_meta("base_energy", 2.2)
	l.shadow_enabled = false
	parent.add_child(l)
	look.track_lamp(l)


func _awning(parent: Node3D, pos: Vector3, yaw: float, w: float, color: Color) -> void:
	var a := _add(LookMeshKit.cloth(w, 3.2, 0.45), mats.cloth(color), pos, parent)
	a.rotation = Vector3(deg_to_rad(-62), yaw, 0)
	for side in [-0.5, 0.5]:
		var post_pos := pos + Vector3(0, 0, 0)
		var off := Vector3(w * side, 0, 0).rotated(Vector3.UP, yaw) + Vector3(0, 0, 2.8).rotated(Vector3.UP, yaw)
		_add(_cyl(0.06, 0.06, 3.1, 6), mats.flat(Color("#4a3a2c")), Vector3(post_pos.x + off.x, FLOOR_Y + 1.55, post_pos.z + off.z), parent)


func _build_lane(port: Node3D) -> void:
	var cloths := [LookMaterials.CLOTH_TEAL, LookMaterials.CLOTH_MADDER, LookMaterials.CLOTH_SAFFRON, LookMaterials.CLOTH_SAND]
	var tops_w := []
	var tops_e := []
	var z := -100.0
	while z < 40.0:
		# West side (doors face +X, the lane).
		var h := _rng.randf_range(6.0, 13.0)
		var band: Color = cloths[_rng.randi() % cloths.size()]
		if _rng.randf() < 0.18:
			var r := _rng.randf_range(5.0, 7.0)
			_dome_house(port, Vector3(-34.5 - r, FLOOR_Y, z), r, h * 0.6, 0.0, band)
			tops_w.append(Vector3(-34.5, FLOOR_Y + h * 0.6, z))
		else:
			var d := _rng.randf_range(10.0, 15.0)
			_block_house(port, Vector3(-34.5 - 6.0, FLOOR_Y, z), Vector3(12.0, h, d), 0.0, band)
			tops_w.append(Vector3(-34.5, FLOOR_Y + h, z))
		if _rng.randf() < 0.6:
			_awning(port, Vector3(-34.2, FLOOR_Y + 4.2, z + _rng.randf_range(-2, 2)), PI * 0.5, _rng.randf_range(4.0, 6.0), cloths[_rng.randi() % 3])
		# East side (doors face -X).
		var h2 := _rng.randf_range(7.0, 16.0)
		var band2: Color = cloths[_rng.randi() % cloths.size()]
		var z2 := z + _rng.randf_range(-4.0, 4.0)
		if _rng.randf() < 0.15:
			var r2 := _rng.randf_range(5.0, 6.5)
			_dome_house(port, Vector3(-13.0 + r2, FLOOR_Y, z2), r2, h2 * 0.55, PI, band2)
			tops_e.append(Vector3(-13.0, FLOOR_Y + h2 * 0.55, z2))
		else:
			_block_house(port, Vector3(-13.0 + 5.0, FLOOR_Y, z2), Vector3(10.0, h2, _rng.randf_range(10.0, 14.0)), PI, band2)
			tops_e.append(Vector3(-13.0, FLOOR_Y + h2, z2))
		if _rng.randf() < 0.5:
			_awning(port, Vector3(-13.3, FLOOR_Y + 4.0, z2 + _rng.randf_range(-2, 2)), -PI * 0.5, _rng.randf_range(4.0, 6.0), cloths[_rng.randi() % 3])
		z += _rng.randf_range(14.0, 18.0)
	# Cables strung across the lane: the most "lived-in" detail per triangle.
	var cable_mat := mats.flat(Color("#2b2522"), 0.7)
	for i in mini(tops_w.size(), tops_e.size()):
		var a: Vector3 = tops_w[i] + Vector3(0, -0.6, 0)
		var b: Vector3 = tops_e[i] + Vector3(0, -0.9, _rng.randf_range(-6, 6))
		_add(LookMeshKit.tube(LookMeshKit.catenary(a, b, _rng.randf_range(1.2, 2.8), 14), 0.045, 4), cable_mat, Vector3.ZERO, port)
		if _rng.randf() < 0.5:
			var a2: Vector3 = tops_w[i] + Vector3(0, -1.8, 3)
			var b2: Vector3 = tops_e[mini(i + 1, tops_e.size() - 1)] + Vector3(0, -2.0, 0)
			_add(LookMeshKit.tube(LookMeshKit.catenary(a2, b2, 2.2, 14), 0.035, 4), cable_mat, Vector3.ZERO, port)
			# Prayer-flag style pennants on some cables.
			var pts := LookMeshKit.catenary(a2, b2, 2.2, 10)
			for k in range(1, pts.size() - 1):
				var pen := _add(LookMeshKit.cloth(0.7, 0.9, 0.05, 2, 2), mats.cloth(cloths[(i + k) % 3]), pts[k], port)
				pen.rotation.y = PI * 0.5
	# People in the lane: scale, and a reason to look down it.
	var robes := [LookMaterials.CLOTH_SAND, Color("#8a7a66"), LookMaterials.CLOTH_TEAL, Color("#5a4a3c"), LookMaterials.CLOTH_MADDER]
	for i in 11:
		var fz := _rng.randf_range(-95.0, 8.0)
		var fx := _rng.randf_range(-31.0, -16.0)
		_hooded_figure(port, Vector3(fx, FLOOR_Y, fz), _rng.randf() * TAU, robes[i % robes.size()], _rng.randf_range(1.55, 1.9))
	# Crates and barrels against the walls.
	var crate_mat := mats.hull(FLOOR_Y, 0.9)
	for i in 26:
		var side := -33.4 if i % 2 == 0 else -14.2
		var p := Vector3(side, FLOOR_Y, _rng.randf_range(-95.0, 35.0))
		var s := _rng.randf_range(0.7, 1.3)
		if _rng.randf() < 0.5:
			_add(_box(Vector3(s, s * 0.8, s * 1.2)), crate_mat, p + Vector3(0, s * 0.4, 0), port, Vector3(0, _rng.randf_range(-20, 20), 0))
		else:
			_add(_cyl(0.4, 0.4, 1.1, 12), mats.flat(Color("#6a5848").lerp(LookMaterials.CLOTH_TEAL, _rng.randf() * 0.4), 0.7, 0.3), p + Vector3(0, 0.55, 0), port)


func _build_spire(port: Node3D, base: Vector3) -> void:
	var spire := Node3D.new()
	spire.name = "CommSpire"
	spire.position = base
	port.add_child(spire)
	var mat := mats.plaster(FLOOR_Y, FLOOR_Y + 9.0, LookMaterials.CLOTH_MADDER, Color("#d2bc98"))
	_solid(_add(_cyl(7.0, 9.0, 10.0, 8), mat, Vector3(0, 5.0, 0), spire))
	_add(_cyl(3.0, 5.0, 48.0, 8), mat, Vector3(0, 34.0, 0), spire)
	for y in [16.0, 27.0, 38.0, 49.0]:
		_add(LookMeshKit.ring_segment(4.4 - y * 0.03, 6.6 - y * 0.03, y, y + 1.3, 0.0, TAU, 16), mats.hull(0.0, 2.0), Vector3.ZERO, spire)
	_add(_cyl(0.5, 1.2, 20.0, 8), mats.hull(0.0, 2.0), Vector3(0, 68.0, 0), spire)
	var dish := SphereMesh.new()
	dish.radius = 5.0
	dish.height = 2.5
	dish.is_hemisphere = true
	_add(dish, mats.hull(0.0, 1.5), Vector3(2.5, 60.0, 0), spire, Vector3(0, 0, 120))
	var beacon := mats.glow(Color("#ff5a3a"))
	beacon.emission_energy_multiplier = 4.0
	var b := SphereMesh.new()
	b.radius = 0.6
	b.height = 1.2
	_add(b, beacon, Vector3(0, 78.5, 0), spire)
	# The fallen empire's banners, half torn down.
	for i in 3:
		var a := TAU * i / 3.0 + 0.4
		var top := Vector3(cos(a) * 5.2, 47.0, sin(a) * 5.2)
		_banner(spire, top, a, 3.0, 16.0 if i != 1 else 7.0, LookMaterials.REMNANT_OXBLOOD)
	# Guy cables down to the rooftops.
	var cable_mat := mats.flat(Color("#2b2522"), 0.7)
	for t in [Vector3(-38, 14, -84), Vector3(-6, 17, -86), Vector3(-40, 12, -128), Vector3(-2, 10, -130)]:
		_add(LookMeshKit.tube(LookMeshKit.catenary(base + Vector3(0, 52, 0), t, 3.0, 18), 0.06, 4), cable_mat, Vector3.ZERO, port)


func _build_landing_bay(port: Node3D, c: Vector3) -> void:
	var bay := Node3D.new()
	bay.name = "LandingBay"
	bay.position = Vector3(c.x, 0, c.z)
	port.add_child(bay)
	_solid(_add(LookMeshKit.ring_segment(26.0, 30.0, 0.5, FLOOR_Y + 0.6, 0.0, TAU, 64), mats.plaster(0.5, 6.0, LookMaterials.CLOTH_SAFFRON), Vector3.ZERO, bay))
	_add(_cyl(26.0, 26.0, 1.0, 64), mats.hull(-10.0, 6.0), Vector3(0, 0.5, 0), bay)
	for i in 6:
		var a := TAU * i / 6.0
		_add(_box(Vector3(4.0, 3.0, 2.0)), mats.hull(0.0, 1.5), Vector3(cos(a) * 24.5, FLOOR_Y + 1.5, sin(a) * 24.5), bay, Vector3(0, -rad_to_deg(a), 0))
	var l := OmniLight3D.new()
	l.position = Vector3(0, 4.0, 0)
	l.light_color = Color("#ffcf8a")
	l.omni_range = 28.0
	l.set_meta("base_energy", 3.0)
	bay.add_child(l)
	look.track_lamp(l)


func _hooded_figure(parent: Node3D, pos: Vector3, yaw: float, cloak: Color, height: float = 1.8) -> void:
	var f := Node3D.new()
	f.position = pos
	f.rotation.y = yaw
	parent.add_child(f)
	var robe := CylinderMesh.new()
	robe.top_radius = 0.22
	robe.bottom_radius = 0.42
	robe.height = height * 0.82
	robe.radial_segments = 10
	_add(robe, mats.cloth(cloak), Vector3(0, height * 0.41, 0), f)
	var hood := SphereMesh.new()
	hood.radius = 0.2
	hood.height = 0.46
	hood.radial_segments = 10
	_add(hood, mats.cloth(cloak.darkened(0.15)), Vector3(0, height * 0.88, 0.03), f)
	# Face wrap: covered faces are a rule (docs/ART_DIRECTION.md, Characters).
	_add(_box(Vector3(0.22, 0.09, 0.05)), mats.flat(Color("#1c1816")), Vector3(0, height * 0.88, -0.17), f)
	var scarf := _add(LookMeshKit.cloth(0.35, 0.9, 0.1, 2, 4), mats.cloth(LookMaterials.CLOTH_MADDER if cloak != LookMaterials.CLOTH_MADDER else LookMaterials.CLOTH_TEAL), Vector3(0.12, height * 0.8, 0.2), f)
	scarf.rotation_degrees = Vector3(-12, 0, 8)
	_add(_cyl(0.025, 0.03, height * 1.05, 5), mats.flat(Color("#4a3a2c")), Vector3(0.38, height * 0.52, -0.05), f, Vector3(0, 0, -4))


func _build_hero_foreground(port: Node3D) -> void:
	# A squat watch tower framing the left of the poster shot.
	var t := Node3D.new()
	t.position = Vector3(-17, FLOOR_Y, -139)
	port.add_child(t)
	var mat := mats.plaster(FLOOR_Y, FLOOR_Y + 7.5, LookMaterials.CLOTH_TEAL)
	_solid(_add(_box(Vector3(6.5, 11, 6.5)), mat, Vector3(0, 5.5, 0), t, Vector3(0, 12, 0)))
	_add(_box(Vector3(7.5, 0.6, 7.5)), mat, Vector3(0, 11.3, 0), t, Vector3(0, 12, 0))
	_add(_box(Vector3(5.0, 3.0, 5.0)), mat, Vector3(0, 13.1, 0), t, Vector3(0, 12, 0))
	_add(_cyl(0.07, 0.07, 9.0, 6), mats.flat(Color("#3b3532"), 0.6, 0.4), Vector3(1.6, 19.0, 1.2), t)
	_lamp(t, Vector3(3.5, 3.2, -1.5))
	# A market stall at the right edge, cloth catching the low sun.
	_awning(port, Vector3(19.0, FLOOR_Y + 3.4, -141.0), PI, 5.5, LookMaterials.CLOTH_MADDER)
	_add(_box(Vector3(4.0, 1.0, 1.6)), mats.hull(FLOOR_Y, 0.8), Vector3(19.0, FLOOR_Y + 0.5, -141.5), port)
	for i in 5:
		_add(_box(Vector3(0.8, 0.6, 0.6)), mats.hull(FLOOR_Y, 0.6), Vector3(16.0 + i * 1.3, FLOOR_Y + 0.3, -138.5 + (i % 2) * 0.8), port, Vector3(0, i * 17, 0))
	# Foreground clutter in the bottom of the frame: crates, a tarp, a water jar.
	var crate := mats.hull(FLOOR_Y, 0.7)
	_add(_box(Vector3(1.4, 1.0, 1.1)), crate, Vector3(-2.6, FLOOR_Y + 0.5, -143.6), port, Vector3(0, 14, 0))
	_add(_box(Vector3(1.0, 0.8, 0.9)), crate, Vector3(-2.4, FLOOR_Y + 1.4, -143.5), port, Vector3(0, -8, 0))
	_add(_box(Vector3(1.2, 0.9, 1.0)), crate, Vector3(-1.0, FLOOR_Y + 0.45, -144.6), port, Vector3(0, 31, 0))
	var tarp := _add(LookMeshKit.cloth(2.2, 1.6, 0.35, 4, 4), mats.cloth(LookMaterials.CLOTH_TEAL), Vector3(-2.6, FLOOR_Y + 1.85, -143.0), port)
	tarp.rotation_degrees = Vector3(-75, 14, 0)
	var jar := SphereMesh.new()
	jar.radius = 0.32
	jar.height = 0.8
	_add(jar, mats.plaster(FLOOR_Y, -1000.0, LookMaterials.CLOTH_TEAL, Color("#b07a52")), Vector3(0.3, FLOOR_Y + 0.4, -144.2), port)
	# Locals keep their distance from what is about to happen at the breach.
	_hooded_figure(port, Vector3(14.5, FLOOR_Y, -143.0), deg_to_rad(60), LookMaterials.CLOTH_TEAL, 1.7)


# ---------------------------------------------------------------- the wreck

func _build_wreck() -> void:
	var gx := 420.0
	var gz := -1650.0
	var gy := terrain.height_at(gx, gz)
	wreck_anchor = Vector3(gx, gy, gz)
	var wreck := Node3D.new()
	wreck.name = "Wreck"
	wreck.position = Vector3(gx, gy, gz)
	wreck.rotation.y = deg_to_rad(-18)
	wreck.scale = Vector3.ONE * 1.25
	add_child(wreck)
	var hull := mats.hull(gy + 14.0, 11.0, gy + 120.0)

	# The main hull came down nose first and stuck, stern raised against the sky.
	# Local +Y runs bow (buried) to stern (up); local +X is the dorsal side.
	var ship := Node3D.new()
	ship.name = "Hull"
	ship.position = Vector3(0, 120, 0)
	ship.rotation_degrees = Vector3(0, 0, 57)
	wreck.add_child(ship)
	_add(_cyl(48.0, 60.0, 420.0, 32), hull, Vector3(0, -150.0, 0), ship)          # buried forward hull
	_add(_cyl(40.0, 46.0, 170.0, 32), hull, Vector3(0, 275.0, 0), ship)           # aft section
	_add(_cyl(26.0, 26.0, 170.0, 16), hull, Vector3(-14.0, 105.0, 0), ship)       # keel through the open section
	# Open section: ribs on the dorsal side, the hull plating torn away.
	for i in 9:
		var y := 30.0 + i * 18.0
		var span := 1.35 - (0.45 if i % 3 == 1 else 0.0) - _rng.randf() * 0.12
		_add(LookMeshKit.ring_segment(47.0, 53.0, y - 2.2, y + 2.2, -span, span * (0.8 if i % 4 == 2 else 1.0), 26), hull, Vector3.ZERO, ship)
	for i in 4:
		var y := 40.0 + i * 38.0 + _rng.randf_range(-6, 6)
		var a := _rng.randf_range(-1.0, 1.0)
		_add(_box(Vector3(2.5, 26.0, 22.0)), hull, Vector3(cos(a) * 52.0, y, sin(a) * 52.0), ship,
			Vector3(_rng.randf_range(-20, 20), -rad_to_deg(a), _rng.randf_range(-25, 25)))
	# The comb: radiator fins along the dorsal spine. The wreck's signature silhouette.
	for i in 9:
		var y := -60.0 + i * 24.0
		if y > 25.0 and y < 195.0:
			continue
		var fin_h := 20.0 + 26.0 * sin(float(i) / 8.0 * PI)
		_add(_box(Vector3(fin_h, 18.0, 3.0)), hull, Vector3(48.0 + fin_h * 0.5, y, 0), ship)
	for i in 5:
		var y := 205.0 + i * 26.0
		var fin_h := 30.0 - i * 3.0
		_add(_box(Vector3(fin_h, 16.0, 3.0)), hull, Vector3(42.0 + fin_h * 0.5, y, 0), ship)
	# Engine bells at the raised stern.
	for i in 4:
		var a := TAU * i / 4.0 + 0.4
		_add(_cyl(13.0, 20.0, 34.0, 20), mats.hull(gy, 3.0), Vector3(cos(a) * 22.0, 375.0, sin(a) * 22.0), ship)
	_add(_cyl(30.0, 40.0, 16.0, 24), hull, Vector3(0, 362.0, 0), ship)

	# A broken-off section lying in the sand, ribs up, like a beached skeleton.
	var piece := Node3D.new()
	piece.position = Vector3(-330, 4, 140)
	piece.rotation_degrees = Vector3(0, 30, 90)
	wreck.add_child(piece)
	for i in 7:
		_add(LookMeshKit.ring_segment(44.0, 49.0, -2.0 + i * 20.0, 2.0 + i * 20.0, -1.2, 1.2 - (0.5 if i == 4 else 0.0), 22), hull, Vector3.ZERO, piece)
	_add(_box(Vector3(6.0, 130.0, 8.0)), hull, Vector3(48.0, 60.0, 0), piece)

	# Scavenger scaffold against the buried hull: tiny, so the wreck reads as huge.
	var scaf := mats.flat(Color("#3a302a"), 0.8, 0.3)
	var base := Vector3(70, 0, 40)
	for k in 4:
		var p0 := base + Vector3(k * 7.0, 0, 0)
		_add(LookMeshKit.tube(PackedVector3Array([p0, p0 + Vector3(-6, 42, -4)]), 0.4, 4), scaf, Vector3.ZERO, wreck)
	for y in [10.0, 22.0, 34.0]:
		_add(LookMeshKit.tube(PackedVector3Array([base + Vector3(-y * 0.14, y, -y * 0.1), base + Vector3(21 - y * 0.14, y, -y * 0.1)]), 0.3, 4), scaf, Vector3.ZERO, wreck)
	var work_light := OmniLight3D.new()
	work_light.position = base + Vector3(10, 30, 8)
	work_light.light_color = Color("#ffcf8a")
	work_light.omni_range = 40.0
	work_light.set_meta("base_energy", 6.0)
	wreck.add_child(work_light)
	look.track_lamp(work_light)

	# Plates thrown across the sand around it.
	for i in 22:
		var p := Vector3(_rng.randf_range(-520, 420), 0, _rng.randf_range(-260, 280))
		var world := wreck.transform * p
		var y := terrain.height_at(world.x, world.z) - gy
		_add(_box(Vector3(_rng.randf_range(8, 26), 1.5, _rng.randf_range(6, 18))), hull, Vector3(p.x, y + 1.0, p.z), wreck,
			Vector3(_rng.randf_range(-35, 35), _rng.randf_range(0, 180), _rng.randf_range(-35, 35)))


func _build_megaring() -> void:
	# A broken orbital ring, standing on edge in the sand. The Halo-scale landmark.
	var gx := -430.0
	var gz := -2350.0
	var gy := terrain.height_at(gx, gz)
	var ring := Node3D.new()
	ring.name = "Megaring"
	ring.position = Vector3(gx, gy + 230.0, gz)
	ring.rotation_degrees = Vector3(90, 28, 5)
	add_child(ring)
	var mat := mats.hull(gy + 12.0, 18.0)
	# Visible arch runs from under the sand on the left to a snapped end on the right.
	_add(LookMeshKit.ring_segment(405.0, 478.0, -36.0, 36.0, PI - 0.62, TAU - 0.95, 90), mat, Vector3.ZERO, ring)
	_add(LookMeshKit.ring_segment(388.0, 398.0, -14.0, 14.0, PI - 0.55, TAU - 1.05, 90), mat, Vector3.ZERO, ring)
	for i in 16:
		var a := PI - 0.5 + i * 0.12
		_add(_box(Vector3(26.0, 10.0, 84.0)), mat, Vector3(cos(a) * 441.0, 0.0, sin(a) * 441.0), ring, Vector3(0, -rad_to_deg(a), 0))
	# The snapped-off piece, fallen flat and half buried.
	var frag := Node3D.new()
	frag.position = Vector3(gx + 520.0, gy - 6.0, gz + 260.0)
	frag.rotation_degrees = Vector3(8, -40, 12)
	add_child(frag)
	_add(LookMeshKit.ring_segment(405.0, 478.0, -36.0, 36.0, -0.18, 0.28, 18), mat, Vector3(-441.0, 0, 0), frag)


# ---------------------------------------------------------------- landforms

func _build_landforms() -> void:
	var land := Node3D.new()
	land.name = "Landforms"
	add_child(land)
	var noise := FastNoiseLite.new()
	noise.seed = 31
	noise.fractal_octaves = 3
	# Mesas: big, simple, layered by fog. [x, z, radius, height]
	var mesas := [
		[-1500, -3100, 300, 230], [1700, -3800, 450, 320], [-2900, -1400, 320, 180],
		[2700, -1300, 240, 170], [-300, -4900, 620, 270], [1500, 1700, 360, 210],
		[-900, 2500, 420, 250], [3100, 900, 300, 190],
	]
	for m in mesas:
		var r: float = m[2]
		var h: float = m[3]
		noise.frequency = 0.9 / r
		var base := _cyl(r * 0.8, r, h, 40)
		base.rings = 14
		var mesh := LookMeshKit.rock(base, noise, 0.18, 28.0 / h, float(m[0]) * 0.01, 0.35)
		var gy := terrain.height_at(m[0], m[1])
		_add(mesh, mats.rock(gy, 0.11), Vector3(m[0], gy + h * 0.42, m[1]), land, Vector3(0, _rng.randf_range(0, 360), 0))
	# Hoodoos in the middle distance: the layer between the port and the horizon.
	var hoodoos := [[-260, -520, 10, 48], [-410, -760, 16, 80], [210, -640, 12, 62], [520, -900, 18, 92],
		[-700, -300, 14, 58], [120, -980, 9, 40], [760, -420, 13, 70], [-180, -1150, 20, 96]]
	for hd in hoodoos:
		var r: float = hd[2]
		var h: float = hd[3]
		noise.frequency = 1.4 / r
		var base := _cyl(r * 0.55, r, h, 16)
		base.rings = 10
		var gy := terrain.height_at(hd[0], hd[1])
		var mat := mats.rock(gy, 0.35)
		_add(LookMeshKit.rock(base, noise, 0.28, 3.0, float(hd[0]), 0.4), mat, Vector3(hd[0], gy + h * 0.45, hd[1]), land)
		var cap := SphereMesh.new()
		cap.radius = r * 0.9
		cap.height = r * 0.8
		cap.radial_segments = 12
		cap.rings = 6
		_add(LookMeshKit.rock(cap, noise, 0.3, 0.0, float(hd[1])), mat, Vector3(hd[0], gy + h * 0.95, hd[1]), land,
			Vector3(0, 0, _rng.randf_range(-12, 12)))
	# Boulders, scattered with a MultiMesh: one draw call for hundreds.
	var boulder_src := BoxMesh.new()
	boulder_src.size = Vector3(2.0, 1.6, 1.8)
	boulder_src.subdivide_width = 2
	boulder_src.subdivide_height = 2
	boulder_src.subdivide_depth = 2
	noise.frequency = 0.9
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = LookMeshKit.rock(boulder_src, noise, 0.4, 0.0, 3.0)
	mm.instance_count = 420
	for i in mm.instance_count:
		var ang := _rng.randf() * TAU
		var dist := 165.0 + pow(_rng.randf(), 1.6) * 1500.0
		var x := cos(ang) * dist
		var z := sin(ang) * dist
		var s := _rng.randf_range(0.5, 1.0) * (1.0 + pow(_rng.randf(), 3.0) * 5.0)
		var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.8, 1.2), s * _rng.randf_range(0.8, 1.3)))
		basis = basis * Basis(Vector3.RIGHT, _rng.randf_range(-0.4, 0.4))
		mm.set_instance_transform(i, Transform3D(basis, Vector3(x, terrain.height_at(x, z) - s * 0.25, z)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mats.rock(8.0, 1.2)
	land.add_child(mmi)


# ---------------------------------------------------------------- characters

var chars: CharacterKit


func _place(c: Node3D, pos: Vector3, yaw_deg: float, parent: Node3D = self) -> Node3D:
	c.position = pos
	c.rotation_degrees.y = yaw_deg
	parent.add_child(c)
	return c


func _build_characters() -> void:
	chars = CharacterKit.new(mats, FLOOR_Y)
	# Lineup: every archetype side by side for review (shot "lineup").
	var lineup := Node3D.new()
	lineup.name = "Lineup"
	add_child(lineup)
	var order := ["remnant_trooper", "remnant_commander", "player_smuggler", "cantina_owner", "duelist", "smuggler", "local"]
	for i in order.size():
		_place(chars.build(order[i]), Vector3(26.0, FLOOR_Y, -104.3 + i * 1.45), -90.0, lineup)

	# Hero shot: the player (smuggler) faces down a duelist standing in the breach.
	var story := Node3D.new()
	story.name = "Story"
	add_child(story)
	_place(chars.build("smuggler"), Vector3(2.6, FLOOR_Y, -134.6), 192.0, story)
	_place(chars.build("duelist"), Vector3(7.4, FLOOR_Y + 0.15, -145.0), -8.0, story)
	_place(chars.build("local"), Vector3(-3.5, FLOOR_Y, -141.5), 140.0, story)

	# Street: a Remnant patrol, led by a commander, pushing through the market.
	_place(chars.build("remnant_commander"), Vector3(-22.0, FLOOR_Y, 6.0), 4.0, story)
	_place(chars.build("remnant_trooper"), Vector3(-25.4, FLOOR_Y, 2.4), 8.0, story)
	_place(chars.build("remnant_trooper"), Vector3(-18.8, FLOOR_Y, 1.2), -6.0, story)
	_place(chars.build("remnant_trooper", "idle"), Vector3(-22.6, FLOOR_Y, -4.5), 0.0, story)
	_place(chars.build("local", "idle"), Vector3(-30.5, FLOOR_Y, -4.0), 70.0, story)
	_place(chars.build("local"), Vector3(-16.0, FLOOR_Y, -40.0), -150.0, story)


# ---------------------------------------------------------------- smoke

func _smoke_texture() -> ImageTexture:
	var n := FastNoiseLite.new()
	n.seed = 77
	n.frequency = 0.05
	n.fractal_octaves = 4
	var size := 128
	var img := Image.create(size, size, true, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var d := Vector2(x - size * 0.5, y - size * 0.5).length() / (size * 0.5)
			var v := n.get_noise_2d(x, y) * 0.5 + 0.5
			var a := clampf((1.0 - d) * 1.6 + (v - 0.5) * 1.1, 0.0, 1.0)
			a = pow(a, 1.6)
			var shade := 0.75 + 0.25 * v
			img.set_pixel(x, y, Color(shade, shade, shade, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _build_smoke() -> void:
	var plume := Node3D.new()
	plume.name = "SmokePlume"
	add_child(plume)
	_smoke_mat = StandardMaterial3D.new()
	_smoke_mat.albedo_texture = _smoke_texture()
	_smoke_mat.albedo_color = Color(0.29, 0.24, 0.21, 0.62)
	_smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_smoke_mat.billboard_keep_scale = true
	_smoke_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# The column thins out as it trails: a few copies with falling opacity.
	_smoke_mats.clear()
	for k in 5:
		var m := _smoke_mat.duplicate() as StandardMaterial3D
		m.set_meta("alpha", lerpf(0.9, 0.22, k / 4.0))
		_smoke_mats.append(m)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var origin := wreck_anchor + Vector3(-40, 70, 10)
	var count := 110
	for i in count:
		var t := pow(float(i) / (count - 1), 1.3)
		# Rises, then shears off downwind (+X) like a real column in a steady breeze.
		# Rises to about 300 m, then the upper wind shears it into a long trailing smear.
		var rise := 300.0 * (1.0 - pow(1.0 - minf(t * 1.8, 1.0), 2.0)) + t * 90.0
		var p := origin + Vector3(pow(t, 1.7) * 1500.0 + _rng.randf_range(-20, 20) * (1.0 + t * 4.0), rise + _rng.randf_range(-15, 15) * t * 4.0, t * 260.0 + _rng.randf_range(-20, 20) * (1.0 + t * 3.0))
		var s := 28.0 + t * 230.0 + _rng.randf_range(-10, 10) * (1.0 + t * 3.0)
		var mi := _add(quad, _smoke_mats[mini(int(t * _smoke_mats.size()), _smoke_mats.size() - 1)], p, plume, Vector3.ZERO, Vector3(s, s, s))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Fire at the root of the column (visible at dusk).
	var fire := mats.glow(Color("#ff7a30"))
	fire.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fire.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	look.track_glow(fire)
	for i in 5:
		_add(quad, fire, origin + Vector3(_rng.randf_range(-40, 40), _rng.randf_range(-30, 0), _rng.randf_range(-20, 20)), plume,
			Vector3.ZERO, Vector3.ONE * _rng.randf_range(8, 18))


# ---------------------------------------------------------------- play mode

func _spawn_player() -> void:
	_player = CharacterBody.new()
	_player.position = Vector3(4.0, FLOOR_Y + 0.05, -128.0)
	add_child(_player)
	_rig = CameraRigNode.new()
	add_child(_rig)
	_rig.set_player(_player)
	_rig.rig.yaw = PI   # face out over the wall, toward the wreck
	if _rig._camera is Camera3D:
		_rig._camera.far = 12000.0
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and event.keycode >= KEY_1 and event.keycode <= KEY_3:
		var ids := ["golden", "noon", "dusk"]
		set_preset(ids[event.keycode - KEY_1])
