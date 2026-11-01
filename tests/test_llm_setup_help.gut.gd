extends GutTest
## Settings > AI brain: every provider has a link and a set-up prompt for a coding
## agent that ends in the values to paste into F10, and a URL typed in F10 takes
## its health check along.


func test_every_provider_has_a_link_and_a_prompt() -> void:
	for id in ["ollama", "local", "cloud"]:
		assert_true(LLMSetupHelp.link(id).begins_with("https://"), "%s link" % id)
		assert_gt(LLMSetupHelp.prompt(id).length(), 1500, "%s prompt is detailed" % id)
	assert_eq(LLMSetupHelp.link("ollama"), "https://ollama.com/download")
	assert_eq(LLMSetupHelp.link("cloud"), "https://platform.claude.com")
	assert_true(LLMSetupHelp.link("local").contains("llama.cpp"))


func test_prompts_end_in_the_values_to_paste() -> void:
	var want := {
		"local": ["Local URL: http://127.0.0.1:8088/v1", "Local model:"],
		"ollama": ["Ollama URL: http://127.0.0.1:11434/v1", "Ollama model:"],
		"cloud": ["Cloud URL: https://api.anthropic.com/v1", "Cloud model:", "Cloud type: anthropic"],
	}
	for id in want:
		var p := LLMSetupHelp.prompt(id)
		for line in want[id]:
			assert_true(p.contains(line), "%s prompt gives %s" % [id, line])
		assert_true(p.contains("What is allowed"), "%s prompt says what is allowed" % id)
		assert_true(p.contains("F10"), "%s prompt says where to paste" % id)


func test_prompt_test_requests_are_valid_json() -> void:
	for id in ["local", "ollama"]:
		var p := LLMSetupHelp.prompt(id)
		var at := p.find("-d '") + 4
		var body = JSON.parse_string(p.substr(at, p.find("'", at) - at))
		assert_true(body is Dictionary, "%s test request parses" % id)
		assert_eq(str(body.response_format.type), "json_schema", id)


func test_intro_says_who_to_give_it_to() -> void:
	var s := LLMSetupHelp.intro()
	assert_true(s.begins_with("Give this to a coding agent with access to the internet and your computer"))
	assert_true(s.contains("trusted location (e.g. ~/"))


func test_cloud_prompt_leaves_the_key_to_the_player() -> void:
	var p := LLMSetupHelp.prompt("cloud")
	assert_true(p.contains("Do not sign in, create the account, enter payment details or create the key for me"))
	assert_true(p.contains("Never ask me to paste the key into this chat"))


func test_a_typed_url_moves_the_health_check_and_server_port() -> void:
	var cfg := LLMConfig.new()
	cfg.user_path = "user://none.json"
	cfg.keys_path = "user://none_keys.cfg"
	cfg.load_all()
	cfg.set_value("profiles/local/base_url", "http://localhost:8080/v1")
	cfg.follow_base_url("local")
	assert_eq(str(cfg.profile("local").health_url), "http://localhost:8080/health")
	assert_eq(int(cfg.profile("local").sidecar.port), 8080)
	cfg.set_value("profiles/ollama/base_url", "http://192.168.1.20:11434/v1")
	cfg.follow_base_url("ollama")
	assert_eq(str(cfg.profile("ollama").health_url), "http://192.168.1.20:11434/api/tags")


func test_default_urls_leave_nothing_to_save() -> void:
	var cfg := LLMConfig.new()
	cfg.user_path = "user://none.json"
	cfg.keys_path = "user://none_keys.cfg"
	cfg.load_all()
	for id in ["local", "ollama"]:
		cfg.follow_base_url(id)
	assert_eq(LLMConfig._diff(cfg._read(LLMConfig.DEFAULTS), cfg.data).get("profiles", {}), {}, "defaults are not written to the user's config")
	assert_eq(str(cfg.profile("local").health_url), "http://127.0.0.1:8088/health")
