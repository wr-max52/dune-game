class_name OpenAICompatProvider
extends LLMProvider
## One adapter for every OpenAI-compatible chat endpoint (M12): the bundled
## llama-server, Ollama's /v1, LM Studio, OpenAI, OpenRouter, Groq, Together,
## Gemini's OpenAI endpoint. Streams with SSE.
##
## Structured replies: when the profile has "grammar": true (llama-server, Ollama)
## the reply schema goes in as response_format json_schema, which those servers
## turn into a grammar, so the JSON cannot be malformed. Cloud profiles without
## grammar get json_object mode and the schema in the system prompt.


func build_request(messages: Array, opts: Dictionary) -> Dictionary:
	var body := {
		"model": model(),
		"messages": messages,
		"stream": true,
		"temperature": float(opts.get("temperature", 0.8)),
		"max_tokens": int(opts.get("max_tokens", 220)),
	}
	if opts.has("schema"):
		if bool(profile.get("grammar", false)):
			body["response_format"] = { "type": "json_schema", "json_schema": { "name": "reply", "strict": true, "schema": opts.schema } }
		else:
			body["response_format"] = { "type": "json_object" }
	if bool(opts.get("stream_usage", true)):
		body["stream_options"] = { "include_usage": true }
	var headers := PackedStringArray(["Content-Type: application/json", "Accept: text/event-stream"])
	if api_key != "":
		headers.append("Authorization: Bearer " + api_key)
	return {
		"url": str(profile.get("base_url", "")).trim_suffix("/") + "/chat/completions",
		"method": "POST",
		"headers": headers,
		"body": JSON.stringify(body),
		"stream": true,
	}


func parse_stream_delta(event: Dictionary) -> String:
	var j = event.get("json")
	if not (j is Dictionary):
		return ""
	var choices: Array = j.get("choices", [])
	if choices.is_empty():
		return ""
	var delta = choices[0].get("delta", {})
	if delta is Dictionary and delta.get("content") is String:
		return delta.content
	return ""


func parse_usage(event: Dictionary) -> Dictionary:
	var j = event.get("json")
	if j is Dictionary and j.get("usage") is Dictionary:
		var u: Dictionary = j.usage
		return { "in": int(u.get("prompt_tokens", 0)), "out": int(u.get("completion_tokens", 0)) }
	return {}


func parse_final(raw: String) -> Dictionary:
	var j = JSON.parse_string(raw)
	if not (j is Dictionary):
		return { "ok": false, "text": "", "usage": {}, "error": "bad json" }
	if j.has("error"):
		return { "ok": false, "text": "", "usage": {}, "error": str(j.error) }
	var choices: Array = j.get("choices", [])
	var text := ""
	if not choices.is_empty():
		text = str(choices[0].get("message", {}).get("content", ""))
	return { "ok": text != "", "text": text, "usage": parse_usage({ "json": j }), "error": "" }
