class_name DesertTerrain
extends Node3D
## One terrain mesh for the whole view: dense near the port, stretched to about 6 km
## at the edges (fog hides the coarse far triangles). Also builds a heightmap
## collider for the walkable area so the scene can be played, not only shot.
##
## Two ways to seat a port on it:
##   - plinth (default, the beauty corner): the port stands on a rock drum above a
##     sunken basin. Unchanged since the look-dev pass.
##   - site (the playable town, `configure_site`): the town's floor level carries on
##     outside the walls as flat packed sand, then blends into the open dunes. The
##     ground dips under any sunken floor (the landing pit) and sits just under the
##     paving inside the walls, so no terrain ever pokes through the town.
## `follow(node)` keeps the collider centred on the player, rebuilt over several
## frames, so the desert is walkable in every direction without a hitch.

const SAND_SHADER := preload("res://src/systems/look/shaders/sand.gdshader")

@export var resolution := 400        ## vertices per side; tests use a small value
@export var extent := 6000.0         ## half-size in metres
@export var near_spacing := 1.5      ## metres between vertices at the centre
@export var port_radius := 150.0
@export var port_height := 7.8
@export var collider_size := 1024.0
@export var basin_depth := 58.0

## Site mode (see configure_site). Empty site_rect = plinth mode.
var site_rect := Rect2()             ## xz: everything at town floor level (town + aprons)
var under_rect := Rect2()            ## xz: inside the walls, where paving covers the ground
var sinks: Array = []                ## [{ rect: Rect2, y: float }] sunken floors to dip under
var pad_y := 0.0                     ## the town's floor level, carried out onto the sand
var under_y := -0.12                 ## ground level hidden under the paving
var pad_margin := 30.0               ## flat sand around the town before the dunes start
var blend := 260.0                   ## metres over which the flat sand becomes open dunes
var dune_offset := 12.0              ## lowers the open dunes so the town sits among them
var sink_grow := 2.0                 ## visual: how far past a sunken floor the dip reaches
var sink_ramp := 3.0                 ## metres from the dip back up to the surrounding ground
const UNDER_INSET := 1.5             ## ramp from under_y up to pad_y inside the wall line

## Collider. Plinth mode: one static 1024 m square at the origin (as before).
## Following: re-centred on `_target` whenever it strays `recenter_distance` from the
## centre; the new heightmap is filled a few rows per frame (at most
## `rebuild_budget_ms` of work, at least one row) and swapped in whole, so the frame
## budget holds. A full rebuild takes about 2.5 s, in which a sprint (7 m/s) covers
## 18 m of the 160 m still under the old collider.
@export var collider_cells := 256
@export var recenter_distance := 96.0
@export var rebuild_budget_ms := 2.0
var collider_center := Vector3.ZERO
var collider_body: StaticBody3D
var collider_shape: CollisionShape3D
var recenters := 0                   ## completed re-centres (read by tests and the trace)
var snaps := 0                       ## synchronous rebuilds after a teleport
var worst_step_ms := 0.0             ## most rebuild work done in one frame
var worst_swap_ms := 0.0             ## of which: handing the new shape to physics
var _target: Node3D
var _pending := false
var _pending_center := Vector3.ZERO
var _pending_row := 0
var _pending_data := PackedFloat32Array()

var material: ShaderMaterial
var _dune := FastNoiseLite.new()
var _warp := FastNoiseLite.new()
var _swell := FastNoiseLite.new()
var _small := FastNoiseLite.new()


func _init() -> void:
	name = "DesertTerrain"
	_dune.seed = 3
	_dune.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_dune.fractal_type = FastNoiseLite.FRACTAL_NONE
	_dune.frequency = 1.0
	_warp.seed = 9
	_warp.frequency = 1.0
	_swell.seed = 21
	_swell.frequency = 1.0
	_swell.fractal_octaves = 3
	_small.seed = 5
	_small.frequency = 1.0
	_small.fractal_octaves = 2


## Height in metres at a world (x, z). Pure function, so gameplay can ask it too.
func height_at(x: float, z: float) -> float:
	if site_rect.has_area():
		return _site_height(x, z, sink_grow)
	return _plinth_height(x, z)


## The ground the player stands on (the collider). Same as height_at except the
## dip under a sunken floor reaches one collider cell further, so the coarser
## collider never props up an invisible slope inside the pit.
func ground_at(x: float, z: float) -> float:
	if site_rect.has_area():
		return _site_height(x, z, sink_grow + _cell_step() + 1.0)
	return _plinth_height(x, z)


## The open dunes, before any port is seated on them. Long crested dunes: ridged
## noise, stretched across the wind, on a slow swell.
func _dunes(x: float, z: float) -> float:
	var wx := x + _warp.get_noise_2d(x * 0.0016, z * 0.0016) * 140.0
	var wz := z + _warp.get_noise_2d(z * 0.0016 + 40.0, x * 0.0016) * 140.0
	var ridge := 1.0 - absf(_dune.get_noise_2d(wx * 0.0021, wz * 0.0042))
	var dunes := pow(ridge, 2.6) * 26.0
	dunes += _swell.get_noise_2d(x * 0.0006, z * 0.0006) * 24.0 + 10.0
	dunes += _small.get_noise_2d(x * 0.012, z * 0.012) * 1.6
	return dunes


