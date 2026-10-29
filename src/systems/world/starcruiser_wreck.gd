class_name StarcruiserWreck
extends RefCounted
## Issue #93, wreck only. A 600 m transport, bow (-Z) driven into the sand,
## stern (+Z) raised. The shell is plates, NOT one closed collision box: the
## town-facing breach opens onto a continuous deck with a fallen-plate approach.
## All geometry below feeds both WorldGround and WorldScenery's physics/visuals.
## No random placement or imported assets.
##
## Issue #148: the crash site is a place to ride and fight in.
##   - A bent hull plate propped on a brace beside the boarding plate is a speeder
##     kicker: ride up it and off the end.
##   - The hold climbs (34 degrees) to a level interior deck high in the stern. Its
##     floors are level with the horizon, not the hull: "level" coordinates are
##     (x, v, w) in the wreck's own unpitched frame, v up and w toward the stern.
##   - A ramp climbs from the interior deck out through a tear in the dorsal plating
##     to the bridge platform; another drops to the stern end of the upper gallery.
##     Broken railings line the open edges.
##   - Everything is a wreck plate, so it all wears the wreck's metal (WorldScenery).
## The Remnant droids that patrol it, and the cargo droid in the deep hold, are
## data (content/core/droids/droids.json, "wreck"); site_point() turns their
## routes into world points.

const HALF_LENGTH := 300.0
const DECK_Y := -24.0
const ENTRY := Vector3(30, DECK_Y, -35)
const PITCH_DEG := -34.0
const HATCH_SECTION := 16          ## the dorsal plates torn away over the bridge ramp
const INTERIOR_V := 136.0          ## the interior deck's floor (level frame)
const BRIDGE_V := 146.0            ## the bridge platform's floor (level frame)
## The speeder kicker, level frame on the sand: start, end, and how high its lip is.
const KICKER_X := 120.0
const KICKER_W := Vector2(20.0, 55.0)
const KICKER_LIP := 8.0


static func add_to_ground(ground: WorldGround, landmark: Dictionary) -> void:
	var at := WorldGround._v3(landmark.get("at", [1350, 0, -120]))
	var sp := ground.sphere()
	var base := sp.surface_at(at.x, at.z) if sp != null else Vector3(at.x, ground.terrain.height_at(at.x, at.z), at.z)
	var up := ground.up_at(base)
	var tangent := PlanetSphere.tilt_to(up) * Basis(Vector3.UP, deg_to_rad(float(landmark.get("yaw_deg", -175.0))))
	var pitch := float(landmark.get("pitch_deg", PITCH_DEG))
	var xf := Transform3D(tangent * Basis(Vector3.RIGHT, deg_to_rad(pitch)),
		base + up * float(landmark.get("bury_height", 58.0)))
	var level := Transform3D(tangent, xf.origin)
	var prefix := str(landmark.get("id", "starcruiser_wreck")) + "/"
	for p in parts(pitch):
		_register(ground, prefix + str(p.id), p.size, xf * p.xf, str(p.finish), base.y,
			"floor" if bool(p.get("floor", false)) else "solid")
		if bool(p.get("shard", false)):
			ground.boxes[-1]["wreck_shard"] = true

	# A fallen ten-metre-wide plate joins actual sand to the breach's deck.
	# Project the outer end onto the planet rather than assuming a flat desert.
	# Issue #148: it meets the deck's top at the deck's edge, so a speeder rides
	# straight on rather than catching the edge (the old end, ENTRY, was 3 m in).
	var end := xf * Vector3(33.0, DECK_Y, ENTRY.z)
	var start := _on_sand(ground, xf * Vector3(145, DECK_Y, -35))
	start += ground.up_at(start) * 0.08
	var z := (end - start).normalized()
	var x := up.cross(z).normalized()
	var y := z.cross(x).normalized()
	var ramp := Transform3D(Basis(x, y, z), (start + end) * 0.5 - y * 0.6)
	_register(ground, prefix + "fallen_boarding_plate", Vector3(10, 1.2, start.distance_to(end) + 1.0),
		ramp, "hull", base.y, "floor")
	# Familiar, human-scale salvage boxes at the approach make its size legible.
	for i in 3:
		var pos := _on_sand(ground, start + x * (9.0 + i * 3.0))
		var box_up := ground.up_at(pos)
		_register(ground, prefix + "salvage_%d" % i, Vector3(1.6, 1.4, 2.0),
			Transform3D(PlanetSphere.tilt_to(box_up), pos + box_up * 0.7), "scorch", base.y)
	_add_kicker(ground, prefix, level, base.y)
	for b in ground.boxes:
		if str(b.id).begins_with(prefix):
			b["wreck_frame"] = xf
			b["wreck_level"] = level


