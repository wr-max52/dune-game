class_name NativeCamp
extends Node3D
## Issue #96: a desert pack's camp. A ring of hide tents round a firepit that is
## always lit, built where the pack's data puts it (a stop on its route). Each tent
## is a full room: walls with a doorway facing the fire, a roof, a rug, a rock
## table and rock seats, a bedroll and a chest of loot. The walls are solid.
##
## Shoot a tent and it takes damage; enough and it falls in (the rock furniture and
## the chest stay). Every tent down and the camp is wrecked: it is rebuilt a few
## in-game hours later (NativesDirector, WorldState.native_camp). What the tents'
## chests hold, who sees you take it, and resting are the director's.
##
## Built from the people's "camp" block (content/core/species/*.json) and the
## pack's own "camp" (the planet's natives data).

signal tent_hit(shooter: Node, amount: float)
signal wrecked

var id := ""
var cfg: Dictionary = {}
var director                          ## NativesDirector: the ground, the materials
var center := Vector3.ZERO            ## the firepit, on the ground
var up := Vector3.UP
var tents: Array = []                 ## see _tent
var fires: Array = []                 ## { root, light, flames: [MeshInstance3D] }
var spots: Array = []                 ## where members stand round the fire (world)
var is_wrecked := false
var lit_near := 140.0                 ## lights and flicker only this close to the player
var _near := false
var _near_t := 0.0
var _t := 0.0


func setup(camp_id: String, camp_cfg: Dictionary, p_director, at: Vector3) -> void:
	id = camp_id
	name = "Camp_" + camp_id
	cfg = camp_cfg
	director = p_director
	center = pick_site(at)
	up = director.up_at(center)


## The flattest ground within site_search_m of `at` for the fire and the ring of
## tents (dunes would cut through them), off any rock. A few hundred ground
## queries, once.
func pick_site(at: Vector3) -> Vector3:
	var search := float(cfg.get("site_search_m", 45.0))
	var u: Vector3 = director.up_at(at)
	var side := NativeSteer._side(u)
	var fwd := side.cross(u).normalized()
	var best := at
	var best_score := INF
	var step := 9.0
	var n := int(search / step)
	for i in range(-n, n + 1):
		for j in range(-n, n + 1):
			var c: Vector3 = at + side * (i * step) + fwd * (j * step)
			if c.distance_to(at) > search:
				continue
			if director.steer != null and director.steer.blocked(c, u):
				continue
			var score := _unevenness(director._on_ground(c)) + c.distance_to(at) * 0.01
			if score < best_score:
				best_score = score
				best = c
	return director._on_ground(best)


## How far apart (up and down) the ground is under the fire and the tents' floors.
func _unevenness(c: Vector3) -> float:
	var u: Vector3 = director.up_at(c)
	var side := NativeSteer._side(u)
	var fwd := side.cross(u).normalized()
	var ring := float(cfg.get("ring_m", 9.0))
	var r := float(cfg.get("tent_radius", 3.0))
	var lo := 0.0
	var hi := 0.0
	for k in 12:
		var a := TAU * float(k) / 12.0
		for d: float in [ring - r, ring, ring + r]:
			var h: float = (director._on_ground(c + (side * cos(a) + fwd * sin(a)) * d) - c).dot(u)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return hi - lo


## Everything, at once (a few dozen meshes and shapes; no bodies).
func build() -> void:
	var mats: LookMaterials = director.demo._flat_mats() if director.demo != null and director.demo.use_look else null
	var n := clampi(int(cfg.get("tents", 3)), 1, 6)
	var ring := float(cfg.get("ring_m", 9.0))
	var side := NativeSteer._side(up)
	var fwd := side.cross(up).normalized()
	var a0 := float(cfg.get("yaw_deg", 0.0)) * PI / 180.0
	for i in n:
		var a := a0 + TAU * float(i) / float(n)
		var at := center + (side * cos(a) + fwd * sin(a)) * ring
		if director.steer != null:
			at = director.steer.clear_spot(at, up)
		var fl := _floor_at(director._on_ground(at))
		tents.append(_tent(i, fl.at, float(fl.depth), mats))
	fires.append(_firepit(center, mats))
	var k := maxi(int(cfg.get("spots", 14)), 1)
	for i in k:
		var a := TAU * (float(i) + 0.5) / float(k)
		var r := 2.6 + float(i % 2) * 1.2
		spots.append(director._on_ground(center + (side * cos(a) + fwd * sin(a)) * r))


