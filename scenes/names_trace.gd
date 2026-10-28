extends SceneTree
## Issue #15 trace (headless): the naming system in the real scenes. The town's
## guards, the town, its planet, your ship and the jetpack get names as they
## spawn; a guard's name floats over them up close; the cantina owner is briefed with
## them; a save and reload keeps every name; a new game with the same world seed
## gives the same names, another seed different ones; the space fight's pilots
## are named (new ones each sortie); and 5,000 people named in one game are all
## different.
##
## Writes test_results/names_trace.txt (KEY=value) for tests/test_names_trace.gut.gd.
## Run: godot --headless --fixed-fps 60 --path . -s res://scenes/names_trace.gd

const OUT := "res://test_results/names_trace.txt"
const CoreContent := preload("res://src/systems/dataload/core_content.gd")
const Dogfight := preload("res://src/systems/flight/dogfight.gd")

var demo
var lines := PackedStringArray()


func _initialize() -> void:
	WorldState.reset()
	GameFlow.reset()
	GameFlow.change_scene = func(_p: String) -> void: pass
	_run()


func out(k: String, v) -> void:
	lines.append("%s=%s" % [k, str(v)])


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func make_town() -> void:
	if demo != null:
		demo.queue_free()
		await frames(2)
	demo = load("res://scenes/town_demo.gd").new()
	demo.use_look = false
	get_root().add_child(demo)
	await frames(5)


func guard_names() -> PackedStringArray:
	var n := PackedStringArray()
	for npc in demo.npcs:
		n.append(npc.display_name)
	return n


