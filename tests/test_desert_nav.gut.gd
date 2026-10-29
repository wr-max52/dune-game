extends GutTest
## Bounded terrain navigation tiles use the same ground surface as collision and
## rotate into the planet's local ground-up frame.


func test_spherical_desert_patch_bakes_walkable_polygons() -> void:
	var terrain := PlanetTerrain.new()
	terrain.set_radius(5000.0)
	var center := terrain.sphere.surface_at(500.0, 120.0)
	var frame := Transform3D(PlanetSphere.tilt_to(terrain.sphere.up_at(center)), center)
	var src := TownNav.terrain_source(terrain, center, 24.0, 2.0, frame)
	var nm := NavigationMesh.new()
	nm.cell_size = TownNav.DEFAULTS.cell_size
	nm.cell_height = TownNav.DEFAULTS.cell_height
	nm.agent_radius = TownNav.DEFAULTS.agent_radius
	nm.agent_height = TownNav.DEFAULTS.agent_height
	nm.agent_max_climb = TownNav.DEFAULTS.agent_max_climb
	nm.agent_max_slope = TownNav.DEFAULTS.agent_max_slope
	nm.filter_baking_aabb = AABB(Vector3(-24, -80, -24), Vector3(48, 160, 48))
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	assert_gt(nm.get_polygon_count(), 0, "a bounded desert patch produces walkable navigation")


func test_flat_desert_patch_keeps_world_up() -> void:
	var terrain := DesertTerrain.new()
	var center := Vector3(200.0, terrain.ground_at(200.0, -100.0), -100.0)
	var frame := Transform3D(Basis.IDENTITY, center)
	var src := TownNav.terrain_source(terrain, center, 20.0, 2.0, frame)
	var nm := NavigationMesh.new()
	nm.cell_size = TownNav.DEFAULTS.cell_size
	nm.cell_height = TownNav.DEFAULTS.cell_height
	nm.agent_radius = TownNav.DEFAULTS.agent_radius
	nm.agent_height = TownNav.DEFAULTS.agent_height
	nm.agent_max_climb = TownNav.DEFAULTS.agent_max_climb
	nm.agent_max_slope = TownNav.DEFAULTS.agent_max_slope
	nm.filter_baking_aabb = AABB(Vector3(-20, -80, -20), Vector3(40, 160, 40))
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	assert_gt(nm.get_polygon_count(), 0, "flat terrain still bakes with ordinary world-up")
