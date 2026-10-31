extends SceneTree
## Focused wreck-only review, NOT the CI/GUT suite. No saved game is loaded.
## godot --headless --path . -s res://tools/review/wreck_probe.gd
## With a display, append: -- shots=/absolute/output/directory
## Uses real WorldScenery colliders and a player-sized capsule to check the
## sand-to-breach-to-deck route. Optional photos show the approach and town vista.

var scene: Node3D
var ground: WorldGround
var scenery: WorldScenery
var deck_xf: Transform3D
var failed := false
var shots := ""
var sand: PlanetTerrain


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("shots="):
			shots = arg.trim_prefix("shots=").trim_suffix("/")
	call_deferred("_review")


func _check(ok: bool, label: String) -> void:
	print("WRECK ", label, "=", ok)
	if not ok:
		failed = true
		push_error(label)


func _review() -> void:
	scene = Node3D.new()
	root.add_child(scene)
	var cfg: Dictionary = ItemKit._read_json("res://content/core/worlds/port_desert.json")
	cfg = cfg.duplicate(true)
	cfg.landmarks = cfg.landmarks.filter(func(lm): return str(lm.kind) == "wreck")
	sand = PlanetTerrain.new()
	sand.near_cells = 96
	sand.near_step = 2.0
	sand.mid_cells = 96
	sand.mid_step = 10.0
	sand.far_chunks = 2
	sand.far_cells = 64
	sand.town_cells = 32
	sand.threaded = false
	var landmark: Dictionary = cfg.landmarks[0]
	sand.collider_center = WorldGround._v3(landmark.at)
	# Match the real port's sand seating, so a wall-height vista is not taken
	# from inside an unflattened dune. No town/NPC scenes need to be loaded.
	var town: Dictionary = ItemKit._read_json("res://content/core/towns/port_square.json")
	var floor_rect := Rect2()
	var sunken: Array = []
	for b in town.boxes:
		if str(b.kind) != "floor":
			continue
		var r := Rect2(float(b.min[0]), float(b.min[2]), float(b.max[0]) - float(b.min[0]), float(b.max[2]) - float(b.min[2]))
		if float(b.max[1]) < -0.1:
			sunken.append({ "rect": r, "y": float(b.min[1]) })
		else:
			floor_rect = floor_rect.merge(r) if floor_rect.has_area() else r
	var bounds: Dictionary = town.bounds
	sand.configure_site(floor_rect, Rect2(float(bounds.min[0]), float(bounds.min[1]),
		float(bounds.max[0]) - float(bounds.min[0]), float(bounds.max[1]) - float(bounds.min[1])), sunken)
	PlanetSphere.current = sand.sphere
	scene.add_child(sand)
	sand.build(not shots.is_empty())
	sand.set_process(false)
	ground = WorldGround.new()
	ground.setup(cfg, null, null, sand.height_at, sand.extent)
	scenery = WorldScenery.new()
	scenery.setup(ground)
	scene.add_child(scenery)
	var deck: Dictionary = ground.boxes.filter(func(b): return str(b.id).ends_with("/lower_deck"))[0]
	# The deck's box origin is one metre below its top.
	deck_xf = WorldGround.box_xf(deck) * Transform3D(Basis.IDENTITY, Vector3(0, 25, 0))
	var ramp: Dictionary = ground.boxes.filter(func(b): return str(b.id).ends_with("/fallen_boarding_plate"))[0]
	await physics_frame
	await physics_frame
	var space := scene.get_world_3d().direct_space_state
	var bow := deck_xf * Vector3(0, 0, -299)
	var stern := deck_xf * Vector3(0, 38, 299)
	_check(sand.sphere.height_above_ground(bow) < -60.0, "bow_buried")
	_check(sand.sphere.height_above_ground(stern) > 200.0, "stern_towers_above_sand")
	var town_view := Vector3(85, 1.8, 0)
	var visible_from_town := true
	for i in range(1, 100):
		if sand.sphere.height_above_ground(town_view.lerp(stern, i / 100.0)) < 0.0:
			visible_from_town = false
			break
	_check(visible_from_town, "stern_visible_over_dunes_from_front_gate_street")
	_check(ground.boxes.size() > 200, "segmented_solid_hull")
	var inside := deck_xf * Vector3(0, -20, 30)
	_check(ground.hit(inside, 0.6) == "", "open_hold_not_a_solid_box")
	var wall := deck_xf * Vector3(-45, 0, 135)
	_check(ground.hit(wall, 5.0) != "", "ship_hits_intact_hull")
	var gap_from := deck_xf * Vector3(80, -12, -35)
	var gap_to := deck_xf * Vector3(0, -12, -35)
	_check(space.intersect_ray(PhysicsRayQueryParameters3D.create(gap_from, gap_to)).is_empty(), "side_breach_is_open")
	_check(ground.boxes.filter(func(b): return bool(b.get("wreck_shard", false))).size() == 22,
		"jagged_fracture_plates_present")
	_check(ground.boxes.filter(func(b): return str(b.id).contains("_rim_")).size() == 64,
		"four_segmented_engine_rims_present")

	var capsule := CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.8
	cs.shape = shape
	cs.position.y = 0.9
	capsule.add_child(cs)
	scene.add_child(capsule)
	await physics_frame
	var ramp_xf := WorldGround.box_xf(ramp)
	var ramp_half := ((ramp.max as Vector3) - (ramp.min as Vector3)) * 0.5
	var route: Array[Vector3] = []
	# Start on the plate where it meets sand; continue through the hole.
	for i in 101:
		route.append(ramp_xf * Vector3(0, ramp_half.y, lerpf(-ramp_half.z + 1, ramp_half.z - 1, i / 100.0)))
	route.append(deck_xf * StarcruiserWreck.ENTRY)
	for i in 31:
		route.append(deck_xf * Vector3(lerpf(30, 0, i / 30.0), StarcruiserWreck.DECK_Y, -35))
	for i in 186:
		route.append(deck_xf * Vector3(0, StarcruiserWreck.DECK_Y, -35 + i))
	var walkable := true
	var queries_match := true
	var previous := Vector3.INF
	for p in route:
		var up := ground.up_at(p)
		var ray := PhysicsRayQueryParameters3D.create(p + up * 3.0, p - up * 4.0)
		ray.exclude = [capsule.get_rid()]
		var result := space.intersect_ray(ray)
		if result.is_empty():
			walkable = false
			print("WRECK missing_floor_at=", p)
			break
		var floor_point: Vector3 = result.position
		if (result.normal as Vector3).dot(up) < cos(deg_to_rad(45)):
			walkable = false
			print("WRECK steep_floor_at=", p)
			break
		var query_point := floor_point + up * 2.0
		if absf(ground.height_above(query_point) - 2.0) > 0.15:
			queries_match = false
		var feet := floor_point + up * 0.25
		capsule.transform = Transform3D(PlanetSphere.tilt_to(up), feet)
		if previous != Vector3.INF and capsule.test_move(capsule.transform, previous - feet):
			walkable = false
			print("WRECK blocked_at=", p)
			break
		previous = feet
	_check(walkable, "capsule_route_sand_to_breach_to_aft_deck")
	_check(queries_match, "flight_ground_matches_physics_on_route")
	# Exercise the actual flight model's descent, not just the geometry queries.
	var ship := AtmoFlight.new()
	ship.setup(ItemKit._read_json("res://content/core/ships/interceptor.json"), ground)
	ship.place_flying(deck_xf * Vector3(20, 70, 180), deck_xf.basis.z, 0.0, 0.0)
	_check(ship.land(), "ship_can_start_landing_on_wreck")
	for i in 1200:
		ship.step(1.0 / 60.0)
		if ship.state == AtmoFlight.State.PARKED:
			break
	_check(ship.state == AtmoFlight.State.PARKED and absf(ship.agl()) < 0.05,
		"ship_lands_on_wreck")
	# A world without planet gravity still gets valid framed-box ground queries.
	var flat := WorldGround.new()
	flat.setup({ "terrain": {}, "landmarks": cfg.landmarks })
	var flat_deck: Dictionary = flat.boxes.filter(func(b): return str(b.id).ends_with("/lower_deck"))[0]
	var flat_p := WorldGround.box_xf(flat_deck) * Vector3(0, 3, 60)
	_check(is_finite(flat.ground_at(flat_p.x, flat_p.z)), "flat_world_unbounded_ground_query")
	if not shots.is_empty():
		scenery.build_visuals()
		var look := LookEnvironment.new()
		scene.add_child(look)
		look.apply("golden")
		look.set_suppressed(["sdfgi", "ssil", "volumetric"])
		var camera := Camera3D.new()
		camera.far = 16000
		camera.fov = 70
		scene.add_child(camera)
		camera.current = true
		DirAccess.make_dir_recursive_absolute(shots)
		await _photo(camera, deck_xf * Vector3(500, 180, 80),
			deck_xf * Vector3(0, 0, 30), shots + "/wreck_overview.png")
		await _photo(camera, ramp_xf * Vector3(0, 3, -ramp_half.z + 8), deck_xf * Vector3(0, -10, 10), shots + "/wreck_entry.png")
		await _photo(camera, deck_xf * Vector3(75, 55, 410),
			deck_xf * Vector3(0, 0, 315), shots + "/wreck_engines.png")
		await _photo(camera, town_view, town_view + Vector3(1600, 0, 0), shots + "/wreck_town_vista.png")
		# Wreck cleanup: the hung decks, catwalks and ramps, and the open hold floor.
		var lv := func(x: float, v: float, w: float) -> Vector3:
			return StarcruiserWreck.site_point(ground, Vector3(x, v, w), "level")
		var hull := func(x: float, y: float, z: float) -> Vector3:
			return StarcruiserWreck.site_point(ground, Vector3(x, y, z), "hull")
		await _photo(camera, hull.call(24, -19, 286), lv.call(0, 128, 196), shots + "/wreck_top_of_floor.png")
		await _photo(camera, lv.call(0, 131, 146), lv.call(0, 128, 215), shots + "/wreck_tiers_from_mid_catwalk.png")
		await _photo(camera, hull.call(0, -18, 120), hull.call(0, -10, 280), shots + "/wreck_speeder_lane.png")
		await _photo(camera, lv.call(30, 165, 165), lv.call(0, 146, 136), shots + "/wreck_landing_pad.png")
		await _photo(camera, lv.call(30, 139.5, 241), lv.call(30, 135, 220), shots + "/wreck_stern_ramp_deck.png")
	PlanetSphere.current = null
	quit(1 if failed else 0)


func _photo(camera: Camera3D, at: Vector3, target: Vector3, path: String) -> void:
	camera.position = at
	camera.look_at(target, ground.up_at(at))
	sand.snap_to(at)
	var map := sand.sphere.world_to_map(at)
	sand._apply("mid", sand._compute("mid", map))
	for i in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("WRECK SHOT ", path)
