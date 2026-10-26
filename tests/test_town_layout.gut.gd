extends GutTest
## M9: the port town data and its validator. The positive tests prove the shipped
## town is valid; the negative tests prove each rule actually catches its break.

const TownLayout := preload("res://src/systems/world/town_layout.gd")
const CoreContent := preload("res://src/systems/dataload/core_content.gd")


func _town() -> TownLayout:
	var t := TownLayout.new()
	assert_true(t.load_town("port_town"), "port_town loads from content/core")
	return t


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
	assert_eq(t.boxes().size(), 112)
	assert_eq(t.markers().size(), 18)
	assert_eq(t.routes().size(), 4)
	assert_eq(t.zones().size(), 8)


func test_town_validates_clean() -> void:
	var errs := _town().validate()
	for e in errs:
		gut.p(str(e))
	assert_eq(errs, [], "port_town has no validation errors")


func test_required_markers_exist() -> void:
	var t := _town()
	for id in ["player_spawn", "gate", "back_gap", "cantina_door", "bar_front", "bartender", "fixer"]:
		assert_false(t.get_marker(id).is_empty(), "marker %s exists" % id)


func test_npc_markers_match_data_layer() -> void:
	var t := _town()
	var cc := CoreContent.new()
	cc.load_from()
	for m in t.markers_with_role("npc"):
		assert_false(cc.get_npc(str(m.npc)).is_empty(), "npc %s is in the data layer" % m.npc)


func test_spawn_is_on_pit_floor() -> void:
	assert_eq(_town().spawn_pos().y, -6.0)


func test_five_trooper_posts() -> void:
	assert_eq(_town().markers_with_role("trooper_post").size(), 5)


func test_route_lengths_match_reference() -> void:
	var t := _town()
	assert_almost_eq(t.route_length("gate_to_cantina"), 234.5, 0.1)
	assert_almost_eq(t.route_length("spawn_to_cantina"), 162.3, 0.1)
	assert_almost_eq(t.route_length("backgap_to_cantina"), 140.0, 0.1)


func test_ramp_ne_top_edge_meets_ground() -> void:
	var rt := TownLayout.ramp_transform(_town().get_box("ramp_ne"))
	var b: Basis = rt.basis
	var top: Vector3 = rt.center + b.y * 0.2 + b.x * (rt.size.x / 2.0)
	assert_almost_eq(top.x, 18.0, 0.01)
	assert_almost_eq(top.y, 0.0, 0.01)
	assert_almost_eq(top.z, 18.5, 0.01)


func test_ramp_sw_top_edge_meets_ground() -> void:
	var rt := TownLayout.ramp_transform(_town().get_box("ramp_sw"))
	var b: Basis = rt.basis
	var top: Vector3 = rt.center + b.y * 0.2 - b.x * (rt.size.x / 2.0)
	assert_almost_eq(top.x, -18.0, 0.01)
	assert_almost_eq(top.y, 0.0, 0.01)
	assert_almost_eq(top.z, -18.5, 0.01)


func test_ramp_angle_is_walkable() -> void:
	var t := _town()
	for id in ["ramp_ne", "ramp_sw"]:
		var rt := TownLayout.ramp_transform(t.get_box(id))
		assert_lt(rad_to_deg(float(rt.angle)), 45.0, "%s is walkable" % id)


func test_catches_overlap() -> void:
	var errs := _bad(func(d): d.boxes[idx_of(d, "shop_2")].min[0] = 45.0)
	assert_true(_has_rule(errs, "V5"), "V5 caught: %s" % str(errs))


func test_catches_outside_zone() -> void:
	var errs := _bad(func(d): d.boxes[idx_of(d, "stall_r1_1")].min[0] = 30.0)
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
