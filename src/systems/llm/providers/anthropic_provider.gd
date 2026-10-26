class_name AnthropicProvider
extends LLMProvider
## Native Messages API (M12). The reply is forced through a single tool whose
## input schema is the reply schema, and streamed: the tool input arrives as
## input_json_delta fragments, which concatenate to exactly the same JSON the
## other providers send, so everything downstream is shared.

const API_VERSION := "2023-06-01"


func build_request(messages: Array, opts: Dictionary) -> Dictionary:
	var system_parts: PackedStringArray = []
	var convo: Array = []
	for m in messages:
		if str(m.get("role", "")) == "system":
			system_parts.append(str(m.content))
		else:
			convo.append({ "role": m.role, "content": str(m.content) })
	# The API wants the first turn to be the user's.
	if convo.is_empty() or str(convo[0].role) != "user":
		convo.push_front({ "role": "user", "content": "(the player walks up to the bar)" })
	var body := {
		"model": model(),
		"max_tokens": int(opts.get("max_tokens", 220)),
		"temperature": float(opts.get("temperature", 0.8)),
		"system": "\n\n".join(system_parts),
		"messages": convo,
		"stream": true,
	}
	if opts.has("schema"):
		body["tools"] = [{ "name": "reply", "description": "Your in-character reply and any actions.", "input_schema": opts.schema }]
		body["tool_choice"] = { "type": "tool", "name": "reply" }
	return {
		"url": str(profile.get("base_url", "https://api.anthropic.com/v1")).trim_suffix("/") + "/messages",
		"method": "POST",
		"headers": PackedStringArray([
			"Content-Type: application/json",
			"x-api-key: " + api_key,
			"anthropic-version: " + API_VERSION,
		]),
		"body": JSON.stringify(body),
		"stream": true,
	}


func parse_stream_delta(event: Dictionary) -> String:
	var j = event.get("json")
	if not (j is Dictionary) or str(j.get("type", "")) != "content_block_delta":
		return ""
	var d: Dictionary = j.get("delta", {})
	match str(d.get("type", "")):
		"input_json_delta":
			return str(d.get("partial_json", ""))
		"text_delta":
			return str(d.get("text", ""))
	return ""


func parse_usage(event: Dictionary) -> Dictionary:
	var j = event.get("json")
	if not (j is Dictionary):
		return {}
	if str(j.get("type", "")) == "message_start":
		var u: Dictionary = j.get("message", {}).get("usage", {})
		return { "in": int(u.get("input_tokens", 0)) }
	if str(j.get("type", "")) == "message_delta":
		return { "out": int(j.get("usage", {}).get("output_tokens", 0)) }
	return {}


func parse_final(raw: String) -> Dictionary:
	var j = JSON.parse_string(raw)
	if not (j is Dictionary):
		return { "ok": false, "text": "", "usage": {}, "error": "bad json" }
	if str(j.get("type", "")) == "error":
		return { "ok": false, "text": "", "usage": {}, "error": str(j.get("error", {})) }
	for block in j.get("content", []):
		if str(block.get("type", "")) == "tool_use":
			return { "ok": true, "text": JSON.stringify(block.get("input", {})), "usage": {}, "error": "" }
		if str(block.get("type", "")) == "text":
			return { "ok": true, "text": str(block.text), "usage": {}, "error": "" }
	return { "ok": false, "text": "", "usage": {}, "error": "empty" }


func health_request() -> Dictionary:
	return {}
