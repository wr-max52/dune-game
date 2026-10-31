extends GutTest
## Issue #42, end to end (scenes/speeder_trace.gd: real physics, the real town,
## the real conversation pipeline with a scripted model): out the back gate to
## Skrugs, buy a speeder, ride it off the ramp, take a bolt, get off.

const Reader := preload("res://tests/trace_reader.gd")
var t: Dictionary


func before_all() -> void:
	t = Reader.read("res://test_results/speeder_trace.txt")


func _true(k: String, why: String = "") -> void:
	assert_eq(t.get(k), "true", why if why != "" else k)


func test_trace_exists() -> void:
	assert_false(t.is_empty(), "run scenes/speeder_trace.gd first (ci.sh does)")


func test_skrugs_is_out_the_back_gate() -> void:
	_true("POST_BUILT")
	assert_eq(t.get("SPOTS"), "cantina_owner,skrugs", "two AI characters in town")
	_true("THROUGH_THE_BACK_GATE", "you can walk out through the back gate")
	_true("REACHED_THE_STALL")
	_true("CAN_TALK_TO_SKRUGS")


func test_he_sells_through_the_real_pipeline() -> void:
	assert_eq(t.get("TALKING_TO"), "Skrugs")
	_true("AI_NOTICE_PINNED", "issue #29: the AI notice is on his conversation too")
	assert_eq(t.get("SKRUGS_KEPT"), "offer_speeder", "his proposal passed the validator")
	_true("SALE_CARD_UP", "the price card comes up; he never takes money himself")
	assert_eq(int(t.get("OFFER_PRICE", 0)), 100, "the game's price, not the 5 the model said")


func test_buying_one() -> void:
	assert_eq(int(t.get("CREDITS_AFTER", 0)), 60, "160 - 100")
	assert_eq(int(t.get("OWNED", 0)), 1)
	assert_eq(t.get("SKRUGS_MOOD"), "warm", "a sale cheers him up")
	_true("SPEEDER_PARKED")
	_true("PARKED_IN_GARAGE", "issue #295: in his garage")


func test_ride_it_off_the_ramp() -> void:
	_true("MOUNT")
	_true("RIDING")
	_true("TO_THE_RAMP")
	_true("LAUNCHED_OFF_RAMP", "the ground fell away at the ramp's end")
	_true("LANDED")
	assert_gt(float(t.get("AIR_TIME", 0)), 0.5, "real air time")
	assert_gt(float(t.get("JUMP_HEIGHT", 0)), 2.0, "well clear of the sand")
	assert_eq(t.get("HULL_AFTER_JUMP"), t.get("HULL_MAX"), "no fall damage")


func test_gunfire_hurts_and_you_get_off() -> void:
	assert_lt(int(t.get("HULL_AFTER_BOLT", 999)), int(t.get("HULL_MAX", 0)), "a bolt on the hull")
	_true("DISMOUNT")
	_true("ON_FOOT")
	_true("PLAYER_ON_GROUND")


func test_no_frame_over_budget() -> void:
	assert_lt(float(t.get("WORST_MS", 999)), 50.0, "buying one does not hitch (shared materials)")
