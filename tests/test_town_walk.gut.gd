extends GutTest
## M9: the headless town walk trace (scenes/town_walk_trace.gd), the machine proof
## that the town is built from data and every main route is walkable with real
## collision: spawn -> ramp -> cantina, cantina -> gate, gate -> cantina, back gap
## -> cantina, with no frame over the 50ms budget.

const TRACE := "res://test_results/town_walk_trace.txt"
const TownLayout := preload("res://src/systems/world/town_layout.gd")
const ROUTES := ["spawn_to_cantina", "cantina_to_gate", "gate_to_cantina", "backgap_to_cantina", "cantina_to_lookout"]


func _trace_lines() -> PackedStringArray:
	var f := FileAccess.open(TRACE, FileAccess.READ)
	if f == null:
		return PackedStringArray()
	var text := f.get_as_text()
	f.close()
	return text.split("\n", false)


func _trace_summary() -> Dictionary:
	var out := {}
	for l in _trace_lines():
		if l.begins_with("SUMMARY "):
			for kv in l.substr(8).split(" ", false):
				var p := kv.split("=")
				if p.size() == 2:
					out[p[0]] = p[1]
	return out


## Logged position rows: [frame, route, wp, x, y, z].
func _trace_rows() -> Array:
	var out: Array = []
	for l in _trace_lines():
		var parts := l.split(" ", false)
		if parts.size() == 7 and parts[6] == "OK" and parts[0].is_valid_int():
			out.append([int(parts[0]), parts[1], int(parts[2]), float(parts[3]), float(parts[4]), float(parts[5])])
	return out


func test_trace_exists() -> void:
	assert_true(FileAccess.file_exists(TRACE), "the trace exists after the trace run")
	assert_gt(_trace_lines().size(), 100, "the trace has rows")


func test_no_failures() -> void:
	for l in _trace_lines():
		assert_false(l.begins_with("FAIL"), l)


func test_all_routes_done() -> void:
	var done: Array = []
	for l in _trace_lines():
		if l.begins_with("ROUTE_DONE "):
			done.append(l.split(" ")[1])
	assert_eq(done.size(), 5, "five routes finished")
	for id in ROUTES:
		assert_true(done.has(id), "%s finished" % id)


func test_every_waypoint_reached() -> void:
	var t := TownLayout.new()
	t.load_town("port_town")
	for id in ROUTES:
		var n := 0
		for l in _trace_lines():
			if l.begins_with("WP_REACHED %s " % id):
				n += 1
		assert_eq(n, t.route_points_3d(id).size() - 1, "every waypoint of %s reached" % id)


func test_built_everything() -> void:
	var s := _trace_summary()
	assert_eq(int(s.get("boxes", 0)), 181)
	assert_eq(int(s.get("markers", 0)), 19)  # art pass 2: + three patrons at the bar


func test_frame_budget() -> void:
	assert_lt(float(_trace_summary().get("worst_ms", 999.0)), 50.0)


func test_player_used_the_ramp() -> void:
	var on_ramp := false
	for r in _trace_rows():
		if r[1] == "spawn_to_cantina" and r[4] > -5.5 and r[4] < -0.5:
			on_ramp = true
	assert_true(on_ramp, "the player walked up the slope out of the pit")


func test_player_never_fell() -> void:
	for r in _trace_rows():
		assert_gt(r[4], -6.5, "y at frame %d" % r[0])


## Art pass 2: the stair tower behind the bar is a real climb. The walk up the
## spiral ramp reaches the lookout floor, well above the cantina roof.
func test_player_climbed_to_the_lookout() -> void:
	var t := TownLayout.new()
	t.load_town("port_town")
	var floor_y := float(t.get_box("lookout").min[1])
	var top := -INF
	for r in _trace_rows():
		if r[1] == "cantina_to_lookout":
			top = maxf(top, r[4])
	assert_almost_eq(top, floor_y, 0.3, "stood on the lookout floor")

