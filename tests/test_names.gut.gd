extends GutTest
## Issue #15: the name engine and the name book, pure. The library loads and is
## big; every kind's grammar only names lists and tongues that exist; nothing in
## it (or anything it makes) is a franchise name or a rude word; the same key
## always gives the same name; names are unique across the game, authored names
## are never handed out, and the book survives a save.

const CoreContent := preload("res://src/systems/dataload/core_content.gd")

var engine: NameEngine
var ip: Dictionary


func before_all() -> void:
	engine = NameBook.load_engine()
	ip = JSON.parse_string(FileAccess.get_file_as_string("res://content/core/llm/ip_blocklist.json"))


func test_the_library_loads_and_is_big() -> void:
	assert_gt(engine.term_count(), 2000, "thousands of terms")
	for k in ["person_remnant", "person_dune", "person_drift", "callsign", "vessel", "equipment", "maker", "town", "planet", "moon", "star"]:
		assert_true(engine.kinds.has(k), "kind " + k)
	for t in ["hard", "dune", "drift", "astral"]:
		assert_true(engine.tongues.has(t), "tongue " + t)


func test_core_content_loads_the_banks_too() -> void:
	var cc := CoreContent.new()
	cc.load_from()
	assert_eq(cc.names.size(), 6, "every bank in the manifest")


## Every {list}, {@rule} and {~tongue} a grammar names exists (a typo would
## quietly make empty names).
func test_every_grammar_reference_resolves() -> void:
	var missing := PackedStringArray()
	var templates := []
	for k in engine.kinds:
		for p in engine.kinds[k].patterns:
			templates.append(str(p[0]))
	for r in engine.rules:
		for p in engine.rules[r]:
			templates.append(str(p[0]) if p is Array else str(p))
	var re := RegEx.create_from_string("\\{([^{}]+)\\}")
	for t in templates:
		for m in re.search_all(t):
			var head: String = m.get_string(1).split(":")[0]
			if head.begins_with("#"):
				continue
			if head.begins_with("@"):
				if not engine.rules.has(head.substr(1)):
					missing.append(head)
			elif head.begins_with("~"):
				if not engine.tongues.has(head.substr(1)):
					missing.append(head)
			elif head.contains("%("):
				for c in ["jetpack", "blaster", "blade", "ship", "armor", "tool"]:
					var l := head.replace("%(class)", c)
					if not engine.lists.has(l):
						missing.append(l)
			elif not engine.lists.has(head):
				missing.append(head)
	assert_eq(missing.size(), 0, "unresolved: " + str(missing))


func test_no_term_is_a_franchise_name() -> void:
	var bad := PackedStringArray()
	var words: Array = ip.get("name_terms", [])
	var subs: Array = ip.get("terms", [])
	for k in engine.lists:
		for term in engine.lists[k]:
			var low := str(term).to_lower()
			for s in subs:
				if low.contains(s):
					bad.append(term)
			for w in low.replace("-", " ").replace("'", " ").replace("\"", " ").split(" ", false):
				if words.has(w):
					bad.append(term)
	assert_eq(bad.size(), 0, "franchise names in the library: " + str(bad))
	assert_gt(words.size(), 100, "the franchise name list loads")


func test_denied_words_and_franchise_names_are_rejected() -> void:
	assert_false(engine.acceptable("Han Dorn"), "a franchise name as a whole word")
	assert_true(engine.acceptable("Hanna Dorn"), "but not as part of another name")
	assert_false(engine.acceptable("Varo Skywalker"))
	assert_false(engine.acceptable("Kit Ass"), "a rude whole word")
	assert_true(engine.acceptable("Cassia Brandt"), "a rude word inside a name is fine")
	assert_false(engine.acceptable("Shitvar Kel"), "a rude fragment anywhere")


## A few hundred of every kind: none empty, all within length, none rejected.
func test_every_kind_makes_good_names() -> void:
	for kind in engine.kinds:
		var k: Dictionary = engine.kinds[kind]
		var empty := 0
		var bad := PackedStringArray()
		for i in 300:
			var n := engine.generate(kind, NameEngine.fnv("%s/%d" % [kind, i]), { "class": "blaster", "planet": "Vessar" })
			if n == "":
				empty += 1
			elif not engine.acceptable(n, k) or n.contains("{") or n.contains("%("):
				bad.append(n)
		assert_lt(empty, 3, "%s: names come out" % kind)
		assert_eq(bad.size(), 0, "%s: %s" % [kind, bad])


func test_made_up_words_stay_pronounceable() -> void:
	for t in engine.tongues:
		for i in 400:
			engine._rng.seed = NameEngine.fnv("%s/%d" % [t, i])
			var w := engine.word(t)
			if w == "":
				continue
			assert_lte(NameEngine._vowel_run(w), int(engine.tongues[t].get("max_vowel_run", 2)), w)
			assert_false(NameEngine._triple(w), w)


