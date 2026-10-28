class_name AsteroidWorld
extends PlatformWorld
## An asteroid you stand on (issue #75). The planet is one rock ball of
## surface.radius; the town and its landing pit sit on top of it:
##
##   - the rock: a sphere, cratered (two sizes, from data) and roughened, with
##     blocky boulders strewn over it and a faceted, moon-grey look. Flattened
##     under the town's floors (and sunk under the pit) and blended back into the
##     ball round them, so paving runs straight onto rock
##   - walkable: a height-map collider over the top of the ball, out to cap x radius
##     (by then it is far too steep to stand on: gravity is the town's, straight
##     down, so you can walk the top of the ball, not round it)
##   - a glass dome over the town (a half-ellipsoid round its walls), solid to
##     people and ships, with a door over the gate under an energy shield you walk
##     through; the landing pit is outside it
##   - sliding off the side kills you, as going over a platform's edge does: a
##     fade, the type's line, and you wake by the landing bay
##
## Pure height function (height_at) shared by the collider, the look, the ships'
## ground (WorldGround) and the fall guard, so what you see is what you stand on.
## Settings: the asteroid type in content/core/planets/types.json ("surface",
## "dome").

const DOME_SEG := 48
const DOME_RINGS := 14

var radius := 900.0
var center := Vector3.ZERO           ## the ball's centre (its top is y = 0 over the town)
var cell_m := 5.0                    ## collider and rock mesh spacing
var extent := 650.0                  ## half-size of the walkable square (cap x radius)
var blend := 45.0                    ## metres from the flat town to open rock
var flats: Array = []                ## Rect2: floors at street level (rock just under)
var sunk: Array = []                 ## { rect, y }: the pit (rock under its floor)
var craters: Array = []              ## surface.craters
var bumps := 1.4
var dome := {}                       ## { c: Vector3, a, b, h, door_half, door_h, door_x }
var dome_tris := 0                   ## triangles in the dome's collider (traces, tests)
var walk_body: StaticBody3D
var _noise := FastNoiseLite.new()
var _edge_y := 0.0


func setup(town_scene, p: Dictionary) -> void:
	super.setup(town_scene, p)
	radius = float(surface.get("radius", 900.0))
	cell_m = float(surface.get("cell_m", 5.0))
	extent = snappedf(radius * float(surface.get("cap", 0.72)), cell_m)
	blend = float(surface.get("blend", 45.0))
	craters = surface.get("craters", [])
	bumps = float(surface.get("bumps", 1.4))
	_noise.seed = 75
	_noise.frequency = 0.018
	_noise.fractal_octaves = 3
	_site(demo.town)
	_edge_y = center.y + sqrt(maxf(radius * radius - extent * extent, 0.0))
	_dome_shape(p.get("type_cfg", {}).get("dome", {}))
	if not dome.is_empty():
		# The rock under the dome is level with the street, out to its foot.
		var c: Vector3 = dome.c
		flats.append(Rect2(c.x - float(dome.a), c.z - float(dome.b), float(dome.a) * 2.0, float(dome.b) * 2.0))


## Where the flat floors are, the pit, and the ball's centre under the middle of
## everything built.
func _site(town) -> void:
	var all := Rect2()
	var first := true
	for b in town.boxes():
		var k := str(b.kind)
		if k != "floor" and k != "bowl":
			continue
		var r := _rect(b)
		all = r if first else all.merge(r)
		first = false
		if k == "bowl" or float(b.max[1]) < -0.1:
			sunk.append({ "rect": r, "y": float(b.min[1]) - 0.5 })
		else:
			flats.append(r)
	var c := all.get_center()
	center = Vector3(c.x, -radius, c.y)


func _dome_shape(cfg: Dictionary) -> void:
	if bounds.size == Vector2.ZERO:
		return
	var spread := float(cfg.get("spread", 1.45))
	var a := bounds.size.x * 0.5 * spread
	var b := bounds.size.y * 0.5 * spread
	var dc := bounds.get_center()
	dome = { "c": Vector3(dc.x, -1.0, dc.y), "a": a, "b": b, "h": minf(a, b) * float(cfg.get("height", 0.8)),
		"door_half": float(cfg.get("door_half", 6.0)), "door_h": float(cfg.get("door_height", 6.5)) }
	# The door is where the street leaves the walls (the gate, in the east wall).
	var gz := (float(gate.z0) + float(gate.z1)) * 0.5 if gate.has("x0") else 0.0
	dome.door_z = gz
	dome.door_x = dc.x + a * sqrt(maxf(0.0, 1.0 - pow((gz - dc.y) / b, 2.0)))


