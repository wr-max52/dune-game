class_name AsteroidWorld
extends PlatformWorld
## The asteroid station's enclosure (issue #99). The asteroid itself is a real
## ball (AsteroidSphere, built by PlanetTerrain like the home planet: rock all the
## way round, gravity toward its centre). This builds the station on top of it,
## sealed, because the locals cannot breathe outside:
##
##   - a round wall round the whole town, a glass dome springing from its top
##   - the gate: a gap in the wall on the main street, closed by a transparent
##     energy shield you walk through, and a covered hallway beyond it
##   - the hallway: wide windows for walls, lit along its ceiling, out to the
##     landing pit, in through a door in the pit's tall round liner and down over
##     the pit's ramp, opening on the pit floor through a round energy shield
##   - the pit: the port's own round pit, its wall carried up above the rock as a
##     tall liner, an energy shield over the top that ships fly through
##   - blocky boulders strewn over the rock round the station
##
## Every number comes from the town's "station" block (TownGen, from the type's
## "station" in content/core/planets/types.json). Colliders are built in the
## greybox too (the traces walk it); dress() adds the looks.

const RING_SEG := 128
const LINER_SEG := 96
const DOME_SEG := 64
const DOME_RINGS := 16

var st: Dictionary = {}                ## the town's "station" block
var sphere: PlanetSphere
var rc := Vector3.ZERO                 ## the ring's centre
var rw := 36.0                         ## the ring's radius
var wall_h := 6.0
var dome_h := 30.0
var gate_half := 4.5
var hall: Dictionary = {}
var pit_c := Vector3.ZERO
var pit_r := 28.0
var liner_h := 13.0
var dome_tris := 0                     ## triangles in the dome's collider (traces, tests)
var shields: Array = []                ## MeshInstance3D: every energy shield (they pulse)
var boulders: Array = []               ## { xform: Transform3D, size: Vector3 }


func setup(town_scene, p: Dictionary) -> void:
	super.setup(town_scene, p)
	sphere = demo.terrain.sphere if demo.terrain is PlanetTerrain else PlanetSphere.current
	_read_station(demo.town.data.get("station", {}))
	_place_boulders()


var exterior_only := false             ## issue #99: seen from another planet's sky (no colliders)


## Issue #99: the station as seen from space, from the home planet's scene: the
## ring, the dome, the liner, the hallway and the shields, no colliders, no floors
## or boulders. Coordinates are the station planet's own (place this node at its
## port's offset).
func build_exterior(station: Dictionary, mats: LookMaterials) -> void:
	exterior_only = true
	name = "StationExterior"
	_read_station(station)
	if st.is_empty():
		return
	var metal := mats.hull(-50.0, 3.0)
	var panel := mats.hull(-50.0, 1.6)
	var trim := mats.flat(Color("#899195"), 0.6, 0.7)
	var dark := mats.flat(Color("#252a2d"), 0.88, 0.55)
	var status := mats.glow(Color("#f0c77c"))
	_mesh("RingWall", _cylinder(rc, rw, 0.0, wall_h, RING_SEG / 2, 1, _ring_gap), metal, true)
	_panelled_wall("RingWallExteriorPanels", rc, rw, wall_h, RING_SEG / 2, 1, panel, trim, dark, status, 1)
	var dome := _mesh("Dome", _dome_triangles(), _glass(), true)
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dome_ribs(metal)
	_mesh("Liner", _cylinder(pit_c, pit_r, 0.0, liner_h, LINER_SEG / 2, 1, _liner_gap), metal, true)
	_panelled_wall("LinerExteriorPanels", pit_c, pit_r, liner_h, LINER_SEG / 2, -1, panel, trim, dark, status, 1)
	_pit_shield()
	_dress_hall(metal, _glass(), null, mats)


