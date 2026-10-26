class_name InventoryPanel
extends CanvasLayer
## What you are carrying (M15), on I. Credits, then every item you own with how
## many, whether it is worn, what a vendor would pay, and a CONTRABAND tag on what
## the Remnant would confiscate at the gate. No game logic: GearController hands it
## the inventory and the item data; it only reads.

const INK := Color(0.95, 0.92, 0.85, 0.95)
const AMBER := Color("#e0a050")
const RED := Color("#ff6a55")

var inventory: Inventory          ## null = WorldState.inventory, read fresh (a load replaces it)
var content                       ## CoreContent (item labels, values, contraband)
var name_of: Callable             ## id -> shown name (GearController._shown); optional
var panel: PanelContainer
var title: Label
var credits_label: Label
var list: VBoxContainer
var rows: Array = []              ## the text of each row, for tests


func _init() -> void:
	name = "InventoryPanel"
	layer = 7


func _ready() -> void:
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -260
	panel.offset_right = 260
	panel.offset_top = -200
	panel.offset_bottom = 200
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
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	title = _text(v, "INVENTORY", 20, AMBER)
	credits_label = _text(v, "", 17, INK)
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	v.add_child(list)
	_text(v, "[I] close", 13, Color(INK, 0.6))


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
	refresh()
	panel.visible = true


func close() -> void:
	panel.visible = false


## Rebuild the rows from the inventory as it is now.
func refresh() -> void:
	rows.clear()
	for c in list.get_children():
		c.queue_free()
	credits_label.text = "Credits:  %d cr" % WorldState.credits
	var inv: Inventory = inventory if inventory != null else WorldState.inventory
	var ids: Array = inv.item_ids()
	if ids.is_empty():
		rows.append("Nothing but the clothes on your back.")
		_text(list, rows[0], 16, Color(INK, 0.7))
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
		_text(list, row, 16, RED if illegal else INK)


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