func _ready() -> void:
	name = "Platform"
	_build_walk_collider()
	_build_dome_collider()


# ------------------------------------------------------------------ the rock

## The rock's height at (x, z): flat under the town, sunk under the pit, the
## cratered ball everywhere else, blended between.
func height_at(x: float, z: float) -> float:
	var p := Vector2(x, z)
	for s in sunk:
		if (s.rect as Rect2).has_point(p):
			return float(s.y)
	var d := INF
	for r in flats:
		d = minf(d, _rect_dist(r, p))
		if d <= 0.0:
			return -0.1
	var nat := natural(x, z)
	if d >= blend:
		return nat
	var t := smoothstep(0.0, blend, d)
	return lerpf(-0.1, nat, t)


## The bare ball: a sphere, its craters and its roughness.
func natural(x: float, z: float) -> float:
	var dx := x - center.x
	var dz := z - center.z
	var r2 := dx * dx + dz * dz
	if r2 >= radius * radius:
		return center.y - radius
	var h := center.y + sqrt(radius * radius - r2)
	for c in craters:
		h += _crater(x, z, c)
	return h + _noise.get_noise_2d(x, z) * bumps


## One crater layer: at most one crater per cell (kept inside it, so only the
## cell (x, z) is in matters), a bowl with a raised rim.
func _crater(x: float, z: float, c: Dictionary) -> float:
	var cell := float(c.get("cell", 100.0))
	var ci := floori(x / cell)
	var cj := floori(z / cell)
	var k := _hash(ci, cj, int(c.get("seed", 1)))
	if float(k & 1023) / 1023.0 > float(c.get("density", 0.5)):
		return 0.0
	var rr: Array = c.get("radius", [10.0, 20.0])
	var r := lerpf(float(rr[0]), float(rr[1]), float((k >> 10) & 1023) / 1023.0)
	r = minf(r, cell * 0.3)
	var room := maxf(0.0, cell * 0.5 - r * 1.6)
	var ox := (float(ci) + 0.5) * cell + (float((k >> 20) & 255) / 255.0 * 2.0 - 1.0) * room
	var oz := (float(cj) + 0.5) * cell + (float((k >> 28) & 255) / 255.0 * 2.0 - 1.0) * room
	var d := Vector2(x - ox, z - oz).length() / r
	var depth := r * float(c.get("depth", 0.24))
	if d < 1.0:
		return depth * (d * d - 1.0) + depth * 0.3 * d * d * d * d
	if d < 1.6:
		var t := 1.0 - (d - 1.0) / 0.6
		return depth * 0.3 * t * t
	return 0.0


static func _hash(i: int, j: int, s: int) -> int:
	var k := (i * 73856093) ^ (j * 19349663) ^ (s * 83492791)
	k = ((k ^ (k >> 13)) * 1274126177) & 0x7fffffffffff
	k ^= k >> 16
	return k & 0x7fffffff


static func _rect_dist(r: Rect2, p: Vector2) -> float:
	var dx := maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x)
	var dz := maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)
	return Vector2(dx, dz).length()


## For the gear's fall guard and the jetpack: the rock (and the floors on it).
func ground_at(x: float, z: float) -> float:
	return 0.0 if _on_flat(x, z) else height_at(x, z)


func _on_flat(x: float, z: float) -> bool:
	for r in flats:
		if (r as Rect2).has_point(Vector2(x, z)):
			return true
	return false


## The walkable rock: one height map over the top of the ball.
func _build_walk_collider() -> void:
	var n := int(round(extent * 2.0 / cell_m))
	var data := PackedFloat32Array()
	data.resize((n + 1) * (n + 1))
	var x0 := center.x - extent
	var z0 := center.z - extent
	for j in n + 1:
		for i in n + 1:
			data[j * (n + 1) + i] = height_at(x0 + i * cell_m, z0 + j * cell_m) / cell_m
	var shape := HeightMapShape3D.new()
	shape.map_width = n + 1
	shape.map_depth = n + 1
	shape.map_data = data
	walk_body = StaticBody3D.new()
	walk_body.name = "Rock"
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3(cell_m, cell_m, cell_m)
	walk_body.add_child(cs)
	walk_body.position = Vector3(center.x, 0.0, center.z)
	add_child(walk_body)


# ------------------------------------------------------------------ the dome

