class_name DroidMerchantOutposts
extends Node3D
## Issue #93: three small, independent droid-trading relays scattered over the
## home planet. Their footprints and map coordinates come from core location and
## world data; this node adds the compact huts, conspicuous antenna arrays, and
## their keepers. It does not join or alter the Remnant's story outposts.

const CoreContent := preload("res://src/systems/dataload/core_content.gd")
const MerchantNPC := preload("res://src/systems/npc/merchant_npc.gd")
const POST_IDS := ["droid_post_wash", "droid_post_ridge", "droid_post_basin"]
const OUTFIT := { "head": "sand", "torso": "blue", "legs": "darker" }

var demo
var ground: WorldGround
var sites: Array = []       ## { id, label, pos, face, xf }


func setup(town_demo, world_ground: WorldGround) -> void:
	demo = town_demo
	ground = world_ground
	name = "DroidMerchantOutposts"


func _ready() -> void:
	if demo == null or ground == null or str(demo.planet.get("id", "")) != PlanetGen.home_id():
		return
	var cc := CoreContent.new()
	cc.load_from()
	var world: Dictionary = demo.world if not demo.world.is_empty() else cc.world_for_town("port_town")
	for id in POST_IDS:
		for lm in world.get("landmarks", []):
			if str(lm.get("location", "")) != id:
				continue
			var loc := cc.get_location(id)
			if loc.is_empty():
				push_error("DroidMerchantOutposts: missing location " + id)
				continue
			_build_site(lm, loc)


func _build_site(lm: Dictionary, loc: Dictionary) -> void:
	var map_at := WorldGround._v3(lm.get("at", [0, 0, 0]))
	var origin := Vector3(map_at.x, ground.terrain.height_at(map_at.x, map_at.z), map_at.z)
	var yaw := deg_to_rad(float(lm.get("yaw_deg", 0.0)))
	var sp := ground.sphere()
	var basis := Basis(Vector3.UP, yaw)
	if sp != null:
		origin = sp.surface_at(map_at.x, map_at.z)
		basis = PlanetSphere.tilt_to(ground.up_at(origin)) * basis
	var xf := Transform3D(basis, origin)
	var root := Node3D.new()
	root.name = str(lm.get("id", loc.get("id", "DroidRelay"))).to_pascal_case()
	add_child(root)
	root.global_transform = xf
	if demo.use_look:
		_dress(root, loc)
	_build_keeper(root, loc)
	var pts: Dictionary = loc.get("points", {})
	var vendor := _world_point(xf, WorldGround._v3(pts.get("merchant", [0, 0, 0])))
	var customer := _world_point(xf, WorldGround._v3(pts.get("customer", [0, 0, 2])))
	var up := ground.up_at(vendor)
	var face := customer - vendor
	face = (face - up * face.dot(up)).normalized()
	sites.append({ "id": str(loc.get("id", "")), "label": str(loc.get("label", "Droid Merchant")),
		"pos": vendor, "face": face, "xf": xf })


func _world_point(xf: Transform3D, local: Vector3) -> Vector3:
	var p := xf * Vector3(local.x, 0.0, local.z)
	var sp := ground.sphere()
	if sp != null:
		var dir := (p - sp.center).normalized()
		return sp.center + dir * (sp.radius + sp.elevation(dir))
	p.y = ground.terrain.height_at(p.x, p.z)
	return p


func _build_keeper(root: Node3D, loc: Dictionary) -> void:
	var pts: Dictionary = loc.get("points", {})
	var at: Vector3 = _world_point(root.global_transform, WorldGround._v3(pts.get("merchant", [0, 0, 0])))
	var face_at: Vector3 = _world_point(root.global_transform, WorldGround._v3(pts.get("customer", [0, 0, 2])))
	var keeper: Node3D
	if demo.use_look:
		keeper = MerchantNPC.new(CharacterKit.new(demo._flat_mats(), 0.0), "local", OUTFIT)
	else:
		keeper = MerchantNPC.new()
	keeper.name = "Keeper"
	add_child(keeper)
	keeper.global_position = at
	var up := ground.up_at(at)
	var facing := face_at - at
	facing = (facing - up * facing.dot(up)).normalized()
	keeper.global_basis = PlanetSphere.tilt_to(up) * Basis(Vector3.UP, atan2(facing.x, facing.z))
	keeper.look_at_target = demo._player


