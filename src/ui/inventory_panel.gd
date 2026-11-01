class_name InventoryPanel
extends HBoxContainer
## The Ledger (M15): a page of the settings panel, on I (DevSettingsPanel; M is its
## Map page). Two columns, each scrolling on its own.
##
## Left, what you own: credits; the backpack (Inventory.slots_used), its numbered
## slots, the pistol in the first, one kind of item in each of the rest, then the
## empty ones; the gear you have on (the jetpack, the armour) with its Take off
## button; your droids; your ships and what T-89 fitted to them (issue #207); the
## fence's gear upgrades (issue #208). Each item says how many, what a vendor would
## pay, and CONTRABAND on what the Remnant would confiscate at the gate.
##
## Right, the story and your jobs (Objective.log_entries), then the optional quests
## (Quests.entries, issue #201), then the tally. Every one with somewhere to point
## has a waypoint button: the one picked is what the HUD's pointer and the Map show
## (Objective.pin; a quest's is Quests.toggle_waypoint). The card the pointer is on
## now is lit, picked or not (unpicked, the pointer takes the most urgent).
##
## No game logic: the settings panel hands it GearController's item data and wear
## toggle; it only reads, and calls the pickers above.
##
## Issue #368: your ships (Fleet.rows), each with its upgrades and where it is; the
## primary marked, with the Call button (greyed out while she is on her way), and a
## Set primary button on each of the others.

const INK := Color(0.95, 0.92, 0.85, 0.95)
const AMBER := Color("#e0a050")
const RED := Color("#ff6a55")
const DIM := 0.55                 ## alpha of the second line under a name, done quests, the tally

var inventory: Inventory          ## null = WorldState.inventory, read fresh (a load replaces it)
var content                       ## CoreContent (item labels, values, contraband)
var name_of: Callable             ## id -> shown name (GearController._shown); optional
var toggle_item: Callable         ## issue #209: id -> put a worn item on or off (GearController.toggle_item); optional
var wear_buttons: Dictionary = {}  ## item id -> its Wear / Take off button (tests)
var on_waypoint: Callable         ## called after a waypoint button changes the pointer (the HUD refreshes); optional
var set_primary: Callable         ## issue #368: Fleet key -> make it the primary (ShipPilot.set_primary); optional
var call_ship: Callable           ## issue #368: -> "" (on her way) or a label key why not (ShipPilot.call_ship); optional
var call_state: Callable          ## issue #368: -> { ok, text } for the Call button (ShipPilot.call_state); optional
var on_called: Callable           ## issue #368: after a call went out (the settings panel closes); optional
var primary_buttons: Dictionary = {}  ## issue #368: Fleet key -> its Set primary button (tests)
var call_button: Button           ## issue #368: the primary's Call button (tests), or null
var title: Label
var credits_label: Label
var backpack_label: Label
var list: VBoxContainer           ## the left column under the credits
var jobs: VBoxContainer           ## the right column under its heading
var rows: Array = []              ## the text of each backpack, worn and droid row, for tests
var owned_rows: Array = []        ## the ships and gear upgrades, for tests
var job_rows: Array = []          ## the job log's text, title then line, for tests
var quest_buttons: Dictionary = {}  ## quest id -> its waypoint toggle (tests)
var point_buttons: Dictionary = {}  ## job log key -> its waypoint toggle (tests)


func _init() -> void:
	name = Objective.line("ledger_tab")    # the tab's title
	add_theme_constant_override("separation", 18)