## Points of the dome's shell: ring i (0 at the ground) round segment j.
func _dome_point(i: int, j: int) -> Vector3:
	var el := (PI * 0.5) * float(i) / float(DOME_RINGS)
	var az := TAU * float(j) / float(DOME_SEG)
	var c: Vector3 = dome.c
	return Vector3(c.x + cos(az) * cos(el) * float(dome.a), c.y + sin(el) * float(dome.h), c.z + sin(az) * cos(el) * float(dome.b))


## Is the quad (ring i, segment j) part of the door? (the gate's opening)
func _in_door(i: int, j: int) -> bool:
	var p := (_dome_point(i, j) + _dome_point(i + 1, j + 1)) * 0.5
	var c: Vector3 = dome.c
	return p.x > c.x and absf(p.z - float(dome.door_z)) < float(dome.door_half) and p.y < float(dome.door_h)


func _dome_triangles() -> PackedVector3Array:
	var tris := PackedVector3Array()
	for i in DOME_RINGS:
		for j in DOME_SEG:
			if _in_door(i, j):
				continue
			var a := _dome_point(i, j)
			var b := _dome_point(i, j + 1)
			var c := _dome_point(i + 1, j + 1)
			var d := _dome_point(i + 1, j)
			tris.append_array([a, b, c, a, c, d])
	return tris


func _build_dome_collider() -> void:
	if dome.is_empty():
		return
	var tris := _dome_triangles()
	dome_tris = tris.size() / 3
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(tris)
	var body := StaticBody3D.new()
	body.name = "Glass"
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


## Ships: the rock is the ground (WorldTerrain over this height function) and
## the dome a glass column they bump into.
func add_to_ground(ground: WorldGround) -> void:
	ground.terrain = WorldTerrain.new({ "skirt_height": center.y - radius, "planet_radius": 1.0e12, "curve_from": 1.0e12 },
		height_at, radius * 3.0)
	if not dome.is_empty():
		ground.columns.append({ "id": "glass_dome", "kind": "glass", "center": dome.c,
			"radius": (float(dome.a) + float(dome.b)) * 0.5, "top": float(dome.h) })


# ------------------------------------------------------------------ falling off

func _physics_process(dt: float) -> void:
	var p: Node3D = demo._player if demo != null else null
	if p == null or not is_instance_valid(p) or bool(p.get("piloting")):
		return
	var at := p.global_position
	if _falling:
		_fade_t += dt
		_set_fade(clampf(_fade_t / 0.8, 0.0, 1.0))
		if _fade_t > 2.0:
			_respawn(p)
		return
	if at.y < minf(height_at(at.x, at.z), _edge_y) - 25.0:
		_falling = true
		_fade_t = 0.0


# ------------------------------------------------------------------ looks

func dress(env: LookEnvironment, mats: LookMaterials) -> void:
	var rock := _rock_material()
	_dress_cap(rock)
	_dress_ball(rock)
	_dress_boulders(rock)
	_dress_debris(rock)
	_dress_dome(env, mats)


func _rock_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = LookEnvironment.make_noise_texture(256, 75, 0.05)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.08, 0.08, 0.08)
	m.roughness = 1.0
	m.metallic = 0.0
	return m


