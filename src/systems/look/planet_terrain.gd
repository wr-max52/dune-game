class_name PlanetTerrain
extends DesertTerrain
## The desert as a whole ball (issue #77): the same jobs as DesertTerrain (the sand
## you see, the ground you stand on, the town seated at floor level) but on a
## PlanetSphere, so the sand goes all the way round and there is no edge to fall
## off. Same public face, so the town, the ship and the traces use it unchanged.
##
## Three layers of sand, all from the sphere's one height function:
##   near -- 256 m square under the player at 1 m: the collider AND a mesh built
##           from the very same heights, so the dunes you see are the dunes you
##           stand on (no sinking into a crest, no floating over a dip).
##   mid  -- 1 km square under the camera at 4 m, mesh only.
##   far  -- the whole ball, a cube sphere at about 40 m, built once.
## Each layer sinks its own sand a few metres wherever the layer inside it covers
## (instance shader parameters), so a coarse crest never pokes through.
##
## near and mid follow (near: `follow`, the player; mid: the camera) and rebuild on
## a worker thread; the new mesh and collider are swapped in whole on one frame.
## `threaded = false` builds on the calling frame instead (tests).

@export var near_cells := 256
@export var near_step := 1.0
@export var near_recenter := 48.0
@export var mid_cells := 256
@export var mid_step := 4.0
@export var mid_recenter := 160.0
@export var far_chunks := 4             ## per cube face side
@export var far_cells := 48             ## per chunk side
@export var hole_sink := 6.0            ## metres an outer layer drops under an inner one
var threaded := true

var sphere: PlanetSphere
var near_mesh: MeshInstance3D
var mid_mesh: MeshInstance3D
var far_root: Node3D
var _with_mesh := true
var _camera_source: Callable = Callable()   ## () -> Vector3, for the mid ring
## In-flight builds: layer -> { task, center: Vector2 (map), result }.
var _jobs := {}
var _near_map := Vector2.INF            ## map centre of the near layer in place
var _mid_map := Vector2.INF


func _init() -> void:
	super._init()
	name = "PlanetTerrain"
	sphere = PlanetSphere.new()
	collider_cells = near_cells
	collider_size = near_cells * near_step
	recenter_distance = near_recenter


func set_radius(r: float) -> void:
	sphere.set_radius(r)
	extent = PI * r


func configure_site(floor_rect: Rect2, walls_rect: Rect2, sunken: Array, floor_y: float = 0.0) -> void:
	super.configure_site(floor_rect, walls_rect, sunken, floor_y)
	sphere.configure_site(floor_rect, walls_rect, sunken, floor_y)
	sphere.pad_margin = pad_margin
	sphere.blend = blend
	sphere.dune_offset = dune_offset
	sphere.sink_ramp = sink_ramp


func height_at(x: float, z: float) -> float:
	return sphere.height_at(x, z, sink_grow)


func ground_at(x: float, z: float) -> float:
	return sphere.height_at(x, z, _collider_grow())


func _collider_grow() -> float:
	return sink_grow + near_step + 1.0


func _cell_step() -> float:
	return near_step


## Where the near layer would be centred for a world position: snapped to whole
## cells in map coordinates, so heights line up between rebuilds. (y = 0: the
## centre is a map position, not a point in the air.)
func snapped_center(pos: Vector3) -> Vector3:
	var m := sphere.world_to_map(pos)
	return Vector3(snappedf(m.x, near_step), 0.0, snappedf(m.y, near_step))


func collider_covers(x: float, z: float, margin: float = 0.0) -> bool:
	var y := height_at(x, z)
	if not is_finite(y):
		return false               # past the rim: no ground on that vertical line
	return _map_covers(sphere.world_to_map(Vector3(x, y, z)), margin)


func _map_covers(m: Vector2, margin: float) -> bool:
	if _near_map == Vector2.INF:
		return false
	var half := collider_size * 0.5 - margin
	return absf(m.x - _near_map.x) <= half and absf(m.y - _near_map.y) <= half