## Issue #148: a torn hull plate bent up off the sand, its lip held KICKER_LIP
## metres up by a brace. A speeder rides up it toward the stern and leaves the
## lip ballistic (HoverModel launches when the ground drops away).
static func _add_kicker(ground: WorldGround, prefix: String, level: Transform3D, sand_y: float) -> void:
	var start := _on_sand(ground, level * Vector3(KICKER_X, 0, KICKER_W.x))
	var foot := _on_sand(ground, level * Vector3(KICKER_X, 0, KICKER_W.y))
	var up := ground.up_at(foot)
	var lip := foot + up * KICKER_LIP
	start += ground.up_at(start) * 0.08
	var z := (lip - start).normalized()
	var x := up.cross(z).normalized()
	var y := z.cross(x).normalized()
	_register(ground, prefix + "speeder_kicker", Vector3(9, 1.2, start.distance_to(lip)),
		Transform3D(Basis(x, y, z), (start + lip) * 0.5 - y * 0.6), "hull", sand_y, "floor")
	# The brace stands under the lip, its top below the plate, so it never trips
	# a speeder on the way up or a landing one from above.
	var brace_h := KICKER_LIP - 1.4
	var tilt := PlanetSphere.tilt_to(up)
	var fwd := (z - up * z.dot(up)).normalized()
	for side in [-1, 1]:
		var at: Vector3 = foot - fwd * 1.5 + x * (3.2 * float(side))
		_register(ground, prefix + "kicker_brace_%d" % (0 if side < 0 else 1), Vector3(1.4, brace_h, 1.4),
			Transform3D(tilt, at + up * (brace_h * 0.5)), "rib", sand_y)


## The sand under a world point (along the planet's up on the ball).
static func _on_sand(ground: WorldGround, p: Vector3) -> Vector3:
	var sp := ground.sphere()
	if sp != null:
		var map := sp.world_to_map(p)
		return sp.surface_at(map.x, map.y)
	return Vector3(p.x, ground.terrain.height_at(p.x, p.z), p.z)


## The wreck's two frames from its boxes: "hull" (pitched with the ship: parts()
## coordinates) or "level" (unpitched: x, v up, w toward the stern). Identity
## when the wreck is not in this ground.
static func frame(ground: WorldGround, id: String = "starcruiser_wreck", kind: String = "level") -> Transform3D:
	var key := "wreck_level" if kind == "level" else "wreck_frame"
	for b in ground.boxes:
		if b.has(key) and str(b.id).begins_with(id + "/"):
			return b[key]
	return Transform3D.IDENTITY


static func has_wreck(ground: WorldGround, id: String = "starcruiser_wreck") -> bool:
	return ground != null and frame(ground, id) != Transform3D.IDENTITY


## A point given in one of the wreck's frames, in the world.
static func site_point(ground: WorldGround, p: Vector3, kind: String = "level", id: String = "starcruiser_wreck") -> Vector3:
	return frame(ground, id, kind) * p


## Issue #148: what you ride or walk on (decks, plates, ramps) is kind "floor":
## ground for height_above, never an obstacle to WorldGround.hit, like the town's
## floors. A speeder easing up to its hover height on a climb would otherwise catch
## the very plate it rides on.
static func _register(ground: WorldGround, id: String, size: Vector3, xf: Transform3D,
		finish: String, sand_y: float, kind: String = "solid") -> void:
	ground.add_box(id, kind, -size * 0.5, size * 0.5, "", false, xf)
	ground.boxes[-1]["wreck_finish"] = finish
	ground.boxes[-1]["sand_y"] = sand_y


