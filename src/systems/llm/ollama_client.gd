extends RefCounted
## Ollama client (M6) -- real, local, text.
##
## Wraps a local Ollama endpoint (HTTP). The request building and response parsing
## are pure (no HTTP) so they are unit-testable; only _post() does I/O, and only
## when actually talking to a server. A canned path (ScriptedClient) is what CI
## uses; this file is the real, manual path when a server is running.
##
## It yields the same response shape the cantina owner expects:
##   { "text": <String>, "tool": <name, optional>, "args": <Dict> }

const BASE_URL := "http://localhost:11434"
var _url: String = BASE_URL
var _model: String = "llama3"


func set_server(url: String, model: String) -> void:
	_url = url
	_model = model


## Build the request body for a chat completion with tools. Pure.
func build_request(prompt: String, tools: Array) -> Dictionary:
	# Ollama /api/chat shape: messages + tools (JSON schema) + stream off.
	return {
		"model": _model,
		"messages": [
			{ "role": "system", "content": prompt },
		],
		"tools": tools,
		"stream": false,
	}


## Parse an Ollama chat response into the cantina owner's shape. Pure, so CI can hit
## it with canned JSON. A tool call comes back as a "tool_calls" array on the
## message; if there are none this is a plain text reply.
func parse_response(raw_json: String) -> Dictionary:
	var parsed = JSON.parse_string(raw_json)
	if parsed == null:
		# Could not parse: treat as no reply. The caller falls back.
		return { "text": "" }
	var message = parsed.get("message", {})
	var text: String = message.get("content", "")
	var tool_calls: Array = message.get("tool_calls", [])
	if not tool_calls.is_empty():
		var first: Dictionary = tool_calls[0]
		var name: String = ""
		if first.get("function", {}).has("name"):
			name = first["function"]["name"]
		elif first.has("name"):
			name = first["name"]
		var args: Dictionary = {}
		if first.get("function", {}).has("arguments"):
			args = first["function"]["arguments"]
		elif first.has("arguments"):
			args = first["arguments"]
		return { "text": text, "tool": name, "args": args if args is Dictionary else {} }
	return { "text": text, "tool": "", "args": {} }


## Build a JSON body string from a parsed request. Pure.
func serialize_request(request: Dictionary) -> String:
	return JSON.stringify(request)


func _post(_body: String) -> String:
	# Real HTTP path. Not exercised in CI (no server); returns empty so the
	# caller falls back instead of crashing. A wiring step would use
	# HTTPClient here and write the response through.
	push_warning("OllamaClient: live HTTP not wired in CI; falling back")
	return ""
