class_name SwordTrail
extends MeshInstance3D
## The glowing smear an energy sword leaves through a swing. A fast swipe turns the
## blade 15-20 degrees between frames, so on its own it strobes; the ribbon fills
## the arc it swept and fades behind it, so the cut reads as one smooth stroke.
##
## The owner calls add(base, tip) once per drawn frame while swinging (world space)
## and tick(dt) every frame. The ribbon is the last LIFE seconds of those samples,
## with CatmullRom points between them so a 60 Hz arc is not a fan of flat panels.
## It lives in world space (top_level), additive, and costs nothing when idle.

const LIFE := 0.085            ## seconds a sample stays on the ribbon
const SUBDIV := 3              ## extra points between two samples
const MAX_SAMPLES := 24

var color := Color("#3aa0ff")
var _samples: Array = []       ## [base, tip, age]
var _mesh := ImmediateMesh.new()


func _ready() -> void:
	name = "SwordTrail"
	top_level = true
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.no_depth_test = false
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material_override = m
	global_transform = Transform3D.IDENTITY


func add(base: Vector3, tip: Vector3) -> void:
	_samples.append([base, tip, 0.0])
	if _samples.size() > MAX_SAMPLES:
		_samples.pop_front()


func clear() -> void:
	_samples.clear()
	_mesh.clear_surfaces()


func is_empty() -> bool:
	return _samples.is_empty()


## Age the samples, drop the old ones and rebuild the ribbon.
func tick(dt: float) -> void:
	if _samples.is_empty():
		return
	for s in _samples:
		s[2] += dt
	while not _samples.is_empty() and float(_samples[0][2]) > LIFE:
		_samples.pop_front()
	_rebuild()


func _rebuild() -> void:
	_mesh.clear_surfaces()
	var n := _samples.size()
	if n < 2:
		return
	global_transform = Transform3D.IDENTITY
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in n - 1:
		var a: Array = _samples[maxi(i - 1, 0)]
		var b: Array = _samples[i]
		var c: Array = _samples[i + 1]
		var d: Array = _samples[mini(i + 2, n - 1)]
		var steps := SUBDIV + 1
		for k in steps + (1 if i == n - 2 else 0):
			var f := float(k) / steps
			var base: Vector3 = (b[0] as Vector3).cubic_interpolate(c[0], a[0], d[0], f)
			var tip: Vector3 = (b[1] as Vector3).cubic_interpolate(c[1], a[1], d[1], f)
			var age := lerpf(float(b[2]), float(c[2]), f)
			var fade := clampf(1.0 - age / LIFE, 0.0, 1.0)
			var col := color
			# Bright at the tip, thin toward the hilt; brightest where the blade is now.
			_mesh.surface_set_color(Color(col.r, col.g, col.b, 0.0))
			_mesh.surface_add_vertex(base)
			_mesh.surface_set_color(Color(col.r, col.g, col.b, 0.6 * fade * fade))
			_mesh.surface_add_vertex(tip)
	_mesh.surface_end()
