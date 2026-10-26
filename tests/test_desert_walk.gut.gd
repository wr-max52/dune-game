extends GutTest
## The headless desert walk (scenes/desert_walk_trace.gd), with real physics: the
## town is seated on the desert. Out of the gate onto sand with no step, 700 m into
## the dunes and back with the collider following, sand outside the walls, the pit
## still a pit, and falling through the world still caught.

const TRACE := "res://test_results/desert_walk_trace.txt"

var t: Dictionary = {}


func before_all() -> void:
	var f := FileAccess.open(TRACE, FileAccess.READ)
	if f == null:
		return
	for l in f.get_as_text().split("\n", false):
		var kv := l.split("=", true, 1)
		if kv.size() == 2:
			t[kv[0]] = kv[1]


func test_trace_exists() -> void:
	assert_false(t.is_empty(), "run scripts/ci.sh (or the trace) first")
	assert_eq(t.get("TERRAIN"), "true")


func test_the_pit_is_still_a_pit() -> void:
	assert_almost_eq(float(t.get("SPAWN_Y", 99)), -6.0, 0.1, "spawn stands on the pit floor")
	assert_eq(t.get("SPAWN_ON_FLOOR"), "true")


func test_out_of_the_gate_onto_sand() -> void:
	assert_eq(t.get("REACHED_GATE"), "true")
	assert_eq(t.get("REACHED_DESERT_EXIT"), "true")
	assert_eq(t.get("EXIT_ON_FLOOR"), "true")


func test_into_the_dunes_and_back() -> void:
	assert_eq(t.get("REACHED_FAR"), "true", "700 m out")
	assert_gt(float(t.get("FAR_X", 0)), 690.0)
	assert_eq(t.get("FAR_ON_FLOOR"), "true", "standing on sand out there")
	assert_lt(float(t.get("FAR_GROUND_ERR", 9)), 0.3)
	assert_gt(float(t.get("DUNE_RANGE", 0)), 10.0, "real dunes on the way")
	assert_gte(int(t.get("RECENTERS_OUT", 0)), 4, "the collider followed")
	assert_eq(t.get("COLLIDER_UNDER_FAR"), "true")
	assert_eq(t.get("REACHED_BACK"), "true")
	assert_eq(t.get("BACK_ON_FLOOR"), "true")
	assert_almost_eq(float(t.get("BACK_Y", 9)), 0.0, 0.1, "back at floor level by the gate")
	assert_eq(t.get("BACK_INSIDE"), "true", "and in through the gate")


func test_never_fell_through_on_the_way() -> void:
	assert_eq(int(t.get("RESCUES_WALKING", 9)), 0, "the fall guard never had to act")
	assert_eq(int(t.get("SNAPS_WALKING", 9)), 0, "walking never forced a synchronous rebuild")
	# Short hops over dune crests are fine; a fall through the ground is not.
	assert_lt(float(t.get("AIR_FRAMES", 9999)), float(t.get("WALK_FRAMES", 1)) * 0.03)
	assert_lt(float(t.get("GROUND_ERR", 9)), 1.0, "feet stay on the (2 m) collider surface")


func test_no_hitch_walking_the_desert() -> void:
	assert_lt(float(t.get("WORST_MS", 999)), 50.0, "no frame over the 50 ms budget")
	# The rebuild stops at 2 ms of work a frame (one ~1 ms row past it at most); the
	# rest is headroom for a loaded CI box, where wall-clock time jumps around.
	assert_lt(float(t.get("WORST_REBUILD_STEP_MS", 999)), 25.0, "collider rebuild is spread out")


func test_sand_outside_the_walls() -> void:
	assert_eq(t.get("NORTH_OUTSIDE_ON_FLOOR"), "true", "outside the north wall there is ground")
	assert_almost_eq(float(t.get("NORTH_OUTSIDE_Y", 9)), 0.0, 0.1, "at the town's floor level")


func test_falling_through_the_world_is_caught() -> void:
	assert_eq(t.get("STOOD_IN_DESERT"), "true")
	assert_lt(float(t.get("STAND_ERR", 9)), 0.3)
	assert_eq(int(t.get("FELL_RESCUED", 0)), 1)
	assert_eq(t.get("RESCUED_ON_SAND"), "true", "put back where they stood in the desert")
