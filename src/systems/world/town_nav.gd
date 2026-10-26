class_name TownNav
extends Node3D
## The town's walkable surface for NPCs. The navmesh is baked at load time from
## the same box data the collision comes from (content/core/locations/*.json), so
## moving a wall in the data moves it for the guards too, with no editor bake and
## no baked file to keep in sync.
##
## The bake takes about a quarter second for port_town, too long for one frame,
## so the live game bakes on a worker thread and NPCs stand still until
## `is_ready`. Traces and tests can bake synchronously.
##
## Scope: the town and its desert apron only. The dunes outside are not in it,
## so nothing paths out into the desert yet.

const TownLayout := preload("res://src/systems/world/town_layout.gd")

## Bake settings. Agent sizes are whole multiples of the cells so nothing gets
## rounded (Godot warns when they do). Radius 0.5 is the 0.4 capsule plus margin.
## Climb is what the body can really do, not what looks fine: the player's capsule
## (radius 0.4, 45 degree floor angle) rolls over about 0.12 m and treats anything
## taller as a wall. At 0.4 the mesh let guards step onto the side of the pit
## ramp near its foot, where they pinned themselves for good.
const DEFAULTS := {
	"cell_size": 0.25,
	"cell_height": 0.1,
	"agent_radius": 0.5,
	"agent_height": 1.8,
	"agent_max_climb": 0.1,
	"agent_max_slope": 40.0,
	"bounds_margin": 1.0,
}

signal baked

var region: NavigationRegion3D
var navmesh: NavigationMesh
var is_ready := false
var bake_ms := 0.0
var settings: Dictionary = DEFAULTS.duplicate()
var _bake_start := 0


## Triangles for every box in the town, ramps tilted the way the scene builds them.
## Built as plain faces (not meshes) so the bake never reads geometry back from
## the GPU, which Godot warns is slow at runtime.
##
## Recast only sees surfaces, so the floor inside a closed box (a building, a
## crate) would bake as a walkable island, and a "nearest point" query could hand
## a guard a spot inside a wall. Every blocking box is also an obstruction, which
## clears its footprint, except a box something stands on (the watchtower top).
static func source_geometry(town) -> NavigationMeshSourceGeometryData3D:
	var src := NavigationMeshSourceGeometryData3D.new()
	src.add_faces(box_faces(town), Transform3D.IDENTITY)
	for b in obstruction_boxes(town):
		var mn := Vector3(float(b.min[0]), float(b.min[1]), float(b.min[2]))
		var mx := Vector3(float(b.max[0]), float(b.max[1]), float(b.max[2]))
		var outline := PackedVector3Array([Vector3(mn.x, 0, mn.z), Vector3(mx.x, 0, mn.z), Vector3(mx.x, 0, mx.z), Vector3(mn.x, 0, mx.z)])
		src.add_projected_obstruction(outline, mn.y, mx.y - mn.y + 0.5, false)
	return src


## Blocking boxes (the town's blocking_kinds) that no marker stands on. Ramps are
## never obstructions.
static func obstruction_boxes(town) -> Array:
	var blocking: Array = town.data.get("blocking_kinds", ["wall", "solid", "cover", "counter", "ship"])
	var out: Array = []
	for b in town.boxes():
		if not (str(b.kind) in blocking):
			continue
		var stood_on := false
		for m in town.markers():
			var p: Array = m.pos
			if absf(float(b.max[1]) - float(p[1])) < 0.05 and float(p[0]) >= float(b.min[0]) and float(p[0]) <= float(b.max[0]) \
					and float(p[2]) >= float(b.min[2]) and float(p[2]) <= float(b.max[2]):
				stood_on = true
		if not stood_on:
			out.append(b)
	return out


## Every box as 12 triangles (36 vertices), in world space.
static func box_faces(town) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for b in town.boxes():
		var xf: Transform3D
		var half: Vector3
		if str(b.kind) == "ramp":
			var rt: Dictionary = TownLayout.ramp_transform(b)
			xf = Transform3D(rt.basis, rt.center)
			half = (rt.size as Vector3) * 0.5
		else:
			var mn := Vector3(float(b.min[0]), float(b.min[1]), float(b.min[2]))
			var mx := Vector3(float(b.max[0]), float(b.max[1]), float(b.max[2]))
			xf = Transform3D(Basis.IDENTITY, (mn + mx) * 0.5)
			half = (mx - mn) * 0.5
		var c := []
		for i in 8:
			c.append(xf * Vector3(half.x * (1 if i & 1 else -1), half.y * (1 if i & 2 else -1), half.z * (1 if i & 4 else -1)))
		# Quads as corner indices; each becomes two triangles.
		for q in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
			faces.append_array(PackedVector3Array([c[q[0]], c[q[1]], c[q[2]], c[q[0]], c[q[2]], c[q[3]]]))
	return faces


