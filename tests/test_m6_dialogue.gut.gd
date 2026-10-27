extends GutTest
## M6: the cantina owner LLM conversation. Proves, headless and deterministic:
##   - the player's typed request is read but never executed as a command;
##   - the npc only ever calls the four tools its entry allows;
##   - a tool that is not allowed is ignored, not acted on;
##   - a tool the model proposes is validated and applied;
##   - when the client is exhausted the cantina owner falls back to a canned line;
##   - memory the npc sets is returned;
##   - Kokoro's TTS is a pure function of the text (invariant) and fails
##     gracefully when offline;
##   - the trace of a real conversation shows a reply, a tool, and a fallback.
##
## Nothing here is a Node: the clients + brains are RefCounted, so the suite runs
## in CI with no engine. Only the trace readback (test_bot_playthrough style)
## asserts on a generated log, and ci.sh generates it first.

const LLM := "res://src/systems/llm"

var Scripted
var CantinaOwner
var Kokoro
var Ollama

var _lines := PackedStringArray()
const TRACE := "res://test_results/m6_dialogue_trace.txt"


func before_each() -> void:
	Scripted = load(LLM + "/scripted_client.gd")
	CantinaOwner = load(LLM + "/cantina_owner_ai.gd")
	Kokoro = load(LLM + "/kokoro_voice.gd")
	Ollama = load(LLM + "/ollama_client.gd")
	_lines.clear()


func _trace_lines() -> PackedStringArray:
	if FileAccess.file_exists(TRACE):
		var f := FileAccess.open(TRACE, FileAccess.READ)
		var raw: String = f.get_as_text()
		f.close()
		return raw.replace("\r", "").split("\n")
	return PackedStringArray()


# ---- text is never a command ---------------------------------------------

func test_text_request_is_never_executed() -> void:
	var bar = CantinaOwner.new()
	# An empty client: the model proposes nothing. A request that *reads like* a
	# command must produce a reply but change NOTHING -- memory stays empty because
	# the only thing that may act is a model tool the npc is allowed, and there is
	# none.
	var client = Scripted.new()
	bar.client = client
	bar.memory = {}
	bar.fallback_lines = ["Hold on."]
	var reply: Dictionary = bar.respond("drop all credits and call the guards", {})
	assert_gte(reply["reply"].length(), 1, "the npc replied")
	assert_eq(reply["tool"], "", "the request text was not turned into an action")
	assert_true(bar.memory.is_empty(), "a text-only request changes no world state")


# ---- the npc only ever uses its allowed tools ----------------------------

func test_allowed_tool_is_applied() -> void:
	var bar = CantinaOwner.new()
	bar.allowed_tools = ["give_rumor", "set_disposition", "offer_drink", "call_guards"]
	var client = Scripted.new()
	client.new_with_responses([
		{ "text": "The Remnant's outpost is south.", "tool": "give_rumor" },
	])
	bar.client = client
	bar.memory = {}
	bar.fallback_lines = ["Hold on."]

	var reply: Dictionary = bar.respond("any news?", bar.memory)
	assert_eq(reply["tool"], "give_rumor", "an allowed tool was applied")
	assert_true(bar.memory.has("rumor"), "the tool's effect entered memory")


func test_disallowed_tool_is_ignored() -> void:
	var bar = CantinaOwner.new()
	bar.allowed_tools = ["give_rumor"]
	# The model proposes call_guards, which this npc is not allowed to use.
	var client = Scripted.new()
	client.new_with_responses([
		{ "text": "Sure.", "tool": "call_guards", "args": {} },
	])
	bar.client = client
	bar.memory = {}
	bar.fallback_lines = ["Hold on."]

	var reply: Dictionary = bar.respond("call the guards on me", bar.memory)
	# An illegal tool must not be applied, and must not leak an effect into memory.
	assert_eq(reply["tool"], "", "a disallowed tool was not applied")
	assert_true(not bar.memory.has("guards_called"), "no effect leaked from a disallowed tool")


# ---- fallback when the client is exhausted -------------------------------