func _read_station(station: Dictionary) -> void:
	st = station
	rc = _v(st.get("center", [0, 0, 0]))
	rw = float(st.get("radius", 36.0))
	wall_h = float(st.get("wall_height", 6.0))
	dome_h = float(st.get("dome_height", rw * 0.85))
	gate_half = float(st.get("gate_half", 4.5))
	hall = st.get("hall", {})
	var pit: Dictionary = st.get("pit", {})
	pit_c = _v(pit.get("center", [0, 0, 0]))
	pit_r = float(pit.get("radius", 28.0))
	liner_h = float(pit.get("liner_height", 13.0))


func _ready() -> void:
	if exterior_only:
		return
	name = "Platform"
	if st.is_empty():
		return
	_build_colliders()


static func _v(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


# ------------------------------------------------------------------ shapes

## Is the ring wall's quad at angle a, height y (its middle) the gate?
func _ring_gap(a: float, y: float) -> bool:
	return cos(a) > 0.0 and absf(sin(a) * rw) < gate_half and y < float(hall.get("height", 5.0)) + 0.3


## The liner's door, where the hallway comes in (the side facing the town).
func _liner_gap(a: float, y: float) -> bool:
	return cos(a) < 0.0 and absf(sin(a) * pit_r) < gate_half + 0.2 and y < float(hall.get("height", 5.0)) + 0.3


## A wall round a circle, as triangles (both faces), leaving out what `gap` says.
static func _cylinder(c: Vector3, r: float, y0: float, y1: float, segs: int, rows: int, gap: Callable) -> PackedVector3Array:
	var tris := PackedVector3Array()
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		for k in rows:
			var ya := lerpf(y0, y1, float(k) / rows)
			var yb := lerpf(y0, y1, float(k + 1) / rows)
			if gap.is_valid() and gap.call((a0 + a1) * 0.5, (ya + yb) * 0.5):
				continue
			var p00 := c + Vector3(cos(a0) * r, ya, sin(a0) * r)
			var p10 := c + Vector3(cos(a1) * r, ya, sin(a1) * r)
			var p11 := c + Vector3(cos(a1) * r, yb, sin(a1) * r)
			var p01 := c + Vector3(cos(a0) * r, yb, sin(a0) * r)
			tris.append_array([p00, p10, p11, p00, p11, p01])
	return tris


func _dome_point(i: int, j: int) -> Vector3:
	var el := (PI * 0.5) * float(i) / float(DOME_RINGS)
	var az := TAU * float(j) / float(DOME_SEG)
	return rc + Vector3(cos(az) * cos(el) * rw, wall_h + sin(el) * dome_h, sin(az) * cos(el) * rw)


func _dome_triangles() -> PackedVector3Array:
	var tris := PackedVector3Array()
	for i in DOME_RINGS:
		for j in DOME_SEG:
			var a := _dome_point(i, j)
			var b := _dome_point(i, j + 1)
			var c := _dome_point(i + 1, j + 1)
			var d := _dome_point(i + 1, j)
			tris.append_array([a, b, c, a, c, d])
	return tris


## The hallway's solid parts as boxes: [centre, size] each (walls full height,
## the roof, and the end wall round its round shield).
func _hall_boxes() -> Array:
	var out: Array = []
	if hall.is_empty():
		return out
	var x0 := float(hall.x0) - 0.6
	var rim := float(hall.rim)
	var x1 := float(hall.end)
	var hw := float(hall.half)
	var h := float(hall.height)
	var bottom := pit_c.y - 6.0
	for sg in [-1.0, 1.0]:
		# Level part, from the gate to the pit's rim; then down beside the ramp.
		out.append([Vector3((x0 + rim) * 0.5, h * 0.5, sg * (hw + 0.15)), Vector3(rim - x0, h, 0.3)])
		out.append([Vector3((rim + x1) * 0.5, (bottom + h) * 0.5, sg * (hw + 0.15)), Vector3(x1 - rim, h - bottom, 0.3)])
	out.append([Vector3((x0 + x1) * 0.5, h + 0.15, 0.0), Vector3(x1 - x0, 0.3, hw * 2.0 + 0.6)])
	# The end wall: round the shield's circle (radius sr, centred cy above the pit floor).
	var sr := 3.0
	var cy := bottom + 3.2
	out.append([Vector3(x1 + 0.15, (cy + sr + h) * 0.5, 0.0), Vector3(0.3, h - cy - sr, hw * 2.0)])
	for sg in [-1.0, 1.0]:
		out.append([Vector3(x1 + 0.15, (bottom + cy + sr) * 0.5, sg * (sr + hw) * 0.5), Vector3(0.3, cy + sr - bottom, hw - sr)])
	return out


func _build_colliders() -> void:
	var body := StaticBody3D.new()
	body.name = "Station"
	add_child(body)
	_add_trimesh(body, _cylinder(rc, rw, 0.0, wall_h, RING_SEG, 4, _ring_gap))
	var dome := _dome_triangles()
	dome_tris = dome.size() / 3
	_add_trimesh(body, dome)
	_add_trimesh(body, _cylinder(pit_c, pit_r, 0.0, liner_h, LINER_SEG, 6, _liner_gap))
	for b in _hall_boxes():
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = b[1]
		cs.shape = shape
		cs.position = b[0]
		body.add_child(cs)
	var rocks := StaticBody3D.new()
	rocks.name = "Boulders"
	add_child(rocks)
	for b in boulders:
		if (b.size as Vector3).y < 1.6:
			continue                   # small stones: step over them
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = b.size
		cs.shape = shape
		cs.transform = Transform3D((b.xform as Transform3D).basis.orthonormalized(), (b.xform as Transform3D).origin)
		rocks.add_child(cs)


static func _add_trimesh(body: StaticBody3D, tris: PackedVector3Array) -> void:
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(tris)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)


