class_name DevSettingsPanel
extends CanvasLayer
## F11 in the town: demo settings for dev and playtests. Opening it pauses the
## game and frees the mouse; closing it resumes and saves (when the bar saves).
## Tabs, so the real settings can move in later:
##   World     time of day (hour slider + presets), game speed, credits
##   Standing  faction standing, and each individual's trust / mood / tab
##   Player    god mode, heal, jetpack (give, endless fuel), teleport, guard debug
##   Character the player's outfit from the kit pieces (CharacterBuilder, issue #48)
##   Flags     every world flag the content reads, on or off, plus custom ones
##   HUD       the 80s HUD's colour (issue #52) and every function key
##   Sound     music and effects volume (issue #16)
##   Story     the main story's chapter, skip to one, and "Reset story" (issue #64)
##
## Everything writes to the same places the game does (WorldState, the npc's
## Relationship, the look), so the cantina owner, rumors and checkpoint react as if
## it had happened in play.
##
## A story save earns what free roam hands out: there the controls that would give
## it (credits, the space fight switch, standing and trust, god mode, heal, the
## jetpack, endless fuel, teleport, guard senses, flags) are greyed out, each page
## saying why. Game speed, the look, HUD, sound, the AI brain and the smuggler's
## own outfit stay the player's. A stuck player may still skip ahead a chapter,
## after a warning that points them at the characters first.

const MOODS := ["wary", "warm", "amused", "irritated"]
const SPEEDS := [0.25, 0.5, 1.0, 2.0, 4.0]

var demo                              ## town_demo.gd
var _panel: PanelContainer
var tabs: TabContainer               ## issue #80: open_tab() picks one by title
var _was_mouse := Input.MOUSE_MODE_VISIBLE
var _refreshers: Array[Callable] = []  ## each puts the live value back into its control
var _hour: HSlider
var _hour_label: Label
var _flags_box: VBoxContainer
var _flag_new: LineEdit
var builder: CharacterBuilder
var _god := false
var _endless_fuel := false
var _cheats: Array[Control] = []       ## greyed out in a story save (_lock_for_story)
var _story_notes: Array[Control] = []  ## shown only in a story save
var skip_confirm: ConfirmationDialog   ## a story save asks before skipping a chapter
var _skip_to := ""

const STUCK_WARNING := "If you are stuck, ask the interactive NPCs for advice, they may have a hint.\n\nAre you sure?"


func _ready() -> void:
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -340
	_panel.offset_right = 340
	_panel.offset_top = -300
	_panel.offset_bottom = 300
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.06, 0.06, 0.96)
	sb.border_color = Color("#b08e50")
	sb.set_border_width_all(1)
	for side in ["left", "right", "top", "bottom"]:
		sb.set("content_margin_" + side, 14)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_panel.add_child(v)
	var title := Label.new()
	title.text = "Demo settings  (F11)"
	title.add_theme_font_size_override("font_size", 18)
	v.add_child(title)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(tabs)
	var h := HBoxContainer.new()
	v.add_child(h)
	for b in [["Save now", _save], ["Close", close]]:
		var btn := Button.new()
		btn.text = b[0]
		btn.pressed.connect(b[1])
		h.add_child(btn)
	visible = false


## The pages themselves, made the first time the panel opens (issue #121: they cost
## about a second to build, on every arrival, for a panel most visits never open).
var tabs_built := false


func _build_tabs() -> void:
	if tabs_built:
		return
	tabs_built = true
	tabs.add_child(_world_tab())
	tabs.add_child(_standing_tab())
	tabs.add_child(_player_tab())
	tabs.add_child(_character_tab())
	tabs.add_child(_flags_tab())
	tabs.add_child(_hud_tab())
	tabs.add_child(_sound_tab())
	tabs.add_child(_story_tab())
	tabs.add_child(_llm_tab())


## _input, not _unhandled_input: a focused slider or text field must not swallow F11.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11:
			toggle()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and visible:
			close()
			get_viewport().set_input_as_handled()