func _dress(root: Node3D, loc: Dictionary) -> void:
	var mats: LookMaterials = demo._flat_mats()
	var look: Dictionary = loc.get("look", {})
	var accent := Color(str(look.get("accent", "#b68a42")))
	var wall := mats.plaster(0.0, 3.4, accent, Color("#49494a"))
	var dark := mats.flat(Color("#202225"), 0.7, 0.35)
	var steel := mats.flat(Color("#71777a"), 0.5, 0.65)
	var trim := mats.flat(accent, 0.65, 0.25)
	var glow := mats.glow(Color("#69e4d6"))
	glow.emission_energy_multiplier = 2.4
	var beacon := mats.glow(Color("#ffad48"))
	beacon.emission_energy_multiplier = 3.2
	for b in loc.get("buildings", []):
		var size := WorldGround._v3(b.get("size", [1, 1, 1]))
		var pos := WorldGround._v3(b.get("position", [0, 0, 0]))
		if str(b.get("id", "")) == "relay_hut":
			_part(root, _box(size + Vector3(0.25, 0.12, 0.25)), wall, pos + Vector3(0, size.y * 0.5, 0))
			_part(root, _box(Vector3(size.x + 0.55, 0.24, size.z + 0.55)), dark,
				pos + Vector3(0, size.y + 0.12, 0))
			_part(root, _box(Vector3(size.x + 0.32, 0.28, size.z + 0.32)), trim,
				pos + Vector3(0, size.y - 0.42, 0))
			_part(root, _box(Vector3(0.12, 2.25, 1.15)), dark,
				pos + Vector3(size.x * 0.5 + 0.04, 1.12, 0.5))
			_part(root, _box(Vector3(0.18, 0.12, 1.35)), glow,
				pos + Vector3(size.x * 0.5 + 0.14, 2.45, 0.5))
			_part(root, _box(Vector3(2.8, 0.12, 1.7)), dark,
				pos + Vector3(size.x * 0.5 + 0.9, 2.5, 1.5))
			# Small roof service panels, visible but subordinate to the tall relay.
			for i in 2:
				_part(root, _box(Vector3(1.35, 0.08, 0.8)), steel,
					pos + Vector3(-1.5 + i * 1.7, size.y + 0.3, 1.15))
		elif str(b.get("id", "")) == "trade_counter":
			_part(root, _box(size), dark, pos + Vector3(0, size.y * 0.5, 0))
			_part(root, _box(Vector3(size.x + 0.2, 0.14, size.z + 0.18)), trim,
				pos + Vector3(0, size.y + 0.07, 0))
		elif str(b.get("id", "")) == "merchant_table":
			var top := Vector3(size.x, 0.12, size.z)
			_part(root, _box(top), steel, pos + Vector3(0, size.y - top.y * 0.5, 0))
			for x_sign in [-1.0, 1.0]:
				for z_sign in [-1.0, 1.0]:
					_part(root, _box(Vector3(0.1, size.y - top.y, 0.1)),
						dark, pos + Vector3(x_sign * (size.x * 0.5 - 0.08), (size.y - top.y) * 0.5,
							z_sign * (size.z * 0.5 - 0.08)))
			_part(root, _box(Vector3(size.x * 0.7, 0.06, size.z * 0.58)), trim,
				pos + Vector3(0, size.y - top.y - 0.04, 0))
	# Chocked cargo cases and a small repair trolley keep the yard detailed,
	# without expanding its building footprint.
	_part(root, _box(Vector3(0.85, 0.8, 0.85)), steel, Vector3(-3.2, 0.4, -2.7))
	_part(root, _box(Vector3(0.9, 0.7, 0.75)), dark, Vector3(-2.25, 0.35, -2.7))
	_part(root, _box(Vector3(1.3, 0.12, 0.55)), trim, Vector3(2.0, 0.55, -2.4))
	_antenna_array(root, float(look.get("antenna_height", 8.5)), str(look.get("array_style", "wide")),
		steel, dark, trim, glow, beacon)


