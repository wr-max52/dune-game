class_name StarcruiserWreck
extends RefCounted
## Issue #93, wreck only. A 600 m transport, bow (-Z) driven into the sand,
## stern (+Z) raised. The shell is plates, NOT one closed collision box: the
## town-facing breach opens onto a continuous deck with a fallen-plate approach.
## All geometry below feeds both WorldGround and WorldScenery's physics/visuals.
## No random placement, imported assets, NPCs or mission logic.

const HALF_LENGTH := 300.0
const DECK_Y := -24.0
const ENTRY := Vector3(30, DECK_Y, -35)


static func add_to_ground(ground: WorldGround, landmark: Dictionary) -> void:
	var at := WorldGround._v3(landmark.get("at", [1350, 0, -120]))
	var sp := ground.sphere()
	var base := sp.surface_at(at.x, at.z) if sp != null else Vector3(at.x, ground.terrain.height_at(at.x, at.z), at.z)
	var up := ground.up_at(base)
	var tangent := PlanetSphere.tilt_to(up) * Basis(Vector3.UP, deg_to_rad(float(landmark.get("yaw_deg", -175.0))))
	var xf := Transform3D(tangent * Basis(Vector3.RIGHT, deg_to_rad(float(landmark.get("pitch_deg", -34.0)))),
		base + up * float(landmark.get("bury_height", 58.0)))
	var prefix := str(landmark.get("id", "starcruiser_wreck")) + "/"
	for p in parts():
		_register(ground, prefix + str(p.id), p.size, xf * p.xf, str(p.finish), base.y)
		if bool(p.get("shard", false)):
			ground.boxes[-1]["wreck_shard"] = true

	# A fallen ten-metre-wide plate joins actual sand to the breach's deck.
	# Project the outer end onto the planet rather than assuming a flat desert.
	var end := xf * ENTRY
	var start := xf * Vector3(145, DECK_Y, -35)
	if sp != null:
		var map := sp.world_to_map(start)
		start = sp.surface_at(map.x, map.y)
	else:
		start.y = ground.terrain.height_at(start.x, start.z)
	start += ground.up_at(start) * 0.08
	var z := (end - start).normalized()
	var x := up.cross(z).normalized()
	var y := z.cross(x).normalized()
	var ramp := Transform3D(Basis(x, y, z), (start + end) * 0.5 - y * 0.6)
	_register(ground, prefix + "fallen_boarding_plate", Vector3(10, 1.2, start.distance_to(end) + 1.0),
		ramp, "hull", base.y)
	# Familiar, human-scale salvage boxes at the approach make its size legible.
	for i in 3:
		var pos := start + x * (9.0 + i * 3.0)
		if sp != null:
			var map := sp.world_to_map(pos)
			pos = sp.surface_at(map.x, map.y)
		else:
			pos.y = ground.terrain.height_at(pos.x, pos.z)
		var box_up := ground.up_at(pos)
		_register(ground, prefix + "salvage_%d" % i, Vector3(1.6, 1.4, 2.0),
			Transform3D(PlanetSphere.tilt_to(box_up), pos + box_up * 0.7), "scorch", base.y)
	for b in ground.boxes:
		if str(b.id).begins_with(prefix):
			b["wreck_frame"] = xf


static func _register(ground: WorldGround, id: String, size: Vector3, xf: Transform3D,
		finish: String, sand_y: float) -> void:
	ground.add_box(id, "solid", -size * 0.5, size * 0.5, "", false, xf)
	ground.boxes[-1]["wreck_finish"] = finish
	ground.boxes[-1]["sand_y"] = sand_y


## A faceted, rounded hull, not a wedge. Shell sections taper only at the bow.
## The +X flank loses 180 m of plating, with broken ribs above/below the opening.
static func parts() -> Array:
	var out: Array = []
	for section in 20:
		var z := -285.0 + section * 30.0
		var width := lerpf(28.0, 48.0, clampf((z + 285.0) / 120.0, 0.0, 1.0))
		for facet in 8:
			if z >= -90.0 and z <= 90.0 and facet in [0, 7]:
				continue
			_facet(out, "plate_%d_%d" % [section, facet], width, 38.0,
				facet, z, 29.8, 2.0, "hull")
		# Regular, heavier frames give the exposed hull its whale-rib silhouette.
		for facet in 8:
			if z >= -90.0 and z <= 90.0 and facet in [0, 7]:
				continue
			_facet(out, "rib_%d_%d" % [section, facet], width + 1.4, 39.4,
				facet, z - 13.0, 2.4, 3.6, "rib")

	# The entire lower deck is traversable; no invisible box across the breach.
	_box(out, "lower_deck", Vector3(66, 2, 570), Vector3(0, DECK_Y - 1.0, 0), "rib")
	# An upper gallery only on the intact flank leaves the breach a tall atrium.
	_box(out, "upper_gallery", Vector3(17, 1.4, 270), Vector3(-22, -4, 100), "rib")
	for z in [-100.0, -40.0, 20.0, 80.0, 140.0, 200.0, 260.0]:
		_box(out, "stanchion_%d" % int(z), Vector3(1.4, 47, 1.4), Vector3(-29, 0, z), "rib")
		# 2.2 m high, 1.1 m wide door frames (open, not painted doors).
		for x in [-1.1, 1.1]:
			_box(out, "door_%d_%s" % [int(z), str(x)], Vector3(0.18, 2.2, 0.22),
				Vector3(-18 + x, DECK_Y + 1.1, z), "marking")
		_box(out, "lintel_%d" % int(z), Vector3(2.4, 0.18, 0.22),
			Vector3(-18, DECK_Y + 2.3, z), "marking")

	# Peeled, pointed fragments make an irregular fracture rather than a cut-out.
	# All lips stay above head height, below the deck or at the ends of the tear:
	# the original boarding plate and walkable route remain completely unchanged.
	for i in 9:
		var roll := deg_to_rad(-28.0 + float((i * 37) % 81))
		_shard(out, "torn_upper_%d" % i, Vector3(12 + i % 3 * 4, 1.2, 17 + i % 4 * 3),
			Vector3(40 + i % 3 * 2, 27 + i % 2 * 3, -92 + i * 23), "rib",
			Basis(Vector3.BACK, roll) * Basis(Vector3.UP, deg_to_rad(-21.0 + i * 5.0)))
	for i in 7:
		_shard(out, "torn_lower_%d" % i, Vector3(8 + i % 3 * 3, 1.0, 15 + i % 2 * 8),
			Vector3(39 + i % 2 * 4, -31, -85 + i * 28), "scorch",
			Basis(Vector3.BACK, deg_to_rad(-18.0 - i * 4.0)))
	for end in [-1, 1]:
		for i in 3:
			_shard(out, "torn_end_%d_%d" % [end, i], Vector3(14, 1.3, 19 + i * 4),
				Vector3(44, -10 + i * 14, end * (99 - i * 3)), "rib",
				Basis(Vector3.BACK, deg_to_rad(72.0 + i * 19)) * Basis(Vector3.UP, end * 0.38))
	# A raised stern bridge and radiator comb make the distant profile distinct.
	_box(out, "bridge", Vector3(38, 12, 70), Vector3(-4, 42, 216), "hull")
	_box(out, "bridge_windows", Vector3(38.4, 2, 53), Vector3(-4, 44, 216), "scorch")
	for i in 6:
		var h := 18.0 + sin(float(i) / 5.0 * PI) * 12.0
		_box(out, "radiator_%d" % i, Vector3(3, h, 11),
			Vector3(0, 39.0 + h * 0.5, 104 + i * 29), "rib")
	# Oxblood identification bands, kept to a few large, quiet accents.
	for z in [-150.0, 135.0, 255.0]:
		_box(out, "hull_band_%d" % int(z), Vector3(2.4, 17, 7),
			Vector3(-47, 0, z), "marking")
	# Keep the same four engine positions and overall stern; detail only the bells.
	# Layered housings, flared lips, recessed black throats and mechanical braces.
	# There is deliberately no glow, exhaust, flame, light or powered animation.
	_box(out, "buried_bow", Vector3(38, 50, 3), Vector3(0, 0, -299), "scorch")
	_box(out, "stern_bulkhead", Vector3(68, 52, 3), Vector3(0, 0, 299), "hull")
	for engine in 4:
		var center := Vector3(-22 if engine % 2 == 0 else 22, -16 if engine < 2 else 16, 315)
		var prefix := "engine_%d_" % engine
		_engine_ring(out, prefix + "root", center + Vector3(0, 0, -10), 12.8, 1.8, 10, "hull")
		_engine_ring(out, prefix + "gasket", center + Vector3(0, 0, -3), 13, 1.6, 1.2, "nozzle")
		_engine_ring(out, prefix + "housing", center + Vector3(0, 0, 1), 13.6, 1.7, 8, "hull")
		_engine_ring(out, prefix + "flared_collar", center + Vector3(0, 0, 9), 14.7, 2.0, 7, "rib")
		_engine_ring(out, prefix + "rim", center + Vector3(0, 0, 14), 15.2, 2.0, 2.4, "rib")
		_engine_ring(out, prefix + "inner_lip", center + Vector3(0, 0, 11), 11.6, 0.9, 3, "nozzle")
		_engine_ring(out, prefix + "throat", center + Vector3(0, 0, -1), 9.1, 1.6, 20, "nozzle")
		_box(out, prefix + "dark_back", Vector3(17, 17, 1), center + Vector3(0, 0, -12), "nozzle")
		for i in 12:
			var a := TAU * i / 12.0
			var radial := Vector3(cos(a), sin(a), 0)
			var rot := Basis(Vector3.BACK, a)
			_box(out, prefix + "brace_%d" % i, Vector3(1.1, 1.4, 19),
				center + radial * 14.0 + Vector3(0, 0, 2), "rib", rot)
			_box(out, prefix + "vent_%d" % i, Vector3(0.7, 2.8, 4.8),
				center + radial * 12.5 + Vector3(0, 0, -6), "nozzle", rot)
			_box(out, prefix + "vane_%d" % i, Vector3(4.3, 0.6, 0.9),
				center + radial * 5.3 + Vector3(0, 0, -10), "rib", Basis(Vector3.BACK, a + 0.3))
	return out


static func _facet(out: Array, id: String, rx: float, ry: float, facet: int,
		z: float, length: float, thickness: float, finish: String) -> void:
	var a := TAU * facet / 8.0
	var b := TAU * (facet + 1) / 8.0
	var p := Vector3(cos(a) * rx, sin(a) * ry, z)
	var q := Vector3(cos(b) * rx, sin(b) * ry, z)
	var edge := q - p
	_box(out, id, Vector3(edge.length() + 0.5, thickness, length), (p + q) * 0.5,
		finish, Basis(Vector3.BACK, atan2(edge.y, edge.x)))


static func _box(out: Array, id: String, size: Vector3, center: Vector3,
		finish: String, basis: Basis = Basis.IDENTITY) -> void:
	out.append({ "id": id, "size": size, "xf": Transform3D(basis, center), "finish": finish })


static func _engine_ring(out: Array, id: String, center: Vector3, radius: float,
		thickness: float, length: float, finish: String) -> void:
	for i in 16:
		var a := TAU * i / 16.0
		var b := TAU * (i + 1) / 16.0
		var p := Vector3(cos(a), sin(a), 0) * radius
		var q := Vector3(cos(b), sin(b), 0) * radius
		var edge := q - p
		_box(out, id + "_%d" % i, Vector3(edge.length() + 0.12, thickness, length),
			center + (p + q) * 0.5, finish, Basis(Vector3.BACK, atan2(edge.y, edge.x)))


static func _shard(out: Array, id: String, size: Vector3, center: Vector3,
		finish: String, basis: Basis) -> void:
	_box(out, id, size, center, finish, basis)
	out[-1]["shard"] = true


## A chisel-pointed plate, shared by the visible mesh and its convex foot collider.
## WorldGround retains its small conservative oriented bounds for flight hits.
static func shard_vertices(size: Vector3) -> PackedVector3Array:
	var h := size * 0.5
	var points := PackedVector3Array()
	for y in [-h.y, h.y]:
		for p in [Vector3(-h.x, y, -h.z), Vector3(h.x, y, -h.z),
				Vector3(h.x, y, -0.1 * h.z), Vector3(-0.3 * h.x, y, h.z)]:
			points.append(p)
	return points


static func shard_mesh(size: Vector3) -> ArrayMesh:
	var points := shard_vertices(size)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face in [[0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4],
			[1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]:
		for i in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(points[face[i]])
	st.generate_normals()
	return st.commit()
