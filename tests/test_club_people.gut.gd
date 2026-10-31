extends GutTest
## Issue #261: the clubs' people. The band's loops keep their hands on their
## instruments and loop cleanly, the port's band and crowd are in the town data,
## the crowd shares the locals' brain, and Oda changes the vibe for free (only
## to a mood the band plays).

const TownLayout := preload("res://src/systems/world/town_layout.gd")
const CoreContent := preload("res://src/systems/dataload/core_content.gd")
const PORT := "res://content/core/locations/port_town.json"


func test_every_loop_poses_every_joint_and_loops_cleanly() -> void:
	for kind in ClubMoves.KINDS:
		var a := ClubMoves.pose(kind, 0.0, 100.0)
		var b := ClubMoves.pose(kind, ClubMoves.LOOP_S * 3.0, 100.0)
		for n in BodyAnimator.JOINTS:
			assert_true(a.joints.has(n), "%s poses %s" % [kind, n])
			assert_almost_eq((a.joints[n] as Vector3).distance_to(b.joints[n]), 0.0, 0.5, "%s loops at %s" % [kind, n])


func test_hands_stay_on_the_instruments() -> void:
	# Through a whole set: wherever a hand reaches, it is near the desk, the kit
	# or the bass neck / body (within a stroke's lift), never off in the room.
	for kind in ClubMoves.KINDS:
		var t := 0.0
		while t < ClubMoves.LOOP_S:
			var p := ClubMoves.pose(kind, t, 100.0)
			for side in ["l", "r"]:
				if float(p.reach[side]) < 0.99 or p.hands[side] == null:
					continue
				var h: Vector3 = p.hands[side]
				assert_between(h.z, -0.2, 0.75, "%s %s hand in front at %.1fs" % [kind, side, t])
				assert_between(h.y, 0.8, 1.75, "%s %s hand at playing height at %.1fs" % [kind, side, t])
			t += 0.25


func test_the_sip_comes_back_to_the_hold() -> void:
	var start := ClubMoves.sip_pose(0.0)
	var end := ClubMoves.sip_pose(1.0)
	assert_almost_eq((start.r_elbow as Vector3).distance_to(ClubMoves.HOLD.r_elbow), 0.0, 0.01)
	assert_almost_eq((end.r_elbow as Vector3).distance_to(ClubMoves.HOLD.r_elbow), 0.0, 0.01)
	assert_lt(float((ClubMoves.sip_pose(0.5).r_elbow as Vector3).x), -120.0, "the bottle is up at the mouth halfway")


func test_the_port_has_a_band_of_three_and_a_crowd() -> void:
	var t = TownLayout.new()
	t.load_from_dict(JSON.parse_string(FileAccess.get_file_as_string(PORT)))
	assert_eq(t.validate(), [], "the port's layout still validates")
	var cc = CoreContent.new()
	cc.load_from()
	var band := []
	var crowd := []
	for m in t.markers():
		var s: Dictionary = cc.get_soldier(str(m.get("soldier", "")))
		if bool(s.get("band", false)):
			band.append(str(s.get("perform", "")))
			assert_true(m.has("prop"), "%s has an instrument" % m.id)
		elif bool(s.get("drinks", false)):
			crowd.append(m)
			assert_eq(str(s.faction), "locals", "the crowd shares the town's brain")
			assert_false(bool(s.get("ambient", false)), "the crowd fights back")
	band.sort()
	assert_eq(band, ["bass", "dj", "drum"])
	assert_gte(crowd.size(), 6)
	assert_gte(crowd.filter(func(m): return m.has("patrol")).size(), 2, "some walk, some stand")
	assert_eq(str(t.data.get("club", {}).get("style", "")), "jazz")


func test_oda_changes_the_vibe_for_free_only_to_a_real_mood() -> void:
	var briefing := { "allowed": ["club_vibe"], "moods": ["chill", "hard"] }
	var v := ActionValidator.validate([{ "type": "club_vibe", "mood": "Hard" }], briefing, {})
	assert_eq(v.kept.size(), 1)
	assert_eq(str(v.kept[0].mood), "hard")
	assert_false(v.kept[0].has("price"), "no charge")
	v = ActionValidator.validate([{ "type": "club_vibe", "mood": "polka" }], briefing, {})
	assert_eq(v.kept.size(), 0, "not a mood the band plays")


func test_her_card_has_the_action_and_offline_she_reads_the_request() -> void:
	var card: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/core/npcs/cantina_owner_card.json"))
	assert_true((card.actions as Array).has("club_vibe"))
	var moods: Array = JSON.parse_string(FileAccess.get_file_as_string("res://content/look/sound.json")).club.moods
	for mood in card.vibe_words:
		assert_true(moods.has(mood), "%s is a club mood" % mood)
	var brain := NpcBrain.new()
	brain.card = card
	assert_eq(brain.vibe_mood("play something harder"), "hard")
	assert_eq(brain.vibe_mood("slow it down a bit"), "chill")
