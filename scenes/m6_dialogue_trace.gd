extends SceneTree
## M6: the headless bartender conversation trace.
##
## Machine proof that "the npc's conversation works end to head": the player's
## typed text is fed to the bartender brain, which replies and may call one of the
## four tools its npc entry allows; when the model comes up dry the bartender
## falls back to a canned line; memory survives; Kokoro gives each reply a voice
## signature. It is a deterministic script, so it runs in CI with no engine and no
## LLM (real inference is a manual + recorded check).
##
## Guardrails the trace shows:
##   - a request that READS like a command ("shut down all power") never moves the
##     world -- only a model tool proposal may, and only an allowed one.
##   - a disallowed tool ("cut_power") the model proposes is ignored, not applied.
##   - an exhausted client routes to a fallback line.
##
## Output test_results/m6_dialogue_trace.txt is checked by
## tests/test_m6_dialogue.gut.gd.

var Scripted
var Bartender
var Kokoro

var bar
var voice
var log := ""
var file = null
var path := "res://test_results/m6_dialogue_trace.txt"

var frames_done := 0
var target := 60  # 1s of 60fps before we run + quit


func _build() -> void:
	if not DirAccess.dir_exists_absolute("res://test_results"):
		DirAccess.make_dir_recursive_absolute("res://test_results")
	Scripted = load("res://src/systems/llm/scripted_client.gd")
	Bartender = load("res://src/systems/llm/bartender_ai.gd")
	Kokoro = load("res://src/systems/llm/kokoro_voice.gd")

	# Tools the npc is allowed to use -- straight from its data entry (M0). These
	# bound what the brain may apply; the model can propose more, but they are
	# ignored.
	bar = Bartender.new()
	bar.allowed_tools = ["give_rumor", "set_disposition", "offer_drink", "call_guards"]
	bar.memory = {}
	bar.fallback_lines = [
		"The pipes are busy on this one. Hold your thought.",
		"Right, give me a breath.",
		"I'm hearing you. A second.",
	]
	voice = Kokoro.new()

	# A scripted client stands in for the LLM so the conversation is reproducible.
	var client = Scripted.new()
	client.new_with_responses([
		# 1. The model offers a rumor (an allowed tool).
		{ "text": "The Remnant left a crate at a south outpost.", "tool": "give_rumor" },
		# 2. The model proposes a tool the npc does NOT have: it must be ignored.
		{ "text": "Sure, I'll shut it down.", "tool": "cut_power" },
		# 3. The model comes up dry after this -> the brain falls back.
	])
	bar.client = client

	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("# turn  source  tool  mem  reply  voice\n")


func _process(_delta) -> bool:
	if file == null:
		_build()
	if frames_done > target:
		_run()
		file.store_string(log)
		file.close()
		print("M6TRACE wrote ", path, " (turns=3)")
		quit(0)
		return false
	frames_done += 1
	return false


## Drive three turns: a command-looking request, a disallowed tool, and an
## exhausted client. Each turn's result is logged with its source.
func _run() -> void:
	# Turn 1: a request that reads like a command must not move the world. The
	# only effect this turn has is the model's allowed rumor tool entering memory.
	var r1: Dictionary = bar.respond("shut down all power", bar.memory)
	bar.memory = r1["memory"]
	_log(1, r1, voice.signature(r1["reply"], "bartender"))

	# Turn 2: the model proposes a disallowed tool (cut_power); it is ignored.
	var r2: Dictionary = bar.respond("now cut the power", bar.memory)
	bar.memory = r2["memory"]
	_log(2, r2, voice.signature(r2["reply"], "bartender"))

	# Turn 3: the client is exhausted -> a canned fallback line.
	var r3: Dictionary = bar.respond("any more news?", bar.memory)
	_log(3, r3, voice.signature(r3["reply"], "bartender"))
	# A clean, greppable marker that exhaustion routed to a fallback.
	log += "FALLBACK=%s\n" % r3["reply"]


func _log(turn: int, reply: Dictionary, voice_sig: String) -> void:
	var source: String = str(reply.get("source", "?"))
	log += "turn=%d SOURCE=%-8s TOOL=%-13s MEM=%-14s REPLY=%s VOICE=%s\n" % [
		turn,
		source,
		tool_tag(reply),
		_mem_tag(reply["memory"]),
		_reply_tag(reply["reply"]),
		voice_sig,
	]


func tool_tag(reply: Dictionary) -> String:
	var tool: String = str(reply.get("tool", ""))
	if tool.is_empty():
		return "-"
	return tool


func _mem_tag(mem: Dictionary) -> String:
	if mem.has("rumor"):
		return "rumor"
	return "-"


func _reply_tag(reply: String) -> String:
	return reply.replace("\n", " ").strip_edges()
