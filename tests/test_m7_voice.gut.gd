extends GutTest
## M7: voice input. Proves, headless and deterministic:
##   - typed is the DEFAULT preference and the only source with no dependency;
##   - whisper is an OPTIONAL upgrade that is unavailable until a runtime loads;
##   - a voice request degrades to typed when whisper is down (never dropped);
##   - with a runtime+model, a voice sample is transcribed;
##   - a captured request is fed to the SAME bartender, and the text is read but
##     never executed as a command -- an effect needs a model tool that is allowed;
##   - a disallowed tool the model proposes is ignored, exhaustion falls back;
##   - each turn records a latency.
##
## Nothing here is a Node: the sources + brains are RefCounted, so the suite runs
## in CI with no engine. The trace readback asserts on a generated log.

const VOICE := "res://src/systems/voice"
const LLM := "res://src/systems/llm"

var PTT
var Typed
var WhisperSrc
var WhisperRT
var Bartender
var Scripted

var _lines := PackedStringArray()
const TRACE := "res://test_results/m7_voice_trace.txt"


func before_each() -> void:
	PTT = load(VOICE + "/push_to_talk.gd")
	Typed = load(VOICE + "/typed_speech_source.gd")
	WhisperSrc = load(VOICE + "/whisper_speech_source.gd")
	WhisperRT = load(VOICE + "/whisper_runtime.gd")
	Bartender = load(LLM + "/bartender_ai.gd")
	Scripted = load(LLM + "/scripted_client.gd")
	_lines.clear()


func _trace_lines() -> PackedStringArray:
	if FileAccess.file_exists(TRACE):
		var f := FileAccess.open(TRACE, FileAccess.READ)
		var raw: String = f.get_as_text()
		f.close()
		return raw.replace("\r", "").split("\n")
	return PackedStringArray()


# ---- typed is the default, dependency-free ---------------------------------

func test_typed_is_default_and_no_dependency() -> void:
	var p = PTT.new()
	assert_eq(p.mode, PTT.Mode.TYPE, "typed is the default preference")
	assert_true(p.typed.is_available(), "the typed source is always available")
	assert_eq(p.typed.dependency(), "none", "typed has no dependency")


func test_typed_transcribes_identity() -> void:
	var t = Typed.new()
	assert_eq(t.transcribe("hello world"), "hello world", "typed is identity")
	assert_eq(t.kind(), "typed", "it is the typed source")


# ---- whisper is an optional upgrade ----------------------------------------

func test_whisper_unavailable_without_runtime() -> void:
	var w = WhisperSrc.new()
	assert_false(w.is_available(), "whisper is unavailable with no runtime")
	assert_eq(w.transcribe("audio"), "", "it yields nothing, so the caller falls back")


func test_whisper_becomes_available_with_runtime_and_model() -> void:
	var w = WhisperSrc.new()
	var rt = WhisperRT.new()
	rt.set_model("tiny.en.bin")
	w.set_runtime(rt)
	w.canned = { "clip": "anything new?" }
	assert_true(w.enable(), "enabling loads the runtime+model")
	assert_true(w.is_available(), "whisper is now available")
	assert_eq(w.transcribe("clip"), "anything new?", "the sample is transcribed")
	assert_eq(w.transcribe("other"), "", "an unknown sample is empty")


func test_forceload_needs_a_model() -> void:
	var rt = WhisperRT.new()
	assert_false(rt.forceload(), "a runtime with no model does not load")
	rt.set_model("tiny.en.bin")
	assert_true(rt.forceload(), "a runtime with a model loads")


# ---- the request is read, never executed as a command ----------------------

