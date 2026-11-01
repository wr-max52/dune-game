class_name InventoryPanel
extends ScrollContainer
## What you are carrying (M15): the Inventory page of the settings panel, on I
## (DevSettingsPanel; M is its Map page). Credits, then every item you own with how
## many, whether it is worn, what a vendor would pay, and a CONTRABAND tag on what
## the Remnant would confiscate at the gate. Beside it, the job log: the story's
## chapter, the drop or goods you are running, the bounty out, and any job taken
## (Objective.log_entries). No game logic: the settings panel hands it
## GearController's item data and wear toggle; it only reads. Issue #201: under
## the jobs, the optional quests (Quests.entries) with a waypoint toggle each.
##
## The backpack (Inventory.slots_used): its numbered slots, the pistol in the
## first, one kind of item in each of the rest, then the empty ones. Activated
## gear (the jetpack on, the armour on) is listed under them, "(activated)",
## without a slot.

const INK := Color(0.95, 0.92, 0.85, 0.95)
const AMBER := Color("#e0a050")
const RED := Color("#ff6a55")

var inventory: Inventory          ## null = WorldState.inventory, read fresh (a load replaces it)
var content                       ## CoreContent (item labels, values, contraband)
var name_of: Callable             ## id -> shown name (GearController._shown); optional
var toggle_item: Callable         ## issue #209: id -> put a worn item on or off (GearController.toggle_item); optional
var wear_buttons: Dictionary = {}  ## item id -> its Wear / Take off button (tests)
var title: Label
var credits_label: Label
var backpack_label: Label
var list: VBoxContainer
var jobs: VBoxContainer
var rows: Array = []              ## the text of each row, for tests
var job_rows: Array = []          ## the job log's text, title then line, for tests
var quest_buttons: Dictionary = {}  ## quest id -> its waypoint toggle (tests)


func _init() -> void:
	name = "Inventory"            # the tab's title
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED


func _ready() -> void:
	# Scrolls (the wheel) when a long job log is taller than the page.
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(cols)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.custom_minimum_size.x = 220
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_stretch_ratio = 0.8
	cols.add_child(v)
	title = _text(v, "INVENTORY", 20, AMBER)
	credits_label = _text(v, "", 17, INK)
	backpack_label = _text(v, "", 15, AMBER)
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	v.add_child(list)
	var jv := VBoxContainer.new()
	jv.add_theme_constant_override("separation", 8)
	jv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(jv)
	_text(jv, Objective.line("log_title"), 20, AMBER)
	jobs = VBoxContainer.new()
	jobs.add_theme_constant_override("separation", 6)
	jv.add_child(jobs)


func _text(parent: Control, t: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


## Rebuild the rows from the inventory as it is now.
func refresh() -> void:
	_job_log()
	rows.clear()
	wear_buttons.clear()
	for c in list.get_children():
		c.queue_free()
	credits_label.text = "Credits:  %d cr" % WorldState.credits
	var inv: Inventory = inventory if inventory != null else WorldState.inventory
	backpack_label.text = "BACKPACK   %d of %d slots" % [inv.slots_used(), Inventory.backpack_slots()]
	var n := 0
	for label in Inventory.fixed_slots():
		n += 1
		rows.append("[%d]  %s" % [n, str(label)])
		_wrap(_text(list, rows[-1], 16, INK))
	for id in inv.packed_ids():
		n += 1
		_item_row(inv, str(id), "[%d]  " % n)
	for i in range(n, Inventory.backpack_slots()):
		rows.append("[%d]  - empty -" % (i + 1))
		_text(list, rows[-1], 16, Color(INK, 0.45))
	for id in inv.item_ids():
		if inv.is_attached(str(id)):
			_item_row(inv, str(id), "")
	_droid_rows()


## One kind of item: name, how many, (activated), value, CONTRABAND, and the
## Wear / Take off button for gear.
func _item_row(inv: Inventory, id: String, prefix: String) -> void:
	var it: Dictionary = content.get_item(id) if content != null else {}
	var shown: String = name_of.call(it, id) if name_of.is_valid() else str(it.get("label", id))
	var row := "%s%s  x%d" % [prefix, shown, inv.count(id)]
	if inv.is_attached(id):
		row += "   (activated)"
	row += "   %d cr" % int(it.get("value", 0))
	var illegal := bool(it.get("contraband", false))
	if illegal:
		row += "   CONTRABAND"
	rows.append(row)
	_wrap(_text(list, row, 16, RED if illegal else INK))
	if toggle_item.is_valid() and str(it.get("slot", "")) != "":
		_wear_button(id, inv.is_attached(id))


## The job log, from Objective: a title over each entry's line, then the tally.
func _job_log() -> void:
	job_rows.clear()
	for c in jobs.get_children():
		c.queue_free()
	for e in Objective.log_entries():
		if str(e.title) != "":
			job_rows.append(str(e.title))
			_text(jobs, str(e.title), 13, AMBER)
		job_rows.append(str(e.text))
		_wrap(_text(jobs, str(e.text), 14, INK))
	_quest_log()
	job_rows.append(Objective.tally())
	_text(jobs, job_rows[-1], 13, Color(INK, 0.6))


## Issue #201: the optional quests under their own heading: title and status,
## the text, and a waypoint toggle while it is open and has somewhere to point.
func _quest_log() -> void:
	quest_buttons.clear()
	var qs := Quests.entries()
	if qs.is_empty():
		return
	job_rows.append(Objective.line("log_quests"))
	_text(jobs, job_rows[-1], 15, AMBER)
	for q in qs:
		var head := "%s   (%s)" % [str(q.title).to_upper(), Objective.line("quest_failed" if q.get("failed", false) else ("quest_done" if q.done else "quest_open"))]
		job_rows.append(head)
		_text(jobs, head, 13, Color(AMBER, 0.6) if q.done else AMBER)
		job_rows.append(str(q.text))
		_wrap(_text(jobs, str(q.text), 14, Color(INK, 0.6) if q.done else INK))
		if not q.can_point:
			continue
		var b := Button.new()
		b.text = Objective.line("quest_point_on" if q.waypoint else "quest_point_off")
		b.toggle_mode = true
		b.button_pressed = q.waypoint
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var id := str(q.id)
		b.pressed.connect(func():
			Quests.toggle_waypoint(id)
			refresh())
		jobs.add_child(b)
		quest_buttons[id] = b


## Issue #209: a worn item's toggle (the jetpack, the armour).
func _wear_button(id: String, on: bool) -> void:
	var b := Button.new()
	b.text = "Take off" if on else "Wear"
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.pressed.connect(func():
		toggle_item.call(id)
		refresh())
	list.add_child(b)
	wear_buttons[id] = b


func _wrap(l: Label) -> void:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 200


## Issue #51: your droids, one row each, with their health and hold size. What
## a cargo droid carries is not listed (and not in the inventory): the gate never
## sees it either.
func _droid_rows() -> void:
	for d in WorldState.droids.owned:
		var row := "%s   (droid)   %d hp" % [DroidRoster.label(str(d.kind)), int(DroidRoster.health(d))]
		if DroidRoster.cargo_slots(d) > 0:
			row += "   hold %d of %d" % [(d.get("cargo", {}) as Dictionary).size(), DroidRoster.cargo_slots(d)]
		row += "   %d cr" % DroidRoster.resale(str(d.kind))
		rows.append(row)
		_wrap(_text(list, row, 16, AMBER))


## Credits change under the open page (the Game page's spin box, a sale).
func _process(_dt: float) -> void:
	if is_visible_in_tree():
		credits_label.text = "Credits:  %d cr" % WorldState.credits