## The top of the ball, from the same heights as the collider, faceted (a normal
## per triangle: the blocky moon look), darker in crater floors, pale on rims;
## and a skirt down from its edge to the rest of the ball.
func _dress_cap(rock: StandardMaterial3D) -> void:
	var n := int(round(extent * 2.0 / cell_m))
	var x0 := center.x - extent
	var z0 := center.z - extent
	var hs := PackedFloat32Array()
	hs.resize((n + 1) * (n + 1))
	for j in n + 1:
		for i in n + 1:
			hs[j * (n + 1) + i] = height_at(x0 + i * cell_m, z0 + j * cell_m)
	var inside := func(i: int, j: int) -> bool:
		if i < 0 or j < 0 or i >= n or j >= n:
			return false
		var cx := x0 + (i + 0.5) * cell_m - center.x
		var cz := z0 + (j + 0.5) * cell_m - center.z
		return cx * cx + cz * cz < extent * extent
	var base := Color(str(surface.get("color", "#7a7a7e")))
	var deep := Color(str(surface.get("deep", "#3a3a3e")))
	var rim := Color(str(surface.get("rim", "#9c9ca0")))
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7575
	for j in n:
		for i in n:
			if not inside.call(i, j):
				continue
			var x := x0 + i * cell_m
			var z := z0 + j * cell_m
			var a := Vector3(x, hs[j * (n + 1) + i], z)
			var b := Vector3(x + cell_m, hs[j * (n + 1) + i + 1], z)
			var c := Vector3(x + cell_m, hs[(j + 1) * (n + 1) + i + 1], z + cell_m)
			var d := Vector3(x, hs[(j + 1) * (n + 1) + i], z + cell_m)
			# How far this cell sits above or below the bare ball: crater floor or rim.
			var mid := (a + c) * 0.5
			var ball := center.y + sqrt(maxf(radius * radius - pow(mid.x - center.x, 2) - pow(mid.z - center.z, 2), 0.0))
			var off := mid.y - ball
			var col := base.lerp(deep, clampf(-off / 6.0, 0.0, 1.0)) if off < 0.0 else base.lerp(rim, clampf(off / 2.0, 0.0, 1.0))
			_tri(verts, norms, cols, a, c, b, col.darkened(rng.randf_range(0.0, 0.12)))
			_tri(verts, norms, cols, a, d, c, col.darkened(rng.randf_range(0.0, 0.12)))
			# Skirt: an edge with no cell beyond it drops 40 m, onto the ball below.
			for e in [[0, -1, a, b], [1, 0, b, c], [0, 1, c, d], [-1, 0, d, a]]:
				if not inside.call(i + int(e[0]), j + int(e[1])):
					var p0: Vector3 = e[2]
					var p1: Vector3 = e[3]
					var out := Vector3((p0.x + p1.x) * 0.5 - center.x, 0.0, (p0.z + p1.z) * 0.5 - center.z).normalized()
					_tri(verts, norms, cols, p0, p1, p1 - Vector3(0, 40, 0), deep, out)
					_tri(verts, norms, cols, p0, p1 - Vector3(0, 40, 0), p0 - Vector3(0, 40, 0), deep, out)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.name = "RockCap"
	mi.mesh = mesh
	mi.material_override = rock
	add_child(mi)


## One faceted triangle facing `out`. Godot's front faces wind clockwise as seen
## from outside, so (b - a) x (c - a) must point inward; the normal is its reverse.
static func _tri(v: PackedVector3Array, nn: PackedVector3Array, cc: PackedColorArray, a: Vector3, b: Vector3, c: Vector3,
		col: Color, out: Vector3 = Vector3.UP) -> void:
	var cr := (b - a).cross(c - a)
	if cr.dot(out) > 0.0:
		var t := b
		b = c
		c = t
		cr = -cr
	var nrm := -cr.normalized()
	v.append_array([a, b, c])
	nn.append_array([nrm, nrm, nrm])
	cc.append_array([col, col, col])


## The rest of the ball, under the cap: what you see from the sky and from space.
func _dress_ball(rock: StandardMaterial3D) -> void:
	var s := SphereMesh.new()
	s.radius = radius - 14.0
	s.height = (radius - 14.0) * 2.0
	s.radial_segments = 96
	s.rings = 48
	var mi := MeshInstance3D.new()
	mi.name = "Asteroid"
	mi.mesh = s
	var m := rock.duplicate() as StandardMaterial3D
	m.vertex_color_use_as_albedo = false
	m.albedo_color = Color(str(surface.get("color", "#7a7a7e"))).darkened(0.1)
	m.uv1_scale = Vector3(0.02, 0.02, 0.02)
	mi.material_override = m
	mi.position = center
	add_child(mi)


## Blocky boulders strewn over the rock (not on the town, not in the pit). The
## big ones are solid.
func _dress_boulders(rock: StandardMaterial3D) -> void:
	var count := int(surface.get("boulders", 700))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4575
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var box := BoxMesh.new()
	mm.mesh = box
	var xforms: Array = []
	var body := StaticBody3D.new()
	body.name = "Boulders"
	add_child(body)
	var tries := 0
	while xforms.size() < count and tries < count * 6:
		tries += 1
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * extent * 0.95
		var x := center.x + cos(a) * r
		var z := center.z + sin(a) * r
		var near := INF
		for f in flats:
			near = minf(near, _rect_dist(f, Vector2(x, z)))
		for sk in sunk:
			near = minf(near, _rect_dist(sk.rect, Vector2(x, z)))
		if near < 8.0:
			continue
		var s := rng.randf_range(0.5, 1.0)
		s = s * s * 4.0 + 0.4
		var size := Vector3(s * rng.randf_range(0.8, 1.6), s * rng.randf_range(0.5, 1.0), s * rng.randf_range(0.8, 1.6))
		var basis := Basis(Vector3(rng.randf() - 0.5, rng.randf() * 2.0, rng.randf() - 0.5).normalized(), rng.randf() * TAU)
		var at := Vector3(x, height_at(x, z) + size.y * 0.2, z)
		xforms.append([Transform3D(basis * Basis.from_scale(size), at), rng.randf_range(0.65, 1.0)])
		if s > 1.8:
			var cs := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = size
			cs.shape = shape
			cs.transform = Transform3D(basis, at)
			body.add_child(cs)
	mm.instance_count = xforms.size()
	var base := Color(str(surface.get("color", "#7a7a7e")))
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i][0])
		mm.set_instance_color(i, base * float(xforms[i][1]))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "BoulderLook"
	mmi.multimesh = mm
	var m := rock.duplicate() as StandardMaterial3D
	m.vertex_color_use_as_albedo = true
	mmi.material_override = m
	add_child(mmi)


