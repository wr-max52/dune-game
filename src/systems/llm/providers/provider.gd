class_name LLMProvider
extends RefCounted
## Provider contract (M12). Providers are pure request builders and response
## parsers; LLMService owns the network and drives them. That split is what lets
## every provider be unit-tested on canned bytes with no server.

var id := ""
var profile: Dictionary = {}
var api_key := ""


func _init(provider_id: String = "", prof: Dictionary = {}, key: String = "") -> void:
	id = provider_id
	profile = prof
	api_key = key


## -> { url, method, headers: PackedStringArray, body: String, stream: bool }
func build_request(_messages: Array, _opts: Dictionary) -> Dictionary:
	return {}


## One SSE event -> the raw text it adds to the reply ("" if none).
func parse_stream_delta(_event: Dictionary) -> String:
	return ""


## Token usage if this event carries it, else {}.
func parse_usage(_event: Dictionary) -> Dictionary:
	return {}


## A whole non-streamed body -> { ok, text, usage, error }.
func parse_final(_raw: String) -> Dictionary:
	return { "ok": false, "text": "", "usage": {}, "error": "not implemented" }


## A cheap GET that proves the server is alive, or {} for "assume up".
func health_request() -> Dictionary:
	var u := str(profile.get("health_url", ""))
	return { "url": u, "method": "GET", "headers": PackedStringArray() } if u != "" else {}


func model() -> String:
	return str(profile.get("model", ""))
