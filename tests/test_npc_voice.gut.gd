extends GutTest
## Issue #83: voice selection and spoken-only tone tags stay deterministic and
## independent from dialogue text. No API calls or credentials are used here.

const VoiceScript := preload("res://src/systems/voice/npc_voice.gd")


func _voice():
	var voice = VoiceScript.new()
	voice._load_profiles()
	return voice


func test_voice_profiles_cover_guards_merchants_locals_and_t89() -> void:
	var voice = _voice()
	assert_true(voice.profile_for_npc("gate-01", { "role": "gate" }) in ["guard", "guard_rough"])
	assert_eq(voice.profile_for_npc("stall-01", { "role": "merchant" }), "merchant")
	assert_true(voice.profile_for_npc("resident-01", { "role": "local" }) in ["relaxed", "woman_relaxed", "merchant"])
	assert_eq(voice.profile_for_npc("t89", {}), "t89")


func test_voice_assignment_is_stable_and_varies_across_locals() -> void:
	var voice = _voice()
	assert_eq(voice.profile_for_npc("resident-a", { "role": "local" }),
		voice.profile_for_npc("resident-a", { "role": "local" }))
	var assigned := {}
	for i in 40:
		assigned[voice.profile_for_npc("resident-%d" % i, { "role": "local" })] = true
	assert_gte(assigned.size(), 2, "locals do not all share one voice")


func test_mood_tags_and_shouts_are_added_only_to_speech_payload() -> void:
	var profile := {
		"style_tag": "[robotic, metallic voice]",
		"mood_tags": { "warm": "[warm, friendly delivery]", "angry": "[angry, forceful delivery]" }
	}
	var tags := VoiceScript.mood_tags_for(profile, "warm")
	var subtitle := "Welcome, pilot."
	assert_eq(VoiceScript.speech_text(subtitle, tags), "[robotic, metallic voice] [warm, friendly delivery] Welcome, pilot.")
	assert_eq(subtitle, "Welcome, pilot.", "the visible subtitle remains unchanged")
	var shout := VoiceScript.mood_tags_for(profile, "warm", true)
	assert_true(shout.has("[shouts]"))
	assert_false(shout.has("[warm, friendly delivery]"), "shouting replaces the mood delivery tag")


func test_elevenlabs_payload_carries_mood_speed_and_v4_model() -> void:
	var profile := {
		"style_tag": "[low, metallic, robotic voice]",
		"stability": 0.82
	}
	var payload := VoiceScript.build_payload("Stand by.", profile, "eleven_v4", 0.85,
		{ "wary": "[cautious, restrained delivery]" }, "wary")
	assert_eq(payload.model_id, "eleven_v4")
	assert_eq(payload.text, "[low, metallic, robotic voice] [cautious, restrained delivery] Stand by.")
	assert_eq(payload.voice_settings.speed, 0.85)
	assert_eq(payload.voice_settings.stability, 0.82)


func test_cache_key_changes_with_voice_speed_and_model() -> void:
	var baseline := VoiceScript.cache_key("hello", "voice-a", "eleven_v4", 1.0)
	assert_ne(baseline, VoiceScript.cache_key("hello", "voice-b", "eleven_v4", 1.0))
	assert_ne(baseline, VoiceScript.cache_key("hello", "voice-a", "eleven_v4", 0.9))
	assert_ne(baseline, VoiceScript.cache_key("hello", "voice-a", "another-model", 1.0))
	assert_ne(baseline, VoiceScript.cache_key("hello", "voice-a", "eleven_v4", 1.0, 0.8))
