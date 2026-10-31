extends GutTest
## Issue #269: the party barge, from the headless trace (scenes/barge_trace.gd):
## built from the planet's block, the cantina's band on top and a DJ below, a
## crowd on every deck, the cantina's club music, bought from the boss, and
## steerage partying too.
## #269 cleanup: a smooth drift (no shaking), everyone killable and back later
## with standing untouched, the control panel and autopilot with the player free
## to walk the deck, a dead stop against anything, and a fireball into the beast.

const Reader := preload("res://tests/trace_reader.gd")
var t: Dictionary


func before_all() -> void:
	t = Reader.read("res://test_results/barge_trace.txt")


func _true(k: String) -> void:
	assert_eq(t.get(k), "true", k)


func test_a_planet_component() -> void:
	_true("BARGE_BUILT")
	_true("NONE_WITHOUT_BLOCK")
	assert_ne(str(t.get("NAME", "")), "")
	assert_ne(str(t.get("BOSS", "")), "")
	assert_gt(int(t.get("HOME_FROM_TOWN_M", 0)), 200, "out in the desert")


func test_the_party() -> void:
	assert_eq(int(t.get("BAND", 0)), 3)
	assert_eq(int(t.get("BAND_ON_TOP", 0)), 2)
	assert_eq(int(t.get("DJ_BELOW", 0)), 1)
	assert_gt(int(t.get("CROWD_TOP", 0)), 0)
	assert_gt(int(t.get("CROWD_LOWER", 0)), 0)
	assert_gt(int(t.get("CROWD_STEERAGE", 0)), 0)
	_true("CLUB")


func test_no_shaking() -> void:
	_true("DRIFT_SMOOTH")


func test_people_killable_and_back() -> void:
	_true("HURT_NOT_DEAD")
	_true("KILLED")
	_true("BODY_DOWN")
	_true("HIT_OFF_WHEN_DEAD")
	_true("GUARD_KILLED")
	_true("RESPAWNED")
	_true("HIT_BACK")
	_true("BAND_DEAD_MUSIC_OFF")
	_true("BAND_BACK_MUSIC_ON")
	_true("STANDING_UNCHANGED")
	_true("STANDING_STILL_UNCHANGED")


func test_taking_it() -> void:
	_true("ON_TOP_DECK")
	_true("NEAR_BOSS")
	_true("PANEL_LOCKED")
	_true("TOO_POOR")
	_true("BOUGHT")
	_true("OWNED_FLAG")
	_true("BOSS_BELOW_PARTYING")


func test_autopilot() -> void:
	_true("NEAR_CONSOLE")
	_true("TOOK_CONSOLE")
	_true("LOCKED_AT_CONSOLE")
	_true("DIAL_STARBOARD")
	_true("STILL_PARKED")
	_true("ENGAGED")
	_true("WALK_FREE")
	assert_gt(float(t.get("DROVE_M", 0)), 20.0)
	_true("SLOW")
	_true("STILL_ON_AUTOPILOT")
	_true("ON_COURSE")
	_true("GANGPLANK_UP")
	_true("PARTY_WHILE_CRUISING")
	_true("PLAYER_RIDES_ON_DECK")


func test_stops_against_things() -> void:
	_true("STOPPED_AGAINST")
	_true("STOPPED_SHORT")
	_true("GANGPLANK_DOWN_WHEN_STOPPED")
	_true("OFF_AGAIN")
	_true("ALL_STOP")


func test_below_deck() -> void:
	_true("IN_LOWER")
	_true("LOWER_PARTY")
	_true("IN_STEERAGE")
	_true("STEERAGE_PARTY")
	_true("STEERAGE_HEARS_CLUB")
	_true("BACK_UP_TOP")
	_true("TOP_STILL_PARTY")


func test_beast_blows_it_up() -> void:
	if t.get("BEAST_HERE") != "true":
		pass_test("no beast on this planet")
		return
	_true("EXPLODED")
	_true("PLAYER_HURT")
	_true("GONE")
	_true("MUSIC_OFF_WRECKED")
	_true("REBUILT")
	_true("REBUILT_AT_HOME")
	_true("STILL_YOURS")
	_true("MUSIC_BACK")