func _ready() -> void:
	var v := _column(0.85)
	var head := HBoxContainer.new()
	v.add_child(head)
	title = _text(head, Objective.line("ledger_owned"), 20, AMBER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	credits_label = _text(head, "", 18, INK)
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	v.add_child(list)
	var jv := _column(1.0)
	_text(jv, Objective.line("log_title"), 20, AMBER)
	jobs = VBoxContainer.new()
	jobs.add_theme_constant_override("separation", 10)
	jv.add_child(jobs)


## One of the two columns: its own scroll, a column to fill inside.
func _column(stretch: float) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = stretch
	add_child(scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	return v


func _text(parent: Control, t: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


## A heading inside a column: gold, small, a rule under it.
func _heading(parent: Control, t: String) -> Label:
	var gap := Control.new()
	gap.custom_minimum_size.y = 4
	parent.add_child(gap)
	var l := _text(parent, t, 15, AMBER)
	var rule := ColorRect.new()
	rule.color = Color(AMBER, 0.35)
	rule.custom_minimum_size.y = 1
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rule)
	return l


## Rebuild both columns from the game as it is now.
func refresh() -> void:
	_job_log()
	rows.clear()
	owned_rows.clear()
	wear_buttons.clear()
	for c in list.get_children():
		c.queue_free()
	credits_label.text = "%d cr" % WorldState.credits
	var inv: Inventory = inventory if inventory != null else WorldState.inventory
	_heading(list, "%s   %d / %d" % [Objective.line("ledger_backpack"), inv.slots_used(), Inventory.backpack_slots()])
	var n := 0
	for label in Inventory.fixed_slots():
		n += 1
		rows.append("[%d]  %s" % [n, str(label)])
		_line(list, "%d  %s" % [n, str(label)], "", INK)
	for id in inv.packed_ids():
		n += 1
		_item_row(inv, str(id), n)
	for i in range(n, Inventory.backpack_slots()):
		rows.append("[%d]  - empty -" % (i + 1))
		_line(list, "%d  -" % (i + 1), "", Color(INK, 0.4))
	var worn: Array = inv.item_ids().filter(func(id): return inv.is_attached(str(id)))
	if not worn.is_empty():
		_heading(list, Objective.line("ledger_worn"))
		for id in worn:
			_item_row(inv, str(id), 0)
	_droid_rows()
	_owned_rows()


## One kind of item: its name over how many, its value and CONTRABAND, with the
## Wear / Take off button for gear on the right. `slot` 0 = worn, no number.
func _item_row(inv: Inventory, id: String, slot: int) -> void:
	var it: Dictionary = content.get_item(id) if content != null else {}
	var shown: String = name_of.call(it, id) if name_of.is_valid() else str(it.get("label", id))
	var prefix := "[%d]  " % slot if slot > 0 else ""
	var row := "%s%s  x%d" % [prefix, shown, inv.count(id)]
	if inv.is_attached(id):
		row += "   (activated)"
	row += "   %d cr" % int(it.get("value", 0))
	var illegal := bool(it.get("contraband", false))
	if illegal:
		row += "   CONTRABAND"
	rows.append(row)
	var detail := "x%d    %d cr" % [inv.count(id), int(it.get("value", 0))]
	if illegal:
		detail += "    CONTRABAND"
	var h := _line(list, ("%d  " % slot if slot > 0 else "") + shown, ("   " if slot > 0 else "") + detail, RED if illegal else INK)
	if toggle_item.is_valid() and str(it.get("slot", "")) != "":
		_wear_button(h, id, inv.is_attached(id), it.get("toggle_labels", ["Wear", "Take off"]))


## A row in the left column: a name, a dim line under it, room on the right for a
## button. Returns the row.
func _line(parent: Control, name_text: String, detail: String, color: Color) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	parent.add_child(h)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	_wrap(_text(v, name_text, 16, color))
	if detail != "":
		_wrap(_text(v, detail, 13, Color(color, DIM)))
	return h


## The job log, from Objective: a card per entry, its title and waypoint button
## over its line; the optional quests; the tally.
func _job_log() -> void:
	job_rows.clear()
	point_buttons.clear()
	for c in jobs.get_children():
		c.queue_free()
	var now := Objective.current_key()
	if now == "map":
		var mark := GlobeMap.waypoint()
		var card := _card(jobs, true)
		var h := _card_head(card, Objective.line("ledger_map"))
		_point_button(h, true, true, func():
			GlobeMap.clear_waypoint()
			_changed())
		_wrap(_text(card, str(mark.get("text", "")), 15, INK))
	for e in Objective.log_entries():
		var key := str(e.get("key", ""))
		var lit := key != "" and key == now
		var card := _card(jobs, lit)
		if str(e.title) != "":
			job_rows.append(str(e.title))
		var h := _card_head(card, str(e.title))
		if key != "" and Objective.can_pin(key):
			var b := _point_button(h, lit, lit and WorldState.objective_pin != key, func():
				Objective.pin(key)
				_changed())
			point_buttons[key] = b
		job_rows.append(str(e.text))
		_wrap(_text(card, str(e.text), 15, INK))
	_quest_log(now)
	job_rows.append(Objective.tally())
	_text(jobs, job_rows[-1], 13, Color(INK, DIM))


## Issue #201: the optional quests under their own heading: title and status,
## the text, and a waypoint toggle while it is open and has somewhere to point.
func _quest_log(now: String) -> void:
	quest_buttons.clear()
	var qs := Quests.entries()
	if qs.is_empty():
		return
	job_rows.append(Objective.line("log_quests"))
	_heading(jobs, job_rows[-1])
	for q in qs:
		var closed: bool = q.done or q.get("failed", false)
		var id := str(q.id)
		var head := "%s   (%s)" % [str(q.title).to_upper(), Objective.line("quest_failed" if q.get("failed", false) else ("quest_done" if q.done else "quest_open"))]
		job_rows.append(head)
		var card := _card(jobs, now == "quest:" + id)
		card.modulate.a = DIM if closed else 1.0
		var h := _card_head(card, head)
		if q.can_point:
			quest_buttons[id] = _point_button(h, q.waypoint, false, func():
				Quests.toggle_waypoint(id)
				_changed())
		job_rows.append(str(q.text))
		_wrap(_text(card, str(q.text), 15, INK))


## A job's card: a thin rim, lit (thicker, the HUD colour) while the pointer is on
## it. Not re-skinned (RetroSkin would give every card the same rim); built fresh
## on each refresh, so it follows a new HUD colour anyway. Returns its column.
func _card(parent: Control, lit: bool) -> VBoxContainer:
	var p := PanelContainer.new()
	p.set_meta("retro_off", true)
	var sb := StyleBoxFlat.new()
	var a := RetroUI.accent
	sb.bg_color = Color(a.darkened(0.85), 0.9) if lit else Color(0, 0, 0, 0.25)
	sb.border_color = a if lit else Color(a, 0.22)
	sb.set_border_width_all(1)
	sb.border_width_left = 4 if lit else 1
	sb.set_content_margin_all(8)
	sb.content_margin_left = 12
	p.add_theme_stylebox_override("panel", sb)
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	return v


func _card_head(card: VBoxContainer, t: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	card.add_child(h)
	var l := _text(h, t, 14, AMBER)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 80
	return h


## The waypoint toggle on a card: "Set waypoint", or lit "Waypoint" when the pointer
## is on it ("Waypoint (auto)" when it is there only for being the most urgent).
func _point_button(h: HBoxContainer, on: bool, auto: bool, act: Callable) -> Button:
	var b := Button.new()
	b.text = Objective.line("point_auto" if auto else ("point_on" if on else "point_off"))
	b.toggle_mode = true
	b.set_pressed_no_signal(on)
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(act)
	h.add_child(b)
	return b


func _changed() -> void:
	refresh()
	if on_waypoint.is_valid():
		on_waypoint.call()


## Issue #209: a worn item's toggle (the jetpack, the armour; the red saber's
## Activate / Put away, its item's "toggle_labels": [on, off]), on its row's right.
func _wear_button(h: HBoxContainer, id: String, on: bool, labels: Array = ["Wear", "Take off"]) -> void:
	var b := Button.new()
	b.text = str(labels[1]) if on else str(labels[0])
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(func():
		toggle_item.call(id)
		refresh())
	h.add_child(b)
	wear_buttons[id] = b


func _wrap(l: Label) -> void:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 120


## Issue #51: your droids, one row each, with their health and hold size. What
## a cargo droid carries is not listed (and not in the inventory): the gate never
## sees it either.
func _droid_rows() -> void:
	if WorldState.droids.owned.is_empty():
		return
	_heading(list, Objective.line("ledger_droids"))
	for d in WorldState.droids.owned:
		var detail := "%d hp" % int(DroidRoster.health(d))
		if DroidRoster.cargo_slots(d) > 0:
			detail += "    hold %d of %d" % [(d.get("cargo", {}) as Dictionary).size(), DroidRoster.cargo_slots(d)]
		detail += "    %d cr" % DroidRoster.resale(str(d.kind))
		rows.append("%s   (droid)   %s" % [DroidRoster.label(str(d.kind)), detail])
		_line(list, DroidRoster.label(str(d.kind)), detail, INK)


## Issues #207, #208: your ships with what T-89 fitted, and the fence's upgrades
## on your guns.
func _owned_rows() -> void:
	primary_buttons.clear()
	call_button = null
	var ships := Fleet.rows()
	if not ships.is_empty():
		_heading(list, Objective.line("log_ships"))
		for r in ships:
			_ship_row(r)
	var gear := GearUpgrades.owned_line()
	if gear != "":
		_heading(list, Objective.line("log_gear"))
		for g in gear.split(", "):
			owned_rows.append(g)
			_line(list, g, "", INK)


## Issue #368: one of your ships: its name (PRIMARY on the one that wakes with you),
## its upgrades and the planet it was left on; Call on the primary, Set primary on
## the others.
func _ship_row(r: Dictionary) -> void:
	var detail := str(r.fits) if str(r.fits) != "" else Objective.line("ledger_stock")
	var planet := str(r.planet)
	if planet != "" and planet != GameFlow.current_planet_id():
		detail += "    " + PlanetGen.display_name(PlanetGen.build(planet))
	if bool(r.wrecked):
		detail += "    " + Objective.line("ledger_wrecked")
	var shown := str(r.label) + ("   " + Objective.line("ledger_primary") if bool(r.primary) else "")
	owned_rows.append("%s: %s" % [shown, detail])
	var h := _line(list, shown, detail, AMBER if bool(r.primary) else INK)
	if bool(r.primary):
		if call_ship.is_valid():
			var st: Dictionary = call_state.call() if call_state.is_valid() else { "ok": true, "text": "Call" }
			call_button = _row_button(h, str(st.get("text", "Call")), func():
				var why: String = call_ship.call()
				if why == "" and on_called.is_valid():
					on_called.call()
				elif why != "":
					owned_rows.append(GameFlow.label(why))
				refresh())
			call_button.disabled = not bool(st.get("ok", true))
	elif set_primary.is_valid():
		var key := str(r.key)
		primary_buttons[key] = _row_button(h, Objective.line("ledger_set_primary"), func():
			set_primary.call(key)
			refresh())


func _row_button(h: HBoxContainer, text: String, pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(pressed)
	h.add_child(b)
	return b


## Credits change under the open page (the Game page's spin box, a sale).
func _process(_dt: float) -> void:
	if is_visible_in_tree():
		credits_label.text = "%d cr" % WorldState.credits