## The town's footprint (all boxes) plus a margin, as the bake limit.
static func town_bounds(town, margin: float = 1.0) -> AABB:
	var box := AABB()
	var first := true
	for b in town.boxes():
		var mn := Vector3(float(b.min[0]), float(b.min[1]), float(b.min[2]))
		var mx := Vector3(float(b.max[0]), float(b.max[1]), float(b.max[2]))
		var a := AABB(mn, mx - mn)
		box = a if first else box.merge(a)
		first = false
	return box.grow(margin)


func make_navmesh(town) -> NavigationMesh:
	var nm := NavigationMesh.new()
	nm.cell_size = float(settings.cell_size)
	nm.cell_height = float(settings.cell_height)
	nm.agent_radius = float(settings.agent_radius)
	nm.agent_height = float(settings.agent_height)
	nm.agent_max_climb = float(settings.agent_max_climb)
	nm.agent_max_slope = float(settings.agent_max_slope)
	nm.filter_baking_aabb = town_bounds(town, float(settings.bounds_margin))
	return nm


## Build the region and bake. `async` = on a worker thread (the live game).
## The town may override any bake setting with a "nav" block in its data.
func build(town, async: bool = true) -> void:
	var over: Dictionary = town.data.get("nav", {}) if town.data is Dictionary else {}
	for k in over:
		settings[k] = over[k]
	is_ready = false
	navmesh = make_navmesh(town)
	var map := get_world_3d().navigation_map
	# The map's cells must match the mesh's, or the server warns and rounds.
	NavigationServer3D.map_set_cell_size(map, float(settings.cell_size))
	NavigationServer3D.map_set_cell_height(map, float(settings.cell_height))
	var src := source_geometry(town)
	_bake_start = Time.get_ticks_usec()
	if async:
		NavigationServer3D.bake_from_source_geometry_data_async(navmesh, src, _on_baked)
	else:
		NavigationServer3D.bake_from_source_geometry_data(navmesh, src)
		_on_baked()


func _on_baked() -> void:
	# The async callback can arrive off the main thread; hand the result back.
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		call_deferred("_on_baked")
		return
	bake_ms = (Time.get_ticks_usec() - _bake_start) / 1000.0
	# The region joins the map only now, already holding the finished mesh. A
	# region added empty and filled later (after an async bake) was never picked
	# up by the map on Godot 4.7.
	region = NavigationRegion3D.new()
	region.name = "NavRegion"
	region.navigation_mesh = navmesh
	add_child(region)
	_wait_for_map()


## The server folds a new mesh into the map on its next sync, so a path query
## straight after assigning it comes back empty. The map also ticks once for the
## empty region, so "the iteration changed" is not enough: wait until the map
## says a point of our mesh belongs to our region.
func _wait_for_map() -> void:
	var map := get_world_3d().navigation_map
	var probe: Vector3 = navmesh.vertices[0] if navmesh.vertices.size() > 0 else Vector3.ZERO
	var frames := 0
	while NavigationServer3D.map_get_iteration_id(map) == 0 or NavigationServer3D.map_get_closest_point_owner(map, probe) != region.get_rid():
		frames += 1
		if frames > 600:
			push_warning("TownNav: the navigation map never picked up the town mesh")
			return
		await get_tree().physics_frame
	is_ready = true
	baked.emit()


func polygon_count() -> int:
	return navmesh.get_polygon_count() if navmesh != null else 0


## A walkable path from `from` to `to`, simplified to its corners. Both ends are
## snapped to the mesh. Empty until the bake is in.
func path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if navmesh == null or region == null or not region.is_inside_tree():
		return PackedVector3Array()
	return NavigationServer3D.map_get_path(get_world_3d().navigation_map, from, to, true)


## The nearest point on the mesh (Vector3.INF before the bake is in).
func closest(p: Vector3) -> Vector3:
	if not is_ready:
		return Vector3.INF
	return NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, p)