## Issue #80: the cursor shows on every page while the settings are open, whatever
## else (a click in the world, a tab's own controls) tried to capture it.
func _process(_dt: float) -> void:
	if visible and Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(_dt: float) -> void:
	var p = _player()
	if p == null:
		return
	if WorldState.story_mode():
		return
	if _god:
		p.invulnerable_left = maxf(p.invulnerable_left, 1.0)
	if _endless_fuel and p.jetpack != null:
		p.jetpack.fuel = p.jetpack.fuel_max()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


## Issue #80: open on a tab by its title ("LLM": F10 lands here).
func open_tab(title: String) -> void:
	open()
	for i in tabs.get_tab_count():
		if tabs.get_tab_title(i) == title:
			tabs.current_tab = i


func open() -> void:
	if visible:
		return
	_build_tabs()
	visible = true
	_was_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false
	Input.mouse_mode = _was_mouse
	_save()


## Pull every control back from the live game (it changes while the panel is shut).
func refresh() -> void:
	if not tabs_built:
		return                      # nothing to refresh until the pages exist
	for r in _refreshers:
		r.call()
	_rebuild_flags()
	_lock_for_story()


## Grey out every control a story save has to earn in play, and show each page's
## note saying so; free roam gets them all back.
func _lock_for_story() -> void:
	var locked := WorldState.story_mode()
	for c in _cheats:
		if c is BaseButton:
			c.disabled = locked
		else:
			c.set("editable", not locked)   # sliders, spin boxes, line edits
	for n in _story_notes:
		n.visible = locked


## Register a control _lock_for_story greys out in a story save. Returns it.
func _cheat(c: Control) -> Control:
	_cheats.append(c)
	return c