## A tent's floor: { at, depth }. Level with the highest ground under it (up to
## half a metre over the middle), so no sand shows through inside; `depth` is how
## far down its earth platform and walls reach to meet the lowest ground.
func _floor_at(at: Vector3) -> Dictionary:
	var u: Vector3 = director.up_at(at)
	var side := NativeSteer._side(u)
	var fwd := side.cross(u).normalized()
	var r := float(cfg.get("tent_radius", 3.0))
	var sum := 0.0
	var lo := 0.0
	var hi := 0.0
	for k in 12:
		var a := TAU * float(k) / 12.0
		for d: float in [r * 0.5, r]:
			var h: float = (director._on_ground(at + (side * cos(a) + fwd * sin(a)) * d) - at).dot(u)
			sum += h
			lo = minf(lo, h)
			hi = maxf(hi, h)
	var floor_h := minf(hi, sum / 24.0 + 0.5) + 0.03
	return { "at": at + u * floor_h, "depth": floor_h - lo + 0.3 }


## The frame of something standing at `at` on the ground, its +Z turned to face `look`.
func _frame(at: Vector3, look: Vector3) -> Transform3D:
	var u: Vector3 = director.up_at(at)
	var tilt := PlanetSphere.tilt_to(u)
	var l := tilt.inverse() * (look - at)
	var yaw := atan2(l.x, l.z) if Vector2(l.x, l.z).length() > 0.01 else 0.0
	return Transform3D(tilt * Basis(Vector3.UP, yaw), at)


# ------------------------------------------------------------------ tents

class TentBody extends StaticBody3D:
	var camp
	var index := 0

	func apply_damage_from(amount: float, shooter: Node) -> void:
		camp._on_tent_hit(index, amount, shooter)

	func apply_damage(amount: float) -> void:
		apply_damage_from(amount, null)


## One tent: { index, xf, body, upright, heap, walls: [CollisionShape3D], hp, down,
## inside: Vector3 (its middle, on the floor), bed, box (chest, world), lid }.
func _tent(i: int, at: Vector3, depth: float, mats: LookMaterials) -> Dictionary:
	var xf := _frame(at, center)            # the doorway (+Z) faces the fire
	var r := float(cfg.get("tent_radius", 3.0))
	var wall_h := float(cfg.get("wall_h", 1.95))
	var root := Node3D.new()
	root.name = "Tent_%d" % i
	add_child(root)
	root.global_transform = xf
	var body := TentBody.new()
	body.name = "Body"
	body.camp = self
	body.index = i
	root.add_child(body)
	var upright := Node3D.new()
	upright.name = "Upright"
	root.add_child(upright)
	var t := { "index": i, "xf": xf, "root": root, "body": body, "upright": upright, "walls": [],
		"hp": float(cfg.get("tent_hp", 90.0)), "down": false, "r": r }
	var hide_col := Color(str(cfg.get("hide", "#a88a64")))
	var hide: Material = null
	var dark: Material = null
	var rock: Material = null
	var wood: Material = null
	if mats != null:
		# Two-sided (seen from inside too). Its own copy, taking no shadows on
		# itself: thin two-sided cloth stripes with shadow acne otherwise.
		var hm := mats.cloth(hide_col).duplicate() as StandardMaterial3D
		hm.disable_receive_shadows = true
		hide = hm
		dark = mats.cloth(hide_col.darkened(0.35))
		rock = mats.flat(Color(str(cfg.get("rock", "#6e6258"))), 1.0)
		wood = mats.flat(Color("#5e4228"), 0.95)
	# The floor: a low platform of packed earth, its sides sloped so you walk up
	# onto it at the doorway, reaching down to the lowest ground under the tent.
	var plat := CylinderMesh.new()
	plat.top_radius = r - 0.05
	plat.bottom_radius = r + depth * 1.6
	plat.height = depth
	plat.radial_segments = 16
	plat.rings = 1
	var earth: Material = mats.flat(Color(str(cfg.get("earth", "#9a7a56"))), 1.0) if mats != null else null
	_mesh(root, plat, earth, Transform3D(Basis.IDENTITY, Vector3(0, -depth * 0.5, 0)))
	_shape(body, plat.create_convex_shape(), Transform3D(Basis.IDENTITY, Vector3(0, -depth * 0.5, 0)))
	# Walls: panels round a circle, the ones at the front left out (the doorway).
	var segs := 14
	var skirt := maxf(float(cfg.get("skirt_m", 0.8)), depth)
	var door := deg_to_rad(float(cfg.get("door_deg", 34.0)))
	var chord := 2.0 * r * sin(PI / segs) + 0.04
	for s in segs:
		var a := TAU * (float(s) + 0.5) / segs
		if absf(wrapf(a, -PI, PI)) < door:
			continue
		# Down into the sand by `skirt`, so a slope never shows a gap under it.
		var pos := Vector3(r * sin(a), (wall_h - skirt) * 0.5, r * cos(a))
		var b := Basis(Vector3.UP, a)
		_mesh(upright, _box(Vector3(chord, wall_h + skirt, 0.06)), hide, Transform3D(b, pos))
		var cs := _shape(body, _box_shape(Vector3(chord, wall_h + skirt, 0.3)), Transform3D(b, pos))
		(t.walls as Array).append(cs)
	# Flaps tied back either side of the doorway.
	for sgn: float in [-1.0, 1.0]:
		var a := sgn * door
		var b := Basis(Vector3.UP, a + sgn * 0.9)
		_mesh(upright, _box(Vector3(0.9, wall_h * 0.92, 0.05)), dark,
			Transform3D(b, Vector3((r + 0.25) * sin(a), wall_h * 0.46, (r + 0.25) * cos(a))))
	# The roof: a low cone to a centre pole, open underneath.
	var roof_h := float(cfg.get("roof_h", 1.5))
	var cone := CylinderMesh.new()
	cone.top_radius = 0.12
	cone.bottom_radius = r + 0.3
	cone.height = roof_h
	cone.cap_top = false
	cone.cap_bottom = false
	cone.radial_segments = segs
	_mesh(upright, cone, hide, Transform3D(Basis.IDENTITY, Vector3(0, wall_h + roof_h * 0.5 - 0.05, 0)))
	_mesh(upright, _cyl(0.06, wall_h + roof_h + 0.3), wood, Transform3D(Basis.IDENTITY, Vector3(0, (wall_h + roof_h + 0.3) * 0.5, 0)))
	_shape(body, _cyl_shape(0.1, wall_h + roof_h), Transform3D(Basis.IDENTITY, Vector3(0, (wall_h + roof_h) * 0.5, 0)))
	# The heap it falls into (hidden until then): the roof flat on the ground.
	var heap := Node3D.new()
	heap.name = "Heap"
	heap.visible = false
	root.add_child(heap)
	var flat := cone.duplicate() as CylinderMesh
	flat.height = 0.35
	flat.top_radius = 0.6
	_mesh(heap, flat, hide, Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3(0.3, 0.2, -0.2)))
	_mesh(heap, _box(Vector3(2.2, 0.06, 1.6)), dark, Transform3D(Basis(Vector3.UP, 0.7), Vector3(-1.2, 0.08, 1.1)))
	_mesh(heap, _cyl(0.06, 3.2), wood, Transform3D(Basis(Vector3.FORWARD, 1.45), Vector3(0, 0.12, 0.4)))
	t["heap"] = heap
	# Inside: a rug, a rock table with rock seats, a bedroll, the chest.
	var rug := Color(str(cfg.get("rug", "#8c3a26")))
	if mats != null:
		_mesh(root, _box(Vector3(r * 1.3, 0.03, r * 1.15)), mats.cloth(rug), Transform3D(Basis.IDENTITY, Vector3(0, 0.02, -0.2)))
	var table := Vector3(0.0, 0.0, -1.1)
	_mesh(root, _cyl(0.3, 0.5), rock, Transform3D(Basis.IDENTITY, table + Vector3(0, 0.25, 0)))
	_mesh(root, _box(Vector3(1.2, 0.14, 0.75)), rock, Transform3D(Basis(Vector3.UP, 0.08), table + Vector3(0, 0.57, 0)))
	_shape(body, _box_shape(Vector3(1.2, 0.64, 0.75)), Transform3D(Basis.IDENTITY, table + Vector3(0, 0.32, 0)))
	for seat: Vector3 in [Vector3(-1.0, 0, -1.0), Vector3(1.0, 0, -1.2), Vector3(0.2, 0, -2.0)]:
		_mesh(root, _cyl(0.27, 0.44), rock, Transform3D(Basis(Vector3.UP, seat.x), seat + Vector3(0, 0.22, 0)))
		_shape(body, _cyl_shape(0.27, 0.44), Transform3D(Basis.IDENTITY, seat + Vector3(0, 0.22, 0)))
	var bed := Vector3(-1.75, 0.0, 0.5)
	if mats != null:
		_mesh(root, _box(Vector3(0.85, 0.12, 1.9)), mats.cloth(hide_col.lightened(0.2)), Transform3D(Basis(Vector3.UP, 0.25), bed + Vector3(0, 0.06, 0)))
		_mesh(root, _box(Vector3(0.6, 0.14, 0.32)), mats.cloth(rug.darkened(0.2)), Transform3D(Basis(Vector3.UP, 0.25), bed + Vector3(0.18, 0.14, -0.75)))
	var chest := Vector3(1.75, 0.0, 0.1)
	var cb := Basis(Vector3.UP, -PI * 0.5)      # its front faces the middle of the tent
	_mesh(root, _box(Vector3(0.85, 0.5, 0.52)), wood, Transform3D(cb, chest + Vector3(0, 0.25, 0)))
	_shape(body, _box_shape(Vector3(0.85, 0.5, 0.52)), Transform3D(cb, chest + Vector3(0, 0.25, 0)))
	var hinge := Node3D.new()
	hinge.name = "Lid"
	root.add_child(hinge)
	hinge.transform = Transform3D(cb, chest + cb * Vector3(0, 0.5, -0.26))
	_mesh(hinge, _box(Vector3(0.88, 0.08, 0.54)), dark if dark != null else wood, Transform3D(Basis.IDENTITY, Vector3(0, 0.04, 0.27)))
	t["lid"] = hinge
	t["inside"] = xf * Vector3(0, 0, -0.3)
	t["bed"] = xf * bed
	t["box"] = xf * (chest + Vector3(0, 0.4, 0))
	# A dim lamp inside, so the room reads (on only near the player).
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.72, 0.42)
	lamp.light_energy = 0.7
	lamp.omni_range = r + 1.2
	lamp.shadow_enabled = false
	lamp.position = Vector3(0, wall_h + 0.1, 0)
	lamp.visible = false
	root.add_child(lamp)
	t["lamp"] = lamp
	return t


## Open or shut tent `i`'s chest lid (open = emptied).
func set_lid(i: int, open: bool) -> void:
	var lid: Node3D = tents[i].lid
	lid.rotation.x = -1.9 if open else 0.0


## Which tent the point is inside (in from its wall), or -1.
func tent_at(p: Vector3, margin: float = 0.4) -> int:
	for t in tents:
		var l: Vector3 = (t.xf as Transform3D).affine_inverse() * p
		if Vector2(l.x, l.z).length() < float(t.r) - margin and l.y > -1.0 and l.y < 3.0:
			return int(t.index)
	return -1


## The tent whose chest `p` is within `reach` of, or -1.
func chest_near(p: Vector3, reach: float = 1.6) -> int:
	for t in tents:
		if (t.box as Vector3).distance_to(p) <= reach:
			return int(t.index)
	return -1


func _on_tent_hit(i: int, amount: float, shooter: Node) -> void:
	var t: Dictionary = tents[i]
	tent_hit.emit(shooter, amount)
	if bool(t.down):
		return
	t.hp = float(t.hp) - amount
	if float(t.hp) <= 0.0:
		knock_down(i)


## Tent `i` falls in: the walls and roof become a heap, the walls stop being walls.
func knock_down(i: int) -> void:
	var t: Dictionary = tents[i]
	if bool(t.down):
		return
	t.down = true
	(t.upright as Node3D).visible = false
	(t.heap as Node3D).visible = true
	for cs in t.walls:
		(cs as CollisionShape3D).disabled = true
	if tents.all(func(x): return bool(x.down)) and not is_wrecked:
		is_wrecked = true
		wrecked.emit()


## Wrecked from the start (a save from inside the hours it takes to come back).
func show_wrecked() -> void:
	for t in tents:
		knock_down(int(t.index))


## Back up: every tent standing and whole again.
func rebuild() -> void:
	is_wrecked = false
	for t in tents:
		t.down = false
		t.hp = float(cfg.get("tent_hp", 90.0))
		(t.upright as Node3D).visible = true
		(t.heap as Node3D).visible = false
		for cs in t.walls:
			(cs as CollisionShape3D).disabled = false


# ------------------------------------------------------------------ fire

func _firepit(at: Vector3, mats: LookMaterials) -> Dictionary:
	var root := Node3D.new()
	root.name = "Firepit"
	add_child(root)
	root.global_transform = _frame(at, at + NativeSteer._side(up))
	var rock: Material = mats.flat(Color("#4e4640"), 1.0) if mats != null else null
	var wood: Material = mats.flat(Color("#3e2a1a"), 1.0) if mats != null else null
	var stones := 9
	for s in stones:
		var a := TAU * float(s) / stones
		var st := SphereMesh.new()
		st.radius = 0.2
		st.height = 0.26
		st.radial_segments = 6
		st.rings = 3
		_mesh(root, st, rock, Transform3D(Basis(Vector3.UP, a), Vector3(0.75 * sin(a), 0.1, 0.75 * cos(a))))
	for k in 3:
		_mesh(root, _cyl(0.06, 1.0), wood, Transform3D(Basis(Vector3.UP, k * 1.05) * Basis(Vector3.RIGHT, 1.35), Vector3(0, 0.12, 0)))
	var flames: Array = []
	if mats != null:
		for k in 3:
			var c := CylinderMesh.new()
			c.top_radius = 0.0
			c.bottom_radius = 0.26 - k * 0.06
			c.height = 0.7 + k * 0.15
			c.radial_segments = 6
			c.rings = 1
			var col := Color("#ff7a1a") if k == 0 else (Color("#ffb03a") if k == 1 else Color("#ffe08a"))
			var fm := mats.glow(col)
			fm.emission_energy_multiplier = 3.0
			fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			fm.albedo_color = col
			var f := _mesh(root, c, fm, Transform3D(Basis.IDENTITY, Vector3(0.05 * (k - 1), 0.2 + c.height * 0.5, 0.04 * k)))
			f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			flames.append(f)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.28)
	light.light_energy = float(cfg.get("fire_energy", 1.8))
	light.omni_range = float(cfg.get("fire_range", 10.0))
	light.shadow_enabled = false
	light.position = Vector3(0, 0.9, 0)
	light.visible = false
	root.add_child(light)
	return { "root": root, "light": light, "flames": flames }


## Lights on and the fire flickering only near the player (checked twice a second).
func tick(dt: float, ppos: Vector3) -> void:
	_t += dt
	_near_t -= dt
	if _near_t <= 0.0:
		_near_t = 0.5
		var near := ppos != Vector3.INF and ppos.distance_to(center) < lit_near
		if near != _near:
			_near = near
			for f in fires:
				(f.light as OmniLight3D).visible = near
			for t in tents:
				(t.lamp as OmniLight3D).visible = near
	if not _near:
		return
	for f in fires:
		var k := 0
		for fl in f.flames:
			var s := 1.0 + 0.16 * sin(_t * (9.0 + k * 3.7) + k) + 0.08 * sin(_t * 23.0 + k * 2.0)
			(fl as Node3D).scale = Vector3(1.0, s, 1.0)
			k += 1
		(f.light as OmniLight3D).light_energy = float(cfg.get("fire_energy", 1.8)) * (0.85 + 0.15 * sin(_t * 11.0))


func lights_on() -> bool:
	return _near


# ------------------------------------------------------------------ bits

func _mesh(parent: Node3D, mesh: Mesh, mat: Material, xf: Transform3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if mat != null:
		mi.material_override = mat
		if mat is BaseMaterial3D and (mat as BaseMaterial3D).cull_mode == BaseMaterial3D.CULL_DISABLED:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED   # thin hide: no striping inside
	mi.transform = xf
	parent.add_child(mi)
	return mi


func _shape(body: StaticBody3D, shape: Shape3D, xf: Transform3D) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = xf
	body.add_child(cs)
	return cs


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _cyl(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 8
	c.rings = 1
	return c


static func _box_shape(size: Vector3) -> BoxShape3D:
	var b := BoxShape3D.new()
	b.size = size
	return b


static func _cyl_shape(r: float, h: float) -> CylinderShape3D:
	var c := CylinderShape3D.new()
	c.radius = r
	c.height = h
	return c
