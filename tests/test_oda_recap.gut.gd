extends GutTest
## Issue #185: back after time away, Oda opens with a recap of what happened since
## you last talked. Events after the last talk are in it; older ones are not; no
## recap on a first visit, a fresh game or when nothing is new; the model's turn
## gets the same events in its briefing; the save remembers when you last talked.


func before_each() -> void:
	WorldState.reset()


func test_first_visit_and_fresh_game_have_no_recap() -> void:
	WorldState.clock = 5.0
	WorldState.log_event("Killed Old Murk, the beast.")
	var b := NpcBrain.new()
	var line := b.begin_visit()
	assert_true(b.recap_events.is_empty(), "never on a first visit")
	assert_false(line.contains("Old Murk"))


func test_only_events_since_the_last_talk() -> void:
	var b := NpcBrain.new()
	WorldState.clock = 10.0
	WorldState.log_event("Old news from before.")
	b.begin_visit()
	b.end_visit()
	WorldState.clock = 20.0
	WorldState.log_event("Killed Old Murk, the beast.")
	WorldState.log_event("Story: some chapter.")
	WorldState.clock = 21.0
	WorldState.log_event("Someone bought a speeder from Skrugs.")
	WorldState.clock = 30.0
	var line := b.begin_visit()        # no model: the authored recap
	assert_eq(b.recap_events.size(), 2, "the two new events, not the story bookkeeping")
	assert_eq(str(b.recap_events[0].text), "Someone bought a speeder from Skrugs.", "newest first")
	assert_string_contains(line, "Killed Old Murk")
	assert_string_contains(line, "speeder from Skrugs")
	assert_false(line.contains("Old news"), "old events are not news")
	assert_false(b.recap_wanted, "no model here, so no model turn")
	b.end_visit()
	b.begin_visit()
	assert_true(b.recap_events.is_empty(), "nothing new: no recap")


func test_the_model_turn_is_briefed_with_the_same_events() -> void:
	var b := NpcBrain.new()
	WorldState.clock = 1.0
	b.begin_visit()
	b.end_visit()
	WorldState.clock = 2.0
	WorldState.log_event("Killed Old Murk, the beast.")
	b.begin_visit()
	b._recap_now = true
	var brief: Array = b._recap_brief()
	assert_eq(brief.size(), 2)
	assert_string_contains(str(brief[0]), "Killed Old Murk")
	assert_string_contains(str(brief[1]).to_lower(), "recap")
	b._recap_now = false
	assert_true(b._recap_brief().is_empty(), "only on the recap turn")


func test_the_save_remembers_the_last_talk() -> void:
	var r := Relationship.new()
	r.heard_until = 42.0
	var r2 := Relationship.new()
	r2.from_save(r.to_save())
	assert_eq(r2.heard_until, 42.0)
	var old := Relationship.new()
	old.from_save({})
	assert_eq(old.heard_until, -1.0, "an older save: nothing is news until the first talk")
