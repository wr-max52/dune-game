class_name DesertTerrain
extends Node3D
## One terrain mesh for the whole view: dense near the port, stretched to about 6 km
## at the edges (fog hides the coarse far triangles). Also builds a heightmap
## collider for the walkable area so the scene can be played, not only shot.

const SAND_SHADER := preload("res://src/systems/look/shaders/sand.gdshader")

@export var resolution := 400        ## vertices per side; tests use a small value
@export var extent := 6000.0         ## half-size in metres
@export var near_spacing := 1.5      ## metres between vertices at the centre
@export var port_radius := 150.0
@export var port_height := 7.8
@export var collider_size := 1024.0
@export var basin_depth := 58.0

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
	var wx := x + _warp.get_noise_2d(x * 0.0016, z * 0.0016) * 140.0
	var wz := z + _warp.get_noise_2d(z * 0.0016 + 40.0, x * 0.0016) * 140.0
	# Long crested dunes: ridged noise, stretched across the wind.
	var ridge := 1.0 - absf(_dune.get_noise_2d(wx * 0.0021, wz * 0.0042))
	var dunes := pow(ridge, 2.6) * 26.0
	dunes += _swell.get_noise_2d(x * 0.0006, z * 0.0006) * 24.0 + 10.0
	dunes += _small.get_noise_2d(x * 0.012, z * 0.012) * 1.6
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


func build() -> void:
	material = ShaderMaterial.new()
	material.shader = SAND_SHADER
	material.set_shader_parameter("noise_tex", LookEnvironment.make_noise_texture(512, 3, 0.01))

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


func _build_collider() -> void:
	var cells := 256
	var step := collider_size / cells
	var data := PackedFloat32Array()
	data.resize((cells + 1) * (cells + 1))
	for j in cells + 1:
		for i in cells + 1:
			data[j * (cells + 1) + i] = height_at(-collider_size * 0.5 + i * step, -collider_size * 0.5 + j * step) / step
	var shape := HeightMapShape3D.new()
	shape.map_width = cells + 1
	shape.map_depth = cells + 1
	shape.map_data = data
	var body := StaticBody3D.new()
	body.name = "Collider"
	var col := CollisionShape3D.new()
	col.shape = shape
	# HeightMapShape3D cells are 1 unit; scale the node to the real spacing.
	col.scale = Vector3(step, step, step)
	body.add_child(col)
	add_child(body)