## Blocky boulders on the rock round the station (none on the station itself).
func _place_boulders() -> void:
	boulders = []
	if sphere == null:
		return
	var count := maxi(0, int(surface.get("boulders", 20)))
	if count == 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 9945
	var site := sphere.site_rect.grow(14.0)
	var phase := rng.randf() * TAU
	var golden_angle := PI * (3.0 - sqrt(5.0))
	for i in count:
		# Fibonacci directions cover the whole sphere with near-uniform spacing.
		# PlanetSphere's inverse projection maps each direction onto its cratered
		# surface while keeping the station's authored site rectangle meaningful.
		var y := 1.0 - 2.0 * (float(i) + 0.5) / float(count)
		var ring := sqrt(maxf(0.0, 1.0 - y * y))
		var a := phase + golden_angle * float(i)
		var direction := Vector3(cos(a) * ring, y, sin(a) * ring)
		var m := sphere.dir_map(direction)
		# A small deterministic azimuth adjustment avoids the station footprint
		# without clustering rocks or changing their latitude band.
		var attempts := 0
		while site.has_point(m) and attempts < 24:
			attempts += 1
			a += golden_angle
			direction = Vector3(cos(a) * ring, y, sin(a) * ring)
			m = sphere.dir_map(direction)
		if site.has_point(m):
			# This can only happen if the keep-out covers the entire latitude band.
			# Keep the requested count by moving this one sample one band farther
			# from the pole, then retain the same deterministic azimuth search.
			y = clampf(y - signf(y) * 0.08, -0.99, 0.99)
			ring = sqrt(maxf(0.0, 1.0 - y * y))
			for attempt in 24:
				a += golden_angle
				direction = Vector3(cos(a) * ring, y, sin(a) * ring)
				m = sphere.dir_map(direction)
				if not site.has_point(m):
					break
		if site.has_point(m):
			continue
		var s := rng.randf_range(0.5, 1.0)
		s = s * s * 3.6 + 0.35
		var size := Vector3(s * rng.randf_range(0.8, 1.7), s * rng.randf_range(0.5, 1.1), s * rng.randf_range(0.8, 1.7))
		var g := sphere.surface_at(m.x, m.y)
		var up := sphere.up_at(g)
		var basis := PlanetSphere.tilt_to(up) * Basis(Vector3(rng.randf() - 0.5, 2.0, rng.randf() - 0.5).normalized(), rng.randf() * TAU)
		boulders.append({ "xform": Transform3D(basis, g + up * size.y * 0.25), "size": size })


