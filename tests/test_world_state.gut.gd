extends GutTest
## M12: WorldState (what is true) and save v2.

func before_each() -> void:
	WorldState.reset()


func after_all() -> void:
	WorldState.reset()


func test_rumors_follow_flags() -> void:
	var ids := func(): return WorldState.rumors("stranger", [], 20).map(func(r): return r.id)
	assert_true(ids.call().has("r_patrol_orbit"))
	assert_false(ids.call().has("r_patrol_beaten"))
	WorldState.on_flight_returned({ "outcome": "complete", "payout": 10 })
	assert_true(ids.call().has("r_patrol_beaten"))
	assert_false(ids.call().has("r_patrol_orbit"), "a rumor stops when it stops being true")


func test_rumor_tier_and_time_conditions() -> void:
	WorldState.set_flag("gate_checkpoint_up")
	WorldState.time_of_day = "dusk"
	var ids := func(tier): return WorldState.rumors(tier, [], 20).map(func(r): return r.id)
	assert_false(ids.call("stranger").has("r_gate_bribe"))
	assert_true(ids.call("regular").has("r_gate_bribe"))
	WorldState.time_of_day = "noon"
	assert_false(ids.call("regular").has("r_gate_bribe"))


func test_unknown_rumors_come_first() -> void:
	WorldState.set_flag("gate_checkpoint_up")
	var first: Array = WorldState.rumors("stranger", [], 2)
	var known := [first[0].id]
	var next: Array = WorldState.rumors("stranger", known, 2)
	assert_ne(next[0].id, first[0].id)


func test_street_shots_cost_standing_once_per_cooldown() -> void:
	var before := int(WorldState.standing.imperial_remnant)
	WorldState.on_player_fired(false)
	WorldState.on_player_fired(false)
	assert_eq(before - int(WorldState.standing.imperial_remnant), 3)
	assert_true(WorldState.has_flag("shots_in_street"))
	WorldState.on_player_fired(true)
	assert_eq(WorldState.count("range_shots"), 1)


func test_jobs_complete_on_real_events() -> void:
	assert_true(WorldState.accept_job("j_range_bet"))
	assert_false(WorldState.accept_job("j_range_bet"), "cannot take it twice")
	assert_false(WorldState.accept_job("j_nope"))
	var c0 := WorldState.credits
	WorldState.on_range_record(17.0)
	assert_eq(WorldState.jobs_taken.j_range_bet, "done")
	assert_eq(WorldState.credits - c0, 40)
	assert_false(WorldState.open_jobs("stranger").map(func(j): return j.id).has("j_range_bet"))


func test_world_save_round_trip() -> void:
	WorldState.set_flag("x")
	WorldState.bump("y", 3)
	WorldState.change_standing("locals", 12, "helped")
	var d := WorldState.to_save()
	WorldState.reset()
	WorldState.from_save(JSON.parse_string(JSON.stringify(d)))
	assert_true(WorldState.has_flag("x"))
	assert_eq(WorldState.count("y"), 3)
	assert_eq(int(WorldState.standing.locals), 17)


func test_save_v1_migrates() -> void:
	var S = load("res://src/systems/save/save_system.gd")
	var v1 := { "player_position": [0, 0, 0], "credits": 5, "mission": {}, "npc_memory": { "player_name": "Rider" }, "version": 1 }
	var d: Dictionary = S.migrate(v1)
	assert_eq(int(d.version), 2)
	assert_true(str(d.relationships.cantina_owner.facts).contains("Rider"))
	var s = S.new()
	s.new_game()
	s.set_relationship("cantina_owner", { "trust": 33 })
	s.set_world({ "credits": 7 })
	assert_true(s.save_to("user://test_save_v2.json"))
	var t = S.new()
	assert_true(t.load_from("user://test_save_v2.json"))
	assert_eq(int(t.get_relationship("cantina_owner").trust), 33)
	assert_eq(int(t.get_world().credits), 7)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_save_v2.json"))
