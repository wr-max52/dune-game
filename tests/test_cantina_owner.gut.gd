extends GutTest
## Issue #47: the Cantina Owner. A chat box you can read, directions by landmark
## (never east/west), and a bottle on the counter for every paid drink, each a
## different colour from the last. Issue #42: what each character may do is on
## their card, so she never sells speeders and Skrugs never offers jobs.

const COMPASS := ["north", "south", "east", "west"]
const TownLayout := preload("res://src/systems/world/town_layout.gd")


func _card(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _builder(card_path: String) -> PromptBuilder:
	return PromptBuilder.new(_card(card_path), _card("res://content/core/llm/world_briefing.json"),
		_card("res://content/core/llm/reply_schema.json"))


# ---- the chat box -------------------------------------------------------------------

func test_the_chat_box_is_big_and_readable() -> void:
	var p := DialoguePanel.new()
	add_child_autofree(p)
	await wait_frames(1)
	var size := p.box_size()
	var vp := get_viewport().get_visible_rect().size
	assert_almost_eq(size.x, clampf(vp.x - DialoguePanel.MARGIN * 2.0, DialoguePanel.MIN_SIZE.x, DialoguePanel.WIDTH), 1.0)
	assert_almost_eq(size.y, clampf(vp.y * 0.5, DialoguePanel.MIN_SIZE.y, DialoguePanel.HEIGHT), 1.0)
	assert_gt(size.y, 230.0, "taller than the old 230 px box")
	assert_gt(DialoguePanel.WIDTH, 940.0, "on a normal window, wider than the old 940 px box")
	assert_gte(p._line.get_theme_font_size("normal_font_size"), 26, "her line is large")
	assert_gte(p._history.get_theme_font_size("normal_font_size"), 18, "the history is readable")
	assert_gte(p._field.get_theme_font_size("font_size"), 20, "so is what you type")


func test_the_sale_card_only_buys_on_a_click_you_can_afford() -> void:
	var p := DialoguePanel.new()
	add_child_autofree(p)
	await wait_frames(1)
	var answers: Array = []
	p.sale_answered.connect(func(id, yes): answers.append([id, yes]))
	p.show_sale({ "id": "speeder", "name": "speeder", "price": 100, "text": "Fast." }, 40)
	assert_true(p._yes.disabled, "40 credits: the Buy button is off")
	p.answer_card(true)
	assert_eq(answers.size(), 0, "nothing bought")
	p.show_sale({ "id": "speeder", "name": "speeder", "price": 100, "text": "Fast." }, 140)
	assert_false(p._yes.disabled)
	p.answer_card(true)
	assert_eq(answers, [["speeder", true]])


# ---- her prompt ----------------------------------------------------------------------

func test_she_gives_directions_by_landmark_never_compass() -> void:
	var b := _builder("res://content/core/npcs/cantina_owner_card.json")
	var persona := str(b.persona_message().content)
	assert_string_contains(persona, "front gate")
	assert_string_contains(persona, "back gate")
	assert_string_contains(str(b.rules_message().content), "Never say north, south, east or west")
	for path in ["res://content/core/llm/world_briefing.json", "res://content/core/rumors/port_town.json",
			"res://content/core/board/bar_board.json", "res://content/core/pickups/port_town.json"]:
		var text := FileAccess.get_file_as_string(path).to_lower()
		for w in COMPASS:
			assert_false(RegEx.create_from_string("\\b" + w + "\\b").search(text) != null, "%s says '%s'" % [path, w])


func test_her_voice_answers_plainly_and_knows_skrugs() -> void:
	var card := _card("res://content/core/npcs/cantina_owner_card.json")
	assert_eq(str(card.label), "Cantina Owner")
	assert_false(str(card.voice).contains("Answers some questions with prices"), "no more riddles in prices")
	assert_true(str(card.voice).contains("Answer what they asked first"))
	assert_lt(float(card.temperature), 0.8, "steadier than the old 0.8")
	assert_string_contains(str(card.people), "Skrugs")


# ---- who may do what -----------------------------------------------------------------

func test_each_character_only_hears_of_their_own_actions() -> void:
	var oda := str(_builder("res://content/core/npcs/cantina_owner_card.json").rules_message().content)
	assert_string_contains(oda, "pour_drink")
	assert_string_contains(oda, "offer_job")
	assert_false(oda.contains("offer_speeder"), "she does not sell speeders")


func test_the_validator_drops_what_a_character_may_not_do() -> void:
	var ids := { "rumors": [], "jobs": ["j1"], "secrets": [], "drinks": {}, "allowed": ["share_rumor", "trust", "offer_speeder"],
		"sale": { "id": "speeder", "name": "speeder", "price": 100 } }
	var v := ActionValidator.validate([{ "type": "offer_job", "id": "j1" }, { "type": "offer_speeder", "price": 1 }], ids, {})
	assert_eq(v.kept.size(), 1)
	assert_eq(str(v.kept[0].type), "offer_speeder")
	assert_eq(int(v.kept[0].price), 100, "the game's price, not the model's")
	assert_eq(str(v.dropped[0].why), "not something this character does")


# ---- bottles on the counter -------------------------------------------------------------

func _bar() -> CantinaOwnerNPC:
	var town := TownLayout.new()
	assert_true(town.load_town("port_town"))
	var dressing := CantinaDressing.new()
	add_child_autofree(dressing)
	dressing.dress(town, LookMaterials.new())
	var npc := CantinaOwnerNPC.new()
	add_child_autofree(npc)
	npc.global_position = Vector3(float(town.get_box("bar_counter").min[0]) - 0.55, 0, 0)
	npc.dressing = dressing
	return npc


func _run(npc: CantinaOwnerNPC, seconds: float) -> void:
	for i in int(seconds * 60.0):
		npc._tick_serve(1.0 / 60.0)


func test_a_paid_drink_puts_a_bottle_on_the_counter() -> void:
	var npc := _bar()
	npc.serve({ "paid": true })
	assert_true(npc.serving(), "she goes for a bottle")
	_run(npc, CantinaOwnerNPC.SERVE_TIME + 0.1)
	assert_eq(npc.bottles_served, 1)
	assert_eq(npc.dressing.served.size(), 1)
	var b: Node3D = npc.dressing.served[0]
	assert_almost_eq(b.global_position.y, npc.dressing.counter_max.y + 0.06, 0.01, "standing on the counter top")
	assert_lt(Vector2(b.global_position.x - npc.global_position.x, b.global_position.z - npc.global_position.z).length(), 1.5, "within her reach")


func test_drinks_on_the_tab_get_no_bottle() -> void:
	var npc := _bar()
	npc.serve({ "paid": false })
	_run(npc, CantinaOwnerNPC.SERVE_TIME + 0.1)
	assert_eq(npc.bottles_served, 0)


func test_every_bottle_a_new_colour_one_after_another() -> void:
	var npc := _bar()
	for i in 5:
		npc.serve({ "paid": true })
	_run(npc, CantinaOwnerNPC.SERVE_TIME * 5 + 0.5)
	assert_eq(npc.bottles_served, 5, "all five brought, one after another")
	for i in range(1, npc.serve_colors.size()):
		assert_ne(npc.serve_colors[i], npc.serve_colors[i - 1], "bottle %d differs from the one before" % i)
	var spots := {}
	for b in npc.dressing.served:
		spots[str(b.global_position.snapped(Vector3.ONE * 0.01))] = true
	assert_eq(spots.size(), 5, "each in its own spot")


func test_the_row_keeps_twelve() -> void:
	var npc := _bar()
	for i in CantinaDressing.SERVED_MAX + 3:
		npc.serve({ "paid": true })
	_run(npc, CantinaOwnerNPC.SERVE_TIME * (CantinaDressing.SERVED_MAX + 3) + 0.5)
	assert_eq(npc.dressing.served.size(), CantinaDressing.SERVED_MAX, "the oldest go once the row is full")
