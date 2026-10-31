class_name EngineFlame
extends RefCounted
## One engine flame, for anything with a nozzle: the jetpack's flame (ItemKit._flame)
## grown for the Remnant cruiser's bells, and the same flame on every ship's engines
## (ShipKit). Layered and additive: a white-hot mouth and core, a body, an outer
## cone, a faint plume, and shock diamonds down the middle. Its -y runs out of the
## nozzle; scale its y to make it longer.

## The jetpack's colours (warm engines) and the cruiser's (cool ones).
const JET := { "hot": "#ffd9a0", "body": "#ff8a2a", "outer": "#ff8a2a", "tail": "#ff3a14" }
const ION := { "hot": "#d9f3ff", "body": "#5cb6ff", "outer": "#2b6cff", "tail": "#5b3dff" }


## The palette for an engine glow colour: the jetpack's for a warm one, else the cruiser's.
static func palette(engine: Color) -> Dictionary:
	var warm := engine.h < 0.17 or engine.h > 0.9
	return JET if warm and engine.s > 0.3 else ION


## A flame on `parent` at `xf`, `nr` its radius at the mouth and `fh` its length.
## `seg` is the cones' sides. Every mesh is a direct child of the returned node.
static func build(parent: Node3D, xf: Transform3D, nr: float, fh: float, pal: Dictionary, seg := 24) -> Node3D:
	var fl := Node3D.new()
	fl.name = "Flame"
	parent.add_child(fl)
	fl.transform = xf
	var hot := Color(str(pal.hot))
	var body := Color(str(pal.body))
	var outer := Color(str(pal.outer))
	var tail := Color(str(pal.tail))
	var mouth := minf(0.3, nr * 0.1)
	var parts := [
		[_cyl(nr * 0.95, nr * 0.95, mouth, seg + 8), _plume(hot.lerp(Color.WHITE, 0.5), 6.0, 1.0), -mouth * 0.5],
		[_cyl(nr * 0.55, 0.0, fh * 0.4, seg), _plume(hot.lerp(Color.WHITE, 0.3), 5.0, 0.9), -fh * 0.2],
		[_cyl(nr * 0.85, nr * 0.1, fh * 0.75, seg), _plume(hot.lerp(body, 0.5), 3.0, 0.6), -fh * 0.375],
		[_cyl(nr * 1.05, 0.0, fh, seg), _plume(body.lerp(outer, 0.5), 2.2, 0.45), -fh * 0.5],
		[_cyl(nr * 1.4, nr * 0.3, fh * 0.85, seg), _plume(tail, 1.4, 0.16), -fh * 0.5],
	]
	for i in 4:
		var s := SphereMesh.new()
		s.radius = nr * (0.32 - i * 0.06)
		s.height = s.radius * 2.0
		s.radial_segments = 16
		s.rings = 8
		parts.append([s, _plume(hot.lerp(Color.WHITE, 0.6), 6.0, 0.8), -fh * (0.16 + i * 0.15)])
	for p in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = p[0]
		mi.material_override = p[1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(0, float(p[2]), 0)
		if p[0] is SphereMesh:
			mi.scale = Vector3(1.0, 1.8, 1.0)
		fl.add_child(mi)
	return fl


## An unshaded, additive flame layer: `alpha` sets how much it adds.
static func _plume(color: Color, energy: float, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color, alpha)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _cyl(top: float, bottom: float, h: float, seg: int) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c
