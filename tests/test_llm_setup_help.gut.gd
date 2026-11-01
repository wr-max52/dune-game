extends GutTest
## Settings > AI brain: every provider has a link and a set-up prompt for a coding
## agent, with this machine's paths filled in and no secrets in it.


func test_every_provider_has_a_link_and_a_prompt() -> void:
	for id in ["ollama", "local", "cloud"]:
		assert_true(LLMSetupHelp.link(id).begins_with("https://"), "%s link" % id)
		assert_ne(LLMSetupHelp.prompt(id), "", "%s prompt" % id)
	assert_eq(LLMSetupHelp.link("ollama"), "https://ollama.com/download")
	assert_eq(LLMSetupHelp.link("cloud"), "https://platform.claude.com")
	assert_true(LLMSetupHelp.link("local").contains("llama.cpp"))


func test_paths_are_filled_in() -> void:
	var paths := { "game_dir": "/g", "user_dir": "/u", "config_file": "/u/llm_config.json" }
	for id in ["ollama", "local", "cloud"]:
		var p := LLMSetupHelp.prompt(id, paths)
		assert_false(p.contains("{game_dir}") or p.contains("{user_dir}") or p.contains("{config_file}"), id)
	assert_true(LLMSetupHelp.prompt("local", paths).contains("/g/runtime/models/"))
	assert_true(LLMSetupHelp.prompt("ollama", paths).contains("/u/llm_config.json"))


func test_intro_says_who_to_give_it_to() -> void:
	var s := LLMSetupHelp.intro()
	assert_true(s.begins_with("Give this to a coding agent with access to the internet and your computer"))
	assert_true(s.contains("trusted location (e.g. ~/"))


func test_cloud_prompt_never_asks_for_the_key_in_chat() -> void:
	var p := LLMSetupHelp.prompt("cloud")
	assert_true(p.contains("Do not create an account"))
	assert_true(p.contains("ask me to paste the key into this chat") or p.contains("paste the key into this chat"))
