extends RefCounted
## Market stalls (town art pass 2). Every counter box with `look: "stall"` gets a
## dressed table, a shade canopy over the vendor's side and wares on top. Visual
## only: posts stand on the counter's own footprint, canopies are above head height.
##
## No two neighbours match: the canopy shape (slanted, peaked tent, twin parasols),
## its colour, and the wares (pottery, produce, cloth, tech, water, spice) all
## step along the row. `face` is the customer side; the vendor stands behind.

const TownBuildings := preload("res://src/systems/world/town_buildings.gd")
const CANOPIES := ["slant", "peak", "parasol"]
const WARES := ["pottery", "produce", "fabric", "tech", "water", "spice"]
const CLOTHS := [LookMaterials.CLOTH_MADDER, LookMaterials.CLOTH_TEAL, LookMaterials.CLOTH_SAFFRON,
	Color("#e6dccb"), Color("#5b3f6e"), Color("#2f5d8a")]
const TERRACOTTA := [Color("#a8603a"), Color("#c27b4a"), Color("#8e4b2e"), Color("#d9b48a"), Color("#2f7f7a")]
const FRUIT := [Color("#e08a2a"), Color("#7aa63a"), Color("#5a2a4a"), Color("#b8322a"), Color("#e2c04a")]
const SPICE := [Color("#b8322a"), Color("#d99a2b"), Color("#7a4a2a"), Color("#e2c04a"), Color("#5f7a3a")]

var kit: TownBuildings        ## shared parts, batching and glows
var mats: LookMaterials
var awnings: Array[MeshInstance3D] = []
var wares := {}               ## stall id -> wares kind (tests, review)
var canopies := {}            ## stall id -> canopy kind
var anchors := {}             ## stall id -> { "front": Vector3, "back": Vector3 } canopy edges (world)
var _rng := RandomNumberGenerator.new()
var _wood: Material
var _wood_top: Material


func _init(building_kit: TownBuildings) -> void:
	kit = building_kit
	mats = kit.mats
	_wood = mats.flat(Color("#6b4a32"), 0.85)
	_wood_top = mats.flat(Color("#8a6444"), 0.8)


func dress(parent: Node3D, stalls: Array) -> void:
	var list := stalls.duplicate()
	list.sort_custom(func(a, b): return str(a.id) < str(b.id))
	for i in list.size():
		_stall(parent, list[i], i)
	_string_lights(parent, list)


func _stall(parent: Node3D, b: Dictionary, i: int) -> void:
	var mn := Vector3(float(b.min[0]), float(b.min[1]), float(b.min[2]))
	var mx := Vector3(float(b.max[0]), float(b.max[1]), float(b.max[2]))
	var face := str(b.get("face", "+z"))
	var along_x := face.ends_with("x")
	var yaw: float = { "+x": 0.0, "-x": PI, "+z": -PI * 0.5, "-z": PI * 0.5 }.get(face, 0.0)
	kit._xf = Transform3D(Basis(Vector3.UP, yaw), Vector3((mn.x + mx.x) * 0.5, mn.y, (mn.z + mx.z) * 0.5))
	var size := mx - mn
	var lx := size.x if along_x else size.z       # depth (customer side is +X)
	var lz := size.z if along_x else size.x       # length along the counter
	var h := size.y
	_rng.seed = hash(str(b.id))
	var id := str(b.id)

	# The table: cabinet, a wider top, a dyed drape on the customer side.
	var drape: Color = CLOTHS[(i * 2 + 1) % CLOTHS.size()]
	kit.part(kit.box(lx - 0.12, h - 0.1, lz - 0.12), _wood, Vector3(0, (h - 0.1) * 0.5, 0))
	kit.part(kit.box(lx + 0.3, 0.1, lz + 0.25), _wood_top, Vector3(0, h - 0.05, 0))
	kit.part(kit.box(0.03, 0.8, lz - 0.2), mats.cloth(drape), Vector3(lx * 0.5 - 0.03, h - 0.5, 0))

	var kind: String = CANOPIES[(i + i / 3) % CANOPIES.size()]
	var color: Color = CLOTHS[(i * 5 + 2) % CLOTHS.size()]
	canopies[id] = kind
	match kind:
		"slant":
			_slant(parent, id, lx, lz, h, color)
		"peak":
			_peak(parent, id, lx, lz, h, color)
		"parasol":
			_parasols(parent, id, lx, lz, h, color, CLOTHS[(i * 5 + 4) % CLOTHS.size()])

	var ware: String = WARES[(i * 5) % WARES.size()]
	wares[id] = ware
	call("_wares_" + ware, lx, lz, h)
	# Stock waiting behind the counter, at one end, out of the vendor's way.
	if _rng.randf() < 0.7:
		var z := (lz * 0.5 - 0.35) * (1.0 if _rng.randf() < 0.5 else -1.0)
		kit.part(kit.box(0.6, 0.5, 0.6), kit.trim, Vector3(-lx * 0.5 - 0.45, 0.25, z), Basis(Vector3.UP, _rng.randf_range(-0.3, 0.3)))
		if _rng.randf() < 0.5:
			kit.part(kit.box(0.5, 0.4, 0.5), kit.trim, Vector3(-lx * 0.5 - 0.45, 0.7, z), Basis(Vector3.UP, _rng.randf_range(-0.4, 0.4)))


