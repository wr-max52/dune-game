extends GutTest
## M0: the core data layer loads every entry under content/core and exposes it
## by id. This is the proof the IP-neutral layer actually works.

const CoreScript := preload("res://src/systems/dataload/core_content.gd")

var content


func before_each() -> void:
	content = CoreScript.new()


func test_loader_loads_manifest() -> void:
	var ok: bool = content.load_from()
	assert_true(ok, "load_from should succeed on the shipped content/core")
	assert_gt(content.manifest.size(), 0, "manifest should not be empty")


func test_all_weapons_present_by_id() -> void:
	content.load_from()
	var pistol: Dictionary = content.get_weapon("pistol_blaster")
	var rifle: Dictionary = content.get_weapon("rifle_blaster")
	var blade: Dictionary = content.get_weapon("energy_blade")
	assert_eq(pistol.get("class"), "pistol", "pistol class label")
	assert_eq(rifle.get("class"), "rifle", "rifle class label")
	assert_eq(blade.get("class"), "melee", "blade class label")
	assert_gt(pistol.get("damage", 0), 0, "pistol has damage")
	assert_eq(pistol.get("visible_bolt"), true, "pistol is a visible-bolt weapon")


func test_bartender_is_the_only_llm_npc() -> void:
	content.load_from()
	var llm_count := 0
	for id in content.npcs:
		if content.get_npc(id).get("kind") == "llm":
			llm_count += 1
	assert_eq(llm_count, 1, "exactly one LLM-driven npc (the bartender)")
	var bartender: Dictionary = content.get_npc("bartender")
	assert_eq(bartender.get("kind"), "llm", "bartender is LLM-driven")
	var expected := PackedStringArray(["give_rumor", "set_disposition", "offer_drink", "call_guards"])
	var tools: Array = bartender.get("tools", [])
	for tool in expected:
		assert_true(tools.has(tool), "tool present: " + str(tool))
	assert_eq(tools.size(), int(expected.size()), "no tools outside the allowed set")


func test_bartender_persona_prompt_is_loaded() -> void:
	content.load_from()
	var prompt: String = content.get_persona("bartender")
	assert_gt(prompt.length(), 50, "persona prompt text is loaded")


func test_fixer_has_authored_dialogue() -> void:
	content.load_from()
	var lines: Array = content.get_dialogue("fixer_lines")
	assert_gt(lines.size(), 0, "fixer has authored dialogue lines")
	var first: Dictionary = lines[0]
	assert_true(first.has("line"), "dialogue line has text")
	assert_true(first.has("speaker"), "dialogue line has speaker")


func test_loader_tolerates_missing_root() -> void:
	var ok: bool = content.load_from("res://this/path/does/not/exist")
	assert_false(ok, "missing root returns false, not crash")