## Seat a town on the dunes. `floor_rect` = every box at floor level (town and
## aprons), `walls_rect` = the paved area inside the walls, `sunken` = floors below
## the town floor as [{ rect, y }] (their lowest point; the dip goes 1.5 m lower).
func configure_site(floor_rect: Rect2, walls_rect: Rect2, sunken: Array, floor_y: float = 0.0) -> void:
	site_rect = floor_rect
	under_rect = walls_rect
	pad_y = floor_y
	under_y = floor_y - 0.12
	sinks.clear()
	for s in sunken:
		sinks.append({ "rect": s.rect, "y": float(s.y) - 1.5 })


func _site_height(x: float, z: float, grow: float) -> float:
	var p := Vector2(x, z)
	var h: float
	var d := _rect_dist(site_rect, p)
	if d <= 0.0 and under_rect.has_point(p):
		# Inside the walls: just under the paving, rising to the floor at the wall line.
		var inset := minf(minf(x - under_rect.position.x, under_rect.end.x - x),
			minf(z - under_rect.position.y, under_rect.end.y - z))
		h = lerpf(pad_y, under_y, clampf(inset / UNDER_INSET, 0.0, 1.0))
	else:
		# Flat packed sand at the town's floor, a faint swell, then the open dunes.
		var k := smoothstep(pad_margin, pad_margin + blend, d)
		var near := pad_y + _small.get_noise_2d(x * 0.012, z * 0.012) * 0.5 * smoothstep(4.0, pad_margin, d)
		h = lerpf(near, _dunes(x, z) - dune_offset, k)
	for s in sinks:
		var r: Rect2 = s.rect.grow(grow)
		var sd := _rect_dist(r, p)
		if sd < sink_ramp:
			h = minf(h, lerpf(float(s.y), h, smoothstep(0.0, sink_ramp, sd)))
	return h


## Distance from p to the rectangle (0 inside).
static func _rect_dist(r: Rect2, p: Vector2) -> float:
	var dx := maxf(maxf(r.position.x - p.x, p.x - r.end.x), 0.0)
	var dz := maxf(maxf(r.position.y - p.y, p.y - r.end.y), 0.0)
	return Vector2(dx, dz).length()


func _plinth_height(x: float, z: float) -> float:
	var dunes := _dunes(x, z)
	var r := Vector2(x, z).length()
	if r < port_radius - 2.0:
		return port_height
	# The port sits on a rock plinth above a sunken basin. Near the plinth the sand
	# is banked against the cliff; further out it falls away into the open dunes.
	var k := smoothstep(port_radius + 20.0, port_radius + 330.0, r)
	return lerpf(-25.0 + _small.get_noise_2d(x * 0.03, z * 0.03) * 2.0, dunes - basin_depth, k)


func _coord(u: float) -> float:
	# Maps -1..1 to metres: linear in the middle, steep toward the edges.
	var a := near_spacing * resolution * 0.5
	var b := extent - a
	return signf(u) * (a * absf(u) + b * pow(absf(u), 4.0))


## with_mesh = false builds only the collider (headless traces never draw).
func build(with_mesh: bool = true) -> void:
	material = ShaderMaterial.new()
	material.shader = SAND_SHADER
	material.set_shader_parameter("noise_tex", LookEnvironment.make_noise_texture(512, 3, 0.01))

	if not with_mesh:
		_build_collider()
		return
	var n := resolution
	var xs := PackedFloat32Array()
	xs.resize(n)
	for i in n:
		xs[i] = _coord(-1.0 + 2.0 * float(i) / (n - 1))
	var h := PackedFloat32Array()
	h.resize(n * n)
	for j in n:
		for i in n:
			h[j * n + i] = height_at(xs[i], xs[j])

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	verts.resize(n * n)
	norms.resize(n * n)
	for j in n:
		for i in n:
			var i0 := maxi(i - 1, 0)
			var i1 := mini(i + 1, n - 1)
			var j0 := maxi(j - 1, 0)
			var j1 := mini(j + 1, n - 1)
			var dhdx := (h[j * n + i1] - h[j * n + i0]) / (xs[i1] - xs[i0])
			var dhdz := (h[j1 * n + i] - h[j0 * n + i]) / (xs[j1] - xs[j0])
			verts[j * n + i] = Vector3(xs[i], h[j * n + i], xs[j])
			norms[j * n + i] = Vector3(-dhdx, 1.0, -dhdz).normalized()
	var idx := PackedInt32Array()
	idx.resize((n - 1) * (n - 1) * 6)
	var w := 0
	for j in n - 1:
		for i in n - 1:
			var v00 := j * n + i
			var v10 := v00 + 1
			var v01 := v00 + n
			var v11 := v01 + 1
			# Clockwise from above = front face in Godot.
			idx[w] = v00; idx[w + 1] = v10; idx[w + 2] = v01
			idx[w + 3] = v10; idx[w + 4] = v11; idx[w + 5] = v01
			w += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.custom_aabb = AABB(Vector3(-extent, -50, -extent), Vector3(extent * 2, 300, extent * 2))
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	mi.material_override = material
	add_child(mi)
	_build_collider()


