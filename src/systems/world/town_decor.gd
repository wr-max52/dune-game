extends Node3D
## Visual-only dressing for the port town. Reads the same TownLayout data as the
## gameplay layer. Adds NO collision. Replaced piece by piece by future art passes.
##
## Rules (docs/town/TOWN_PLAN.md addendum, D1 to D6):
##   - never adds collision, never moves or resizes a box, never edits port_town.json
##   - no market art (awnings, cables, goods) and no character art
##   - look numbers come from LookMaterials constants or time_of_day.json
## `_lamp_at` and `_banner` are copies of the beauty corner helpers, on purpose:
## the beauty corner is the art reference and is not edited.

var mats: LookMaterials
var look: LookEnvironment
var lamps: Array[OmniLight3D] = []
var banners: Array[MeshInstance3D] = []
var skipped_kinds := {}       ## kind -> true, for boxes that keep their greybox color
var _rng := RandomNumberGenerator.new()


func dress(town, look_env: LookEnvironment) -> void:
	name = "TownDecor"
	look = look_env
	mats = LookMaterials.new()
	_rng.seed = 9001                      # fixed seed: same town every run
	_apply_materials(town)
	_add_lamps(town)
	_add_banners(town)


# ---------------------------------------------------------------- materials

func _box_mesh(id: String) -> MeshInstance3D:
	var body := get_parent().get_node_or_null("Town/" + id)
	if body == null:
		return null
	for c in body.get_children():
		if c is MeshInstance3D:
			return c
	return null


func _inside_bounds(town, b: Dictionary) -> bool:
	var bounds: Dictionary = town.data.get("bounds", {})
	if bounds.is_empty():
		return true
	return float(b.min[0]) >= float(bounds.min[0]) and float(b.max[0]) <= float(bounds.max[0]) \
		and float(b.min[2]) >= float(bounds.min[1]) and float(b.max[2]) <= float(bounds.max[1])


## The material for one box, per the addendum's table. null = keep greybox.
func material_for(town, b: Dictionary) -> Material:
	var id := str(b.id)
	var kind := str(b.kind)
	var zone := str(b.get("zone", ""))
	var min_y := float(b.min[1])
	var h := float(b.max[1]) - min_y
	const BANDS := [LookMaterials.CLOTH_TEAL, LookMaterials.CLOTH_MADDER,
		LookMaterials.CLOTH_SAFFRON, LookMaterials.CLOTH_SAND]

	# Ids first: they override their kind's row.
	if id == "pit_floor":
		return mats.hull(-6.0, 6.0)
	if id == "dock_booth":
		return mats.hull(0.0, 1.5)
	match kind:
		"floor":
			if zone == "ground":
				return mats.paving(2.4) if _inside_bounds(town, b) else mats.flat(LookMaterials.CLOTH_SAND)
		"wall":
			if zone == "perimeter":
				return mats.plaster(0.0, 5.2, LookMaterials.REMNANT_OXBLOOD.darkened(0.1))
			if zone == "spaceport":
				return mats.plaster(-6.0, -1.0, LookMaterials.CLOTH_SAFFRON)
			if zone == "cantina":
				return mats.plaster(0.0, 3.6, LookMaterials.CLOTH_TEAL)
		"overhead", "roof":
			if zone == "cantina":
				return mats.plaster(0.0, 3.6, LookMaterials.CLOTH_TEAL)
		"solid":
			if zone == "residential_w" or zone == "residential_e":
				return mats.plaster(0.0, h * 0.35, BANDS[_rng.randi() % BANDS.size()])
			if zone == "market":
				return mats.plaster(0.0, 1.4, LookMaterials.CLOTH_SAFFRON)
			if zone == "barracks":
				return mats.plaster(0.0, 2.0, LookMaterials.REMNANT_OXBLOOD)
		"ship":
			return mats.hull(-6.0, 4.0)
		"cover", "counter", "ramp":
			return mats.hull(min_y, 0.8)
	return null