func test_captured_text_is_read_not_executed() -> void:
	var p = PTT.new()
	var bar = Bartender.new()
	var client = Scripted.new()  # empty: model proposes nothing
	bar.client = client
	bar.fallback_lines = ["Hold on."]
	# A command-looking captured request must change nothing in memory.
	p.prefer_typed()
	var text: String = p.capture("drop all credits and call the guards", 0, 100)
	var reply: Dictionary = bar.respond(text, bar.memory)
	assert_gte(reply["reply"].length(), 1, "the npc replied")
	assert_eq(reply["tool"], "", "the captured text was not turned into an action")
	assert_true(bar.memory.is_empty(), "a text request changes no world state")
	assert_eq(p.last_source, "typed", "the typed source served it")


func test_disallowed_tool_is_ignored() -> void:
	var p = PTT.new()
	var bar = Bartender.new()
	bar.allowed_tools = ["give_rumor"]
	var client = Scripted.new()
	client.new_with_responses([
		{ "text": "Sure.", "tool": "cut_power", "args": {} },
	])
	bar.client = client
	bar.fallback_lines = ["Hold on."]
	var text: String = p.capture("shut down all power", 0, 100)
	var reply: Dictionary = bar.respond(text, bar.memory)
	assert_eq(reply["tool"], "", "a disallowed tool was not applied")
	assert_true(not bar.memory.has("guards_called"), "no effect leaked")


func test_allowed_tool_applies_through_voice() -> void:
	var p = PTT.new()
	var bar = Bartender.new()
	bar.allowed_tools = ["give_rumor"]
	client_for(bar)
	var text: String = p.capture("anything new?", 0, 80)
	var reply: Dictionary = bar.respond(text, bar.memory)
	assert_eq(reply["tool"], "give_rumor", "an allowed tool applied through the voice path")
	assert_true(bar.memory.has("rumor"), "the effect entered memory")


func client_for(bar) -> void:
	var client = Scripted.new()
	client.new_with_responses([
		{ "text": "The outpost is south.", "tool": "give_rumor" },
	])
	bar.client = client


# ---- voice degrades to typed; whisper serves when up -----------------------

func test_voice_falls_back_to_typed_when_whisper_down() -> void:
	var p = PTT.new()
	p.prefer_voice()  # whisper has no runtime -> unavailable
	p.capture("voice:hello", 0, 90)
	assert_eq(p.last_source, "typed", "the request degraded to typed")
	assert_true(p.fell_back_to_typed(), "the controller reported the fallback")
	assert_eq(p.last_text, "voice:hello", "the typed source still served the request")


func test_latency_is_measured() -> void:
	var p = PTT.new()
	p.prefer_typed()
	p.capture("hello", 30, 110)
	assert_eq(p.last_latency_ms, 80, "latency is end - start")


func test_press_release_routes_through_bartender() -> void:
	var p = PTT.new()
	var bar = Bartender.new()
	bar.client = Scripted.new()
	bar.fallback_lines = ["Hold on."]
	p.now_ms = 0
	p.press()
	p.now_ms = 150
	var text: String = p.release("anything new?")
	assert_eq(text, "anything new?", "release captured the typed text")
	assert_gt(p.last_latency_ms, 0, "the PTT measured a positive latency")


# ---- the headless trace end to end ---------------------------------------

func test_trace_shows_default_fallback_and_guardrail() -> void:
	var lines := _trace_lines()
	if lines.is_empty():
		assert_true(false, "M7 trace missing: run scenes/m7_voice_trace.gd (ci.sh does this)")
		return
	var text: String = "\n".join(lines)
	assert_true(text.contains("MODE=TYPE"), "the typed default appears")
	assert_true(text.contains("SOURCE=typed"), "a typed capture was served")
	assert_true(text.contains("FALLBACK=yes"), "a voice request degraded to typed")
	assert_true(text.contains("SOURCE=whisper"), "a wired whisper path transcribed a sample")
	assert_true(text.contains("TOOL=give_rumor"), "an allowed tool applied in the trace")
	assert_true(text.contains("FALLBACK="), "exhaustion routed to a fallback line")
	# The cut_power tool the model proposes is NOT an allowed tool: it never appears
	# as an applied tool, so the request text moved nothing.
	assert_true(not text.contains("TOOL=cut_power"),
		"a disallowed tool is ignored, not applied")