## Ships: the dome is a glass column they bump into (the rock is the ball's own
## ground, which WorldTerrain already asks).
func add_to_ground(ground: WorldGround) -> void:
	if st.is_empty():
		return
	ground.columns.append({ "id": "glass_dome", "kind": "glass", "center": rc, "radius": rw, "top": wall_h + dome_h })


func ground_at(x: float, z: float) -> float:
	return demo.terrain.ground_at(x, z) if demo.terrain != null else 0.0


## No edge to fall off: the ball's gravity holds you everywhere.
func _physics_process(_dt: float) -> void:
	pass


func _process(_dt: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for s in shields:
		var m := (s as MeshInstance3D).material_override as StandardMaterial3D
		m.albedo_color.a = 0.16 + 0.06 * sin(t * 2.2 + float(s.get_index()))


# ------------------------------------------------------------------ looks

func dress(env: LookEnvironment, mats: LookMaterials) -> void:
	if st.is_empty():
		return
	var metal := mats.hull(-50.0, 3.0)
	var panel := mats.hull(-50.0, 1.6)
	var trim := mats.flat(Color("#899195"), 0.6, 0.7)
	var dark := mats.flat(Color("#252a2d"), 0.88, 0.55)
	var status := mats.glow(Color("#f0c77c"))
	status.emission_energy_multiplier = 1.8
	var glass := _glass()
	_floors(mats)
	_mesh("RingWall", _cylinder(rc, rw, 0.0, wall_h, RING_SEG, 4, _ring_gap), metal, true)
	_mesh("RingCap", _cylinder(rc, rw + 0.01, wall_h - 0.25, wall_h + 0.15, RING_SEG, 1, Callable()), metal, true)
	_panelled_wall("RingWallPanels", rc, rw, wall_h, RING_SEG / 2, 1, panel, trim, dark, status, -1)
	_panelled_wall("RingWallExteriorPanels", rc, rw, wall_h, RING_SEG / 2, 1, panel, trim, dark, status, 1)
	var dome := _mesh("Dome", _dome_triangles(), glass, true)
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dome_ribs(metal)
	_shield("GateShield", Vector3(rc.x + rw, float(hall.get("height", 5.0)) * 0.5, rc.z), Vector3(0.08, float(hall.get("height", 5.0)), gate_half * 2.0))
	_mesh("Liner", _cylinder(pit_c, pit_r, 0.0, liner_h, LINER_SEG, 6, _liner_gap), metal, true)
	_mesh("LinerCap", _cylinder(pit_c, pit_r + 0.02, liner_h - 0.3, liner_h + 0.2, LINER_SEG, 1, Callable()), metal, true)
	_panelled_wall("LinerPanels", pit_c, pit_r, liner_h, LINER_SEG / 2, -1, panel, trim, dark, status, -1)
	_panelled_wall("LinerExteriorPanels", pit_c, pit_r, liner_h, LINER_SEG / 2, -1, panel, trim, dark, status, 1)
	_pit_shield()
	_dress_hall(metal, glass, env, mats)
	_station_lighting(env, status)
	_dress_boulders()
	if env != null:
		env.set_ambient_energy_scale(1.25)


## Repeated hull plates, seams, and service lights give the station walls the
## layered, manufactured surface already used on the town's metal structures.
func _panelled_wall(node_name: String, center: Vector3, radius: float, height: float, count: int,
		gate_direction: int, panel: Material, trim: Material, dark: Material,
		status: StandardMaterial3D, face_sign: int) -> void:
	var root := Node3D.new()
	root.name = node_name
	add_child(root)
	var arc := TAU * radius / float(count)
	var width := arc - 0.42
	var panel_h := maxf(1.0, height - 1.4)
	var panel_xforms: Array[Transform3D] = []
	var dark_xforms: Array[Transform3D] = []
	var trim_xforms: Array[Transform3D] = []
	var status_xforms: Array[Transform3D] = []
	for i in count:
		var angle := TAU * (float(i) + 0.5) / float(count)
		if gate_direction != 0 and cos(angle) * gate_direction > 0.0 \
				and absf(sin(angle) * radius) < gate_half + 2.0:
			continue
		var basis := _radial_basis(angle)
		if face_sign < 0:
			basis = Basis(-basis.x, basis.y, -basis.z)
		var panel_radius := radius + float(face_sign) * 0.06
		var at := center + Vector3(cos(angle) * panel_radius, height * 0.5, sin(angle) * panel_radius)
		panel_xforms.append(Transform3D(basis, at))
		dark_xforms.append(Transform3D(basis, at + basis.z * 0.027))
		trim_xforms.append(Transform3D(basis,
			at + Vector3(0, panel_h * 0.5 - 0.08, 0) + basis.z * 0.025))
		trim_xforms.append(Transform3D(basis,
			at - Vector3(0, panel_h * 0.5 - 0.08, 0) + basis.z * 0.025))
		if i % 4 == 0:
			status_xforms.append(Transform3D(basis,
				at + Vector3(width * 0.34, 0, 0) + basis.z * 0.025))
	_instances(root, "PanelPlates", Vector3(width, panel_h, 0.1), panel, panel_xforms)
	_instances(root, "PanelInserts", Vector3(width * 0.5, panel_h * 0.72, 0.035), dark, dark_xforms)
	_instances(root, "PanelTrim", Vector3(width, 0.1, 0.04), trim, trim_xforms)
	_instances(root, "PanelStatus", Vector3(0.12, 0.22, 0.035), status, status_xforms)


func _instances(root: Node3D, node_name: String, size: Vector3, mat: Material,
		transforms: Array[Transform3D]) -> void:
	if transforms.is_empty():
		return
	var mesh := BoxMesh.new()
	mesh.size = size
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	var bounds := AABB(transforms[0].origin, Vector3.ZERO)
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		bounds = bounds.expand(transforms[i].origin)
	mm.custom_aabb = bounds.grow(size.length() * 0.5)
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = mm
	instance.material_override = mat
	root.add_child(instance)


func _radial_basis(angle: float) -> Basis:
	return Basis(Vector3(sin(angle), 0, -cos(angle)), Vector3.UP,
		Vector3(cos(angle), 0, sin(angle)))


func _station_lighting(env: LookEnvironment, status: StandardMaterial3D) -> void:
	if env == null:
		return
	env.track_glow(status)
	_add_wall_lamps(env, rc, rw, wall_h, 8, 1, status, 1.45, 15.0)
	_add_wall_lamps(env, pit_c, pit_r, liner_h, 8, -1, status, 1.1, 13.0)


func _add_wall_lamps(env: LookEnvironment, center: Vector3, radius: float, height: float,
		count: int, gate_direction: int, status: StandardMaterial3D, energy: float,
		range_m: float) -> void:
	var root := Node3D.new()
	root.name = "StationLamps_%d" % int(radius)
	add_child(root)
	for i in count:
		var angle := TAU * (float(i) + 0.5) / float(count)
		if cos(angle) * gate_direction > 0.0 and absf(sin(angle) * radius) < gate_half + 2.0:
			continue
		var basis := _radial_basis(angle)
		var at := center + Vector3(cos(angle) * (radius - 0.3), height - 0.85,
			sin(angle) * (radius - 0.3))
		_box(root, at, Vector3(0.55, 0.34, 0.12), status, basis)
		var lamp := OmniLight3D.new()
		lamp.light_color = Color("#ffe1ac")
		lamp.light_energy = energy
		lamp.omni_range = range_m
		lamp.shadow_enabled = false
		lamp.position = at - Vector3(cos(angle) * 1.2, 0.2, sin(angle) * 1.2)
		root.add_child(lamp)
		env.track_lamp(lamp)


func _pit_shield() -> void:
	var top := MeshInstance3D.new()
	top.name = "PitShield"
	var cm := CylinderMesh.new()
	cm.top_radius = pit_r
	cm.bottom_radius = pit_r
	cm.height = 0.1
	cm.radial_segments = 64
	top.mesh = cm
	top.material_override = _shield_mat()
	top.position = pit_c + Vector3(0, liner_h, 0)
	top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(top)
	shields.append(top)


func _glass() -> StandardMaterial3D:
	var g := StandardMaterial3D.new()
	g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	g.albedo_color = Color(0.72, 0.88, 0.96, 0.12)
	g.metallic = 0.3
	g.roughness = 0.05
	g.cull_mode = BaseMaterial3D.CULL_DISABLED
	return g


func _shield_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.35, 0.85, 1.0, 0.2)
	m.emission_enabled = true
	m.emission = Color("#5fe0ff")
	m.emission_energy_multiplier = 1.2
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _shield(n: String, at: Vector3, size: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _shield_mat()
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	shields.append(mi)
	return mi


## Triangles as a mesh (flat normals), optionally both faces.
func _mesh(n: String, tris: PackedVector3Array, mat: Material, both: bool) -> MeshInstance3D:
	var stl := SurfaceTool.new()
	stl.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in range(0, tris.size(), 3):
		var a := tris[t]
		var b := tris[t + 1]
		var c := tris[t + 2]
		var nrm := (b - a).cross(c - a).normalized()
		for v in [a, b, c]:
			stl.set_normal(-nrm)
			stl.add_vertex(v)
		if both:
			for v in [a, c, b]:
				stl.set_normal(nrm)
				stl.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = stl.commit()
	mi.material_override = mat
	add_child(mi)
	return mi


## The floor inside the ring drawn round (the square paving under it hidden), and
## the hallway's and the pit ring's decks in metal.
func _floors(mats: LookMaterials) -> void:
	var sq := demo.get_node_or_null("Town/ground/Mesh") as MeshInstance3D
	if sq != null:
		sq.visible = false
	var disc := MeshInstance3D.new()
	disc.name = "StationFloor"
	var cm := CylinderMesh.new()
	cm.top_radius = rw
	cm.bottom_radius = rw
	cm.height = 0.5
	cm.radial_segments = 96
	disc.mesh = cm
	disc.material_override = mats.paving(2.4)
	disc.position = rc + Vector3(0, -0.25, 0)
	add_child(disc)
	var deck := mats.hull(-50.0, 2.0)
	for id in ["hall_floor", "bay_ground_n", "bay_ground_s", "bay_ground_w", "bay_ground_e"]:
		var mi := demo.get_node_or_null("Town/%s/Mesh" % id) as MeshInstance3D
		if mi != null:
			mi.material_override = deck


## Ribs over the dome: every eighth meridian and three rings.
func _dome_ribs(metal: Material) -> void:
	var stl := SurfaceTool.new()
	stl.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(0, DOME_SEG, 8):
		for i in DOME_RINGS:
			_strip(stl, _dome_point(i, j), _dome_point(i + 1, j), 0.22)
	for i in [0, DOME_RINGS / 3, 2 * DOME_RINGS / 3]:
		for j in DOME_SEG:
			_strip(stl, _dome_point(i, j), _dome_point(i, j + 1), 0.18)
	var mi := MeshInstance3D.new()
	mi.name = "DomeRibs"
	mi.mesh = stl.commit()
	mi.material_override = metal
	add_child(mi)


func _strip(stl: SurfaceTool, a: Vector3, b: Vector3, w: float) -> void:
	var out := ((a + b) * 0.5 - (rc + Vector3(0, wall_h, 0))).normalized()
	var side := (b - a).cross(out).normalized() * w
	var o := out * 0.06
	for v in [a - side + o, b - side + o, b + side + o, a - side + o, b + side + o, a + side + o]:
		stl.set_normal(out)
		stl.add_vertex(v)
	for v in [a - side - o, b + side - o, b - side - o, a - side - o, a + side - o, b + side - o]:
		stl.set_normal(-out)
		stl.add_vertex(v)


## The hallway: metal sills and headers with wide windows between, posts, a roof,
## strip lights down both sides of the ceiling and lamps along it, and the round
## shield it opens through onto the pit floor.
func _dress_hall(metal: Material, glass: Material, env: LookEnvironment, mats: LookMaterials) -> void:
	if hall.is_empty():
		return
	var root := Node3D.new()
	root.name = "Hallway"
	add_child(root)
	var x0 := float(hall.x0) - 0.6
	var rim := float(hall.rim)
	var x1 := float(hall.end)
	var hw := float(hall.half)
	var h := float(hall.height)
	var bottom := pit_c.y - 6.0
	for sg in [-1.0, 1.0]:
		var z: float = sg * (hw + 0.15)
		_box(root, Vector3((x0 + rim) * 0.5, 0.5, z), Vector3(rim - x0, 1.0, 0.3), metal)
		_box(root, Vector3((rim + x1) * 0.5, (bottom + 1.0) * 0.5, z), Vector3(x1 - rim, 1.0 - bottom, 0.3), metal)
		_box(root, Vector3((x0 + x1) * 0.5, h - 0.4, z), Vector3(x1 - x0, 0.8, 0.3), metal)
		_box(root, Vector3((x0 + x1) * 0.5, (1.0 + h - 0.8) * 0.5, z), Vector3(x1 - x0, h - 1.8, 0.08), glass)
		var x := x0 + 4.0
		while x < x1:
			_box(root, Vector3(x, (bottom if x > rim else 0.0) * 0.5 + h * 0.5, z), Vector3(0.25, h - (bottom if x > rim else 0.0), 0.35), metal)
			x += 4.0
	_box(root, Vector3((x0 + x1) * 0.5, h + 0.15, 0.0), Vector3(x1 - x0, 0.3, hw * 2.0 + 0.6), metal)
	# The end wall round its shield (the same boxes as the collider).
	var boxes := _hall_boxes()
	for k in range(boxes.size() - 3, boxes.size()):
		_box(root, boxes[k][0], boxes[k][1], metal)
	var disc := MeshInstance3D.new()
	disc.name = "HallShield"
	var cm := CylinderMesh.new()
	cm.top_radius = 3.0
	cm.bottom_radius = 3.0
	cm.height = 0.08
	cm.radial_segments = 48
	disc.mesh = cm
	disc.material_override = _shield_mat()
	disc.rotation = Vector3(0, 0, PI * 0.5)
	disc.position = Vector3(x1 + 0.15, bottom + 3.2, 0.0)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(disc)
	shields.append(disc)
	# Lights: two glowing strips under the roof, and a lamp every 10 m.
	var lamp_glow := mats.glow(Color("#bfefff"))
	lamp_glow.emission_energy_multiplier = 2.2
	for sg in [-1.0, 1.0]:
		_box(root, Vector3((x0 + x1) * 0.5, h - 0.05, sg * (hw - 0.6)), Vector3(x1 - x0, 0.08, 0.25), lamp_glow)
	var x := x0 + 5.0
	while x < x1:
		var l := OmniLight3D.new()
		l.light_color = Color("#d8f4ff")
		l.light_energy = 1.2
		l.omni_range = 9.0
		l.shadow_enabled = false
		l.position = Vector3(x, h - 0.6, 0.0)
		root.add_child(l)
		if env != null:
			env.track_lamp(l)
		x += 10.0


func _box(root: Node3D, at: Vector3, size: Vector3, mat: Material,
		basis: Basis = Basis.IDENTITY) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = at
	mi.basis = basis
	root.add_child(mi)


func _dress_boulders() -> void:
	if boulders.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = BoxMesh.new()
	mm.instance_count = boulders.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var look: Dictionary = surface.get("look", {})
	var base := Color(str(look.get("rock_mid", "#76767b")))
	for i in boulders.size():
		var b: Dictionary = boulders[i]
		var xf: Transform3D = b.xform
		mm.set_instance_transform(i, Transform3D(xf.basis * Basis.from_scale(b.size), xf.origin))
		mm.set_instance_color(i, base * rng.randf_range(0.7, 1.15))
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = LookEnvironment.make_noise_texture(256, 75, 0.05)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.4, 0.4, 0.4)
	m.roughness = 1.0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "BoulderLook"
	mmi.multimesh = mm
	mmi.material_override = m
	add_child(mmi)