## A page's line on what a story save keeps for play, hidden in free roam.
func _story_note(v: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = "Story save: " + text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	l.visible = false
	v.add_child(l)
	_story_notes.append(l)


# ------------------------------------------------------------------ world

func _world_tab() -> Control:
	var v := _tab("World")
	_section(v, "Time of day")
	_hour = HSlider.new()
	_hour.min_value = 0.0
	_hour.max_value = 24.0
	_hour.step = 0.25
	_hour.custom_minimum_size = Vector2(380, 0)
	_hour_label = Label.new()
	_hour_label.custom_minimum_size = Vector2(110, 0)
	_hour.value_changed.connect(func(h):
		demo.set_hour(h)
		_show_hour())
	var hr := _row(v, "Hour", _hour)
	hr.add_child(_hour_label)
	var presets := HBoxContainer.new()
	for id in ["golden", "noon", "dusk"]:
		var btn := Button.new()
		btn.text = id.capitalize()
		btn.pressed.connect(func():
			demo.set_preset(id)
			_hour.set_value_no_signal(maxf(0.0, demo.look.hour_of(id)) if demo.look != null else 0.0)
			_show_hour())
		presets.add_child(btn)
	_row(v, "Preset", presets)
	_refreshers.append(func():
		var h: float = demo.look.hour if demo.look != null and demo.look.hour >= 0.0 else \
			(demo.look.hour_of(demo.preset) if demo.look != null else 0.0)
		_hour.set_value_no_signal(maxf(0.0, h))
		_show_hour())

	_section(v, "Game")
	_story_note(v, "credits are earned and the Remnant fleet always meets you in orbit.")
	var speed := OptionButton.new()
	for s in SPEEDS:
		speed.add_item("%sx" % str(s))
	speed.item_selected.connect(func(i): Engine.time_scale = SPEEDS[i])
	_row(v, "Game speed", speed)
	_refreshers.append(func(): speed.select(maxi(0, SPEEDS.find(Engine.time_scale))))
	var credits: SpinBox = _cheat(_spin(0, 99999, 10))
	credits.value_changed.connect(func(x): WorldState.credits = int(x))
	_row(v, "Credits", credits)
	_refreshers.append(func(): credits.set_value_no_signal(WorldState.credits))
	# Issue #46: whether flying out of the atmosphere starts the pad's space fight.
	var dogfight: CheckBox = _cheat(CheckBox.new())
	dogfight.text = "Flying to space starts a dogfight"
	dogfight.toggled.connect(func(on): GameFlow.set_space_dogfight(on))
	_row(v, "", dogfight)
	_refreshers.append(func(): dogfight.set_pressed_no_signal(GameFlow.space_dogfight()))
	return v.get_parent()


func _show_hour() -> void:
	var h := _hour.value
	var preset: String = demo.preset if demo != null else ""
	_hour_label.text = "%02d:%02d  %s" % [int(h) % 24, int(round(fmod(h, 1.0) * 60.0)) % 60, preset]


# ------------------------------------------------------------------ standing

func _standing_tab() -> Control:
	var v := _tab("Standing")
	_story_note(v, "where you stand with each faction and person is earned in play. Shown here, not set.")
	_section(v, "Factions  (-100 hostile .. 100 allied)")
	for fac in WorldState.FACTIONS:
		var s: HSlider = _cheat(_slider(-100, 100))
		var lab := Label.new()
		lab.custom_minimum_size = Vector2(120, 0)
		var paint := func(x): lab.text = "%d  %s" % [int(x), WorldState.standing_label(int(x))]
		s.value_changed.connect(func(x):
			WorldState.standing[fac] = int(x)
			paint.call(x))
		_row(v, _faction_label(fac), s).add_child(lab)
		_refreshers.append(func():
			var x := int(WorldState.standing.get(fac, 0))
			s.set_value_no_signal(x)
			paint.call(x))
	var reset: Button = _cheat(Button.new())
	reset.text = "Reset to defaults"
	reset.pressed.connect(func():
		WorldState.standing = WorldState.DEFAULT_STANDING.duplicate()
		refresh())
	_row(v, "", reset)

	for who in _individuals():
		_individual(v, who.label, who.rel)
	return v.get_parent()


## Named people the player has a Relationship with. Only the cantina owner so far;
## add the next one here when an npc gets a Relationship.
func _individuals() -> Array:
	var out: Array = []
	if demo != null and demo.bar != null and demo.bar.brain != null:
		out.append({ "label": str(demo.bar.brain.card.get("name", "Cantina Owner")), "rel": demo.bar.brain.rel })
	return out


func _individual(v: VBoxContainer, label: String, rel: Relationship) -> void:
	_section(v, label + "  (trust 0 .. 100)")
	var trust: HSlider = _cheat(_slider(0, 100))
	var lab := Label.new()
	lab.custom_minimum_size = Vector2(120, 0)
	var paint := func(x): lab.text = "%d  %s" % [int(x), Relationship.tier_for(int(x))]
	trust.value_changed.connect(func(x):
		rel.trust = int(x)
		paint.call(x))
	_row(v, "Trust", trust).add_child(lab)
	var mood: OptionButton = _cheat(OptionButton.new())
	for m in MOODS:
		mood.add_item(m)
	mood.item_selected.connect(func(i): rel.mood = MOODS[i])
	_row(v, "Mood", mood)
	var tab: SpinBox = _cheat(_spin(0, 9999, 1))
	tab.value_changed.connect(func(x): rel.tab = int(x))
	var h := _row(v, "Tab owed", tab)
	var unban := Button.new()
	unban.text = "Clear ban"
	unban.pressed.connect(func():
		rel.banned_until = -1.0
		unban.disabled = true)
	h.add_child(unban)
	_refreshers.append(func():
		trust.set_value_no_signal(rel.trust)
		paint.call(rel.trust)
		mood.select(maxi(0, MOODS.find(rel.mood)))
		tab.set_value_no_signal(rel.tab)
		unban.disabled = WorldState.story_mode() or rel.banned_until <= WorldState.clock)


func _faction_label(id: String) -> String:
	var f := FileAccess.open("res://content/core/factions/%s.json" % id, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f != null else null
	return str(d.get("label", id)) if d is Dictionary else id


# ------------------------------------------------------------------ player

func _player_tab() -> Control:
	var v := _tab("Player")
	_story_note(v, "no god mode, free gear, teleports or guard x-ray; you live by your wits. How you look is on the Character page.")
	_section(v, "Body")
	var god: CheckBox = _cheat(CheckBox.new())
	god.text = "God mode (no damage)"
	god.toggled.connect(func(on):
		_god = on
		var p = _player()
		if p != null and not on:
			p.invulnerable_left = 0.0)
	v.add_child(god)
	var heal: Button = _cheat(Button.new())
	heal.text = "Heal / revive"
	heal.pressed.connect(func():
		var p = _player()
		if p != null:
			p.revive(0.0))
	_row(v, "", heal)

	_section(v, "Jetpack")
	var give: Button = _cheat(Button.new())
	give.text = "Give and wear jetpack"
	give.pressed.connect(_give_jetpack)
	_row(v, "", give)
	var fuel: CheckBox = _cheat(CheckBox.new())
	fuel.text = "Endless fuel"
	fuel.toggled.connect(func(on): _endless_fuel = on)
	v.add_child(fuel)

	_section(v, "Teleport")
	var where: OptionButton = _cheat(OptionButton.new())
	var ids: Array = []
	if demo != null:
		for m in demo.town.markers():
			if str(m.role) in ["spawn", "waypoint", "interact"]:
				ids.append(str(m.id))
				where.add_item(str(m.id).replace("_", " "))
	var go: Button = _cheat(Button.new())
	go.text = "Go"
	go.pressed.connect(func():
		if where.selected >= 0:
			teleport(ids[where.selected]))
	_row(v, "Marker", where).add_child(go)

	_section(v, "Debug")
	var npc_dbg: CheckBox = _cheat(CheckBox.new())
	npc_dbg.text = "Guard senses (F4)"
	npc_dbg.toggled.connect(func(on): NpcBody.show_debug = on)
	v.add_child(npc_dbg)
	_refreshers.append(func():
		god.set_pressed_no_signal(_god)
		fuel.set_pressed_no_signal(_endless_fuel)
		npc_dbg.set_pressed_no_signal(NpcBody.show_debug))
	return v.get_parent()


func _player():
	return demo._player if demo != null else null


# ------------------------------------------------------------------ character

## The builder saves each pick itself; the player's body wears it at once.
func _character_tab() -> Control:
	var v := _tab("Character")
	_story_note(v, "you play the smuggler; every piece and colour of their own kit is yours to pick.")
	builder = CharacterBuilder.new()
	builder.outfit_changed.connect(func(o):
		var a = _avatar()
		if a != null:
			a.set_outfit(o))
	v.add_child(builder)
	_refreshers.append(func():
		var a = _avatar()
		builder.show_outfit(a.worn_outfit() if a != null else PlayerOutfit.load_outfit()))
	return v.get_parent()


func _avatar() -> PlayerAvatar:
	return demo.player_kit.avatar if demo != null and demo.player_kit != null else null


func _give_jetpack() -> void:
	if demo == null or demo.gear == null:
		return
	var item: Dictionary = demo.gear.content.get_item("jetpack")
	var inv := WorldState.inventory
	if not inv.has("jetpack"):
		inv.add("jetpack")
	var on := inv.in_slot(str(item.get("slot", "")))
	if on != "" and on != "jetpack":
		inv.detach(on)
	inv.attach("jetpack", item)
	demo.gear.sync_gear()


## Stand on a town marker (not while flying, nor in a story save).
func teleport(marker_id: String) -> bool:
	var p = _player()
	if p == null or p.piloting or WorldState.story_mode() or demo.town.get_marker(marker_id).is_empty():
		return false
	p.global_position = demo.town.marker_pos(marker_id) + Vector3(0, 0.05, 0)
	if p.has_method("align_to_ground"):
		p.call("align_to_ground", true)
	else:
		p.velocity = Vector3.ZERO
	return true


# ------------------------------------------------------------------ flags

func _flags_tab() -> Control:
	var v := _tab("Flags")
	var note := Label.new()
	note.text = "World flags the content reads (rumors, jobs, moods). Changes apply at once."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)
	_story_note(v, "the story sets these as you play. Shown here, not set.")
	_flags_box = VBoxContainer.new()
	v.add_child(_flags_box)
	_flag_new = _cheat(LineEdit.new())
	_flag_new.placeholder_text = "custom_flag"
	_flag_new.custom_minimum_size = Vector2(260, 0)
	var add: Button = _cheat(Button.new())
	add.text = "Set"
	add.pressed.connect(func():
		var n := _flag_new.text.strip_edges()
		if n != "":
			WorldState.set_flag(n)
			_flag_new.text = ""
			_rebuild_flags())
	_row(v, "Add", _flag_new).add_child(add)
	return v.get_parent()


func _rebuild_flags() -> void:
	for c in _flags_box.get_children():
		c.queue_free()
	for flag in known_flags():
		var cb := CheckBox.new()
		cb.text = flag
		cb.button_pressed = WorldState.has_flag(flag)
		cb.disabled = WorldState.story_mode()   # made fresh each refresh, so not a _cheat
		cb.toggled.connect(func(on): WorldState.set_flag(flag, on))
		_flags_box.add_child(cb)


## Flags set now, plus every flag a rumor, job or mood rule asks about. Sorted.
func known_flags() -> Array:
	var seen := {}
	for f in WorldState.flags:
		seen[str(f)] = true
	var reqs: Array = []
	for r in WorldState.all_rumors():
		reqs.append(r.get("requires", {}))
	for j in WorldState.board():
		reqs.append(j.get("requires", {}))
	for req in reqs:
		for f in req.get("flags", []) + req.get("not_flags", []):
			seen[str(f)] = true
	if demo != null and demo.bar != null and demo.bar.brain != null:
		for r in demo.bar.brain.card.get("mood_rules", []):
			for f in r.get("if_flags", []):
				seen[str(f)] = true
	var out := seen.keys()
	out.sort()
	return out


# ------------------------------------------------------------------ story (issue #64)

func _story_tab() -> Control:
	var v := _tab("Story")
	_section(v, "Main story")
	var now := Label.new()
	now.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(now)
	var pick := OptionButton.new()
	for id in Story.chapter_ids():
		pick.add_item(str(id).replace("_", " "))
	var go := Button.new()
	go.pressed.connect(func():
		if pick.selected >= 0:
			skip_chapter(str(Story.chapter_ids()[pick.selected])))
	_row(v, "Chapter", pick).add_child(go)
	_story_note(v, "chapters are there to be played, but if you are truly stuck you can skip ahead (never back).")
	skip_confirm = ConfirmationDialog.new()
	skip_confirm.title = "Skip ahead?"
	skip_confirm.dialog_text = STUCK_WARNING
	skip_confirm.dialog_autowrap = true
	skip_confirm.min_size = Vector2i(420, 0)
	skip_confirm.ok_button_text = "Yes"
	skip_confirm.cancel_button_text = "No"
	skip_confirm.confirmed.connect(func():
		Story.skip_to(_skip_to)
		refresh())
	v.add_child(skip_confirm)
	_section(v, "New game")
	var note := Label.new()
	note.text = "Starts again as on a first play: credits, gear, droids, ships, every flag, faction standing and what each character thinks of you. Names are kept. The town reloads.\nStory: the story from the start, every faction neutral, the pistol only, locked to the smuggler.\nFree roam: drops and bounties on repeat, any character."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)
	var row := HBoxContainer.new()
	for m in [[WorldState.STORY, "New story game"], [WorldState.FREEPLAY, "New free roam game"]]:
		var b := Button.new()
		b.text = m[1]
		b.pressed.connect(func(): new_game(m[0]))
		row.add_child(b)
	_row(v, "", row)
	_refreshers.append(func():
		var b := WorldState.bounty
		now.text = "Now: %s save, %s%s" % ["story" if WorldState.story_mode() else "free roam", Story.chapter().replace("_", " "),
			("   ·   bounty on %s (%s)" % [b.name, b.state]) if str(b.get("state", "")) in ["out", "dead"] else ""]
		var at := Story.index(Story.chapter())
		pick.select(maxi(0, at))
		for i in pick.item_count:
			pick.set_item_disabled(i, WorldState.story_mode() and (i <= at or not Story.applies(Story.chapters()[i])))
		go.text = "Skip ahead" if WorldState.story_mode() else "Skip to it")
	return v.get_parent()


