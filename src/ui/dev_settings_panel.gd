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
##
## Everything writes to the same places the game does (WorldState, the npc's
## Relationship, the look), so the cantina owner, rumors and checkpoint react as if
## it had happened in play.

const MOODS := ["wary", "warm", "amused", "irritated"]
const SPEEDS := [0.25, 0.5, 1.0, 2.0, 4.0]

var demo                              ## town_demo.gd
var _panel: PanelContainer
var _was_mouse := Input.MOUSE_MODE_VISIBLE
var _refreshers: Array[Callable] = []  ## each puts the live value back into its control
var _hour: HSlider
var _hour_label: Label
var _flags_box: VBoxContainer
var _flag_new: LineEdit
var builder: CharacterBuilder
var _god := false
var _endless_fuel := false


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
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(tabs)
	tabs.add_child(_world_tab())
	tabs.add_child(_standing_tab())
	tabs.add_child(_player_tab())
	tabs.add_child(_character_tab())
	tabs.add_child(_flags_tab())
	tabs.add_child(_hud_tab())
	var h := HBoxContainer.new()
	v.add_child(h)
	for b in [["Save now", _save], ["Close", close]]:
		var btn := Button.new()
		btn.text = b[0]
		btn.pressed.connect(b[1])
		h.add_child(btn)
	visible = false


## _input, not _unhandled_input: a focused slider or text field must not swallow F11.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11:
			toggle()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and visible:
			close()
			get_viewport().set_input_as_handled()


func _physics_process(_dt: float) -> void:
	var p = _player()
	if p == null:
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


func open() -> void:
	if visible:
		return
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
	for r in _refreshers:
		r.call()
	_rebuild_flags()


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
	var speed := OptionButton.new()
	for s in SPEEDS:
		speed.add_item("%sx" % str(s))
	speed.item_selected.connect(func(i): Engine.time_scale = SPEEDS[i])
	_row(v, "Game speed", speed)
	_refreshers.append(func(): speed.select(maxi(0, SPEEDS.find(Engine.time_scale))))
	var credits := _spin(0, 99999, 10)
	credits.value_changed.connect(func(x): WorldState.credits = int(x))
	_row(v, "Credits", credits)
	_refreshers.append(func(): credits.set_value_no_signal(WorldState.credits))
	# Issue #46: whether flying out of the atmosphere starts the pad's space fight.
	var dogfight := CheckBox.new()
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
	_section(v, "Factions  (-100 hostile .. 100 allied)")
	for fac in WorldState.FACTIONS:
		var s := _slider(-100, 100)
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
	var reset := Button.new()
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
	var trust := _slider(0, 100)
	var lab := Label.new()
	lab.custom_minimum_size = Vector2(120, 0)
	var paint := func(x): lab.text = "%d  %s" % [int(x), Relationship.tier_for(int(x))]
	trust.value_changed.connect(func(x):
		rel.trust = int(x)
		paint.call(x))
	_row(v, "Trust", trust).add_child(lab)
	var mood := OptionButton.new()
	for m in MOODS:
		mood.add_item(m)
	mood.item_selected.connect(func(i): rel.mood = MOODS[i])
	_row(v, "Mood", mood)
	var tab := _spin(0, 9999, 1)
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
		unban.disabled = rel.banned_until <= WorldState.clock)


func _faction_label(id: String) -> String:
	var f := FileAccess.open("res://content/core/factions/%s.json" % id, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f != null else null
	return str(d.get("label", id)) if d is Dictionary else id


# ------------------------------------------------------------------ player

func _player_tab() -> Control:
	var v := _tab("Player")
	_section(v, "Body")
	var god := CheckBox.new()
	god.text = "God mode (no damage)"
	god.toggled.connect(func(on):
		_god = on
		var p = _player()
		if p != null and not on:
			p.invulnerable_left = 0.0)
	v.add_child(god)
	var heal := Button.new()
	heal.text = "Heal / revive"
	heal.pressed.connect(func():
		var p = _player()
		if p != null:
			p.revive(0.0))
	_row(v, "", heal)

	_section(v, "Jetpack")
	var give := Button.new()
	give.text = "Give and wear jetpack"
	give.pressed.connect(_give_jetpack)
	_row(v, "", give)
	var fuel := CheckBox.new()
	fuel.text = "Endless fuel"
	fuel.toggled.connect(func(on): _endless_fuel = on)
	v.add_child(fuel)

	_section(v, "Teleport")
	var where := OptionButton.new()
	var ids: Array = []
	if demo != null:
		for m in demo.town.markers():
			if str(m.role) in ["spawn", "waypoint", "interact"]:
				ids.append(str(m.id))
				where.add_item(str(m.id).replace("_", " "))
	var go := Button.new()
	go.text = "Go"
	go.pressed.connect(func():
		if where.selected >= 0:
			teleport(ids[where.selected]))
	_row(v, "Marker", where).add_child(go)

	_section(v, "Debug")
	var npc_dbg := CheckBox.new()
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


## Stand on a town marker (not while flying).
func teleport(marker_id: String) -> bool:
	var p = _player()
	if p == null or p.piloting or demo.town.get_marker(marker_id).is_empty():
		return false
	p.global_position = demo.town.marker_pos(marker_id) + Vector3(0, 0.05, 0)
	p.velocity = Vector3.ZERO
	return true


# ------------------------------------------------------------------ flags

func _flags_tab() -> Control:
	var v := _tab("Flags")
	var note := Label.new()
	note.text = "World flags the content reads (rumors, jobs, moods). Changes apply at once."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)
	_flags_box = VBoxContainer.new()
	v.add_child(_flags_box)
	_flag_new = LineEdit.new()
	_flag_new.placeholder_text = "custom_flag"
	_flag_new.custom_minimum_size = Vector2(260, 0)
	var add := Button.new()
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


# ------------------------------------------------------------------ save

func _save() -> void:
	if demo != null and demo.bar != null:
		demo.bar._save_memory()


# ------------------------------------------------------------------ HUD (issue #52)

const KEYS := [
	["F1", "Info: planet, town, time, credits, standing"],
	["F3", "AI debug overlay"],
	["F4", "Guard debug (what each guard sees and hears)"],
	["F10", "AI model settings (Shift+F10: next model)"],
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
