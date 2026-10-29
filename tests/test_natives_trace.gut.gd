extends GutTest
## Issue #96: the first milestone from the headless trace (scenes/natives_trace.gd):
## a friendly food-for-quartz trade, a sand pig hunt, a hostile attack, a 5-minute
## survival that ends in trade, and a kill that locks a pack hostile.

const Reader := preload("res://tests/trace_reader.gd")
var t: Dictionary


func before_all() -> void:
	t = Reader.read("res://test_results/natives_trace.txt")


func _true(k: String, why: String = "") -> void:
	assert_eq(t.get(k), "true", why if why != "" else k)


func test_packs() -> void:
	_true("NATIVES_BUILT")
	assert_eq(t.get("PEOPLE"), "dune_nomads")
	assert_eq(int(t.get("PACKS", 0)), 2)
	assert_between(int(t.get("FRIENDLY_SIZE", 0)), 10, 20)
	assert_gt(int(t.get("CHILDREN", 0)), 0)
	_true("CHILD_SMALLER")
	_true("NO_RIFLES")
	assert_gt(int(t.get("PIGS", 0)), 0)


func test_food_for_quartz() -> void:
	_true("FOOD_STALL")
	assert_eq(int(t.get("FOOD_BOUGHT", 0)), 3)
	_true("FRIENDLY_GREETS")
	_true("TRADE_PACK_IN_REACH")
	assert_eq(t.get("TRADE"), "traded")
	assert_gt(int(t.get("QUARTZ", 0)), 0)
	assert_gt(int(t.get("QUARTZ_SOLD_FOR", 0)), 0)


func test_sand_pig() -> void:
	_true("PIG_DEAD")
	_true("BUTCHER_PROMPT")
	assert_gt(int(t.get("FOOD_FROM_PIG", 0)), 0)


func test_hostile_and_won_over() -> void:
	_true("HORN")
	_true("HOSTILE_ATTACKS")
	_true("PLAYER_HURT")
	_true("WON_OVER", "five minutes, nobody killed")
	assert_between(float(t.get("SURVIVED_S", 0)), 299.0, 320.0)
	assert_eq(int(t.get("HOSTILE_KILLS", 1)), 0)
	assert_eq(t.get("TRADE_AFTER_WIN"), "traded")


func test_a_kill_locks_it() -> void:
	_true("KILLED_ONE")
	_true("LOCKED")
	_true("NEVER_FRIENDLY")
	_true("SAVED")