func _cell_step() -> float:
	return collider_size / collider_cells


func _build_collider() -> void:
	var cells := collider_cells
	var data := PackedFloat32Array()
	data.resize((cells + 1) * (cells + 1))
	for j in cells + 1:
		_fill_row(data, collider_center, j)
	collider_body = StaticBody3D.new()
	collider_body.name = "Collider"
	collider_shape = CollisionShape3D.new()
	# HeightMapShape3D cells are 1 unit; scale the node to the real spacing.
	var step := _cell_step()
	collider_shape.scale = Vector3(step, step, step)
	collider_shape.shape = _shape_from(data)
	collider_body.position = collider_center
	collider_body.add_child(collider_shape)
	add_child(collider_body)


func _fill_row(data: PackedFloat32Array, center: Vector3, j: int) -> void:
	var cells := collider_cells
	var step := _cell_step()
	var x0 := center.x - collider_size * 0.5
	var z := center.z - collider_size * 0.5 + j * step
	for i in cells + 1:
		data[j * (cells + 1) + i] = ground_at(x0 + i * step, z) / step


func _shape_from(data: PackedFloat32Array) -> HeightMapShape3D:
	var shape := HeightMapShape3D.new()
	shape.map_width = collider_cells + 1
	shape.map_depth = collider_cells + 1
	shape.map_data = data
	return shape


## Keep the collider under `node` from now on. Call after build().
func follow(node: Node3D) -> void:
	_target = node
	set_physics_process(node != null)


## Where the collider would be centred for a world position: snapped to whole
## cells, so heights line up between rebuilds.
func snapped_center(pos: Vector3) -> Vector3:
	var step := _cell_step()
	return Vector3(snappedf(pos.x, step), 0.0, snappedf(pos.z, step))


## True if (x, z) is on the current collider with room to spare.
func collider_covers(x: float, z: float, margin: float = 0.0) -> bool:
	var half := collider_size * 0.5 - margin
	return absf(x - collider_center.x) <= half and absf(z - collider_center.z) <= half


## Rebuild the collider around `pos` right now (synchronous: a load, not a frame).
func snap_to(pos: Vector3) -> void:
	if collider_shape == null:
		return
	var c := snapped_center(pos)
	var data := PackedFloat32Array()
	data.resize((collider_cells + 1) * (collider_cells + 1))
	for j in collider_cells + 1:
		_fill_row(data, c, j)
	collider_shape.shape = _shape_from(data)
	collider_body.position = c
	collider_center = c
	_pending = false
	_pending_data = PackedFloat32Array()
	snaps += 1


func is_rebuilding() -> bool:
	return _pending


func _physics_process(_dt: float) -> void:
	if _target == null or not is_instance_valid(_target) or collider_body == null:
		return
	var p := _target.global_position
	# Teleported (a respawn, a scripted move) past the edge: rebuild now. A one-off
	# hitch beats falling through the world.
	if not collider_covers(p.x, p.z, 8.0):
		snap_to(p)
		return
	if _pending and Vector2(p.x - _pending_center.x, p.z - _pending_center.z).length() >= recenter_distance:
		_pending = false             # the target left the area being built; start over
	if not _pending:
		if Vector2(p.x - collider_center.x, p.z - collider_center.z).length() < recenter_distance:
			return
		_pending = true
		_pending_center = snapped_center(p)
		_pending_row = 0
		_pending_data = PackedFloat32Array()
		_pending_data.resize((collider_cells + 1) * (collider_cells + 1))
	var t0 := Time.get_ticks_usec()
	var budget_us := int(rebuild_budget_ms * 1000.0)
	while _pending_row <= collider_cells:
		_fill_row(_pending_data, _pending_center, _pending_row)
		_pending_row += 1
		if Time.get_ticks_usec() - t0 >= budget_us:
			break
	if _pending_row > collider_cells:
		# Swap shape and position together, in one physics frame.
		var ts := Time.get_ticks_usec()
		collider_shape.shape = _shape_from(_pending_data)
		collider_body.position = _pending_center
		collider_center = _pending_center
		_pending = false
		_pending_data = PackedFloat32Array()
		recenters += 1
		worst_swap_ms = maxf(worst_swap_ms, (Time.get_ticks_usec() - ts) / 1000.0)
	worst_step_ms = maxf(worst_step_ms, (Time.get_ticks_usec() - t0) / 1000.0)