## Move the main story to chapter `id`. Free roam: at once, any chapter. A story
## save: only ahead, and only after the player says yes to STUCK_WARNING (the
## characters may have a hint first). Returns false when it will not skip.
func skip_chapter(id: String) -> bool:
	if Story.index(id) < 0:
		return false
	if not WorldState.story_mode():
		Story.skip_to(id)
		refresh()
		return true
	if Story.index(id) <= Story.index(Story.chapter()) or not Story.applies(Story.chapter_cfg(id)):
		return false
	_skip_to = id
	skip_confirm.popup_centered()
	return true


## Issue #64: back to the start, as on a first play. Everything the player has or
## has done goes (WorldState: credits, gear, droids, the bought ship, flags,
## standing, the story), every character's opinion of them goes back to a
## stranger's, T-89 says hello again; the names stay. Issue #200: in `mode`
## (WorldState.STORY or FREEPLAY). Saved, then the town is built again from
## scratch. `reload` false: just the state (tests).
func new_game(mode: String, reload := true) -> void:
	var kept := WorldState.names
	WorldState.new_game(mode)
	WorldState.names = kept
	ShipSalesman.greeted = false
	if WorldState.story_mode():
		# what free roam may have switched, which outlives the town reloading
		GameFlow.dogfight_override = null
		NpcBody.show_debug = false
	if demo != null and demo.bar != null:
		for s in demo.bar.spots:
			s.brain.rel = Relationship.new()
		demo.bar._save_memory()
	if not reload or not is_inside_tree():
		return
	visible = false
	get_tree().paused = false
	get_tree().reload_current_scene()


