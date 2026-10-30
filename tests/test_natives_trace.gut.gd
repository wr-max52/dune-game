extends GutTest
## Issue #96: the first milestone from the headless trace (scenes/natives_trace.gd):
## a friendly food-for-quartz trade, a sand pig hunt, a hostile attack, a 5-minute
## survival that ends in trade, and a kill that locks a pack hostile. Then the
## camps: each pack starts at its own, a rest in a friendly tent, a chest taken
## unseen and then seen, and a camp shot down that comes back.

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
	assert_between(float(t.get("ATTACK_S", 0)), 299.0, 320.0, "five minutes from the horn")
	assert_between(float(t.get("SURVIVED_S", 0)), 280.0, 320.0, "counted from the first blow, a few seconds after the horn")
	assert_eq(int(t.get("HOSTILE_KILLS", 1)), 0)
	assert_eq(t.get("TRADE_AFTER_WIN"), "traded")


func test_a_kill_locks_it() -> void:
	_true("KILLED_ONE")
	_true("LOCKED")
	_true("NEVER_FRIENDLY")
	_true("SAVED")


func test_camps() -> void:
	assert_eq(int(t.get("CAMPS", 0)), 2)
	_true("STARTS_AT_CAMP")
	_true("CHIEF_MELEE")
	_true("NO_VOICE")


func test_rest_in_a_friendly_tent() -> void:
	_true("REST_TENT")
	_true("RESTED")
	_true("HEALED")
	assert_gt(float(t.get("HOURS_SLEPT", 0)), 0.5)


func test_chests_and_stealing() -> void:
	assert_gt(int(t.get("CHEST_ITEMS", 0)), 0)
	_true("CHEST_EMPTY_AFTER")
	_true("UNSEEN_STILL_FRIENDLY")
	_true("SEEN_STEALING_TURNS")
	_true("SEEN_NOT_LOCKED")


func test_rocks_and_clubs() -> void:
	assert_gt(int(t.get("ROCKS_THROWN", 0)), 0)
	assert_gt(int(t.get("SWINGS_LANDED", 0)), 0)


func test_a_wrecked_camp_comes_back() -> void:
	_true("CAMP_WRECKED")
	_true("CAMP_STILL_DOWN")
	_true("CAMP_BACK")