func _run() -> void:
	var cc := CoreContent.new()
	cc.load_from()

	# ---------------------------------------------------------------- the town
	await make_town()
	var g := guard_names()
	out("GUARDS", demo.npcs.size())
	out("GUARD_NAMES", "|".join(g))
	var all_named := g.size() > 0
	for n in g:
		all_named = all_named and n != ""
	out("GUARDS_ALL_NAMED", all_named)
	var ranks: Array = WorldState.names.engine.lists.get("remnant_rank", [])
	var ranked := true
	for n in g:
		var ok := false
		for r in ranks:
			ok = ok or n.begins_with(str(r) + " ")
		ranked = ranked and ok
	out("GUARDS_HAVE_RANKS", ranked)
	out("GUARDS_UNIQUE", _unique(g))
	out("TOWN_NAME", demo.town_name)
	out("PLANET_NAME", demo.planet_name)
	out("PLACE_CARD", demo.place_card.text if demo.place_card != null else "")
	out("VESSEL_NAME", demo.pilot.vessel_name)
	out("BOARD_PROMPT", demo.pilot._foot_prompt.text)
	out("HUD_SHOWS_VESSEL", demo.pilot.hud.vessel_name == demo.pilot.vessel_name)
	var jet: Dictionary = cc.get_item("jetpack")
	out("JETPACK_SHOWN", demo.gear._shown(jet, "jetpack"))
	out("JETPACK_MODEL", NameHooks.equipment(jet, "jetpack"))
	out("CANTINA_OWNER_RESERVED", WorldState.names.by_key.get("npc:cantina_owner", ""))

	# Issue #65: names no longer float over heads; a calm guard shows no bar either.
	var guard = demo.npcs[0]
	var p = demo._player
	_place(p, guard.global_position + Vector3(3, 0, 0))
	await frames(4)
	out("NAMEPLATE_UP_CLOSE", guard.nameplate_shown())
	_place(p, guard.global_position + Vector3(40, 0, 0))
	await frames(4)
	out("NAMEPLATE_FAR_AWAY", guard.nameplate_shown())
	out("HEALTH_BAR_CALM", guard.health_bar_shown())
	out("DEBUG_LINE_NAMED", guard.debug_text().begins_with(guard.display_name))

	# The cantina owner is briefed with the place and the people.
	var builder := PromptBuilder.new({}, _json("res://content/core/llm/world_briefing.json"), {})
	var world := cc.get_world(str(builder.world_text.get("world", "")))
	var brief: Dictionary = builder.briefing({ "flags": {}, "standing": {}, "time": "golden", "events": [],
		"place": { "town": NameHooks.town(world), "planet": NameHooks.planet(world) },
		"people": NameHooks.known("npc:") }, Relationship.new(), [], [])
	var text := str(brief.message.content)
	out("BRIEF_PLACE_LINE", Array(text.split("\n")).filter(func(l): return l.begins_with("WHERE YOU ARE"))[0] if text.contains("WHERE YOU ARE") else "")
	out("BRIEF_HAS_TOWN", text.contains(demo.town_name))
	out("BRIEF_HAS_PLANET", text.contains(demo.planet_name))
	out("BRIEF_HAS_GUARD", text.contains(g[0]))

	# ---------------------------------------------------------------- save, reload
	var save := WorldState.to_save()
	var json := JSON.stringify(save)
	WorldState.from_save(JSON.parse_string(json))
	await make_town()
	out("RELOAD_SAME_GUARDS", "|".join(guard_names()) == "|".join(g))
	out("RELOAD_SAME_TOWN", demo.town_name == lines_get("TOWN_NAME"))
	out("RELOAD_SAME_VESSEL", demo.pilot.vessel_name == lines_get("VESSEL_NAME"))

	# Same world seed, new game: the same names (deterministic, no dice).
	WorldState.reset()
	await make_town()
	out("NEW_GAME_SAME_NAMES", "|".join(guard_names()) == "|".join(g) and demo.town_name == lines_get("TOWN_NAME"))
	# Another seed: another world.
	WorldState.reset()
	WorldState.names.world_seed = 99173
	await make_town()
	out("OTHER_SEED_TOWN", demo.town_name)
	out("OTHER_SEED_DIFFERENT", "|".join(guard_names()) != "|".join(g) and demo.town_name != lines_get("TOWN_NAME"))
	demo.queue_free()
	await frames(2)

	# ---------------------------------------------------------------- space
	WorldState.reset()
	var pilots := PackedStringArray()
	var callsigns := PackedStringArray()
	var named := 0
	var vessel := ""
	for sortie in 2:
		var df = Dogfight.new(cc, "orbital_skirmish", 7)
		df.names = WorldState.names
		df.name_scope = "pilot:orbital_skirmish/%d" % sortie
		df.start()
		for w in (df.encounter.get("waves", []) as Array).size():   # bring every wave in now
			df._spawn_wave(w)
		for s in df.ships:
			if s.is_player:
				vessel = s.vessel_name
				continue
			if s.pilot_name != "":
				named += 1
				pilots.append(s.pilot_name)
				callsigns.append(s.callsign)
		if sortie == 0:
			var foe: Dictionary = df.ships.filter(func(x): return not x.is_player and x.team != df.TEAM_PLAYER)[0]
			out("KILL_CALLOUT", Dogfight.who(foe))
	out("PILOTS_NAMED", named)
	out("PILOT_SAMPLE", "|".join(pilots.slice(0, 4)))
	out("CALLSIGN_SAMPLE", "|".join(callsigns.slice(0, 4)))
	out("PILOTS_UNIQUE", _unique(pilots))
	out("CALLSIGNS_UNIQUE", _unique(callsigns))
	out("SPACE_VESSEL_NAME", vessel)
	var fight = load("res://scenes/flight/dogfight_demo.gd").new()
	fight.autopilot = true
	get_root().add_child(fight)
	await frames(3)
	out("SPACE_PLANET", fight.planet_name)
	fight.queue_free()
	await frames(2)

	# ---------------------------------------------------------------- volume
	var book := NameBook.new()
	var many := PackedStringArray()
	var kinds := ["person_remnant", "person_dune", "person_drift"]
	var t0 := Time.get_ticks_usec()
	for i in 5000:
		many.append(book.name_for(kinds[i % 3], "crowd:%d" % i))
	out("CROWD_MS", snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1))
	out("CROWD_NAMED", many.size() - many.count(""))
	out("CROWD_UNIQUE", _unique(many))
	out("CROWD_CLASHES", book.clashes)
	out("LIBRARY_TERMS", book.engine.term_count())

	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_results"))
		f = FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("NAMESTRACE wrote ", OUT, " (", lines.size(), " lines)")
	GameFlow.reset()
	quit()


func lines_get(k: String) -> String:
	for l in lines:
		if l.begins_with(k + "="):
			return l.substr(k.length() + 1)
	return ""


func _unique(names: PackedStringArray) -> bool:
	var seen := {}
	for n in names:
		var k := NameEngine.normalize(n)
		if k == "" or seen.has(k):
			return false
		seen[k] = true
	return true


func _place(p, at: Vector3) -> void:
	p.global_position = at
	p.velocity = Vector3.ZERO
	p.controller.velocity = Vector3.ZERO
	p.controller.body_pos = at


func _json(path: String) -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}
