extends GutTest
## Issue #220: the desert blob, from the headless trace (scenes/blob_trace.gd): it
## is built out in the home planet's desert, it is purple, it rolls along the
## ground, it farts, and touching it kills the player, who then wakes again.

const Reader := preload("res://tests/trace_reader.gd")
var t: Dictionary


func before_all() -> void:
	t = Reader.read("res://test_results/blob_trace.txt")


func _true(k: String) -> void:
	assert_eq(t.get(k), "true", k)


func test_built_in_the_desert() -> void:
	_true("BLOB_BUILT")
	_true("PURPLE")
	assert_gt(float(t.get("RADIUS", 0)), 2.5, "a large blob")
	assert_gt(int(t.get("HOME_FROM_TOWN_M", 0)), 300, "its home is out in the desert, not in town")


func test_rolls() -> void:
	assert_gt(float(t.get("ROLLED_M", 0)), 3.0)
	_true("MOVED")
	_true("SPUN")
	_true("ON_GROUND")


func test_farts() -> void:
	_true("FARTED")
	_true("FART_SOUND")


func test_touch_kills() -> void:
	_true("DIED_ON_TOUCH")
	assert_eq(int(t.get("KILLS", 0)), 1)
	_true("WOKE")
	_true("WOKE_AWAY_FROM_BLOB")


func test_data_has_no_town_pull() -> void:
	var d := JSON.parse_string(FileAccess.get_file_as_string("res://content/core/hazards/desert_blob.json")) as Dictionary
	assert_false(d.has("town_pull"), "the blob neither seeks nor avoids the town")
	assert_true((d.get("planets", []) as Array).has("port_desert"))