func build(with_mesh: bool = true) -> void:
	_with_mesh = with_mesh
	material = ShaderMaterial.new()
	material.shader = SAND_SHADER
	material.set_shader_parameter("noise_tex", LookEnvironment.make_noise_texture(512, 3, 0.01))
	material.set_shader_parameter("planet_center", sphere.center)
	material.set_shader_parameter("planet_radius", sphere.radius)
	collider_body = StaticBody3D.new()
	collider_body.name = "Collider"
	collider_shape = CollisionShape3D.new()
	collider_shape.scale = Vector3(near_step, near_step, near_step)
	collider_body.add_child(collider_shape)
	add_child(collider_body)
	if with_mesh:
		near_mesh = _layer_mesh("Near")
		mid_mesh = _layer_mesh("Mid")
		# Only the sand round the player casts shadows: coarse dunes further out would
		# shade themselves in blotches the size of shadow-map texels.
		mid_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_build_far()
	_apply("near", _compute("near", Vector2(collider_center.x, collider_center.z)))
	if with_mesh:
		_apply("mid", _compute("mid", Vector2.ZERO))


func _layer_mesh(n: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.material_override = material
	add_child(mi)
	return mi


## The mid ring follows whatever this returns (the camera); none = the player.
func follow_camera(source: Callable) -> void:
	_camera_source = source


func snap_to(pos: Vector3) -> void:
	if collider_shape == null:
		return
	var c := snapped_center(pos)
	_jobs.erase("near")
	_apply("near", _compute("near", Vector2(c.x, c.z)))
	_pending = false
	snaps += 1


func is_rebuilding() -> bool:
	return _jobs.has("near")


func prefetch(pos: Vector3) -> void:
	if collider_body == null:
		return
	var c := snapped_center(pos)
	var m := Vector2(c.x, c.z)
	if _near_map != Vector2.INF and m.distance_to(_near_map) < recenter_distance:
		return
	if _jobs.has("near") and m.distance_to(_jobs.near.center) < recenter_distance:
		return
	_start("near", m)
	set_physics_process(true)


func _physics_process(_dt: float) -> void:
	if collider_body == null:
		return
	_finish_jobs()
	var following := _target != null and is_instance_valid(_target)
	if following:
		var p := _target.global_position
		var m := sphere.world_to_map(p)
		if not _map_covers(m, 8.0) and not (_jobs.has("near") and _jobs.near.get("snap", false)):
			# Teleported past the edge: rebuild now. A one-off hitch beats a fall.
			snap_to(p)
		elif m.distance_to(_near_map) >= recenter_distance:
			if not _jobs.has("near") or m.distance_to(_jobs.near.center) >= recenter_distance:
				var c := snapped_center(p)
				_start("near", Vector2(c.x, c.z))
	if _with_mesh:
		var eye: Vector3 = _camera_source.call() if _camera_source.is_valid() \
			else (_target.global_position if following else Vector3.ZERO)
		var me := sphere.world_to_map(eye)
		if me.distance_to(_mid_map) >= mid_recenter and not _jobs.has("mid"):
			_start("mid", Vector2(snappedf(me.x, mid_step), snappedf(me.y, mid_step)))


func _start(layer: String, center: Vector2) -> void:
	if not threaded:
		_apply(layer, _compute(layer, center))
		if layer == "near":
			recenters += 1
		return
	var job := { "center": center, "result": null }
	job.task = WorkerThreadPool.add_task(func(): job.result = _compute(layer, center), false, "terrain " + layer)
	if _jobs.has(layer):
		_stale.append(_jobs[layer].task)   # superseded: reaped once done, result dropped
	_jobs[layer] = job


var _stale: Array = []


func _finish_jobs() -> void:
	for t in _stale.duplicate():
		if WorkerThreadPool.is_task_completed(t):
			WorkerThreadPool.wait_for_task_completion(t)
			_stale.erase(t)
	for layer in _jobs.keys():
		var job: Dictionary = _jobs[layer]
		if not WorkerThreadPool.is_task_completed(job.task):
			continue
		WorkerThreadPool.wait_for_task_completion(job.task)
		_jobs.erase(layer)
		var ts := Time.get_ticks_usec()
		_apply(layer, job.result)
		var ms := (Time.get_ticks_usec() - ts) / 1000.0
		worst_swap_ms = maxf(worst_swap_ms, ms)
		worst_step_ms = maxf(worst_step_ms, ms)
		if layer == "near":
			recenters += 1


## Heights (and, with the look on, the mesh arrays) for a layer centred at map c.
## Runs on a worker thread: touches nothing but the sphere (read-only).
func _compute(layer: String, c: Vector2) -> Dictionary:
	var near := layer == "near"
	var cells := near_cells if near else mid_cells
	var step := near_step if near else mid_step
	var grow := _collider_grow() if near else sink_grow
	var p := sphere.patch(c.x, c.y, cells, step, grow)
	p.center = c
	p.cells = cells
	p.step = step
	if _with_mesh:
		p.arrays = _grid_arrays(p.verts, cells + 1)
	return p


func _apply(layer: String, p: Dictionary) -> void:
	var xf: Transform3D = p.xform
	if layer == "near":
		var step: float = p.step
		var data: PackedFloat32Array = p.heights
		var scaled := PackedFloat32Array()
		scaled.resize(data.size())
		for i in data.size():
			scaled[i] = data[i] / step
		var shape := HeightMapShape3D.new()
		shape.map_width = int(p.cells) + 1
		shape.map_depth = int(p.cells) + 1
		shape.map_data = scaled
		collider_shape.shape = shape
		collider_body.global_transform = xf
		collider_center = Vector3(p.center.x, 0.0, p.center.y)
		_near_map = p.center
		_pending = false
		if near_mesh != null:
			_set_mesh(near_mesh, p.arrays, xf, p.cells * step)
			_set_hole(mid_mesh, xf, p.cells * step * 0.5)
	elif mid_mesh != null:
		_mid_map = p.center
		_set_mesh(mid_mesh, p.arrays, xf, int(p.cells) * float(p.step))
		if far_root != null:
			for c in far_root.get_children():
				_set_hole(c, xf, int(p.cells) * float(p.step) * 0.5)


func _set_mesh(mi: MeshInstance3D, arrays: Array, xf: Transform3D, size: float) -> void:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.custom_aabb = AABB(Vector3(-size * 0.5, -200, -size * 0.5), Vector3(size, 400, size))
	mi.mesh = mesh
	mi.global_transform = xf


## Tell an outer layer where the inner one lies, so it sinks out of the way there.
func _set_hole(mi: GeometryInstance3D, xf: Transform3D, half: float) -> void:
	if mi == null:
		return
	mi.set_instance_shader_parameter("hole_origin", Vector4(xf.origin.x, xf.origin.y, xf.origin.z, half))
	mi.set_instance_shader_parameter("hole_x", xf.basis.x)
	mi.set_instance_shader_parameter("hole_z", xf.basis.z)


## Mesh arrays for a (n x n) grid of points: normals from neighbours, wound to face
## up (clockwise from above = front in Godot).
static func _grid_arrays(verts: PackedVector3Array, n: int) -> Array:
	var norms := PackedVector3Array()
	norms.resize(n * n)
	for j in n:
		var j0 := maxi(j - 1, 0)
		var j1 := mini(j + 1, n - 1)
		for i in n:
			var i0 := maxi(i - 1, 0)
			var i1 := mini(i + 1, n - 1)
			var dx := verts[j * n + i1] - verts[j * n + i0]
			var dz := verts[j1 * n + i] - verts[j0 * n + i]
			norms[j * n + i] = dz.cross(dx).normalized()
	var idx := PackedInt32Array()
	idx.resize((n - 1) * (n - 1) * 6)
	var w := 0
	for j in n - 1:
		for i in n - 1:
			var v00 := j * n + i
			var v10 := v00 + 1
			var v01 := v00 + n
			var v11 := v01 + 1
			idx[w] = v00; idx[w + 1] = v10; idx[w + 2] = v01
			idx[w + 3] = v10; idx[w + 4] = v11; idx[w + 5] = v01
			w += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	return arrays


# ---------------------------------------------------------------- the far ball

## The whole ball: each cube face split into far_chunks^2 meshes, built in
## parallel at load. All chunks share one spacing, so their edges meet exactly.
func _build_far() -> void:
	far_root = Node3D.new()
	far_root.name = "Far"
	add_child(far_root)
	var count := 6 * far_chunks * far_chunks
	var results := []
	results.resize(count)
	var g := WorkerThreadPool.add_group_task(func(k: int): results[k] = _far_chunk(k), count, -1, true, "planet far")
	WorkerThreadPool.wait_for_group_task_completion(g)
	for k in count:
		var mi := MeshInstance3D.new()
		mi.name = "Chunk%d" % k
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, results[k])
		mi.mesh = mesh
		mi.material_override = material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		far_root.add_child(mi)