## A faceted, rounded hull, not a wedge. Shell sections taper only at the bow.
## The +X flank loses 180 m of plating, with broken ribs above/below the opening.
## Issue #148: one stern section's dorsal plates (facets 1 and 2) are torn away
## where the bridge ramp comes up through the hull.
static func parts(pitch_deg: float = PITCH_DEG) -> Array:
	var out: Array = []
	for section in 20:
		var z := -285.0 + section * 30.0
		var width := lerpf(28.0, 48.0, clampf((z + 285.0) / 120.0, 0.0, 1.0))
		for facet in 8:
			if z >= -90.0 and z <= 90.0 and facet in [0, 7]:
				continue
			if section == HATCH_SECTION and facet in [1, 2]:
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
	out[-1]["floor"] = true
	# An upper gallery only on the intact flank leaves the breach a tall atrium.
	_box(out, "upper_gallery", Vector3(17, 1.4, 270), Vector3(-22, -4, 100), "rib")
	out[-1]["floor"] = true
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
	# Issue #148: the bridge stands level on struts, over the torn dorsal plates.
	_interior(out, pitch_deg)
	for i in 6:
		if i == 3:
			continue                 # issue #148: the bridge platform stands where it was
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


## Issue #148: the level interior (all positions in the level frame, x, v, w).
## The interior deck meets the climbing hold floor at its stern end, where the
## hold reaches INTERIOR_V: walk up the hold's starboard side (x > 26), step onto
## the deck there and walk back toward the bow along it.
static func _interior(out: Array, pitch_deg: float) -> void:
	var meet := (INTERIOR_V - DECK_Y * cos(deg_to_rad(-pitch_deg))) / sin(deg_to_rad(-pitch_deg))
	var meet_w := _level_w(Vector3(0, DECK_Y, meet), pitch_deg)
	# The interior deck, and the landing where the gallery ramp arrives.
	_slab(out, "interior_deck", Vector2(-12, 26), Vector2(172, meet_w + 0.6), INTERIOR_V, pitch_deg)
	_slab(out, "gallery_landing", Vector2(-26, -11), Vector2(218, 228), INTERIOR_V, pitch_deg)
	# The upper gallery's stern end (it is pitched with the hull) up to the landing.
	var g_end := Vector3(-20, -3.3, 235)
	_ramp(out, "gallery_ramp", Vector3(-20, _level_v(g_end, pitch_deg), _level_w(g_end, pitch_deg)),
		Vector3(-20, INTERIOR_V, 218.5), 10.0, pitch_deg)
	# Up through the torn dorsal plating to the bridge platform.
	_ramp(out, "bridge_ramp", Vector3(0, INTERIOR_V, 180), Vector3(0, BRIDGE_V, 150), 10.0, pitch_deg)
	_slab(out, "bridge_platform", Vector2(-14, 14), Vector2(112, 151), BRIDGE_V, pitch_deg)
	_level(out, "bridge", Vector3(26, 10, 12), Vector3(0, BRIDGE_V + 5.0, 118), "hull", pitch_deg)
	_level(out, "bridge_windows", Vector3(26.4, 2, 9), Vector3(0, BRIDGE_V + 7.0, 118), "scorch", pitch_deg)
	# Struts from the platform's bow corners down onto the hull.
	for sx in [-11.0, 11.0]:
		var top := BRIDGE_V - 1.0
		var foot := _level_v(Vector3(sx, 34.0, 0), pitch_deg, 116.0)
		_level(out, "bridge_strut_%d" % int(sx), Vector3(1.6, top - foot, 1.6),
			Vector3(sx, (top + foot) * 0.5, 116), "rib", pitch_deg)
	# Broken railings: runs of 6 m panels along the open edges, some missing,
	# some sagging. Each entry: id, from (x, w), to (x, w), floor v, gaps (panel
	# indexes knocked out).
	for r in [
		["deck_bow_rail", Vector2(-12, 172), Vector2(26, 172), INTERIOR_V, [2, 5]],
		["deck_starboard_rail", Vector2(26, 172), Vector2(26, 232), INTERIOR_V, [3, 7]],
		["deck_port_rail", Vector2(-12, 186), Vector2(-12, 216), INTERIOR_V, [1]],
		["landing_rail", Vector2(-26, 228), Vector2(-12, 228), INTERIOR_V, []],
		["bridge_port_rail", Vector2(-14, 124), Vector2(-14, 151), BRIDGE_V, [2]],
		["bridge_starboard_rail", Vector2(14, 124), Vector2(14, 151), BRIDGE_V, [1, 3]],
		["bridge_stern_rail_a", Vector2(-14, 151), Vector2(-6, 151), BRIDGE_V, []],
		["bridge_stern_rail_b", Vector2(6, 151), Vector2(14, 151), BRIDGE_V, [0]],
	]:
		_railing(out, str(r[0]), r[1], r[2], float(r[3]), r[4], pitch_deg)