# ------------------------------------------------------------------ save

func _save() -> void:
	if demo != null and demo.bar != null:
		demo.bar._save_memory()


# ------------------------------------------------------------------ LLM (issue #80)

## The AI brain settings (they were a separate F10 panel): where the cantina
## owner's brain runs, its URLs, models and key, Test and Save.
func _llm_tab() -> Control:
	var v := _tab("LLM")
	var bar = demo.bar if demo != null and "bar" in demo else null
	if bar != null and bar.settings != null:
		_section(v, "AI CHARACTERS' BRAIN  (F10 opens this tab)")
		bar.settings.embed_into(v, self)
		_refreshers.append(func(): bar.settings._load())
	else:
		var l := Label.new()
		l.text = "No AI characters in this scene."
		v.add_child(l)
	return v.get_parent()


# ------------------------------------------------------------------ HUD (issue #52)

const KEYS := [
	["F1", "Info: planet, town, time, credits, standing"],
	["F3", "AI debug overlay"],
	["F4", "Guard debug (what each guard sees and hears; free roam only)"],
	["F10", "AI model settings: the LLM tab here (Shift+F10: next model)"],
	["F11", "These settings"],
	["E", "Interact: talk, board, ride, pick up"],
	["L", "Cycle the lighting"],
	["V", "First / third person"],
	["Esc", "Free the mouse, close a panel"],
]


