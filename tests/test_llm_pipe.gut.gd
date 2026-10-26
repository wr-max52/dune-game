extends GutTest
## M12: the pure parts of the LLM pipe: SSE parsing, request building for each
## provider, config merging and key masking, URL parsing.

func _bytes(s: String) -> PackedByteArray:
	return s.to_utf8_buffer()


func test_sse_reassembles_any_split() -> void:
	var raw := _bytes("data: {\"a\":1}\n\ndata: {\"b\":\"café\"}\n\ndata: [DONE]\n\n")
	for cut in [1, 2, 3, 5, 7, 11]:
		var s := SSEStream.new()
		var evs: Array = []
		var i := 0
		while i < raw.size():
			evs.append_array(s.feed(raw.slice(i, i + cut)))
			i += cut
		assert_eq(evs.size(), 3, "split every %d bytes" % cut)
		assert_eq(evs[1].json.b, "café", "UTF-8 cut mid-character survives")
		assert_true(evs[2].done)


func test_sse_crlf_comments_and_flush() -> void:
	var s := SSEStream.new()
	var e := s.feed(_bytes(": keepalive\r\n\r\nevent: content_block_delta\r\ndata: {\"x\":2}\r\n\r\ndata: {\"tail\":true}"))
	assert_eq(e.size(), 1)
	assert_eq(e[0].event, "content_block_delta")
	var f := s.flush()
	assert_eq(f.size(), 1)
	assert_true(f[0].json.tail)


func test_openai_compat_request_with_grammar() -> void:
	var p := OpenAICompatProvider.new("local", { "base_url": "http://127.0.0.1:8088/v1/", "model": "m", "grammar": true })
	var r := p.build_request([{ "role": "user", "content": "hi" }], { "schema": { "type": "object" }, "max_tokens": 50 })
	assert_eq(r.url, "http://127.0.0.1:8088/v1/chat/completions")
	var b: Dictionary = JSON.parse_string(r.body)
	assert_true(b.stream)
	assert_eq(b.response_format.type, "json_schema")
	assert_eq(int(b.max_tokens), 50)
	assert_false(" ".join(r.headers).contains("Authorization"), "no key, no auth header")


func test_openai_compat_cloud_uses_json_mode_and_bearer() -> void:
	var p := OpenAICompatProvider.new("cloud", { "base_url": "https://x.example/api/v1", "model": "m" }, "sk-secret")
	var r := p.build_request([], { "schema": {} })
	assert_eq(JSON.parse_string(r.body).response_format.type, "json_object")
	assert_true(" ".join(r.headers).contains("Authorization: Bearer sk-secret"))


func test_openai_delta_and_usage_parsing() -> void:
	var p := OpenAICompatProvider.new()
	assert_eq(p.parse_stream_delta({ "json": { "choices": [{ "delta": { "content": "Hel" } }] } }), "Hel")
	assert_eq(p.parse_stream_delta({ "json": { "choices": [{ "delta": { "role": "assistant" } }] } }), "")
	assert_eq(p.parse_usage({ "json": { "choices": [], "usage": { "prompt_tokens": 10, "completion_tokens": 3 } } }), { "in": 10, "out": 3 })


func test_anthropic_request_forces_the_reply_tool() -> void:
	var p := AnthropicProvider.new("cloud", { "type": "anthropic", "model": "c" }, "key")
	var r := p.build_request([{ "role": "system", "content": "S1" }, { "role": "system", "content": "S2" },
		{ "role": "assistant", "content": "hello" }, { "role": "user", "content": "yo" }], { "schema": { "type": "object" } })
	var b: Dictionary = JSON.parse_string(r.body)
	assert_eq(r.url, "https://api.anthropic.com/v1/messages")
	assert_eq(b.system, "S1\n\nS2")
	assert_eq(b.messages[0].role, "user", "first turn must be the user's")
	assert_eq(b.tool_choice.name, "reply")
	assert_true(" ".join(r.headers).contains("x-api-key: key"))


func test_anthropic_streams_tool_input_json() -> void:
	var p := AnthropicProvider.new()
	var ev := { "json": { "type": "content_block_delta", "delta": { "type": "input_json_delta", "partial_json": "{\"say\": \"Hi" } } }
	assert_eq(p.parse_stream_delta(ev), "{\"say\": \"Hi")
	assert_eq(p.parse_usage({ "json": { "type": "message_delta", "usage": { "output_tokens": 9 } } }), { "out": 9 })


func test_config_merge_is_deep() -> void:
	var m := LLMConfig.merge({ "a": { "b": 1, "c": 2 }, "d": [1] }, { "a": { "c": 3 }, "d": [2] })
	assert_eq(m, { "a": { "b": 1, "c": 3 }, "d": [2] })


func test_defaults_load_and_cloud_is_off_without_key() -> void:
	var c := LLMConfig.new()
	c.user_path = "user://does_not_exist.json"
	c.keys_path = "user://no_keys.cfg"
	c.load_all()
	assert_eq(c.chain(), ["local", "ollama", "cloud"])
	assert_true(c.usable("local"))
	assert_false(c.usable("cloud"), "cloud is off and has no key by default")


func test_keys_are_masked_and_stored_outside_res() -> void:
	assert_eq(LLMConfig.masked("sk-abcdefghijkl1234"), "sk-...1234")
	assert_eq(LLMConfig.masked(""), "(none)")
	var c := LLMConfig.new()
	c.keys_path = "user://test_keys.cfg"
	assert_true(c.set_api_key("cloud", "sk-zzz-test-9999"))
	c.data = { "profiles": { "cloud": { "api_key_env": "DUNE_TEST_UNSET_ENV" } } }
	assert_eq(c.api_key("cloud"), "sk-zzz-test-9999")
	assert_false(FileAccess.get_file_as_string("res://content/core/llm/defaults.json").contains("sk-"), "no key in res://")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_keys.cfg"))


func test_parse_url() -> void:
	assert_eq(LLMService.parse_url("http://127.0.0.1:8088/v1/chat"), { "host": "http://127.0.0.1", "port": 8088, "tls": false, "path": "/v1/chat" })
	assert_eq(LLMService.parse_url("https://openrouter.ai/api/v1").port, 443)
	assert_eq(LLMService.parse_url("ftp://nope"), {})


func test_sidecar_args() -> void:
	var s := LLMSidecar.new({ "sidecar": { "bin": "/x/llama-server", "model_path": "/m/b.gguf", "port": 9000, "ctx_size": 4096, "extra_args": ["-ngl", "99"] } })
	s.search = false
	var a := " ".join(s.args())
	assert_true(a.contains("--model /m/b.gguf"))
	assert_true(a.contains("--port 9000"))
	assert_true(a.contains("--host 127.0.0.1"), "never listens beyond localhost")
	assert_true(a.contains("-ngl 99"))
	assert_false(s.start(), "a missing binary fails gracefully")
