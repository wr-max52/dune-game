extends RefCounted
## Deterministic test/client for the LLM interface (M6). It replays canned
## responses in order, so a conversation is reproducible in CI. When it is
## exhausted it returns null, which makes the cantina owner fall back.
##
## Responses are the same shape the real client yields:
##   { "text": <String>, "tool": <name>, "args": <Dict> }

var _responses: Array = []


func new_with_responses(responses: Array) -> void:
	_responses = responses


func pop_next() -> Variant:
	if _responses.is_empty():
		return null
	var r = _responses.pop_front()
	return r