func _hud_tab() -> Control:
	var v := _tab("HUD")
	_section(v, "HUD COLOUR")
	var grid := GridContainer.new()
	grid.columns = 3
	for name in RetroUI.PRESETS:
		var b := Button.new()
		b.text = name
		b.custom_minimum_size = Vector2(190, 0)
		b.pressed.connect(func(): _set_hud_color(RetroUI.PRESETS[name]))
		grid.add_child(b)
	v.add_child(grid)
	var pick := ColorPickerButton.new()
	pick.custom_minimum_size = Vector2(120, 30)
	pick.edit_alpha = false
	pick.color = RetroUI.accent
	pick.color_changed.connect(_set_hud_color)
	_row(v, "Your own", pick)
	_refreshers.append(func(): pick.color = RetroUI.accent)
	# Issue #71: one number sizes every UI element; saved per machine.
	_section(v, "TEXT SIZE")
	RetroUI.load_settings()
	var ui := RetroUI.ui()
	var size := _slider(int(round(float(ui.get("min", 0.75)) * 100.0)), int(round(float(ui.get("max", 2.0)) * 100.0)))
	size.step = float(ui.get("step", 0.05)) * 100.0
	size.value = roundf(RetroUI.text_scale * 100.0)
	var shown := Label.new()
	shown.text = "%d%%" % int(size.value)
	size.drag_ended.connect(func(_changed): RetroUI.set_text_scale(get_tree(), size.value / 100.0))
	size.value_changed.connect(func(x):
		shown.text = "%d%%" % int(x)
		if not size.has_focus():
			RetroUI.set_text_scale(get_tree(), x / 100.0))
	var row := _row(v, "Size", size)
	row.add_child(shown)
	var reset := Button.new()
	reset.text = "Default"
	reset.pressed.connect(func(): size.value = roundf(float(ui.get("text_scale", 1.25)) * 100.0); RetroUI.set_text_scale(get_tree(), size.value / 100.0))
	row.add_child(reset)
	_refreshers.append(func(): size.set_value_no_signal(roundf(RetroUI.text_scale * 100.0)); shown.text = "%d%%" % int(size.value))
	_section(v, "KEYS")
	for k in KEYS:
		var l := Label.new()
		l.text = "[%s]" % k[0]
		l.custom_minimum_size = Vector2(70, 0)
		var h := _row(v, "", l)
		h.get_child(0).custom_minimum_size = Vector2(0, 0)
		var what := Label.new()
		what.text = k[1]
		h.add_child(what)
	return v.get_parent()


