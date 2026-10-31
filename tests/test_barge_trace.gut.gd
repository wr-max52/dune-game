extends GutTest
## Issue #269: the party barge, from the headless trace (scenes/barge_trace.gd):
## built from the planet's block, a band and a crowd on every deck, the cantina's
## club music, bought from the boss, driven slowly from the helm with the party
## going the whole time, and steerage partying too.

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
	assert_eq(int(t.get("BAND", 0)), 4)
	assert_gt(int(t.get("CROWD_TOP", 0)), 0)
	assert_gt(int(t.get("CROWD_LOWER", 0)), 0)
	assert_gt(int(t.get("CROWD_STEERAGE", 0)), 0)
	_true("CLUB")


func test_taking_it() -> void:
	_true("ON_TOP_DECK")
	_true("NEAR_BOSS")
	_true("HELM_LOCKED")
	_true("TOO_POOR")
	_true("BOUGHT")
	_true("OWNED_FLAG")
	_true("BOSS_BELOW_PARTYING")


func test_driving_while_partying() -> void:
	_true("TOOK_HELM")
	assert_gt(float(t.get("DROVE_M", 0)), 20.0)
	_true("SLOW")
	_true("PARTY_WHILE_DRIVING")
	_true("BAND_PLAYS_WHILE_DRIVING")
	_true("PLAYER_RIDES_AT_HELM")
	_true("STILL_ON_DECK")
	_true("STOPPED")


func test_below_deck() -> void:
	_true("IN_LOWER")
	_true("LOWER_PARTY")
	_true("IN_STEERAGE")
	_true("STEERAGE_PARTY")
	_true("STEERAGE_HEARS_CLUB")
	_true("BACK_UP_TOP")
	_true("TOP_STILL_PARTY")