func _apply_materials(town) -> void:
	for b in town.boxes():
		var mi := _box_mesh(str(b.id))
		if mi == null:
			push_warning("TownDecor: no gameplay node for box " + str(b.id))
			continue
		var m := material_for(town, b)
		if m == null:
			var key := str(b.kind)
			if not skipped_kinds.has(key):
				skipped_kinds[key] = true
				push_warning("TownDecor: no decor material for kind '%s' (keeps greybox)" % key)
			continue
		mi.material_override = m


# ---------------------------------------------------------------- lamps

func _v3(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## Copied from beauty_corner.gd `_lamp` (renamed). Bulb + omni light, both tracked
## so dusk turns them on.
func _lamp_at(parent: Node3D, pos: Vector3) -> void:
	var bulb := mats.glow(Color("#ffb46a"))
	look.track_glow(bulb)
	var s := SphereMesh.new()
	s.radius = 0.16
	s.height = 0.32
	var mi := MeshInstance3D.new()
	mi.mesh = s
	mi.material_override = bulb
	mi.position = pos
	parent.add_child(mi)
	var l := OmniLight3D.new()
	l.position = pos + Vector3(0.3, 0, 0)
	l.light_color = Color("#ffb46a")
	l.omni_range = 9.0
	l.set_meta("base_energy", 2.2)
	l.shadow_enabled = false
	parent.add_child(l)
	look.track_lamp(l)
	lamps.append(l)


func _add_lamps(town) -> void:
	var root := Node3D.new()
	root.name = "Lamps"
	add_child(root)
	# Cantina: three along the bar, 1 m on the door side, and one at the door.
	var bar: Dictionary = town.get_box("bar_counter")
	if not bar.is_empty():
		var z0 := float(bar.min[2])
		var z1 := float(bar.max[2])
		for i in 3:
			var z := lerpf(z0, z1, (i + 0.5) / 3.0)
			_lamp_at(root, Vector3(float(bar.max[0]) + 1.0, 3.0, z))
	if not town.get_marker("cantina_door").is_empty():
		_lamp_at(root, town.marker_pos("cantina_door") + Vector3(1.0, 2.9, 2.5))
	# Pit: one big light over the pad, set up like the beauty corner's landing bay.
	var pit: Dictionary = town.get_box("pit_floor")
	if not pit.is_empty():
		var c := (_v3(pit.min) + _v3(pit.max)) * 0.5
		var l := OmniLight3D.new()
		l.name = "PitLight"
		l.position = Vector3(c.x, float(pit.max[1]) + 4.0, c.z)
		l.light_color = Color("#ffcf8a")
		l.omni_range = 28.0
		l.set_meta("base_energy", 3.0)
		root.add_child(l)
		look.track_lamp(l)
		lamps.append(l)
	# Gate: one lamp each side.
	if not town.get_marker("gate").is_empty():
		var g: Vector3 = town.marker_pos("gate")
		for side in [-7.0, 7.0]:
			_lamp_at(root, Vector3(g.x, 3.5, g.z + side))


# ---------------------------------------------------------------- banners

## Copied from beauty_corner.gd `_banner`. Hangs a cloth strip from `top`.
func _banner(parent: Node3D, top: Vector3, facing: float, w: float, h: float, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = LookMeshKit.cloth(w, h, 0.5)
	m.material_override = mats.cloth(color)
	m.position = top
	parent.add_child(m)
	m.rotation.y = -facing + PI * 0.5
	m.set_meta("decor", "banner")
	banners.append(m)
	return m


## Two torn remnant banners on the watchtower: the only cloth in this pass.
func _add_banners(town) -> void:
	var t: Dictionary = town.get_box("watchtower")
	if t.is_empty():
		return
	var root := Node3D.new()
	root.name = "Banners"
	add_child(root)
	var mn := _v3(t.min)
	var mx := _v3(t.max)
	var y := mx.y - 0.5
	var c := (mn + mx) * 0.5
	# Toward the gate (+X): full length.
	_banner(root, Vector3(mx.x + 0.05, y, c.z), 0.0, 2.4, 7.0, LookMaterials.REMNANT_OXBLOOD)
	# Toward main street (-Z): torn short.
	_banner(root, Vector3(c.x, y, mn.z - 0.05), -PI * 0.5, 2.4, 4.0, LookMaterials.REMNANT_OXBLOOD)