## A layered roof relay, deliberately much taller and broader than the little
## house: a mast, three cross-arm tiers, two auxiliary whips, bracing and beacons.
func _antenna_array(root: Node3D, height: float, style: String, steel: Material,
		dark: Material, trim: Material, glow: Material, beacon: Material) -> void:
	var roof_y := 3.55
	var base := Vector3(-1.2, roof_y, -0.7)
	_part(root, _box(Vector3(1.3, 0.24, 1.3)), dark, base + Vector3(0, 0.12, 0))
	var mast_y := height * 0.5
	_rod(root, 0.09, height, steel, base + Vector3(0, mast_y, 0), Vector3.UP)
	for side in [-1.0, 1.0]:
		_rod(root, 0.045, height * 0.83, trim,
			base + Vector3(side * 0.35, height * 0.415, 0), Vector3(side * 0.04, 1, 0).normalized())
	var span := 3.4 if style == "wide" else 2.7
	for tier in 3:
		var y := height * (0.3 + tier * 0.25)
		var tier_span := span if tier == 1 or style == "wide" else span * 0.68
		_rod(root, 0.055 if tier == 1 else 0.04, tier_span, steel,
			base + Vector3(0, y, 0), Vector3.RIGHT)
		_rod(root, 0.04, 0.95, dark, base + Vector3(0, y + 0.28, 0), Vector3.FORWARD)
		for side in [-1.0, 1.0]:
			_rod(root, 0.027, 0.8, trim,
				base + Vector3(side * tier_span * 0.31, y - 0.22, 0),
				Vector3(side * 0.45, 1, 0).normalized())
			_part(root, _box(Vector3(0.13, 0.22, 0.13)),
				glow if tier == 2 else dark, base + Vector3(side * tier_span * 0.5, y, 0))
	for side in [-1.0, 1.0]:
		var wing := base + Vector3(side * 1.35, height * 0.15, 0.2)
		_rod(root, 0.035, height * 0.48, steel,
			wing + Vector3(0, height * 0.24, 0), Vector3.UP)
		_rod(root, 0.025, 1.0, trim, wing + Vector3(0, height * 0.48, 0), Vector3.FORWARD)
		_rod(root, 0.022, Vector3(0.9, height * 0.35, 0).length(), dark,
			base + Vector3(side * 0.32, height * 0.12, 0),
			Vector3(side * 0.9, height * 0.35, 0).normalized())
	_part(root, _box(Vector3(0.32, 0.38, 0.32)), trim, base + Vector3(0, height + 0.18, 0))
	_part(root, _box(Vector3(0.24, 0.24, 0.24)), beacon, base + Vector3(0, height + 0.48, 0))
	# The dish is a small directional receiver below the top array.
	var dish := CylinderMesh.new()
	dish.top_radius = 0.08
	dish.bottom_radius = 0.72
	dish.height = 0.22
	dish.radial_segments = 12
	_part(root, dish, steel, base + Vector3(0, height * 0.72, -0.28),
		Basis(Vector3.RIGHT, deg_to_rad(68.0)))
	_part(root, _box(Vector3(0.11, 1.1, 0.11)), trim,
		base + Vector3(0, height * 0.72 + 0.52, -0.28))


func _rod(root: Node3D, radius: float, length: float, mat: Material, at: Vector3,
		direction: Vector3) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 6
	_part(root, mesh, mat, at, Basis(Quaternion(Vector3.UP, direction.normalized())))


func _part(root: Node3D, mesh: Mesh, mat: Material, at: Vector3,
		basis: Basis = Basis.IDENTITY) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(mi)
	mi.position = at
	mi.basis = basis


func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh
