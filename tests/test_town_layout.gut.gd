extends GutTest
## M9: the port town data and its validator. The positive tests prove the shipped
## town is valid; the negative tests prove each rule actually catches its break.

const TownLayout := preload("res://src/systems/world/town_layout.gd")
const CoreContent := preload("res://src/systems/dataload/core_content.gd")


func _town() -> TownLayout:
	var t := TownLayout.new()
	assert_true(t.load_town("port_town"), "port_town loads from content/core")
	return t


## Issue #237: port_town is its planet's saved layout, and either layout loads.
func test_port_town_is_a_saved_layout() -> void:
	var t := _town()
	assert_eq(str(t.data.id), "port_town")
	assert_ne(str(t.data.get("layout", "")), "", "built to a named layout")
	var sq := TownLayout.new()
	assert_true(sq.load_town("port_town", "port_square"), "port_square loads by name")
	assert_eq(int(sq.data.size), 50)
	assert_eq(sq.validate(), [], "port_square is valid")
	assert_false(TownLayout.new().load_town("port_town", "no_such_layout"), "an unknown layout is no town")


## Deep-copy the real town, break one thing, return the validator errors.
func _bad(mutator: Callable) -> Array:
	var t := _town()
	var copy: Dictionary = t.data.duplicate(true)
	mutator.call(copy)
	var t2 := TownLayout.new()
	t2.load_from_dict(copy)
	return t2.validate()


func _has_rule(errs: Array, rule: String) -> bool:
	for e in errs:
		if String(e).begins_with(rule):
			return true
	return false


func idx_of(d: Dictionary, id: String, list: String = "boxes") -> int:
	var arr: Array = d[list]
	for i in arr.size():
		if str(arr[i].id) == id:
			return i
	return -1


func test_town_loads_with_expected_counts() -> void:
	var t := _town()
	assert_eq(t.boxes().size(), 182)   # issue #76: + the barracks landing pad
	assert_eq(t.markers().size(), 42)  # locals: five walkers and four stall keepers; art pass 2: + three patrons at the bar; issue #58: + T-89; + three roof riflemen; issue #261: + the band of three and eight club patrons
	assert_eq(t.routes().size(), 17)   # M15: + patrol loops; locals: + five walkers' loops; art pass 2: + the climb to the lookout; issue #261: + three club strolls
	assert_eq(t.zones().size(), 8)


func test_town_validates_clean() -> void:
	var errs := _town().validate()
	for e in errs:
		gut.p(str(e))
	assert_eq(errs, [], "port_town has no validation errors")


func test_required_markers_exist() -> void:
	var t := _town()
	for id in ["player_spawn", "gate", "back_gap", "cantina_door", "bar_front", "cantina_owner", "fixer"]:
		assert_false(t.get_marker(id).is_empty(), "marker %s exists" % id)


func test_no_gray_homes_on_the_desert_port() -> void:
	var homes: Array = _town().boxes().filter(func(b):
		return str(b.get("id", "")).begins_with("cantina_home_"))
	assert_eq(homes, [], "the gray homes are the station's (#114), not the port's")


func test_npc_markers_match_data_layer() -> void:
	var t := _town()
	var cc := CoreContent.new()
	cc.load_from()
	for m in t.markers_with_role("npc"):
		assert_false(cc.get_npc(str(m.npc)).is_empty(), "npc %s is in the data layer" % m.npc)


func test_spawn_is_on_pit_floor() -> void:
	assert_eq(_town().spawn_pos().y, -6.0)


func test_eight_trooper_posts() -> void:
	assert_eq(_town().markers_with_role("trooper_post").size(), 8)


func test_three_riflemen_on_the_barracks_roof() -> void:
	var t := _town()
	var hall: Dictionary = t.get_box("barracks_hall")
	var on_roof := t.markers_with_role("trooper_post").filter(func(m): return str(m.soldier) == "roof_rifleman")
	assert_eq(on_roof.size(), 3)
	for m in on_roof:
		var p: Vector3 = t.marker_pos(str(m.id))
		assert_almost_eq(p.y, float(hall.max[1]), 0.01, "%s stands on the hall roof" % m.id)
		assert_true(p.x > float(hall.min[0]) and p.x < float(hall.max[0]) and p.z > float(hall.min[2]) and p.z < float(hall.max[2]),
			"%s is inside the roof's edge" % m.id)


