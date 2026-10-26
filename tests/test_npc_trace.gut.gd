extends GutTest
## NPCs on foot with real physics (scenes/npc_trace.gd): the navmesh bakes off the
## main thread, the gate guards walk a patrol, across town, into the pit and back
## on the player's movement code without getting stuck, their senses see, miss,
## are blocked by the watchtower, hear and forget, and a real bolt hurts one until
## it drops. No frame over the 50 ms budget.

const TRACE := "res://test_results/npc_trace.txt"

var kv := {}


func before_all() -> void:
	var f := FileAccess.open(TRACE, FileAccess.READ)
	if f == null:
		return
	for l in f.get_as_text().split("\n", false):
		var i := l.find("=")
		if i > 0 and not l.begins_with("#"):
			kv[l.substr(0, i)] = l.substr(i + 1)
	f.close()


func _f(key: String) -> float:
	return float(kv.get(key, "nan"))


func _b(key: String) -> bool:
	return str(kv.get(key, "")) == "true"


func test_trace_ran_clean() -> void:
	assert_true(FileAccess.file_exists(TRACE), "trace exists (run scenes/npc_trace.gd)")
	assert_eq(str(kv.get("FAILED", "")), "false", "no FAIL lines")
	assert_eq(int(_f("NPCS")), 2, "both gate guards spawned")


func test_navmesh_bakes_off_the_main_thread() -> void:
	assert_true(_b("NAV_READY"))
	assert_gt(_f("NAV_POLYS"), 200.0)
	assert_gt(_f("NAV_PATH_GATE_TO_CANTINA_POINTS"), 1.0, "a path from the gate to the cantina")
	assert_lt(_f("NAV_PATH_TO_PIT_END_Y"), -5.0, "a path down into the pit")
	assert_true(_b("NAV_NOT_INSIDE_BARRACKS"), "no floor inside a building")
	assert_lt(_f("WORST_FRAME_MS"), 50.0, "the bake never stalls a frame past budget")


func test_patrol_and_back_to_post() -> void:
	for i in 3:
		var t := _f("PATROL_LEG_%d_S" % i)
		assert_between(t, 0.0, 15.0, "patrol leg %d" % i)
	assert_lt(_f("POST_DIST"), 1.0, "back on the post")
	assert_lt(_f("POST_FACING_ERR_DEG"), 5.0, "facing the way it was posted")


func test_long_walks_do_not_get_stuck() -> void:
	assert_gt(_f("LONG_OUT_S"), 0.0, "reached the cantina")
	assert_gt(_f("LONG_BACK_S"), 0.0, "came back")
	assert_lt(_f("LONG_OUT_WALKED"), _f("LONG_PATH_LEN") * 1.15, "walked about the path, not a wander")
	assert_gt(_f("PIT_DOWN_S"), 0.0, "ran down into the pit")
	assert_lt(_f("PIT_MIN_Y"), -5.5, "actually reached the pit floor")
	assert_gt(_f("PIT_UP_S"), 0.0, "and back up the ramp")
	assert_eq(_f("PATH_FAILURES"), 0.0, "every path to a reachable place was found")
	assert_true(_b("UNREACHABLE_FLAGGED"), "an unreachable goal is reported")


func test_sees_what_is_in_front() -> void:
	assert_true(_b("FRONT_VISIBLE"))
	assert_between(_f("FRONT_NOTICE_S"), 0.2, 2.0, "noticed in about a second at 15 m")
	assert_between(_f("RAYS_PER_S_IN_VIEW"), 3.0, 6.0, "line of sight checked about 5 times a second")


func test_misses_what_it_should_miss() -> void:
	assert_false(_b("SIDE_IN_CONE"), "90 degrees off is out of view")
	assert_eq(_f("SIDE_AWARENESS"), 0.0)
	assert_false(_b("CROUCH_25M_VISIBLE"), "crouched at 25 m is too far to see")
	assert_true(_b("TOWER_IN_CONE"), "looking right at the tower")
	assert_false(_b("TOWER_VISIBLE"), "the watchtower blocks the view")
	assert_eq(_f("TOWER_AWARENESS"), 0.0)


func test_feels_close_and_spots_weapons() -> void:
	assert_true(_b("CLOSE_BEHIND_VISIBLE"), "someone right behind is felt")
	assert_lt(_f("ARMED_25M_NOTICE_S"), _f("UNARMED_25M_NOTICE_S"), "a drawn weapon is noticed faster")
	assert_true(_b("SAW_WEAPON"))


func test_forgets() -> void:
	assert_between(_f("FORGET_S"), 7.0, 12.0, "lets go about forget_s after losing sight")


func test_hears_shots() -> void:
	assert_true(_b("HEARD_30M"))
	assert_true(_b("HEARD_POS_OK"), "knows where the shot came from")
	assert_almost_eq(_f("HEARD_AWARENESS"), 0.6, 0.01)
	assert_false(_b("HEARD_80M"), "out of earshot")


func test_takes_a_bolt_and_drops() -> void:
	assert_eq(_f("BOLT_DAMAGE"), 15.0, "a real bolt did its damage")
	assert_eq(_f("FLINCH_HITS"), 1.0)
	assert_true(_b("DEAD"))
	assert_false(_b("DEAD_BLOCKS_RAYS"), "a body does not stop bolts or sight")
	assert_true(_b("DEAD_STAYS_PUT"))
	assert_true(_b("DEAD_IGNORES_ORDERS"))
