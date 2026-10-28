class_name WorldScenery
extends Node3D
## What M14 adds to the desert around the port, beyond what the town's
## DesertTerrain and DesertLandforms already build (the sand, its walkable
## collider, the mesas and hoodoos):
##   - the world's location landmarks (the outpost's buildings): colliders always
##     (the CI greybox flies into them too), placeholder boxes with the look on,
##   - with the look on: the planet skirt, a ring beyond the desert's edge that
##     keeps falling away with the planet's curve, so a high ship sees a curved
##     horizon instead of the edge of the sand.
## Shapes come from WorldGround (the same boxes the ship collides with); colours
## from content/look/world.json.

const LOOK_PATH := "res://content/look/world.json"

var ground: WorldGround
var terrain: WorldTerrain
var look: Dictionary = {}
var _mats: LookMaterials


func setup(world_ground: WorldGround) -> void:
	ground = world_ground
	terrain = world_ground.terrain


func _ready() -> void:
	name = "WorldScenery"
	look = ItemKit._read_json(LOOK_PATH)
	_build_landmark_colliders()


## Build the visible world. `sand` = the desert's own material (DesertTerrain.material),
## so the skirt carries on the same sand and its seam does not show from high up.
func build_visuals(mats: LookMaterials = null, sand: Material = null) -> void:
	_mats = mats if mats != null else LookMaterials.new()
	if terrain.sphere == null:
		_build_skirt(sand)       # a ball (issue #77) has sand all the way round already
	_build_landmark_visuals()


## The location landmarks' boxes (ids "<landmark>/<building>"); town boxes collide
## in the town already.
func landmark_boxes() -> Array:
	return ground.boxes.filter(func(b): return str(b.id).contains("/"))


func _build_landmark_colliders() -> void:
	var root := StaticBody3D.new()
	root.name = "LandmarkColliders"
	add_child(root)
	for b in landmark_boxes():
		if str(b.get("rise", "")) != "":
			continue                 # a ramp: its dresser builds the sloped collider
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		var mn: Vector3 = b.min
		var mx: Vector3 = b.max
		shape.size = mx - mn
		cs.shape = shape
		cs.position = (mn + mx) * 0.5
		root.add_child(cs)


## A ring beyond the desert that keeps falling away with the planet. It starts
## just inside the desert's edge, a metre under the skirt level, so the sand's
## corners cover it and its seam never flickers.
func _build_skirt(sand: Material = null) -> void:
	var r0 := terrain.extent * 0.97
	# Issue #46: out to the horizon seen from three times the edge of space, and no
	# further: on a smaller planet the rest is round the curve and never drawn.
	var horizon := terrain.curve_from + sqrt(2.0 * terrain.planet_radius * ground.space_altitude() * 3.0)
	var rings := [r0, terrain.extent * 1.5]
	for r in [14000.0, 24000.0, 40000.0, 60000.0, 100000.0]:
		if r < horizon:
			rings.append(r)
	rings.append(horizon)
	var seg := 96
	var base := terrain.skirt_height - 1.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in rings.size() - 1:
		var ra: float = rings[k]
		var rb: float = rings[k + 1]
		for s in seg:
			var a0 := TAU * s / seg
			var a1 := TAU * (s + 1) / seg
			var p00 := Vector3(cos(a0) * ra, base - terrain.drop(ra), sin(a0) * ra)
			var p01 := Vector3(cos(a1) * ra, base - terrain.drop(ra), sin(a1) * ra)
			var p10 := Vector3(cos(a0) * rb, base - terrain.drop(rb), sin(a0) * rb)
			var p11 := Vector3(cos(a1) * rb, base - terrain.drop(rb), sin(a1) * rb)
			for v in [p00, p10, p11, p00, p11, p01]:      # wound to face up (the sand culls backs)
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.name = "PlanetSkirt"
	mi.mesh = st.commit()
	if sand != null:
		mi.material_override = sand
	else:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(str(look.get("terrain", {}).get("skirt_color", "#b8916a")))
		m.roughness = 1.0
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 1000.0
	add_child(mi)


func _build_landmark_visuals() -> void:
	var root := Node3D.new()
	root.name = "Landmarks"
	add_child(root)
	var op: Dictionary = look.get("outpost", {})
	for b in landmark_boxes():
		if not bool(b.get("visual", true)):
			continue                 # dressed elsewhere (issue #42: Skrugs's post)
		var mn: Vector3 = b.min
		var mx: Vector3 = b.max
		var bm := BoxMesh.new()
		bm.size = mx - mn + Vector3(0, 2.0, 0)       # a skirt of wall below the sand
		var mi := MeshInstance3D.new()
		mi.name = str(b.id).replace("/", "_")
		mi.mesh = bm
		mi.material_override = _mats.plaster(mn.y, mn.y + (mx.y - mn.y) * 0.75,
			Color(str(op.get("trim", "#6b1e1e"))), Color(str(op.get("color", "#b9a48a"))))
		mi.position = (mn + mx) * 0.5 - Vector3(0, 1.0, 0)
		root.add_child(mi)
