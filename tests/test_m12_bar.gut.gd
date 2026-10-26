extends GutTest
## M12: the live bartender, from the headless trace (scenes/m12_bar_trace.gd).
## Part 1 runs scripted providers through the real pipe; part 2 runs the same
## brain over real HTTP against tools/llm/mock_llm_server.py (ci.sh starts it
## when python3 exists; those tests are skipped otherwise).

const Reader := preload("res://tests/trace_reader.gd")
var t: Dictionary


func before_all() -> void:
	t = Reader.read("res://test_results/m12_bar_trace.txt")


func test_trace_exists() -> void:
	assert_false(t.is_empty(), "run scenes/m12_bar_trace.gd first (ci.sh does)")


func test_walk_up_and_talk_locks_the_player() -> void:
	assert_eq(t.get("IN_RANGE"), "true")
	assert_eq(t.get("TALKING"), "true")
	assert_eq(t.get("PLAYER_LOCKED"), "true")
	assert_eq(t.get("UNLOCKED"), "true")


func test_player_words_reach_the_model_fenced() -> void:
	assert_eq(t.get("T1_PLAYER_TEXT_SENT"), "true")
	assert_eq(t.get("T1_FENCED"), "true")


func test_rumors_only_from_the_briefing() -> void:
	assert_eq(t.get("T1_BRIEFING_HAS_CHECKPOINT"), "true")
	assert_true(str(t.get("T1_KEPT")).contains("share_rumor:r_checkpoint"))
	assert_true(str(t.get("T1_DROPPED")).contains("rumor not in briefing"))
	assert_eq(t.get("T1_KNOWN"), "r_checkpoint")


func test_trust_is_clamped() -> void:
	assert_eq(int(t.get("T1_TRUST_GAIN", 99)), 2, "a +9 proposal becomes +2")


func test_locked_secrets_are_not_in_the_prompt() -> void:
	assert_eq(t.get("T1_NO_LOCKED_SECRET"), "true")


func test_fallback_to_next_provider_and_real_job() -> void:
	assert_eq(t.get("T2_PROVIDER"), "scripted_b")
	assert_eq(t.get("T2_FELL_BACK"), "scripted_a:connect")
	assert_eq(t.get("T2_KEPT"), "offer_job:j_patrol_bounty", "the invented job is dropped")
	assert_eq(t.get("T2_JOB_CARD"), "true")
	assert_eq(t.get("T2_JOB_TAKEN"), "active")


func test_breaking_character_is_deflected() -> void:
	assert_eq(t.get("T3_FILTER"), "meta")
	assert_eq(t.get("T3_NO_AI"), "true")


func test_franchise_terms_are_rewritten() -> void:
	assert_eq(t.get("T4_SCRUBBED"), "true")
	assert_true(str(t.get("T4_FILTER")).contains("ip_term"))


func test_drinks_cost_the_menu_price() -> void:
	assert_eq(t.get("T5_KEPT"), "pour_drink:dust_ale")
	assert_eq(int(t.get("T5_CHARGED", 0)), 4, "not the 999 the model asked for")


func test_cannot_throw_out_a_polite_player() -> void:
	assert_true(str(t.get("T6_DROPPED")).contains("not hostile"))
	assert_eq(t.get("T6_STILL_SERVING"), "true")


func test_offline_answers_are_canned_but_true() -> void:
	assert_eq(t.get("T7_SOURCE"), "canned")
	assert_true(str(t.get("T7_KEPT")).begins_with("share_rumor:r_"))


func test_stalled_stream_keeps_what_was_said() -> void:
	assert_eq(t.get("T8_STALLED"), "true")
	assert_eq(t.get("T8_SAY"), "Well, the thing about")


func test_first_token_timeout_falls_back_with_a_beat() -> void:
	assert_eq(t.get("T9_PROVIDER"), "scripted_b")
	assert_eq(t.get("T9_FELL_BACK"), "scripted_a:timeout")
	assert_eq(t.get("T9_BARKED"), "true")


