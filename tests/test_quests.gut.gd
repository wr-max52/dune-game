extends GutTest
## Issue #201: optional quests in the job log, announced with a toast, with a
## waypoint the player switches on.


func before_each() -> void:
	WorldState.reset()


func after_each() -> void:
	WorldState.reset()


func test_an_event_unlocks_a_quest_with_news_and_no_waypoint() -> void:
	Story.event("heard_of_rifle")
	assert_eq(Quests.state("barracks_rifle"), "open")
	assert_eq(Quests.take_news(), ["barracks_rifle"], "the toast's news")
	assert_eq(Quests.take_news(), [], "announced once")
	assert_true(Quests.waypoint().is_empty(), "no automatic waypoint")
	Story.event("heard_of_rifle")
	assert_eq(Quests.take_news(), [], "not offered twice")


func test_the_waypoint_toggle_leads_the_pointer_one_at_a_time() -> void:
	Quests.unlock("barracks_rifle")
	Quests.unlock("tower_blade")
	assert_true(Quests.toggle_waypoint("barracks_rifle"))
	assert_eq(Objective.current().target, "marker:barracks_upper")
	assert_true(Quests.toggle_waypoint("tower_blade"))
	assert_false(bool(WorldState.quests.barracks_rifle.waypoint), "the other goes off")
	assert_false(Quests.toggle_waypoint("tower_blade"), "off again")
	assert_true(Quests.waypoint().is_empty())
	Quests.unlock("nomad_trade")
	assert_false(Quests.toggle_waypoint("nomad_trade"), "nowhere to point yet")


func test_done_clears_the_waypoint_and_survives_save_and_load() -> void:
	Quests.unlock("tower_blade")
	Quests.toggle_waypoint("tower_blade")
	Story.event("blade_taken")
	assert_eq(Quests.state("tower_blade"), "done")
	assert_true(Quests.waypoint().is_empty())
	Quests.unlock("barracks_rifle")
	var d := WorldState.to_save()
	WorldState.from_save(d)
	assert_eq(Quests.state("tower_blade"), "done")
	assert_eq(Quests.state("barracks_rifle"), "open")
	assert_eq(Quests.take_news(), [], "a load is not news")


func test_the_log_lists_quests_with_a_toggle() -> void:
	Quests.unlock("barracks_rifle")
	var p := InventoryPanel.new()
	add_child_autofree(p)
	p.refresh()
	assert_true(p.job_rows.has(Objective.line("log_quests")))
	assert_true(p.quest_buttons.has("barracks_rifle"))
	p.quest_buttons.barracks_rifle.pressed.emit()
	assert_true(bool(WorldState.quests.barracks_rifle.waypoint), "the button switches it on")
