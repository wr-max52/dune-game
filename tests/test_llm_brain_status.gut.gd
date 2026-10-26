extends GutTest
## Why is the bartender dumb? The sidecar and the service must always be able to
## say, in words, and a second health check must never swallow the first one's
## callback (that once meant llama-server was never started).


func test_missing_binary_is_reported_plainly() -> void:
	var s := LLMSidecar.new({ "sidecar": { "bin": "/nope/llama-server", "model_path": "/nope/m.gguf" } })
	var places := s.candidates()
	s.search = false              # do not find a real install on this machine
	assert_false(s.start())
	assert_eq(s.state, LLMSidecar.State.NO_BINARY)
	assert_true(s.reason().contains("brew install llama.cpp"))
	assert_true(places.has("/opt/homebrew/bin/llama-server"), "Apple Silicon Homebrew is searched")
	assert_true(places.has("/usr/local/bin/llama-server"), "Intel Homebrew is searched")


func test_missing_model_is_reported_plainly() -> void:
	# Any existing file stands in for the binary; the model is what is missing.
	var fake_bin := ProjectSettings.globalize_path("res://project.godot")
	var s := LLMSidecar.new({ "sidecar": { "bin": fake_bin, "model_path": "/nope/missing.gguf" } })
	assert_false(s.start())
	assert_eq(s.state, LLMSidecar.State.NO_MODEL)
	assert_true(s.reason().contains("fetch_runtime.sh"))


func test_report_names_the_reason_when_offline() -> void:
	var svc := LLMService.new()
	add_child_autofree(svc)
	var cfg := LLMConfig.new()
	cfg.user_path = "user://none.json"
	cfg.keys_path = "user://none_keys.cfg"
	cfg.load_all()
	svc.configure(cfg)
	svc.sidecar = LLMSidecar.new(cfg.profile("local"))
	svc.sidecar.state = LLMSidecar.State.NO_BINARY
	svc.health = { "local": { "up": false }, "ollama": { "up": false } }
	var rep := svc.brain_report()
	assert_false(rep.any_up)
	assert_true(str(rep.summary).contains("canned"))
	assert_true(str(rep.lines).contains("brew install llama.cpp"))
	assert_true(str(rep.lines).contains("ollama: not running"))
	assert_true(str(rep.lines).contains("cloud: off"))


func test_second_health_check_waits_instead_of_dropping() -> void:
	var svc := LLMService.new()
	add_child_autofree(svc)
	var cfg := LLMConfig.new()
	cfg.user_path = "user://none.json"
	cfg.load_all()
	cfg.set_value("profiles/local/health_url", "http://127.0.0.1:9/health")
	svc.configure(cfg)
	var calls := [0]
	svc._check_health("local")
	svc._check_health("local", func(_ok): calls[0] += 1)
	var t0 := Time.get_ticks_msec()
	while svc._health_reqs.has("local") and Time.get_ticks_msec() - t0 < 4000:
		await get_tree().process_frame
	assert_eq(calls[0], 1, "the queued callback ran")


func test_schema_numbers_are_integers_on_the_wire() -> void:
	# llama-server rejected "maxItems": 3.0 with HTTP 400, so every turn was canned.
	var b := BartenderBrain.new()
	var p := OpenAICompatProvider.new("local", { "base_url": "http://x/v1", "grammar": true })
	var body := str(p.build_request([], { "schema": b.builder.schema }).body)
	assert_true(body.contains("\"maxItems\":3"), body.substr(0, 300))
	assert_false(body.contains("3.0"), "no float limits in the schema")


func test_say_is_first_in_alphabetical_order() -> void:
	# llama-server orders grammar keys alphabetically; "say" must still come first
	# so the subtitle can stream before the rest of the reply.
	var b := BartenderBrain.new()
	var keys: Array = b.builder.schema.properties.keys()
	var sorted := keys.duplicate()
	sorted.sort()
	assert_eq(sorted[0], "say")
	assert_eq(ReplyParser.parse("{\"say\":\"Hi.\",\"then\":[{\"type\":\"trust\",\"delta\":1}],\"tone\":\"warm\"}").mood, "warm")
