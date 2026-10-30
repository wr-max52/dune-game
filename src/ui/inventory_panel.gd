class_name InventoryPanel
extends CanvasLayer
## What you are carrying (M15), on I. Credits, then every item you own with how
## many, whether it is worn, what a vendor would pay, and a CONTRABAND tag on what
## the Remnant would confiscate at the gate. Beside it, the job log: the story's
## chapter, the drop or goods you are running, the bounty out, and any job taken
## (Objective.log_entries). No game logic: GearController hands it the inventory
## and the item data; it only reads. Issue #201: under the jobs, the optional
## quests (Quests.entries) with a waypoint toggle each; the mouse is free while
## the panel is open so the toggles can be clicked.

const INK := Color(0.95, 0.92, 0.85, 0.95)
const AMBER := Color("#e0a050")
const RED := Color("#ff6a55")
const SIZE := Vector2(800, 460)   ## the panel's size, shrunk to fit a small (or text-scaled) screen
const MARGIN := Vector2(16, 48)   ## kept clear on each side: the HUD's banner and footer

var inventory: Inventory          ## null = WorldState.inventory, read fresh (a load replaces it)
var content                       ## CoreContent (item labels, values, contraband)
var name_of: Callable             ## id -> shown name (GearController._shown); optional
var toggle_item: Callable         ## issue #209: id -> put a worn item on or off (GearController.toggle_item); optional
var wear_buttons: Dictionary = {}  ## item id -> its Wear / Take off button (tests)
var panel: PanelContainer
var title: Label
var credits_label: Label
var list: VBoxContainer
var jobs: VBoxContainer
var rows: Array = []              ## the text of each row, for tests
var job_rows: Array = []          ## the job log's text, title then line, for tests
var quest_buttons: Dictionary = {}  ## quest id -> its waypoint toggle (tests)
var _mouse_before := Input.MOUSE_MODE_VISIBLE


func _init() -> void:
	name = "InventoryPanel"
	layer = 7


func _ready() -> void:
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.06, 0.05, 0.9)
	sb.border_color = AMBER
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false
	add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	panel.add_child(outer)
	# Scrolls (the wheel) when a long job log is taller than the panel, so the
	# panel never grows past the screen.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(cols)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.custom_minimum_size.x = 220
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_stretch_ratio = 0.8
	cols.add_child(v)
	title = _text(v, "INVENTORY", 20, AMBER)
	credits_label = _text(v, "", 17, INK)
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
	_text(outer, "[I] close", 13, Color(INK, 0.6))


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


func is_open() -> bool:
	return panel != null and panel.visible


func toggle() -> void:
	if is_open():
		close()
	else:
		open()


func open() -> void:
	_fit()
	refresh()
	if not panel.visible:
		_mouse_before = Input.mouse_mode
	panel.visible = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Centre the panel at SIZE, or smaller when the screen (after the text scale)
## is: the columns wrap to whatever width they get.
func _fit() -> void:
	var vp := panel.get_viewport_rect().size if panel.is_inside_tree() else SIZE
	var half := Vector2(minf(SIZE.x, vp.x - 2.0 * MARGIN.x), minf(SIZE.y, vp.y - 2.0 * MARGIN.y)) * 0.5
	panel.offset_left = -half.x
	panel.offset_right = half.x
	panel.offset_top = -half.y
	panel.offset_bottom = half.y


func close() -> void:
	if not panel.visible:
		return
	panel.visible = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = _mouse_before


## Rebuild the rows from the inventory as it is now.
func refresh() -> void:
	_job_log()
	rows.clear()
	wear_buttons.clear()
	for c in list.get_children():
		c.queue_free()
	credits_label.text = "Credits:  %d cr" % WorldState.credits
	var inv: Inventory = inventory if inventory != null else WorldState.inventory
	var ids: Array = inv.item_ids()
	_droid_rows()
	if ids.is_empty():
		if not rows.is_empty():
			return
		rows.append("Nothing but the clothes on your back.")
		_wrap(_text(list, rows[0], 16, Color(INK, 0.7)))
		return
	for id in ids:
		var it: Dictionary = content.get_item(str(id)) if content != null else {}
		var shown: String = name_of.call(it, str(id)) if name_of.is_valid() else str(it.get("label", id))
		var row := "%s  x%d" % [shown, inv.count(str(id))]
		if inv.is_attached(str(id)):
			row += "   (worn)"
		row += "   %d cr" % int(it.get("value", 0))
		var illegal := bool(it.get("contraband", false))
		if illegal:
			row += "   CONTRABAND"
		rows.append(row)
		_wrap(_text(list, row, 16, RED if illegal else INK))
		if toggle_item.is_valid() and str(it.get("slot", "")) != "":
			_wear_button(str(id), inv.is_attached(str(id)))


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
		var head := "%s   (%s)" % [str(q.title).to_upper(), Objective.line("quest_done" if q.done else "quest_open")]
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


## Issue #51: your droids, one row each. What a cargo droid carries is not
## listed (and not in the inventory): the gate never sees it either.
func _droid_rows() -> void:
	for d in WorldState.droids.owned:
		var row := "%s   (droid)   %d cr" % [DroidRoster.label(str(d.kind)), DroidRoster.resale(str(d.kind))]
		rows.append(row)
		_wrap(_text(list, row, 16, AMBER))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		toggle()
		get_viewport().set_input_as_handled()
	elif is_open() and event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _process(_dt: float) -> void:
	if is_open():
		credits_label.text = "Credits:  %d cr" % WorldState.credits
