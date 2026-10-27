extends GutTest
## M11: the player's body and hand weapons, from the headless trace
## (scenes/m11_body_trace.gd, real physics). See also the unit tests for
## BodyAnimator, WeaponHolder and SwordCombo.

const Reader := preload("res://tests/trace_reader.gd")
var t: Dictionary


func before_all() -> void:
	t = Reader.read("res://test_results/m11_body_trace.txt")


func test_trace_exists() -> void:
	assert_false(t.is_empty(), "run scenes/m11_body_trace.gd first (ci.sh does)")


func test_body_is_built_with_three_weapons() -> void:
	assert_eq(t.get("BODY_BUILT"), "true")
	assert_eq(int(t.get("WEAPON_MODELS", 0)), 3)


func test_walk_and_sprint_speeds() -> void:
	assert_almost_eq(float(t.get("WALK_SPEED", 0)), 4.0, 0.3)
	assert_gt(float(t.get("SPRINT_SPEED", 0)), 6.0)
	assert_eq(t.get("GAIT_PHASE_MOVED"), "true")


func test_every_locomotion_state_is_reached() -> void:
	var seen: String = t.get("STATES_SEEN", "")
	for s in ["LOCOMOTION", "AIRBORNE", "JUMP", "FALL", "LAND"]:
		assert_true(seen.contains(s), "state seen: " + s)


func test_crouch_lowers_the_hips() -> void:
	assert_lt(float(t.get("CROUCH_PELVIS", 1)), 0.8)


func test_hands_free_body_faces_travel() -> void:
	assert_eq(t.get("FACES_TRAVEL"), "true")


func test_view_toggle_spam_never_desyncs() -> void:
	assert_eq(t.get("TOGGLE_SPAM_OK"), "true")


func test_first_person_hides_body_keeps_arms() -> void:
	assert_eq(t.get("FPV_BODY_SHADOW_ONLY"), "true")
	assert_eq(t.get("FPV_ARMS_VISIBLE"), "true")


func test_third_person_camera_stays_out_of_walls() -> void:
	assert_eq(t.get("CAM_INSIDE_PIT"), "true", "camera x %s must stay inside the pit wall" % t.get("CAM_X_NEAR_WALL"))


func test_swap_spam_ends_clean() -> void:
	assert_eq(t.get("SWAP_END"), "energy_blade")
	assert_eq(t.get("SWAP_IDLE"), "true")
	assert_eq(t.get("SWAP_VISIBLE"), "energy_blade", "only the weapon in hand is visible")
	assert_eq(t.get("BLADE_LIT"), "true")
	assert_eq(t.get("HOLSTER_BLADE_OFF"), "true")


func test_blaster_hits_and_drops_a_target() -> void:
	assert_gt(int(t.get("PISTOL_SHOTS", 0)), 5)
	assert_gt(int(t.get("TARGET_HITS", 0)), 0)
	assert_eq(t.get("TARGET_DOWN"), "true")
	assert_eq(t.get("RELOADED"), "true")


func test_range_shots_are_sanctioned() -> void:
	assert_gt(int(t.get("RANGE_SHOTS_COUNTED", 0)), 0)
	assert_eq(t.get("NO_STREET_FLAG_ON_RANGE"), "true")


func test_right_click_toggles_aim_on_off() -> void:
	assert_eq(t.get("AIM_ON"), "true", "right-click toggles aim (zoom) on")
	assert_eq(t.get("AIM_ZOOMED"), "true", "zoomed in while aim is on")
	assert_eq(t.get("AIM_OFF"), "true", "re-click toggles aim off")


func test_sword_chains_three_and_hits() -> void:
	assert_eq(int(t.get("COMBO_SWINGS", 0)), 3)
	assert_eq(int(t.get("COMBO_STAGES", 0)), 3)
	assert_gt(int(t.get("SWORD_HITS", 0)), 0)


func test_timed_block_deflects_bolts_back() -> void:
	assert_gt(int(t.get("DEFLECTIONS", 0)), 0)
	assert_gt(int(t.get("REMOTE_HITS", 0)), 0, "a deflected bolt goes back and hits the remote")
	assert_eq(int(t.get("PLAYER_HITS_TAKEN", -1)), 0)


func test_street_shots_change_the_world() -> void:
	assert_eq(t.get("STREET_FLAG"), "true")
	assert_gt(int(t.get("REMNANT_STANDING_DROP", 0)), 0)


func test_frame_budget() -> void:
	assert_lt(float(t.get("WORST_FRAME_MS", 999)), 50.0)
