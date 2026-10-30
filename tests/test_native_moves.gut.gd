extends GutTest
## Issue #96: the desert packs' moves (NativeMoves): a club swing, a rock throw and
## the trade gestures, played over the walk.

const MOVES := ["swing", "slash", "thrust", "throw", "gesture_wave", "gesture_offer", "gesture_thanks", "gesture_no", "gesture_lower"]


func test_every_move_has_a_length_and_joints() -> void:
	for m in MOVES:
		assert_gt(NativeMoves.length(m), 0.2, m)
		assert_false(NativeMoves.pose(m, 0.5, 0.5).is_empty(), m + " moves something")


func test_moves_blend_in_and_back_out() -> void:
	for m in MOVES:
		assert_almost_eq(NativeMoves.weight(m, 0.0), 0.0, 0.001, m + " starts from the walk")
		assert_almost_eq(NativeMoves.weight(m, 0.5), 1.0, 0.001, m + " is all move in the middle")
		assert_almost_eq(NativeMoves.weight(m, 1.0), 0.0, 0.001, m + " ends back in the walk")


func test_the_club_goes_up_over_the_head_then_comes_down() -> void:
	var up: Vector3 = NativeMoves.pose("swing", 0.38).r_shoulder
	var down: Vector3 = NativeMoves.pose("swing", 0.6).r_shoulder
	assert_lt(up.x, -150.0, "raised over the head")
	assert_gt(down.x, -70.0, "brought down in front")


func test_a_rock_leaves_the_hand_with_the_arm_coming_through() -> void:
	var wind: Vector3 = NativeMoves.pose("throw", 0.42).r_shoulder
	var rel: Vector3 = NativeMoves.pose("throw", NativeMoves.RELEASE).r_shoulder
	assert_lt(wind.x, -140.0, "wound back high")
	assert_between(rel.x, -120.0, -60.0, "forward at the release")
	assert_true(NativeMoves.is_attack("throw"))
	assert_false(NativeMoves.is_attack("gesture_offer"))
