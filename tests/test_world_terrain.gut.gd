extends GutTest
## M14: the ground under a flying ship. Inside the desert it is the town's own
## DesertTerrain (the sand you see and walk on), beyond its edge the planet curves
## away; the ground query finds roofs, streets, ramps and the tops of the desert's
## mesas and hoodoos; obstacles are walls, buildings and rocks but never floors or
## the parked ship's own box.

const CoreScript := preload("res://src/systems/dataload/core_content.gd")
const TownLayout := preload("res://src/systems/world/town_layout.gd")

var content
var world: Dictionary
var town
var desert: DesertTerrain
var keep_out: Rect2
var ground: WorldGround


func before_each() -> void:
	content = CoreScript.new()
	content.load_from()
	world = content.get_world("port_desert")
	town = TownLayout.new()
	town.load_town("port_town")
	# Seat the desert exactly as the town scene does (its desert_site() footprints).
	var demo = load("res://scenes/town_demo.gd").new()
	demo.town = town
	var site: Dictionary = demo.desert_site()
	demo.free()
	keep_out = site.floor
	desert = DesertTerrain.new()
	desert.configure_site(site.floor, site.walls, site.sunken, 0.0)
	ground = WorldGround.new()
	ground.setup(world, town, content, desert.height_at, desert.extent)
	ground.add_landforms(DesertLandforms.load_data(), keep_out)


func after_each() -> void:
	desert.free()


func test_world_loads_and_names_its_town() -> void:
	assert_eq(world.get("id"), "port_desert")
	assert_eq(content.world_for_town("port_town").get("id"), "port_desert")
	assert_gt(float(world.atmosphere.space_altitude), 1000.0)


func test_inside_the_desert_the_ground_is_the_desert() -> void:
	var t: WorldTerrain = ground.terrain
	assert_eq(t.extent, desert.extent, "the desert's own extent wins")
	for p in [Vector2(0, 75), Vector2(300, -200), Vector2(1500, 900), Vector2(-4000, 3500)]:
		assert_almost_eq(t.height_at(p.x, p.y), desert.height_at(p.x, p.y), 0.0001,
			"same height as the sand at %s" % p)
	assert_true(ground.landable(1500, 900))
	assert_false(ground.landable(7000, 0), "nothing to walk on past the sand")


func test_beyond_the_desert_the_planet_curves_away() -> void:
	var t: WorldTerrain = ground.terrain
	assert_eq(t.drop(1000.0), 0.0, "flat near the port")
	assert_eq(t.drop(t.extent), 0.0, "and at the desert's edge: the sand and the skirt meet")
	assert_gt(t.drop(24000.0), 1000.0, "the surface falls away far out")
	assert_almost_eq(t.height_at(9000, 0), t.skirt_height - t.drop(9000.0), 0.001)
	assert_almost_eq(t.altitude(Vector3(20000, 100, 0)), 100.0 + t.drop(20000.0), 0.01,
		"altitude is measured above the curved sea level")


func test_no_desert_means_flat_ground() -> void:
	var g := WorldGround.new()
	g.setup(world, town, content)
	assert_eq(g.terrain.height_at(1500, 900), 0.0)
	assert_eq(g.terrain.extent, float(world.terrain.extent))


func test_ground_finds_streets_roofs_and_ramps() -> void:
	assert_almost_eq(ground.ground_at(40, 0), 0.0, 0.01, "the street")
	assert_almost_eq(ground.ground_at(0.3, 0), -6.0, 0.01, "the pit floor (the ship's own box is skipped)")
	var ramp: Dictionary = town.get_box("ramp_ne")
	var mid := ground.ground_at((float(ramp.min[0]) + float(ramp.max[0])) * 0.5, (float(ramp.min[2]) + float(ramp.max[2])) * 0.5)
	assert_almost_eq(mid, -3.0, 0.2, "half way up the ramp")
	var roof: Dictionary = town.get_box("watchtower")
	var cx := (float(roof.min[0]) + float(roof.max[0])) * 0.5
	var cz := (float(roof.min[2]) + float(roof.max[2])) * 0.5
	assert_almost_eq(ground.ground_at(cx, cz), float(roof.max[1]), 0.01, "the watchtower's top from above")
	assert_almost_eq(ground.ground_at(cx, cz, 2.0), 0.0, 0.01, "but not when you are below its top")


func test_the_desert_rocks_are_solid_to_the_ship() -> void:
	var data := DesertLandforms.load_data()
	var placed := 0
	var clear := keep_out.grow(float(data.keep_out_margin))
	for m in data.mesas + data.hoodoos:
		if not clear.grow(float(m[2])).has_point(Vector2(m[0], m[1])):
			placed += 1
	assert_eq(ground.columns.size(), placed, "every mesa and hoodoo DesertLandforms places, no more")
	assert_gt(placed, 10)
	var mesa: Dictionary = ground.columns.filter(func(c): return c.id == "mesa_1500_1700")[0]
	var c: Vector3 = mesa.center
	assert_almost_eq(c.y, desert.height_at(1500, 1700), 0.001, "standing on the sand")
	assert_almost_eq(ground.ground_at(c.x, c.z), float(mesa.top), 0.01, "land on top")
	assert_eq(ground.hit(Vector3(c.x + float(mesa.radius) + 1.0, c.y + 40.0, c.z), 2.0), "mesa_1500_1700", "fly into the side")
	assert_eq(ground.hit(Vector3(c.x, float(mesa.top) + 3.0, c.z), 2.0), "", "hover above the top")
	var hd: Dictionary = ground.columns.filter(func(x): return x.kind == "hoodoo")[0]
	assert_ne(ground.hit(Vector3((hd.center as Vector3).x, float(hd.top) - 2.0, (hd.center as Vector3).z), 1.0), "",
		"a hoodoo's cap stops you too")


func test_obstacles_are_walls_not_floors() -> void:
	assert_eq(ground.hit(Vector3(40, 1.0, 0), 1.0), "", "the street is ground, not an obstacle")
	assert_ne(ground.hit(Vector3(0, 3.0, 74), 1.5), "", "the north wall is")
	assert_eq(ground.hit(Vector3(0.3, -4.5, 0), 2.0), "", "the parked ship's pad box is not")


func test_the_outpost_stands_in_the_desert() -> void:
	var b: Array = ground.boxes.filter(func(x): return str(x.id).begins_with("outpost/"))
	assert_eq(b.size(), content.get_location("outpost").buildings.size(), "every outpost building")
	for x in b:
		assert_gt((x.min as Vector3).x, 1000.0, "out in the desert, not in town")