# ---------------------------------------------------------------- canopies

func _post(x: float, z: float, y0: float, y1: float) -> void:
	kit.part(kit.cyl(0.045, 0.055, y1 - y0, 6), kit.metal, Vector3(x, (y0 + y1) * 0.5, z))


## A cloth panel from edge `a` down to edge `b` (both local, mid-width), `w` wide across Z.
func _panel(parent: Node3D, a: Vector3, b: Vector3, w: float, color: Color, bow: float = 0.18) -> MeshInstance3D:
	var d := b - a
	var u := Vector3(0, 0, 1)
	var v := -d.normalized()
	var n := u.cross(v)
	var mi := MeshInstance3D.new()
	mi.mesh = LookMeshKit.cloth(w, d.length(), bow, 6, 4)
	mi.material_override = mats.cloth(color)
	mi.transform = kit._xf * Transform3D(Basis(u, v, n), a)
	mi.set_meta("decor", "awning")
	parent.add_child(mi)
	awnings.append(mi)
	return mi


## A short fringe hanging straight down from a canopy edge.
func _valance(parent: Node3D, top: Vector3, w: float, color: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = LookMeshKit.cloth(w, 0.28, 0.02, 6, 1)
	mi.material_override = mats.cloth(color.darkened(0.15))
	mi.transform = kit._xf * Transform3D(Basis(Vector3.UP, -PI * 0.5), top)
	mi.set_meta("decor", "awning")
	parent.add_child(mi)
	awnings.append(mi)


func _anchor(id: String, front: Vector3, back: Vector3) -> void:
	anchors[id] = { "front": kit._xf * front, "back": kit._xf * back }


## One sheet, high over the vendor, sloping down past the customer's side.
func _slant(parent: Node3D, id: String, lx: float, lz: float, h: float, color: Color) -> void:
	var back := Vector3(-lx * 0.5 - 1.7, 2.95, 0)
	var front := Vector3(lx * 0.5 + 0.9, 2.4, 0)
	_panel(parent, back, front, lz + 0.8, color)
	_valance(parent, front + Vector3(0, -0.02, 0), lz + 0.8, color)
	for s in [-1.0, 1.0]:
		var z: float = s * (lz * 0.5 - 0.06)
		_post(lx * 0.5 - 0.06, z, h, lerpf(2.95, 2.4, (lx * 0.5 - 0.06 - back.x) / (front.x - back.x)) - 0.08)
		_post(-lx * 0.5 + 0.06, z, h, lerpf(2.95, 2.4, (-lx * 0.5 + 0.06 - back.x) / (front.x - back.x)) - 0.08)
		# A brace out to the far back corner.
		kit.part(kit.box(1.8, 0.05, 0.05), kit.metal, Vector3(-lx * 0.5 - 0.8, 2.75, z), Basis(Vector3.BACK, -0.12))
	_anchor(id, front, back)


## A tent: ridge over the counter's back edge, eaves both sides.
func _peak(parent: Node3D, id: String, lx: float, lz: float, h: float, color: Color) -> void:
	var ridge := Vector3(-0.3, 3.2, 0)
	var front := Vector3(lx * 0.5 + 0.9, 2.45, 0)
	var back := Vector3(-lx * 0.5 - 1.5, 2.45, 0)
	_panel(parent, ridge, front, lz + 0.6, color, 0.12)
	_panel(parent, ridge, back, lz + 0.6, color, 0.12)
	_valance(parent, front + Vector3(0, -0.02, 0), lz + 0.6, color)
	for s in [-1.0, 1.0]:
		var z: float = s * (lz * 0.5 - 0.06)
		_post(-0.3, z, h, 3.12)
	kit.part(kit.cyl(0.04, 0.04, lz + 0.6, 6), kit.metal, ridge + Vector3(0, -0.04, 0), kit.AXIS_Z)
	_anchor(id, front, back)


## Two parasols, one at each end of the counter, in two colours.
func _parasols(parent: Node3D, id: String, lx: float, lz: float, h: float, a: Color, b: Color) -> void:
	for k in 2:
		var z := (lz * 0.25) * (1.0 if k == 0 else -1.0)
		var c := Vector3(-0.3, 2.75, z)
		_post(-0.3, z, h, 2.9)
		var cone := CylinderMesh.new()
		cone.top_radius = 0.06
		cone.bottom_radius = 1.75
		cone.height = 0.62
		cone.radial_segments = 10
		cone.rings = 1
		cone.cap_bottom = false
		var mi := MeshInstance3D.new()
		mi.mesh = cone
		mi.material_override = mats.cloth(a if k == 0 else b)
		mi.transform = kit._xf * Transform3D(Basis.IDENTITY, c)
		mi.set_meta("decor", "awning")
		parent.add_child(mi)
		awnings.append(mi)
		kit.part(kit.ball(0.07, 0.14, false, 8), kit.metal, c + Vector3(0, 0.34, 0))
	_anchor(id, Vector3(lx * 0.5 + 1.0, 2.45, 0), Vector3(-lx * 0.5 - 1.2, 2.45, 0))


# ---------------------------------------------------------------- wares

## Even spots along the table top, with a little jitter, between z0 and z1.
func _row(n: int, lz: float, x: float, h: float) -> Array:
	var out: Array = []
	for k in n:
		var t := (k + 0.5) / n
		out.append(Vector3(x + _rng.randf_range(-0.05, 0.05), h, (t - 0.5) * (lz - 0.4) + _rng.randf_range(-0.06, 0.06)))
	return out


func _wares_pottery(_lx: float, lz: float, h: float) -> void:
	for p in _row(6, lz, 0.05, h):
		var r := _rng.randf_range(0.11, 0.2)
		var tall := r * _rng.randf_range(1.8, 2.8)
		var c: Color = TERRACOTTA[_rng.randi() % TERRACOTTA.size()]
		var m := mats.flat(c, 0.75)
		kit.part(kit.ball(r, tall, false, 12), m, p + Vector3(0, tall * 0.5, 0))
		kit.part(kit.cyl(r * 0.45, r * 0.5, 0.08, 10), m, p + Vector3(0, tall + 0.02, 0))
	for p in _row(4, lz, -0.3, h):
		kit.part(kit.cyl(0.12, 0.08, 0.1, 10), mats.flat(TERRACOTTA[_rng.randi() % 3], 0.75), p + Vector3(0, 0.05, 0))


func _wares_produce(_lx: float, lz: float, h: float) -> void:
	var basket := mats.flat(Color("#9a7a4a"), 0.95)
	for p in _row(3, lz, 0.0, h):
		kit.part(kit.cyl(0.32, 0.26, 0.14, 14), basket, p + Vector3(0, 0.07, 0))
		var m := mats.flat(FRUIT[_rng.randi() % FRUIT.size()], 0.6)
		var r := _rng.randf_range(0.06, 0.09)
		for k in 7:
			var a := TAU * k / 7.0
			var off := Vector3(cos(a), 0, sin(a)) * (0.0 if k == 0 else 0.17)
			kit.part(kit.ball(r, r * 2.0, false, 8), m, p + off + Vector3(0, 0.15 + (0.04 if k == 0 else 0.0), 0))


func _wares_fabric(_lx: float, lz: float, h: float) -> void:
	var n := 7
	for k in n:
		var z := (float(k) / (n - 1) - 0.5) * (lz - 0.6)
		var c: Color = CLOTHS[(k + _rng.randi()) % CLOTHS.size()]
		kit.part(kit.cyl(0.11, 0.11, 0.75, 10), mats.cloth(c), Vector3(0, h + 0.11, z), kit.AXIS_X)
		if k < n - 1:
			var c2: Color = CLOTHS[(k + 3) % CLOTHS.size()]
			kit.part(kit.cyl(0.1, 0.1, 0.7, 10), mats.cloth(c2.lightened(0.1)), Vector3(0, h + 0.3, z + (lz - 0.6) / (n - 1) * 0.5), kit.AXIS_X)


func _wares_tech(_lx: float, lz: float, h: float) -> void:
	for p in _row(4, lz, -0.15, h):
		var s := Vector3(_rng.randf_range(0.2, 0.4), _rng.randf_range(0.12, 0.3), _rng.randf_range(0.2, 0.4))
		kit.part(kit.box(snappedf(s.x, 0.05), snappedf(s.y, 0.05), snappedf(s.z, 0.05)), kit.trim, p + Vector3(0, s.y * 0.5, 0), Basis(Vector3.UP, _rng.randf_range(-0.4, 0.4)))
	for p in _row(6, lz, 0.25, h):
		kit.part(kit.cyl(0.05, 0.05, 0.22, 8), kit.door_glow, p + Vector3(0, 0.11, 0))
	kit.part(kit.ring(0.1, 0.17, 0.0, 0.06, 14), kit.metal, Vector3(0.1, h, lz * 0.3))
	# A salvaged readout panel, tilted toward the customer.
	kit.part(kit.box(0.05, 0.3, 0.45), kit.door_glow, Vector3(-0.25, h + 0.2, -lz * 0.32), Basis(Vector3.BACK, -0.35))


func _wares_water(_lx: float, lz: float, h: float) -> void:
	var can := mats.flat(Color("#5b6f78"), 0.4, 0.6)
	for row in [-0.15, 0.2]:
		for p in _row(6, lz - 0.9, row, h):
			kit.part(kit.cyl(0.09, 0.1, 0.38, 10), can, p + Vector3(0, 0.19, -0.45))
	kit.part(kit.cyl(0.3, 0.32, 0.55, 14), mats.flat(Color("#3f5a63"), 0.45, 0.5), Vector3(0, h + 0.275, lz * 0.5 - 0.4))
	kit.part(kit.box(0.2, 0.05, 0.05), kit.metal, Vector3(0.38, h + 0.1, lz * 0.5 - 0.4))


func _wares_spice(_lx: float, lz: float, h: float) -> void:
	var sack := mats.cloth(LookMaterials.CLOTH_SAND)
	for p in _row(5, lz - 0.8, 0.0, h):
		var q: Vector3 = p + Vector3(0, 0, -0.4)
		kit.part(kit.ball(0.22, 0.34, false, 12), sack, q + Vector3(0, 0.15, 0))
		kit.part(kit.cyl(0.16, 0.16, 0.04, 12), mats.flat(SPICE[_rng.randi() % SPICE.size()], 1.0), q + Vector3(0, 0.3, 0))
	# A brass balance at the end.
	var brass := mats.flat(Color("#b08a3a"), 0.4, 0.8)
	var z := lz * 0.5 - 0.4
	kit.part(kit.cyl(0.08, 0.1, 0.35, 8), brass, Vector3(0, h + 0.175, z))
	kit.part(kit.box(0.04, 0.03, 0.5), brass, Vector3(0, h + 0.37, z))
	for s in [-0.22, 0.22]:
		kit.part(kit.cyl(0.09, 0.07, 0.03, 10), brass, Vector3(0, h + 0.22, z + s))


# ---------------------------------------------------------------- lights

## Strings of bulbs across the lane, from each stall to the one facing it.
func _string_lights(parent: Node3D, stalls: Array) -> void:
	var cable := mats.flat(Color("#2b2522"), 0.7)
	var bulb := kit.ball(0.06, 0.12, false, 6)
	var ids := anchors.keys()
	for a_id in ids:
		var a: Dictionary = anchors[a_id]
		var best := ""
		var best_d := INF
		for b_id in ids:
			if b_id == a_id:
				continue
			var b: Dictionary = anchors[b_id]
			var d: float = (a.back as Vector3).distance_to(b.front)
			if d < best_d and absf((a.back as Vector3).x - (b.front as Vector3).x) < 1.0:
				best_d = d
				best = b_id
		if best == "" or best_d > 16.0:
			continue
		var p0: Vector3 = a.back + Vector3(0, -0.05, 0)
		var p1: Vector3 = anchors[best].front + Vector3(0, -0.05, 0)
		var pts := LookMeshKit.catenary(p0, p1, 0.6, 16)
		var mi := MeshInstance3D.new()
		mi.mesh = LookMeshKit.tube(pts, 0.015, 4)
		mi.material_override = cable
		parent.add_child(mi)
		for k in range(1, pts.size() - 1):
			kit.put(bulb, kit.window_glow, Transform3D(Basis.IDENTITY, pts[k] + Vector3(0, -0.08, 0)))