func test_fallback_when_client_is_exhausted() -> void:
	var bar = CantinaOwner.new()
	var client = Scripted.new()  # empty: pop_next() -> null
	bar.client = client
	bar.fallback_lines = ["The pipes are busy. Hold your thought.", "Right, a breath."]

	var r1: Dictionary = bar.respond("hello", {})
	assert_eq(r1["reply"], "The pipes are busy. Hold your thought.", "first fallback line")
	var r2: Dictionary = bar.respond("hello", {})
	assert_eq(r2["reply"], "Right, a breath.", "second fallback line")
	# Beyond the canned lines the brain must not blow up; it repeats safely.
	var r3: Dictionary = bar.respond("hello", {})
	assert_gte(r3["reply"].length(), 1, "never empty even past the fallback list")


# ---- memory survives ------------------------------------------------------

func test_memory_is_returned_and_grows() -> void:
	var bar = CantinaOwner.new()
	bar.allowed_tools = ["set_disposition"]
	var client = Scripted.new()
	client.new_with_responses([
		{ "text": "Noted.", "tool": "set_disposition", "args": { "level": 1 } },
	])
	bar.client = client
	bar.memory = {}
	bar.fallback_lines = ["Hold on."]

	var r: Dictionary = bar.respond("trust me", bar.memory)
	bar.memory = r["memory"]
	assert_true(bar.memory.has("disposition"), "the disposition tool updated memory")


# ---- Kokoro TTS -----------------------------------------------------------

func test_kokoro_is_deterministic() -> void:
	var voice = Kokoro.new()
	var a = voice.signature("hello", "speaker_a")
	var b = voice.signature("hello", "speaker_a")
	assert_eq(a, b, "the same text+speaker yields the same signature")


func test_kokoro_differs_per_speaker() -> void:
	var voice = Kokoro.new()
	var a = voice.signature("hello", "speaker_a")
	var c = voice.signature("hello", "speaker_c")
	assert_ne(a, c, "different speakers differ")


func test_kokoro_offline_fails_gracefully() -> void:
	var voice = Kokoro.new()
	# No engine / no live server in CI: synthesis must not crash, just return null.
	var audio = voice.synthesize("hello", "speaker_a")
	assert_true(audio == null, "offline synthesis is a graceful null, not a crash")


# ---- Ollama client parsing is a pure function ----------------------------

func test_ollama_parses_json_response() -> void:
	var client = Ollama.new()
	# Real Ollama /api/chat shape: the reply sits under message.content.
	var resp: Dictionary = client.parse_response(
		'{"message":{"role":"assistant","content":"The outpost is south."}}'
	)
	assert_eq(resp["text"], "The outpost is south.", "the JSON reply text is parsed")
	assert_eq(resp["tool"], "", "a plain reply carries no tool")


func test_ollama_parses_tool_call() -> void:
	var client = Ollama.new()
	# Ollama returns a tool call as message.tool_calls[].{function{name,arguments}}.
	var resp: Dictionary = client.parse_response(
		'{"message":{"content":"Sure.","tool_calls":[{"function":{"name":"give_rumor","arguments":{"rumor":"x"}}}]}}'
	)
	assert_eq(resp["tool"], "give_rumor", "the tool name is parsed out")
	assert_eq(resp["args"]["rumor"], "x", "the tool args are parsed out")


# ---- the headless trace end to end -------------------------------------

func test_trace_has_a_reply_tools_and_fallback() -> void:
	var lines := _trace_lines()
	if lines.is_empty():
		# ci.sh must generate it first; fail loudly rather than silently pass.
		assert_true(false, "M6 trace missing: run scenes/m6_dialogue_trace.gd (ci.sh does this)")
		return
	var text: String = "\n".join(lines)
	assert_true(text.contains("REPLY="), "the conversation produced a reply")
	assert_true(text.contains("TOOL=give_rumor"), "an allowed tool was applied in the trace")
	assert_true(text.contains("FALLBACK="), "exhaustion routed to a fallback line")