const _FACES := [
	[Vector3.RIGHT, Vector3.BACK, Vector3.UP], [Vector3.LEFT, Vector3.FORWARD, Vector3.UP],
	[Vector3.UP, Vector3.RIGHT, Vector3.BACK], [Vector3.DOWN, Vector3.LEFT, Vector3.BACK],
	[Vector3.BACK, Vector3.LEFT, Vector3.UP], [Vector3.FORWARD, Vector3.RIGHT, Vector3.UP],
]


func _far_chunk(k: int) -> Array:
	var per := far_chunks * far_chunks
	var face: Array = _FACES[k / per]
	var ci := (k % per) % far_chunks
	var cj := (k % per) / far_chunks
	# One extra row of points all round, so the normals on a chunk's edge come out
	# the same as its neighbour's (no lighting seam); the border is cut off after.
	var n := far_cells + 3
	var verts := PackedVector3Array()
	verts.resize(n * n)
	var norm: Vector3 = face[0]
	var ax: Vector3 = face[1]
	var ay: Vector3 = face[2]
	for j in n:
		for i in n:
			# Equal-angle cube mapping keeps the cells near the same size everywhere.
			var a := (float(ci * far_cells + i - 1) / (far_chunks * far_cells)) * 2.0 - 1.0
			var b := (float(cj * far_cells + j - 1) / (far_chunks * far_cells)) * 2.0 - 1.0
			var dir := (norm + ax * tan(a * PI * 0.25) + ay * tan(b * PI * 0.25)).normalized()
			verts[j * n + i] = sphere.center + dir * (sphere.radius + sphere.elevation(dir, sink_grow))
	var full := _grid_arrays(verts, n)
	var m := n - 2
	var cv := PackedVector3Array()
	var cn := PackedVector3Array()
	cv.resize(m * m)
	cn.resize(m * m)
	var fn: PackedVector3Array = full[Mesh.ARRAY_NORMAL]
	for j in m:
		for i in m:
			cv[j * m + i] = verts[(j + 1) * n + i + 1]
			cn[j * m + i] = fn[(j + 1) * n + i + 1]
	var arrays := _grid_arrays(cv, m)
	arrays[Mesh.ARRAY_NORMAL] = cn
	verts = cv
	n = m
	# Face winding differs per face: flip the triangles that came out facing in.
	var mid := verts[(n / 2) * n + n / 2]
	var nm: Vector3 = (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array)[(n / 2) * n + n / 2]
	if nm.dot(mid - sphere.center) < 0.0:
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for t in range(0, idx.size(), 3):
			var s := idx[t + 1]
			idx[t + 1] = idx[t + 2]
			idx[t + 2] = s
		arrays[Mesh.ARRAY_INDEX] = idx
		var ns: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for q in ns.size():
			ns[q] = -ns[q]
		arrays[Mesh.ARRAY_NORMAL] = ns
	return arrays
