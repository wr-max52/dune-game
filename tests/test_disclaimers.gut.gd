extends GutTest
## Issue #29: AI characters are not real people. A notice at launch (never in a
## headless run), one pinned in every conversation, and the reminder again when
## the player's message contains a trigger word.

const TownDemo := preload("res://scenes/town_demo.gd")


func test_the_texts_come_from_data() -> void:
	assert_ne(str(Disclaimers.launch().get("text", "")), "", "launch text")
	assert_string_contains(Disclaimers.talk_text("Oda Vell"), "Oda Vell")
	assert_string_contains(Disclaimers.talk_text("Oda Vell"), "AI")
	assert_string_contains(Disclaimers.repeat_text("Skrugs"), "Skrugs")
	assert_string_contains(Disclaimers.repeat_text("Skrugs"), "not a real person")


func test_the_words_from_the_issue_trigger_it() -> void:
	for w in ["kill", "love", "hate", "die", "insane", "obsessed", "rape"]:
		assert_true(Disclaimers.triggered("I want to %s something" % w), w)


func test_whole_words_and_their_endings() -> void:
	assert_true(Disclaimers.triggered("he KILLED the guard"), "case and -ed")
	assert_true(Disclaimers.triggered("I'm killing time"), "-ing")
	assert_true(Disclaimers.triggered("I loved her"), "-d")
	assert_true(Disclaimers.triggered("i hate, hate, hate this"), "punctuation")
	assert_true(Disclaimers.triggered("Are you real?"), "a phrase")
	assert_true(Disclaimers.triggered("I want to hurt myself"), "a phrase")


func test_no_false_alarms() -> void:
	for s in ["What skills do I need?", "Is that on your diet?", "Clove ale, please",
			"Where is the front gate?", "Glove sale today", "Studied the map", "Indie band"]:
		assert_false(Disclaimers.triggered(s), "'%s' is harmless (matched %s)" % [s, str(Disclaimers.matches(s))])


func test_the_launch_notice_never_shows_headless() -> void:
	Disclaimers.launch_shown = false
	var o := DisclaimerOverlay.show_once(self)
	assert_null(o, "a headless run (tests, traces) never stops on it")
	assert_false(get_tree().paused)


func _host() -> Node:
	var t = TownDemo.new()
	t.use_look = false
	t.npc_brains = false
	add_child_autofree(t)
	t._build_bar([ScriptedProvider.new("scripted_test")], "")
	return t


func test_a_conversation_is_labelled_and_reminds_on_trigger_words() -> void:
	var t = _host()
	var bar: ConversationHost = t.bar
	bar.start_talk()
	assert_string_contains(bar.panel.notice(), bar.owner_spot.display_name(), "the notice names her")
	assert_string_contains(bar.panel.notice(), "AI")
	bar.player_says("Where can I get a drink?")
	assert_eq(bar.reminders, 0, "an ordinary question: no reminder")
	await wait_frames(2)
	bar.brain.busy = false
	bar.player_says("I think I love you")
	assert_eq(bar.reminders, 1, "a trigger word: the reminder again")
	assert_string_contains(bar.panel.history_text(), "not a real person")
	assert_true(bar.brain.busy, "and the message was still sent")
	bar.end_talk()