## Rocks drifting round the ball, well clear of it.
func _dress_debris(rock: StandardMaterial3D) -> void:
	var n := int(surface.get("debris", 40))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4545
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = BoxMesh.new()
	mm.instance_count = n
	for i in n:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 0.3), rng.randf_range(-1, 1)).normalized()
		var s := rng.randf_range(3.0, 16.0)
		var basis := Basis(Vector3(rng.randf(), rng.randf(), rng.randf()).normalized(), rng.randf() * TAU).scaled(Vector3(s, s * 0.7, s))
		mm.set_instance_transform(i, Transform3D(basis, center + dir * radius * rng.randf_range(1.35, 2.6)))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Debris"
	mmi.multimesh = mm
	var m := rock.duplicate() as StandardMaterial3D
	m.vertex_color_use_as_albedo = false
	m.albedo_color = Color(str(surface.get("color", "#7a7a7e")))
	mmi.material_override = m
	add_child(mmi)


## The glass dome: the same shell as its collider, ribs, a metal ring round its
## foot and the door's shield.
func _dress_dome(env: LookEnvironment, mats: LookMaterials) -> void:
	if dome.is_empty():
		return
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.72, 0.88, 0.96, 0.12)
	glass.metallic = 0.3
	glass.roughness = 0.05
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var tris := _dome_triangles()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in tris:
		st.set_normal((v - (dome.c as Vector3)).normalized())
		st.add_vertex(v)
	var shell := MeshInstance3D.new()
	shell.name = "Dome"
	shell.mesh = st.commit()
	shell.material_override = glass
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shell)
	# Ribs: every fourth meridian (not through the door), and two rings.
	var frame := mats.hull(-50.0, 3.0)
	var kit := SurfaceTool.new()
	kit.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(0, DOME_SEG, 4):
		for i in DOME_RINGS:
			if _in_door(i, j) or _in_door(i, posmod(j - 1, DOME_SEG)):
				continue
			_strip(kit, _dome_point(i, j), _dome_point(i + 1, j), 0.18)
	for i in [0, DOME_RINGS / 2]:
		for j in DOME_SEG:
			if _in_door(i, j) and i == 0:
				continue
			_strip(kit, _dome_point(i, j), _dome_point(i, j + 1), 0.25 if i == 0 else 0.15)
	var ribs := MeshInstance3D.new()
	ribs.name = "DomeRibs"
	ribs.mesh = kit.commit()
	ribs.material_override = frame
	add_child(ribs)
	# The door's shield: walk straight through it.
	shield = MeshInstance3D.new()
	shield.name = "DomeShield"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.08, float(dome.door_h), float(dome.door_half) * 2.0 + 4.0)
	shield.mesh = bm
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.35, 0.85, 1.0, 0.22)
	m.emission_enabled = true
	m.emission = Color("#5fe0ff")
	m.emission_energy_multiplier = 1.2
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shield.material_override = m
	shield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shield.position = Vector3(float(dome.door_x) - 1.0, float(dome.door_h) * 0.5, float(dome.door_z))
	add_child(shield)


## A thin flat strip from a to b on the dome (a rib), facing out from its centre.
func _strip(st: SurfaceTool, a: Vector3, b: Vector3, w: float) -> void:
	var out := ((a + b) * 0.5 - (dome.c as Vector3)).normalized()
	var side := (b - a).cross(out).normalized() * w
	var o := out * 0.05
	for v in [a - side + o, b - side + o, b + side + o, a - side + o, b + side + o, a + side + o]:
		st.set_normal(out)
		st.add_vertex(v)
	for v in [a - side - o, b + side - o, b - side - o, a - side - o, a + side - o, b + side - o]:
		st.set_normal(-out)
		st.add_vertex(v)
