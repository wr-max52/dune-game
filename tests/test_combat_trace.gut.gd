extends GutTest
## Combat NPCs at the gate with real physics (scenes/combat_trace.gd): patrols,
## every standing band, night bribes, escalation, mouthing off, pushing through,
## and the three ways a fight ends (you win, you run, you are knocked out).

const TRACE := "res://test_results/combat_trace.txt"

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
	assert_true(FileAccess.file_exists(TRACE), "trace exists (run scenes/combat_trace.gd)")
	assert_eq(_s("FAILED"), "false")
	assert_lt(_f("WORST_FRAME_MS"), 50.0, "no frame over budget")


func test_guards_walk_their_loops() -> void:
	for i in 2:
		assert_gt(_f("PATROL_WALKED_%d" % i), 15.0, "guard %d walks" % i)
		assert_gt(_f("PATROL_FARTHEST_%d" % i), 5.0, "guard %d leaves its post" % i)
		assert_true(_b("PATROL_BACK_AT_POST_%d" % i), "guard %d comes back" % i)
		assert_eq(_f("PATROL_STUCK_%d" % i), 0.0)


func test_friends_are_waved_through() -> void:
	assert_true(_b("WAVE_SAID_WAVE"))
	assert_eq(_f("WAVE_CARDS"), 0.0)
	assert_true(_b("WAVE_OUTSIDE"))
	assert_false(_b("WAVE_HOSTILE"))


func test_papers() -> void:
	assert_eq(_s("PAPERS_BAND"), "papers")
	assert_eq(_s("PAPERS_CHOICES"), "papers,bribe,mouth_off,walk_away")
	assert_eq(_s("PAPERS_STATE"), "CLEARED")
	assert_eq(_f("PAPERS_STANDING_DELTA"), 1.0)
	assert_true(_b("PAPERS_OUTSIDE"))
	assert_false(_b("PAPERS_HOSTILE"))


func test_search() -> void:
	assert_eq(_s("SEARCH_BAND"), "search", "the default standing (-10) gets searched")
	assert_true(_b("SEARCH_HELD_STILL"), "held still while searched")
	assert_eq(_s("SEARCH_STATE_DURING"), "SEARCHING")
	assert_eq(_s("SEARCH_STATE"), "CLEARED")
	assert_true(_b("SEARCH_OUTSIDE"))
	assert_false(_b("SEARCH_HOSTILE"))


func test_bribes() -> void:
	assert_eq(_f("BRIBE_CREDITS"), 60.0 - _f("BRIBE_PRICE"))
	assert_true(_b("BRIBE_FLAG"))
	assert_eq(_s("NIGHT_BAND"), "night_hostile", "after dark a wanted face can pay")
	assert_eq(_s("NIGHT_STATE"), "CLEARED")
	assert_lt(_f("NIGHT_CREDITS"), 60.0)
	assert_false(_b("NIGHT_HOSTILE"))
	assert_false(_b("BROKE_BRIBE_ENABLED"), "no coin, no bribe")
	assert_true(_b("BROKE_SAID_NO_CREDITS"))
	assert_eq(_f("BROKE_CREDITS"), 10.0)


func test_escalation() -> void:
	assert_eq(_s("ARMED_BAND"), "search", "a drawn weapon makes papers a search")
	assert_eq(_s("SHOT_BAND"), "search", "so does gunfire in the street")
	assert_eq(_s("MOUTH_BAND_AFTER"), "search")
	assert_true(_b("MOUTH_CARD_OPEN"))
	assert_eq(_f("MOUTH_STANDING_DELTA"), -2.0)
	assert_eq(_s("MOUTH_STATE"), "HOSTILE", "mouthing off twice starts a fight")
	assert_true(_b("PUSH_WARNED"), "walking through a checkpoint gets a warning")
	assert_eq(_s("PUSH_STATE"), "HOSTILE", "then a fight")


func test_the_fight() -> void:
	assert_true(_b("FIGHT_WARN_FIRST"), "hostile standing warns first")
	assert_between(_f("FIGHT_HOSTILE_AFTER_S"), 2.0, 4.0)
	assert_gte(_f("FIGHT_COVER_SPOTS"), 2.0, "the gate guards (at least) took cover")
	assert_true(_b("FIGHT_COVER_DISTINCT"), "different spots")
	assert_true(_b("FIGHT_COVER_HIDES_FROM_PLAYER"), "that really hide them")
	assert_true(_b("FIGHT_COVER_STAYS_INSIDE"), "on their side of the gate")
	assert_gte(_f("FIGHT_CROUCHED_BEHIND_COVER"), 2.0)
	assert_gt(_f("FIGHT_GUARD_SHOTS"), 6.0, "they shoot")
	assert_gt(_f("FIGHT_PLAYER_HITS"), 1.0, "and hit a player standing in the open")


func test_you_can_win() -> void:
	assert_true(_b("FIGHT_WON"), "both guards down")
	assert_eq(_f("FIGHT_KILLED"), _f("FIGHT_TROOPERS"), "the alarm brings the whole garrison: all of them down")
	assert_eq(_f("FIGHT_TROOPERS"), 5.0)
	assert_eq(_s("FIGHT_STATE_AFTER"), "IDLE")
	assert_lte(_f("FIGHT_STANDING_DELTA"), -30.0, "standing drops hard")
	assert_true(_b("FIGHT_FLAG_FIGHT"))
	assert_true(_b("FIGHT_FLAG_DOWN"))
	assert_true(_b("FIGHT_CHECKPOINT_FLAG_CLEARED"), "the checkpoint is no longer up")
	assert_true(_b("FIGHT_RUMOR_FIGHT"), "the bartender has heard")
	assert_true(_b("FIGHT_RUMOR_DEAD"))
	assert_true(_b("FIGHT_OUTSIDE"), "and the gate is yours")


func test_you_can_run() -> void:
	assert_true(_b("FLEE_WAS_HOSTILE"))
	assert_true(_b("FLEE_RAN"))
	assert_gt(_f("FLEE_GAVE_UP_AFTER_S"), 0.0, "they give up the chase")
	assert_true(_b("FLEE_FLAG_FLED"))
	assert_lt(_f("FLEE_STANDING_DELTA"), 0.0, "running costs standing too")
	assert_true(_b("FLEE_SEARCHED"), "they search first")
	assert_lt(_f("FLEE_FARTHEST_FROM_GATE_AFTER"), 60.0, "on a leash (barracks troopers 55 m from their post)")
	assert_gt(_f("FLEE_BACK_ON_PATROL_S"), 0.0, "then go back to their loops")
	assert_true(_b("FLEE_REMEMBERED"), "and remember you when you come back")


func test_you_can_lose() -> void:
	assert_between(_f("DOWNED_DOWNED_AFTER_S"), 3.0, 30.0, "standing in the open gets you dropped")
	assert_true(_b("DOWNED_WOKE_IN_PIT"))
	assert_eq(_f("DOWNED_HP_AFTER"), 100.0)
	assert_lt(_f("DOWNED_CREDITS"), 50.0, "lighter in the pocket")
	assert_eq(_s("DOWNED_STATE"), "IDLE")
	assert_true(_b("DOWNED_GUARDS_STOOD_DOWN"))


func test_shooting_a_friendly_guard() -> void:
	assert_true(_b("SNEAK_WAVED"))
	assert_true(_b("SNEAK_HIT"))
	assert_eq(_s("SNEAK_STATE"), "HOSTILE", "shoot a guard and it is a fight, whatever your standing")
	assert_true(_b("SNEAK_OTHER_FIGHTING"), "the other one joins in")
