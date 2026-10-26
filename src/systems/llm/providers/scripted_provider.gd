class_name ScriptedProvider
extends LLMProvider
## CI provider (M12): replays recorded replies through the SAME chain, parser,
## validator and filter as a live model, with no network. Each reply is streamed
## out in small slices across frames (like a real model), or fails on purpose to
## exercise the fallback rules:
##   { "text": "<raw reply json>", "chunk": 8, "ms_first": 120, "ms_per_chunk": 15 }
##   { "fail": "connect" | "timeout" | "stall" | "empty" }

var replies: Array = []
var requests: Array = []         ## every message list we were sent (tests read these)


func _init(provider_id: String = "scripted", script: Array = []) -> void:
	id = provider_id
	replies = script.duplicate(true)


func push(reply: Dictionary) -> void:
	replies.append(reply)


func next_reply() -> Dictionary:
	if replies.is_empty():
		return { "fail": "empty" }
	return replies.pop_front()
