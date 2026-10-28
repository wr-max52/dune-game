extends GutTest
## Issue #15: names in the real scenes, from the headless trace
## (scenes/names_trace.gd). Everyone and everything that spawns gets a name, the
## names hold across a save and a new game, and they reach the cantina owner.

const Reader := preload("res://tests/trace_reader.gd")
var t: Dictionary


func before_all() -> void:
	t = Reader.read("res://test_results/names_trace.txt")


func _true(k: String, why: String = "") -> void:
	assert_eq(t.get(k), "true", why if why != "" else k)


func test_trace_exists() -> void:
	assert_false(t.is_empty(), "run scenes/names_trace.gd first (ci.sh does)")


func test_every_guard_is_named_on_spawn() -> void:
	assert_gt(int(t.get("GUARDS", 0)), 0)
	_true("GUARDS_ALL_NAMED")
	_true("GUARDS_HAVE_RANKS", "a Remnant rank from the library")
	_true("GUARDS_UNIQUE")
	_true("DEBUG_LINE_NAMED", "F4 shows who they are")


func test_no_name_floats_over_them_issue_65() -> void:
	assert_eq(t.get("NAMEPLATE_UP_CLOSE"), "false", "enemies show a health bar, not a name")
	assert_eq(t.get("NAMEPLATE_FAR_AWAY"), "false")
	assert_eq(t.get("HEALTH_BAR_CALM"), "false", "a calm, unhurt guard shows no bar")


func test_the_town_and_planet_are_named() -> void:
	assert_ne(str(t.get("TOWN_NAME", "")), "")
	assert_ne(str(t.get("PLANET_NAME", "")), "")
	assert_eq(t.get("PLACE_CARD"), "%s  ·  %s" % [t.get("TOWN_NAME"), t.get("PLANET_NAME")])
	assert_eq(t.get("SPACE_PLANET"), t.get("PLANET_NAME"), "the same planet from orbit")


func test_your_ship_and_gear_are_named() -> void:
	assert_ne(str(t.get("VESSEL_NAME", "")), "")
	assert_true(str(t.get("BOARD_PROMPT", "")).ends_with(str(t.get("VESSEL_NAME"))))
	_true("HUD_SHOWS_VESSEL")
	assert_eq(t.get("SPACE_VESSEL_NAME"), t.get("VESSEL_NAME"), "the same ship in space")
	assert_eq(t.get("JETPACK_SHOWN"), "Jetpack (%s)" % t.get("JETPACK_MODEL"))


func test_authored_names_stay_authored() -> void:
	assert_eq(t.get("CANTINA_OWNER_RESERVED"), "Oda Vell")


func test_the_cantina_owner_knows_the_names() -> void:
	_true("BRIEF_HAS_TOWN")
	_true("BRIEF_HAS_PLANET")
	_true("BRIEF_HAS_GUARD")


func test_names_survive_a_reload_and_repeat_for_the_same_seed() -> void:
	_true("RELOAD_SAME_GUARDS")
	_true("RELOAD_SAME_TOWN")
	_true("RELOAD_SAME_VESSEL")
	_true("NEW_GAME_SAME_NAMES", "deterministic: same seed, same world")
	_true("OTHER_SEED_DIFFERENT")


func test_pilots_are_named_in_space() -> void:
	assert_gt(int(t.get("PILOTS_NAMED", 0)), 6, "two sorties' worth")
	_true("PILOTS_UNIQUE", "new pilots each sortie, never a repeat")
	_true("CALLSIGNS_UNIQUE")
	assert_true(str(t.get("KILL_CALLOUT", "")).begins_with("\""), "a kill calls out the callsign and name")


func test_a_crowd_of_5000_is_all_different() -> void:
	assert_eq(int(t.get("CROWD_NAMED", 0)), 5000)
	_true("CROWD_UNIQUE")
	assert_lt(float(t.get("CROWD_MS", 99999)), 10000.0, "well under a millisecond or two each")
	assert_gt(int(t.get("LIBRARY_TERMS", 0)), 2000)
