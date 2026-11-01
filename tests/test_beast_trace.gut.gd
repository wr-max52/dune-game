extends GutTest
## Issue #220: the planet's beast, from the headless trace (scenes/beast_trace.gd):
## it is built from the home planet's data, named, out in the desert; it is a beetle-centipede (issue #266),
## rolls along the ground and farts; touching it kills the player, who wakes again;
## the player's hits set it chasing until they are 1 km away; it has 1000 health
## and stays dead; the locals and the AI characters know it by name.

const Reader := preload("res://tests/trace_reader.gd")
var t: Dictionary


func before_all() -> void:
	t = Reader.read("res://test_results/beast_trace.txt")


func _true(k: String) -> void:
	assert_eq(t.get(k), "true", k)


func test_built_from_the_planet() -> void:
	_true("BEAST_BUILT")
	_true("NAME_FROM_PLANET")
	assert_gte(int(t.get("SEGMENTS", 0)), 10, "a long body")
	assert_eq(int(t.get("LEGS", 0)), int(t.get("SEGMENTS", 0)) * 2, "a pair of legs per segment")
	assert_eq(int(t.get("MANDIBLES", 0)), 2)
	_true("DESERT_HIDE")
	assert_eq(int(t.get("HP", 0)), 1000)
	assert_gt(float(t.get("RADIUS", 0)), 2.5, "a large beast")
	assert_gt(int(t.get("HOME_FROM_TOWN_M", 0)), 300, "its home is out in the desert, not in town")


func test_the_locals_know_it() -> void:
	_true("BRIEF_NAMES_IT")
	_true("LORE_NAMES_IT")
	assert_gt(int(t.get("LORE_LINES", 0)), 2)
	_true("LOCAL_SPOKE_OF_IT")


func test_rolls() -> void:
	assert_gt(float(t.get("ROLLED_M", 0)), 3.0)
	_true("MOVED")
	_true("BODY_FOLLOWS")
	_true("LEGS_STEP")
	_true("TAIL_ON_GROUND")
	_true("ON_GROUND")


func test_does_not_go_round_in_circles() -> void:
	_true("TURNS_SMOOTHLY")
	_true("UNSTUCK")
	_true("WALKED_OUT")


func test_farts() -> void:
	_true("FARTED")
	_true("FART_SOUND")


func test_touch_kills() -> void:
	_true("DIED_ON_TOUCH")
	_true("BODY_KILLS")
	assert_eq(int(t.get("KILLS", 0)), 1)
	_true("WOKE")
	_true("WOKE_AWAY_FROM_BEAST")


func test_hurt_it_and_it_chases() -> void:
	_true("RAY_HITS_IT")
	_true("STRAY_BOLT_HURTS")
	_true("STRAY_BOLT_NO_CHASE")
	_true("PLAYER_HIT_CHASES")
	assert_gt(int(t.get("CHASE_CLOSED_M", 0)), 20, "it rolls at you")
	_true("CHASE_CAUGHT")
	_true("CHASE_STOPS_ON_KILL")
	_true("ALIVE_BEFORE_BLADE")
	_true("BLADE_HIT_CHASES")
	_true("GAVE_UP_AT_1KM")


func test_dies_and_stays_dead() -> void:
	_true("DEAD")
	assert_eq(int(t.get("HITS_TO_KILL", 0)), 40, "1000 health, less 10 + 12 + 20 taken earlier, at 24 a hit")
	_true("SLAIN_FLAG")
	_true("NOT_REBUILT")
	_true("LORE_AFTER")
	_true("BRIEF_AFTER_SLAIN")
	_true("DEAD_DOES_NOT_KILL")


func test_data() -> void:
	var d := JSON.parse_string(FileAccess.get_file_as_string("res://content/core/hazards/beast.json")) as Dictionary
	assert_false(d.has("town_pull"), "the beast neither seeks nor avoids the town")
	assert_eq(float(d.get("chase_give_up_m", 0)), 1000.0)
	var p := JSON.parse_string(FileAccess.get_file_as_string("res://content/core/planets/port_desert.json")) as Dictionary
	assert_ne(str(p.get("beast", {}).get("name", "")), "", "the home planet's beast has a name")