func test_same_key_same_name_every_time() -> void:
	var a := NameBook.new(engine)
	var b := NameBook.new(engine)
	for i in 50:
		var key := "npc:test/%d" % i
		assert_eq(a.name_for("person_dune", key), b.name_for("person_dune", key))
	assert_eq(a.name_for("person_dune", "npc:test/3"), a.name_for("person_dune", "npc:test/3"), "asked twice, one name")


func test_another_world_seed_another_world() -> void:
	var a := NameBook.new(engine)
	var b := NameBook.new(engine)
	b.world_seed = a.world_seed + 1
	var same := 0
	for i in 40:
		if a.name_for("town", "town:%d" % i) == b.name_for("town", "town:%d" % i):
			same += 1
	assert_lt(same, 4)


func test_names_are_unique_across_the_game() -> void:
	var book := NameBook.new(engine)
	var seen := {}
	for i in 1500:
		var n := book.name_for("callsign", "pilot:%d" % i)
		assert_ne(n, "", "callsign %d" % i)
		assert_false(seen.has(NameEngine.normalize(n)), "duplicate " + n)
		seen[NameEngine.normalize(n)] = true
	assert_gt(book.clashes, 0, "with 1,500 callsigns some first picks were taken and re-rolled")


func test_authored_names_are_never_handed_out() -> void:
	var a := NameBook.new(engine)
	var wanted := a.name_for("person_remnant", "npc:x")
	var b := NameBook.new(engine)
	assert_true(b.reserve(wanted, "npc:authored"))
	var got := b.name_for("person_remnant", "npc:x")
	assert_ne(got, "")
	assert_ne(NameEngine.normalize(got), NameEngine.normalize(wanted), "the reserved name went to its author")
	assert_eq(b.by_key.get("npc:cantina_owner", ""), "Oda Vell", "the cantina owner's own name is reserved from the start")
	assert_false(b.reserve("Oda Vell", "npc:someone_else"), "and nobody else can claim it")


func test_titles_are_picked_not_spent() -> void:
	var book := NameBook.new(engine)
	var shown := NameHooks.person({ "kind": "person_remnant", "titles": "remnant_rank" }, "npc:t", book)
	var name: String = book.by_key["npc:t"]
	assert_true(shown.ends_with(name))
	assert_true(engine.lists.remnant_rank.has(shown.trim_suffix(" " + name)))
	assert_eq(NameHooks.person({ "kind": "person_remnant", "titles": "remnant_rank" }, "npc:t", book), shown, "stable")
	assert_eq(NameHooks.person({}, "npc:none", book), "", "no naming block, no name")


func test_hooks_name_things_from_their_data() -> void:
	var cc := CoreContent.new()
	cc.load_from()
	var book := NameBook.new(engine)
	assert_ne(NameHooks.equipment(cc.get_item("jetpack"), "jetpack", book), "")
	assert_ne(NameHooks.vessel(cc.get_ship("interceptor"), "vessel:player/interceptor", book), "")
	var world := cc.get_world("port_desert")
	assert_ne(NameHooks.town(world, book), "")
	assert_ne(NameHooks.planet(world, book), "")
	assert_ne(NameHooks.callsign(cc.get_ship("remnant_fighter").naming, "pilot:x", book), "")
	assert_eq(NameHooks.callsign({}, "pilot:y", book), "", "no callsign unless the data asks")


func test_the_book_survives_a_save() -> void:
	WorldState.reset()
	var n := WorldState.names.name_for("planet", "planet:save_test")
	var shown := NameHooks.person({ "kind": "person_drift", "titles": "remnant_rank" }, "npc:save_test")
	var saved := JSON.parse_string(JSON.stringify(WorldState.to_save()))
	WorldState.reset()
	WorldState.names.world_seed = 5
	WorldState.from_save(saved)
	assert_eq(WorldState.names.by_key.get("planet:save_test", ""), n)
	assert_eq(NameHooks.person({ "kind": "person_drift", "titles": "remnant_rank" }, "npc:save_test"), shown)
	assert_true(WorldState.names.is_taken(n), "still taken after a reload")
	assert_eq(WorldState.names.world_seed, NameBook.new(engine).world_seed, "the saved seed comes back")
	WorldState.reset()


func test_roman_numerals_and_modifiers() -> void:
	assert_eq(NameEngine.roman(4), "IV")
	assert_eq(NameEngine.roman(1999), "MCMXCIX")
	assert_eq(NameEngine.modify("veyra prime", "title"), "Veyra Prime")
	assert_eq(NameEngine.modify("kesh", "first"), "K")
	assert_eq(NameEngine.normalize("Kael-Dorn"), NameEngine.normalize("kael dorn"))