func test_circuit_breaker_opens() -> void:
	assert_eq(t.get("CIRCUIT_A_OPEN"), "true")
	assert_eq(t.get("CHAIN_WITHOUT_A"), "scripted_b")


func test_conversation_never_blocks_a_frame() -> void:
	assert_lt(float(t.get("CONVO_WORST_FRAME_MS", 999)), 50.0)


func test_memory_is_saved_v2() -> void:
	assert_eq(t.get("SAVED"), "true")
	assert_eq(int(t.get("SAVE_VERSION", 0)), 2)
	assert_eq(t.get("SAVED_TRUST_MATCHES"), "true")
	assert_true(str(t.get("SAVED_KNOWN")).contains("r_checkpoint"))
	assert_eq(t.get("SAVED_JOB"), "active")


func test_second_visit_remembers_and_world_changed() -> void:
	assert_eq(int(t.get("V2_VISITS", 0)), 2)
	assert_eq(int(t.get("V2_TRUST_GAIN", 0)), 6, "came back (+1) and finished her job (+5), capped at 6")
	assert_eq(t.get("V2_JOB_DONE"), "done")
	assert_eq(t.get("V2_BRIEF_NEW_RUMOR"), "true", "the won flight makes a new rumor true")
	assert_eq(t.get("V2_BRIEF_OLD_RUMOR_GONE"), "true", "and the stale one stops being shown")
	assert_eq(t.get("V2_KEPT"), "share_rumor:r_patrol_beaten")
	assert_eq(t.get("V2_REMEMBERS"), "true")


# ---- real HTTP (mock server)

func _live() -> bool:
	if t.get("LIVE") != "on":
		pending("real HTTP part skipped (no python3 / mock server)")
		return false
	return true


func test_live_stream_reaches_the_model_and_back() -> void:
	if not _live():
		return
	assert_eq(t.get("LIVE_SOURCE"), "model")
	assert_eq(t.get("LIVE_PROVIDER"), "local")
	assert_gt(int(t.get("LIVE_DELTAS", 0)), 3, "the subtitle streams in pieces")
	assert_eq(t.get("LIVE_ECHO"), "true", "the mock echoes the player's words")
	assert_eq(t.get("LIVE_UTF8"), "true", "a character cut across chunks survives")
	assert_true(str(t.get("LIVE_KEPT")).contains("share_rumor:r_"))
	assert_eq(int(t.get("LIVE_USAGE_IN", 0)), 321)
	assert_gt(int(t.get("LIVE_MS_FIRST", -1)), -1)
	assert_lt(float(t.get("LIVE_WORST_FRAME_MS", 999)), 50.0)


func test_live_fallbacks() -> void:
	if not _live():
		return
	assert_eq(t.get("LIVE_TIMEOUT_PROVIDER"), "ollama")
	assert_eq(t.get("LIVE_TIMEOUT_FELL_BACK"), "local:timeout")
	assert_eq(t.get("LIVE_500_PROVIDER"), "ollama")
	assert_eq(t.get("LIVE_500_FELL_BACK"), "local:http")
	assert_eq(t.get("LIVE_ALL_DOWN_SOURCE"), "canned")


func test_live_non_json_reply_is_repaired() -> void:
	if not _live():
		return
	assert_eq(t.get("LIVE_GARBAGE_SOURCE"), "model")
	assert_eq(t.get("LIVE_GARBAGE_REPAIRED"), "true")
	assert_true(str(t.get("LIVE_GARBAGE_SAY")).contains("gate"))


func test_live_health_checks() -> void:
	if not _live():
		return
	assert_eq(t.get("HEALTH_LOCAL_UP"), "false")
	assert_eq(t.get("HEALTH_OLLAMA_UP"), "true")
	assert_eq(t.get("HEALTH_CHAIN"), "ollama")
