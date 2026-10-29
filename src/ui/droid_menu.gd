class_name DroidMenu
extends CanvasLayer
## A numbered pick list (issue #51): the droid merchant, a cargo droid's hold, and
## "you already run three droids: sell one?". Keys 1-9 pick, Esc walks away. No
## game logic: the caller hands it the options and a callback. Issue #58: an
## optional body (what T-89 is saying) sits between the title and the options.

const INK := Color(0.95, 0.92, 0.85, 0.95)
const AMBER := Color("#e0a050")

var panel: PanelContainer
var title_label: Label
var body_label: Label
var list: VBoxContainer
var options: Array = []           ## [{ id, text }]
var on_pick: Callable             ## (id: String) -> void; "" = walked away
var rows: Array = []              ## the text of each row, for tests
signal option_selected(id: String)


func _init() -> void:
	name = "DroidMenu"
	layer = 8


func _ready() -> void:
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -280
	panel.offset_right = 280
	panel.offset_top = -170
	panel.offset_bottom = 170
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 20)
	title_label.add_theme_color_override("font_color", AMBER)
	box.add_child(title_label)
	body_label = Label.new()
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.custom_minimum_size = Vector2(520, 0)
	body_label.add_theme_font_size_override("font_size", 17)
	body_label.add_theme_color_override("font_color", INK)
	box.add_child(body_label)
	list = VBoxContainer.new()
	box.add_child(list)
	panel.visible = false


func is_open() -> bool:
	return panel != null and panel.visible


func open(title: String, opts: Array, pick: Callable, body: String = "") -> void:
	options = opts.slice(0, 9)
	on_pick = pick
	rows.clear()
	if panel == null:
		return
	title_label.text = title
	body_label.text = body
	body_label.visible = body != ""
	for c in list.get_children():
		c.queue_free()
	for i in options.size():
		var row := "[%d]  %s" % [i + 1, str(options[i].text)]
		rows.append(row)
		var l := Label.new()
		l.text = row
		l.add_theme_font_size_override("font_size", 16)
		l.add_theme_color_override("font_color", INK)
		list.add_child(l)
	var esc := Label.new()
	esc.text = "[Esc]  Walk away"
	esc.add_theme_color_override("font_color", Color(INK, 0.6))
	list.add_child(esc)
	panel.visible = true


## Pick an option by id ("" = walk away). The same path the keys use.
func choose(id: String) -> void:
	if panel != null:
		panel.visible = false
	var cb := on_pick
	on_pick = Callable()
	option_selected.emit(id)
	if cb.is_valid():
		cb.call(id)


func _unhandled_input(event: InputEvent) -> void:
	if not is_open() or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := (event as InputEventKey).keycode
	if k == KEY_ESCAPE:
		choose("")
		get_viewport().set_input_as_handled()
	elif k >= KEY_1 and k <= KEY_9 and k - KEY_1 < options.size():
		choose(str(options[k - KEY_1].id))
		get_viewport().set_input_as_handled()