func test_route_lengths_match_reference() -> void:
	var t := _town()
	# Art pass 2: round the cantina stage instead of across it, and round the bigger pit.
	assert_almost_eq(t.route_length("gate_to_cantina"), 255.2, 0.1)
	assert_almost_eq(t.route_length("spawn_to_cantina"), 218.2, 0.1)
	assert_almost_eq(t.route_length("backgap_to_cantina"), 150.7, 0.1)


func test_ramp_ne_top_edge_meets_ground() -> void:
	var rt := TownLayout.ramp_transform(_town().get_box("ramp_ne"))
	var b: Basis = rt.basis
	var top: Vector3 = rt.center + b.y * 0.2 + b.x * (rt.size.x / 2.0)
	assert_almost_eq(top.x, 28.0, 0.01)   # art pass 2: the round pit's east ramp
	assert_almost_eq(top.y, 0.0, 0.01)
	assert_almost_eq(top.z, 0.0, 0.01)


func test_ramp_sw_top_edge_meets_ground() -> void:
	var rt := TownLayout.ramp_transform(_town().get_box("ramp_sw"))
	var b: Basis = rt.basis
	var top: Vector3 = rt.center + b.y * 0.2 - b.x * (rt.size.x / 2.0)
	assert_almost_eq(top.x, -28.0, 0.01)   # and its west ramp
	assert_almost_eq(top.y, 0.0, 0.01)
	assert_almost_eq(top.z, 0.0, 0.01)


func test_ramp_angle_is_walkable() -> void:
	var t := _town()
	for id in ["ramp_ne", "ramp_sw"]:
		var rt := TownLayout.ramp_transform(t.get_box(id))
		assert_lt(rad_to_deg(float(rt.angle)), 45.0, "%s is walkable" % id)


func test_catches_overlap() -> void:
	var errs := _bad(func(d): d.boxes[idx_of(d, "shop_2")].min[0] = 45.0)
	assert_true(_has_rule(errs, "V5"), "V5 caught: %s" % str(errs))


func test_catches_outside_zone() -> void:
	var errs := _bad(func(d): d.boxes[idx_of(d, "stall_n1")].min[0] = 30.0)
	assert_true(_has_rule(errs, "V4"), "V4 caught: %s" % str(errs))


func test_catches_blocked_marker() -> void:
	var errs := _bad(func(d): d.markers[idx_of(d, "fixer", "markers")].pos = [-65.0, 0.0, 10.0])
	assert_true(_has_rule(errs, "V6"), "V6 caught: %s" % str(errs))


func test_catches_unsupported_marker() -> void:
	var errs := _bad(func(d): d.markers[idx_of(d, "vendor_1", "markers")].pos[1] = 3.0)
	assert_true(_has_rule(errs, "V7"), "V7 caught: %s" % str(errs))


func test_catches_blocked_route() -> void:
	var errs := _bad(func(d): d.boxes.append({ "id": "junk", "zone": "main_street", "kind": "solid",
		"min": [60.0, 0.0, -2.0], "max": [62.0, 2.0, 2.0] }))
	assert_true(_has_rule(errs, "V8"), "V8 caught: %s" % str(errs))


func test_catches_low_overhead() -> void:
	var errs := _bad(func(d): d.boxes[idx_of(d, "gate_lintel")].min[1] = 1.5)
	assert_true(_has_rule(errs, "V3"), "V3 caught: %s" % str(errs))


func test_catches_duplicate_id() -> void:
	var errs := _bad(func(d): d.markers[idx_of(d, "vendor_2", "markers")].id = "vendor_1")
	assert_true(_has_rule(errs, "V1"), "V1 caught: %s" % str(errs))


func test_chunks_are_port_kind() -> void:
	var chunks: Array = _town().data.chunks
	assert_eq(chunks.size(), 2)
	var centers: Array = []
	for c in chunks:
		assert_eq(str(c.kind), "port")
		centers.append(float(c.center))
	centers.sort()
	assert_eq(centers, [-50.0, 50.0])


