extends GutTest
## The whole garrison, sound, crouching and smuggling with real physics
## (scenes/garrison_trace.gd).

const TRACE := "res://test_results/garrison_trace.txt"

var kv := {}


func before_all() -> void:
	var f := FileAccess.open(TRACE, FileAccess.READ)
	if f == null:
		return
	for l in f.get_as_text().split("\n", false):
		var i := l.find("=")
		if i > 0 and not l.begins_with("#"):
			kv[l.substr(0, i)] = l.substr(i + 1)
	f.close()


func _f(k: String) -> float:
	return float(kv.get(k, "nan"))


func _b(k: String) -> bool:
	return str(kv.get(k, "")) == "true"


func _s(k: String) -> String:
	return str(kv.get(k, ""))


func test_trace_ran_clean() -> void:
	assert_true(FileAccess.file_exists(TRACE), "trace exists (run scenes/garrison_trace.gd)")
	assert_eq(_s("FAILED"), "false")
	assert_lt(_f("WORST_FRAME_MS"), 50.0, "no frame over budget")


func test_town_wide_alarm() -> void:
	assert_eq(_s("YARD_CALM_BEFORE"), "CALM")
	assert_true(_b("YARD_HIT"))
	assert_eq(_s("YARD_ALARM"), "ALARM", "hurting a barracks trooper raises the town alarm")
	assert_eq(_s("YARD_ALARM_WHY"), "attacked")
	assert_eq(_f("YARD_KLAXON"), 1.0, "the klaxon sounds")
	assert_true(_b("YARD_SAID_ALARM"))
	assert_eq(_f("YARD_FIGHTING"), _f("YARD_ALIVE"), "every trooper in town is fighting")
	assert_true(_b("YARD_GATE_FIGHTING"), "the gate guards too")
	assert_true(_b("YARD_SENTRY_FIGHTING"), "and the tower")
	assert_eq(_s("YARD_CHECKPOINT"), "HOSTILE", "the gate is on a war footing")
	assert_true(_b("YARD_B_CLOSED_IN"), "the other barracks trooper runs to the fight")
	assert_true(_b("YARD_FLAG_FIGHT"))
	assert_eq(_f("YARD_STANDING"), 45.0, "one standing hit for the alarm")


func test_tower_sentry() -> void:
	assert_gte(_f("SENTRY_RAISED_AFTER_S"), 0.0, "the tower spots a wanted face in the street")
	assert_eq(_s("SENTRY_ALARM_WHY"), "spotted")
	assert_true(_b("SENTRY_SAID_HALT"), "after a warning")
	assert_gt(_f("SENTRY_SENTRY_SHOTS"), 0.0, "and shoots from up there")
	assert_true(_b("SENTRY_SENTRY_STAYED"), "without leaving the tower")


func test_sound() -> void:
	assert_true(_b("SOUND_STEPS"), "footsteps while they walk")
	assert_gt(_f("SOUND_RIFLE"), 0.0, "rifles")
	assert_gt(_f("SOUND_VOICE"), 0.0, "radio chatter under the barks")
	assert_eq(_f("SOUND_HURT"), 1.0, "a grunt when hit")
	assert_gt(_f("SOUND_KLAXON"), 0.0)
	assert_true(_b("SOUND_KLAXON_STREAM"))
	assert_true(_b("SOUND_STREAMS_LOADED"), "every sound file loads")


func test_crouch() -> void:
	assert_eq(_f("CROUCH_STAND_H"), 1.8)
	assert_lt(_f("CROUCH_CROUCH_H"), 1.2, "the capsule shrinks")
	assert_almost_eq(_f("CROUCH_EYE"), 1.0, 0.05, "the eye drops")
	assert_true(_b("CROUCH_STAYED_DOWN_UNDER_LID"), "no standing up into a ceiling")
	assert_true(_b("CROUCH_STOOD_UP"))
	assert_true(_b("CROUCH_CROUCHED_HIDDEN"), "crouched behind a barricade: not seen")
	assert_true(_b("CROUCH_STANDING_SEEN"), "standing up: seen")


func test_searches_check_pockets() -> void:
	assert_eq(_s("FOUND_STATE"), "FOUND")
	assert_eq(_s("FOUND_CHOICES"), "hand_over,bribe_keep,run")
	assert_true(_b("FOUND_SAID_FOUND"))
	assert_eq(_f("FOUND_CELLS_LEFT"), 0.0, "handed over")
	assert_true(_b("FOUND_FLAG"))
	assert_eq(_s("FOUND_STATE_AFTER"), "CLEARED")
	assert_eq(_s("FOUND_ALARM"), "CALM")
	assert_eq(_f("KEEP_CREDITS"), 100.0 - _f("KEEP_PRICE"), "paid to keep it")
	assert_eq(_f("KEEP_CELLS_LEFT"), 3.0)
	assert_eq(_s("RUN_ALARM"), "ALARM", "running with it is a fight")
	assert_eq(_f("RUN_CELLS_LEFT"), 3.0)
	assert_eq(_s("BRIBEFIRST_STATE"), "CLEARED")
	assert_eq(_f("BRIBEFIRST_CELLS_LEFT"), 3.0, "a bribe up front means no search")
	assert_true(_b("SPOT_SAID_SPOT"))
	assert_true(_b("SPOT_FOUND"), "papers are no free pass")


func test_smuggling_loop() -> void:
	assert_true(_b("SMUGGLE_CACHE_PLACED"))
	assert_eq(_s("SMUGGLE_PICKED"), "picked_up")
	assert_eq(_f("SMUGGLE_CELLS"), 3.0)
	assert_true(_b("SMUGGLE_CHALLENGED"))
	assert_true(_b("SMUGGLE_THROUGH"), "past the checkpoint on papers")
	assert_eq(_f("SMUGGLE_SOLD"), 3.0)
	assert_eq(_f("SMUGGLE_EARNED"), 90.0, "the fence pays")
	assert_eq(_f("SMUGGLE_CELLS_AFTER"), 0.0)
	assert_true(_b("SMUGGLE_PANEL_OPEN"), "I opens the inventory")
