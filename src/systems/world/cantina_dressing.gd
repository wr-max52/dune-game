class_name CantinaDressing
extends Node3D
## Visual dressing for the cantina (M12): a back bar with shelves and bottles, the
## framed card deck, taps on the counter, stools, and warm hanging lamps. Visual
## only: no collision, so the M9 walk routes and validation are untouched. Every
## position is derived from the bar_counter and cantina wall boxes in the town data.

var mats: LookMaterials


func dress(town, materials: LookMaterials) -> void:
	name = "CantinaDressing"
	mats = materials
	var counter: Dictionary = town.get_box("bar_counter")
	var wall_w: Dictionary = town.get_box("cantina_wall_w")
	if counter.is_empty() or wall_w.is_empty():
		return
	var cmin := Vector3(counter.min[0], counter.min[1], counter.min[2])
	var cmax := Vector3(counter.max[0], counter.max[1], counter.max[2])
	var back_x := float(wall_w.max[0]) + 0.05
	var wood := mats.flat(Color("#5a3a24"), 0.7)
	var dark_wood := mats.flat(Color("#3a2618"), 0.75)
	var brass := mats.flat(Color("#b08e50"), 0.35, 0.8)
	var top := mats.flat(Color("#2e2620"), 0.35, 0.2)
	# Counter top slab and a brass foot rail on the customer side.
	_box(Vector3((cmin.x + cmax.x) * 0.5, cmax.y + 0.03, 0.0), Vector3(cmax.x - cmin.x + 0.2, 0.06, cmax.z - cmin.z + 0.2), top)
	_cyl(Vector3(cmax.x + 0.25, 0.2, 0.0), 0.03, cmax.z - cmin.z, brass, Vector3(90, 0, 0))
	# Back bar: three shelves of bottles against the west wall.
	var shelf_z := 6.5
	for i in 3:
		var y := 1.2 + i * 0.55
		_box(Vector3(back_x + 0.2, y, 0.0), Vector3(0.4, 0.05, shelf_z * 2.0), dark_wood)
		var rng := RandomNumberGenerator.new()
		rng.seed = 11 + i
		var z := -shelf_z + 0.25
		while z < shelf_z - 0.2:
			var h := rng.randf_range(0.22, 0.38)
			var col: Color = [Color("#7fb07a"), Color("#c98a3a"), Color("#6a2a24"), Color("#c9b896"), Color("#4a6a8a"), Color("#e0a050")][rng.randi() % 6]
			var glass := StandardMaterial3D.new()
			glass.albedo_color = Color(col.r, col.g, col.b, 0.75)
			glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			glass.roughness = 0.15
			glass.emission_enabled = true
			glass.emission = col
			glass.emission_energy_multiplier = 0.25
			_cyl(Vector3(back_x + 0.2 + rng.randf_range(-0.08, 0.08), y + 0.025 + h * 0.5, z), rng.randf_range(0.035, 0.055), h, glass)
			_cyl(Vector3(back_x + 0.2, y + 0.025 + h + 0.05, z), 0.015, 0.1, glass)
			z += rng.randf_range(0.14, 0.3)
	# Back bar cabinet under the shelves.
	_box(Vector3(back_x + 0.35, 0.5, 0.0), Vector3(0.7, 1.0, shelf_z * 2.0), wood)
	# The framed card deck: her famous cursed deck.
	_box(Vector3(back_x + 0.03, 2.95, 0.0), Vector3(0.04, 0.5, 0.8), brass)
	_box(Vector3(back_x + 0.06, 2.95, 0.0), Vector3(0.02, 0.42, 0.72), mats.flat(Color("#1c1816"), 0.9))
	for k in 4:
		_box(Vector3(back_x + 0.075, 2.95 + (k % 2) * 0.06 - 0.03, -0.24 + k * 0.16), Vector3(0.01, 0.16, 0.11), mats.flat(Color("#e8dcc0"), 0.8))
	# Taps on the counter.
	for z in [-1.5, -1.1, -0.7]:
		_cyl(Vector3(cmin.x + 0.4, cmax.y + 0.2, z), 0.025, 0.34, brass)
		_box(Vector3(cmin.x + 0.4, cmax.y + 0.4, z), Vector3(0.05, 0.1, 0.03), dark_wood)
	# Stools on the customer side (no collision).
	for z in [-3.6, -2.4, -1.2, 1.2, 2.4, 3.6, 4.8, -4.8]:
		var sx := cmax.x + 0.75
		_cyl(Vector3(sx, 0.38, z), 0.03, 0.76, brass)
		_cyl(Vector3(sx, 0.78, z), 0.2, 0.07, mats.flat(Color("#6a2a24"), 0.8))
	# Warm hanging lamps over the counter and the room, on cords from the ceiling.
	var roof: Dictionary = town.get_box("cantina_roof")
	var ceiling := float(roof.min[1]) if not roof.is_empty() else 5.0
	var lamp_glow := mats.glow(Color("#ffb060"))
	lamp_glow.emission_energy_multiplier = 3.0
	var lamps := [Vector3(cmin.x + 0.5, 3.3, -4.0), Vector3(cmin.x + 0.5, 3.3, 0.0), Vector3(cmin.x + 0.5, 3.3, 3.5)]
	for id in ["cantina_table_1", "cantina_table_2", "cantina_table_3"]:
		var t: Dictionary = town.get_box(id)
		if not t.is_empty():
			lamps.append(Vector3((float(t.min[0]) + float(t.max[0])) * 0.5, 3.6, (float(t.min[2]) + float(t.max[2])) * 0.5))
	for p in lamps:
		_cyl(Vector3(p.x, (p.y + ceiling) * 0.5, p.z), 0.008, ceiling - p.y, brass)
		_cyl(p, 0.22, 0.18, mats.flat(Color("#2a2420"), 0.6, 0.5))
		var bulb := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.07
		s.height = 0.14
		bulb.mesh = s
		bulb.material_override = lamp_glow
		bulb.position = p + Vector3(0, -0.1, 0)
		add_child(bulb)
		var l := OmniLight3D.new()
		l.light_color = Color("#ffb070")
		l.light_energy = 2.2
		l.omni_range = 7.0
		l.omni_attenuation = 1.4
		l.shadow_enabled = false
		l.position = p + Vector3(0, -0.25, 0)
		add_child(l)


func _box(pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.material_override = mat
	m.position = pos
	add_child(m)
	return m


func _cyl(pos: Vector3, r: float, h: float, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 10
	m.mesh = c
	m.material_override = mat
	m.position = pos
	m.rotation_degrees = rot
	add_child(m)
	return m