## Art pass 2: the residential districts are not a grid any more. Huts on the
## market side, towers (with rooftop bridges) on the barracks side.
func test_neighbourhoods_are_not_a_grid() -> void:
	var t := _town()
	var huts: Array = []
	var towers: Array = []
	var bridges := 0
	for b in t.boxes():
		var look := str(b.get("look", ""))
		if str(b.zone) == "residential_w" and look.begins_with("hut_"):
			huts.append(b)
		elif str(b.zone) == "residential_e" and look.begins_with("tower_"):
			towers.append(b)
		elif str(b.zone) == "residential_e" and look == "bridge":
			bridges += 1
			assert_eq(str(b.kind), "overhead", "%s is walked over, not into" % b.id)
	assert_gt(huts.size(), 30, "plenty of huts by the market")
	assert_gt(towers.size(), 12, "a tower block by the barracks")
	assert_gt(bridges, 4, "with bridges between the roofs")
	# Off-grid: many different row and column starts.
	var xs := {}
	var zs := {}
	for b in huts:
		xs[float(b.min[0])] = true
		zs[float(b.min[2])] = true
	assert_gt(xs.size(), 20, "hut columns do not line up")
	assert_gt(zs.size(), 8, "hut rows do not line up")
	var hut_h := 0.0
	var tower_h := 0.0
	for b in huts:
		hut_h = maxf(hut_h, float(b.max[1]))
	for b in towers:
		tower_h += float(b.max[1]) / towers.size()
	assert_lte(hut_h, 5.0, "huts stay low")
	assert_gt(tower_h, 11.0, "towers stand tall")


func test_every_building_has_a_door_side() -> void:
	for b in _town().boxes():
		if str(b.get("look", "")) in ["", "bridge", "cistern", "stage", "stair_tower", "lookout", "crates", "stall_back"]:
			continue
		assert_true(str(b.get("face", "")) in ["+x", "-x", "+z", "-z"], "%s has a door side" % b.id)
		if str(b.get("shape", "")) == "round":
			assert_almost_eq(float(b.max[0]) - float(b.min[0]), float(b.max[2]) - float(b.min[2]), 0.01, "%s: round on a square footprint" % b.id)


## Art pass 2: the cantina has a stage in the middle that the walk routes go
## round, and patrons on the bar stools facing the cantina owner.
func test_cantina_stage_and_patrons() -> void:
	var t := _town()
	var stage := t.get_box("cantina_stage")
	assert_false(stage.is_empty(), "the stage exists")
	assert_eq(str(stage.kind), "cover", "you cannot walk through it")
	var roof := t.get_box("cantina_roof")
	assert_gte(float(roof.min[1]), 8.0, "a tall hall")
	# The bar stools (patron_1, _2, ...) face the cantina owner; issue #261's club
	# patrons stand at tables and booths or stroll, facing their own way.
	var patrons := 0
	for m in t.markers():
		var id := str(m.id)
		if id.begins_with("patron_") and id.trim_prefix("patron_").is_valid_int():
			patrons += 1
			var f := Vector3(float(m.face[0]), float(m.face[1]), float(m.face[2]))
			assert_almost_eq(f.distance_to(t.marker_pos("cantina_owner")), 0.0, 0.5, "%s faces the cantina owner" % m.id)
		elif id.begins_with("patron_"):
			assert_true(m.has("face") or m.has("patrol"), "%s faces somewhere or strolls" % id)
	assert_gte(patrons, 3, "locals at the bar")


## Art pass 2: a round pit with four bays. The player's ship is on the launch
## pad and the spawn is beside it. Issue #58: two bays hold other flyable ships
## (the round freighter among them) and the fourth is an empty pad.
func test_round_pit_with_three_ships_and_an_empty_pad() -> void:
	var t := _town()
	var bowl := t.get_box("pit_bowl")
	assert_eq(str(bowl.kind), "bowl")
	assert_true(bool(bowl.get("hollow", false)), "other boxes sit inside it")
	var ships: Array = []
	for b in t.boxes():
		if str(b.kind) == "ship":
			ships.append(b)
	assert_eq(ships.size(), 3, "three ships in the pit")
	var kinds := {}
	for b in ships:
		if b.has("ship"):
			kinds[str(b.ship)] = true
	assert_eq(kinds.keys().size(), 2, "two other flyable ships, all different (issue #43)")
	assert_true(kinds.has("freighter"), "the round one stays")
	var pad := t.get_box("spare_pad")
	assert_eq(str(pad.get("kind", "")), "pad", "the fourth bay is an empty pad")
	assert_false(pad.has("ship"), "nothing parked on it until you buy a ship")
	ships.append(pad)
	var own := t.get_box("ship")
	var c := Vector3((float(own.min[0]) + float(own.max[0])) * 0.5, -6.0, (float(own.min[2]) + float(own.max[2])) * 0.5)
	assert_lt(t.spawn_pos().distance_to(c), 10.0, "the player spawns by their own ship")
	var r := (float(bowl.max[0]) - float(bowl.min[0])) * 0.5
	for b in ships:
		for x in [float(b.min[0]), float(b.max[0])]:
			for z in [float(b.min[2]), float(b.max[2])]:
				assert_lt(Vector2(x, z).length(), r, "%s fits inside the round wall" % b.id)