## The level frame's height and stern-ward distance of a hull-frame point
## (`w_override` keeps w and asks for the level v of hull-frame height y at x).
static func _level_v(hull: Vector3, pitch_deg: float, w_override: float = NAN) -> float:
	var a := deg_to_rad(-pitch_deg)
	if not is_nan(w_override):
		return (hull.y + w_override * sin(a)) / cos(a)
	return hull.y * cos(a) + hull.z * sin(a)


static func _level_w(hull: Vector3, pitch_deg: float) -> float:
	var a := deg_to_rad(-pitch_deg)
	return -hull.y * sin(a) + hull.z * cos(a)


## A box placed in the level frame (center (x, v, w), its own `basis` in that
## frame), stored in the hull frame like every other part.
static func _level(out: Array, id: String, size: Vector3, center: Vector3, finish: String,
		pitch_deg: float, basis: Basis = Basis.IDENTITY) -> void:
	var to_hull := Basis(Vector3.RIGHT, deg_to_rad(-pitch_deg))
	_box(out, id, size, to_hull * center, finish, to_hull * basis)


## A level floor one metre thick with its top at v.
static func _slab(out: Array, id: String, xs: Vector2, ws: Vector2, v: float, pitch_deg: float) -> void:
	_level(out, id, Vector3(xs.y - xs.x, 1.0, ws.y - ws.x),
		Vector3((xs.x + xs.y) * 0.5, v - 0.5, (ws.x + ws.y) * 0.5), "rib", pitch_deg)
	out[-1]["floor"] = true


## A straight ramp whose top runs from a to b (level frame, same x), `width` wide.
static func _ramp(out: Array, id: String, a: Vector3, b: Vector3, width: float, pitch_deg: float) -> void:
	if b.z < a.z:
		var t := a
		a = b
		b = t
	var run := b - a
	var basis := Basis(Vector3.RIGHT, -atan2(run.y, run.z))
	_level(out, id, Vector3(width, 1.0, run.length() + 0.6),
		(a + b) * 0.5 - basis.y * 0.5, "rib", pitch_deg, basis)
	out[-1]["floor"] = true


## A railing along a floor edge: a top rail and a post per 6 m panel, 1.1 m high.
## Knocked-out panels leave a gap; every third standing one sags outward.
static func _railing(out: Array, id: String, from: Vector2, to: Vector2, v: float,
		gaps: Array, pitch_deg: float) -> void:
	var span := to - from
	var panels := maxi(1, int(round(span.length() / 6.0)))
	var along := Vector3(span.x, 0, span.y).normalized()
	var yaw := atan2(along.x, along.z)
	for i in panels:
		if i in gaps:
			continue
		var a := from + span * (float(i) / panels)
		var b := from + span * (float(i + 1) / panels)
		var mid := (a + b) * 0.5
		var sag := Basis(along, deg_to_rad(18.0)) if i % 3 == 2 else Basis.IDENTITY
		var length := (b - a).length()
		_level(out, "%s_%d" % [id, i], Vector3(0.16, 0.12, length), Vector3(mid.x, v + 1.05, mid.y),
			"marking", pitch_deg, sag * Basis(Vector3.UP, yaw))
		_level(out, "%s_post_%d" % [id, i], Vector3(0.16, 1.1, 0.16), Vector3(a.x, v + 0.55, a.y),
			"rib", pitch_deg)


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
