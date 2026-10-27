extends RefCounted
## Cantina Owner brain (M6). Pure, headless. This is the single LLM-driven NPC.
##
## The brain talks to the LLM through a client (ScriptedClient in CI, OllamaClient
## live). A KEY GUARDRAIL: the player's typed text is READ but NEVER executed as a
## command -- it is only something to talk about. An effect on the world happens
## only when the MODEL proposes a tool, and only that tool, and only one of the
## npc's allowed set (which comes from its data entry). A tool the model proposes
## that is not allowed is ignored, so it cannot leak an effect into memory.
##
## When the client is exhausted (pop_next() -> null) the brain falls back to a
## canned line, so a conversation never dead-ends.

var client         # an LLMClient: has pop_next() -> Variant (a response or null)
var allowed_tools: Array = []   # from the npc data entry; bounds what may be applied
var fallback_lines: Array = []  # canned lines for when the client is exhausted
var memory: Dictionary = {}

var _fallback_index := 0
const DEFAULT_REPLY := "Right. Hold on a tick."


## Consume one turn. The request is read, not acted on. Returns the turn result:
##   { reply, tool, args, memory, source }  (source is "model" or "fallback").
func respond(text_request: String, memory_in: Dictionary) -> Dictionary:
	# Read the request. Do NOT act on it; only the model's tool proposal may
	# change world state.
	memory = memory_in if memory_in is Dictionary else {}
	var r = _next_response()
	if r == null:
		return {
			"reply": _fallback(),
			"tool": "",
			"args": {},
			"memory": memory,
			"source": "fallback",
		}

	var reply_text: String = str(r.get("text", ""))
	var tool_name: String = str(r.get("tool", ""))
	var args: Dictionary = r.get("args", {})
	if not (args is Dictionary):
		args = {}

	# Guardrail: apply only a tool the npc is allowed to use. A disallowed tool is
	# ignored entirely -- it does not enter memory.
	if not allowed_tools.has(tool_name):
		tool_name = ""
		args = {}
	_apply_tool(tool_name, reply_text, args)

	return {
		"reply": reply_text,
		"tool": tool_name,
		"args": args,
		"memory": memory,
		"source": "model",
	}


func _next_response() -> Variant:
	if client == null:
		return null
	return client.pop_next()


## The only place an effect is applied. Bounded to the allowed tool set by the
## guardrail in respond(); the empty name is a no-op.
func _apply_tool(name: String, text: String, args: Dictionary) -> void:
	match name:
		"give_rumor":
			memory["rumor"] = text
		"set_disposition":
			memory["disposition"] = int(args.get("level", 0))
		"offer_drink":
			memory["drink"] = str(args.get("name", "water"))
		"call_guards":
			memory["guards_called"] = true
		"":
			pass
		_:
			pass


## A canned line, cycled, so exhaustion is graceful and never empty.
func _fallback() -> String:
	if not fallback_lines.is_empty():
		var idx: int = _fallback_index
		if idx < fallback_lines.size():
			_fallback_index = idx + 1
			return str(fallback_lines[idx])
		_fallback_index = 0
		return str(fallback_lines[0])
	return DEFAULT_REPLY
