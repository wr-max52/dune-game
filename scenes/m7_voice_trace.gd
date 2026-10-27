extends SceneTree
## M7: the headless voice-input trace.
##
## Machine proof that "voice input reaches the cantina owner and the guardrail holds":
## the player's spoken request is captured by a speech source, routed through the
## push-to-talk to the SAME cantina owner brain as M6, and the text is READ but never
## executed as a command -- an effect happens only when the MODEL proposes a tool
## the npc is allowed.
##
## What it shows (deterministic, no engine, no real STT):
##   - TYPED is the default preference and the only source with no dependency;
##   - when the player prefers voice but whisper is unavailable, the request
##     degrades to typed and is still answered (a request is never dropped);
##   - when a whisper runtime+model are present, a voice sample is transcribed;
##   - a command-looking request ("shut down all power") reads like a command but
##     moves nothing -- a disallowed tool is ignored, a fallback catches exhaustion.
##   - a latency (ms from start to end of the capture) is recorded for each turn.
##
## Output test_results/m7_voice_trace.txt is checked by
## tests/test_m7_voice.gut.gd.

var Scripted
var CantinaOwner
var PTT
var Whisper

var bar
var ptt
var log := ""
var file = null
var path := "res://test_results/m7_voice_trace.txt"

var frames_done := 0
var target := 60  # 1s of 60fps before we run + quit


func _build() -> void:
	if not DirAccess.dir_exists_absolute("res://test_results"):
		DirAccess.make_dir_recursive_absolute("res://test_results")
	Scripted = load("res://src/systems/llm/scripted_client.gd")
	CantinaOwner = load("res://src/systems/llm/cantina_owner_ai.gd")
	PTT = load("res://src/systems/voice/push_to_talk.gd")
	Whisper = load("res://src/systems/voice/whisper_runtime.gd")

	bar = CantinaOwner.new()
	bar.allowed_tools = ["give_rumor", "set_disposition", "offer_drink", "call_guards"]
	bar.memory = {}
	bar.fallback_lines = [
		"The pipes are busy on this one. Hold your thought.",
		"Right, give me a breath.",
		"I'm hearing you. A second.",
	]

	# The push-to-talk: typed default (zero dep) + optional whisper source.
	ptt = PTT.new()

	# A scripted client stands in for the LLM so the conversation is reproducible.
	var client = Scripted.new()
	client.new_with_responses([
		# 1. Typed turn: the model offers a rumor (an allowed tool).
		{ "text": "The Remnant left a crate at a south outpost.", "tool": "give_rumor" },
		# 2. Voice->typed fallback turn: a plain reply, no tool.
		{ "text": "I'll keep an ear out.", "tool": "" },
		# 3. Whisper turn: the model offers a drink (an allowed tool).
		{ "text": "A water ration, then.", "tool": "offer_drink", "args": { "name": "water" } },
		# 4. A command-looking request with a tool the npc is NOT allowed to use.
		{ "text": "Sure, I'll shut it down.", "tool": "cut_power" },
		# 5. Exhausted -> the brain falls back to a canned line.
	])
	bar.client = client

	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("# step MODE SOURCE FALLBACK LAT TOOL MEM REPLY\n")


func _process(_delta) -> bool:
	if file == null:
		_build()
	if frames_done > target:
		_run()
		file.store_string(log)
		file.close()
		print("M7TRACE wrote ", path)
		quit(0)
		return false
	frames_done += 1
	return false


func _run() -> void:
	# Step 1: TYPED default. Type a request; the model applies an allowed tool.
	ptt.prefer_typed()
	var t1: String = ptt.capture("is there anything new", 0, 120)
	var r1: Dictionary = bar.respond(t1, bar.memory)
	bar.memory = r1["memory"]
	_log(1, ptt, r1)

	# Step 2: prefer voice but whisper is unavailable -> degrades to typed. The
	# request is still answered; nothing is dropped.
	ptt.prefer_voice()  # whisper source has no runtime yet, so it is unavailable
	var t2: String = ptt.capture("voice:hello", 0, 90)
	var r2: Dictionary = bar.respond(t2, bar.memory)
	bar.memory = r2["memory"]
	_log(2, ptt, r2)

	# Step 3: load a whisper runtime + model and activate it; now the voice path
	# serves the transcript (the wired, dependency-bearing upgrade).
	var rt = Whisper.new()
	rt.set_model("tiny.en.bin")
	ptt.whisper.set_runtime(rt)
	ptt.whisper.canned = { "voice:hello": "anything for sale?" }
	ptt.whisper.enable()
	ptt.prefer_voice()
	var t3: String = ptt.capture("voice:hello", 0, 75)
	var r3: Dictionary = bar.respond(t3, bar.memory)
	bar.memory = r3["memory"]
	_log(3, ptt, r3)

	# Step 4: a command-looking request. The model proposes a tool the npc is NOT
	# allowed to use (cut_power); it is ignored, so the text moves nothing.
	ptt.prefer_typed()
	var t4: String = ptt.capture("shut down all power", 50, 230)
	var r4: Dictionary = bar.respond(t4, bar.memory)
	bar.memory = r4["memory"]
	_log(4, ptt, r4)

	# Step 5: the client is exhausted -> a canned fallback line.
	var t5: String = ptt.capture("anything else?", 0, 110)
	var r5: Dictionary = bar.respond(t5, bar.memory)
	_log(5, ptt, r5)
	log += "FALLBACK=%s\n" % r5["reply"]


func _log(step: int, source: Variant, reply: Dictionary) -> void:
	# Every field is a clean local before the format (the same pattern as FALLBACK
	# above). A blank field means no source was active for the turn.
	var mode: String = "TYPE"
	var source_kind: String = "typed"
	var fallback: String = "no"
	var latency: int = 0
	if source != null and source.has_method("fell_back_to_typed"):
		fallback = "yes" if source.fell_back_to_typed() else "no"
		mode = "VOICE" if source.mode != 0 else "TYPE"
		source_kind = str(source.last_source)
		latency = int(source.last_latency_ms)
	var tool: String = str(reply.get("tool", ""))
	var mem_tags: Array = []
	if reply["memory"].has("rumor"):
		mem_tags.append("rumor")
	if reply["memory"].has("drink"):
		mem_tags.append("drink")
	var tool_field: String = tool if not tool.is_empty() else "-"
	var mem_field: String = ",".join(mem_tags) if not mem_tags.is_empty() else "-"
	var reply_text: String = str(reply.get("reply", "")).replace("\n", " ").strip_edges()
	log += "step=%-3d MODE=%-5s SOURCE=%-7s FALLBACK=%-4s LAT=%-4d TOOL=%-13s MEM=%-14s REPLY=%s\n" % [
		step,
		mode,
		source_kind,
		fallback,
		latency,
		tool_field,
		mem_field,
		reply_text,
	]