## Issue #16: the music and the effects each get a volume, saved per machine.
func _sound_tab() -> Control:
	var v := _tab("Sound")
	_section(v, "VOLUME  (0 .. 100)")
	for bus in [[Sound.MUSIC_BUS, "Music"], [Sound.SFX_BUS, "Effects"]]:
		var s := _slider(0, 100)
		s.value = roundf(Sound.volume(bus[0]) * 100.0)
		s.value_changed.connect(func(x): Sound.set_volume(bus[0], x / 100.0))
		_row(v, bus[1], s)
		_refreshers.append(func(): s.set_value_no_signal(roundf(Sound.volume(bus[0]) * 100.0)))
	return v.get_parent()


func _set_hud_color(c: Color) -> void:
	if RetroSkin.current != null:
		RetroSkin.current.set_color(c)
	else:
		RetroUI.accent = c
		RetroUI.save_settings()


# ------------------------------------------------------------------ layout

## A scrolling page in the tab container; returns the column to fill.
func _tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	scroll.add_child(v)
	return v


func _section(v: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color("#d8b878"))
	v.add_child(l)


func _row(v: VBoxContainer, label: String, c: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(160, 0)
	h.add_child(l)
	h.add_child(c)
	v.add_child(h)
	return h


func _slider(lo: float, hi: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 1
	s.custom_minimum_size = Vector2(300, 0)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return s


func _spin(lo: float, hi: float, step: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	return s
