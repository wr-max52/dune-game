class_name DialoguePanel
extends CanvasLayer
## The bar conversation UI (M12): her name and mood, a streamed subtitle (driven
## by real deltas, not fake typing), the last few lines, a text field, credits and
## tab, and the job card. Enter speaks, Esc leaves.

signal submitted(text: String)
signal leave_requested
signal job_answered(job_id: String, accepted: bool)

var npc_name := "Bartender"
var _root: PanelContainer
var _name: Label
var _mood: Label
var _history: RichTextLabel
var _line: RichTextLabel
var _field: LineEdit
var _money: Label
var _hint: Label
var _job: PanelContainer
var _job_title: Label
var _job_text: Label
var _job_id := ""
var _lines: Array = []


func _ready() -> void:
	layer = 6
	_root = PanelContainer.new()
	_root.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_root.offset_left = -470
	_root.offset_right = 470
	_root.offset_top = -250
	_root.offset_bottom = -20
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.06, 0.05, 0.86)
	sb.border_color = Color("#b08e50")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	_root.add_theme_stylebox_override("panel", sb)
	add_child(_root)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_root.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	_name = Label.new()
	_name.add_theme_font_size_override("font_size", 20)
	_name.add_theme_color_override("font_color", Color("#e0a050"))
	head.add_child(_name)
	_mood = Label.new()
	_mood.add_theme_font_size_override("font_size", 14)
	_mood.add_theme_color_override("font_color", Color(0.75, 0.7, 0.62))
	_mood.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_mood)
	_money = Label.new()
	_money.add_theme_font_size_override("font_size", 14)
	_money.add_theme_color_override("font_color", Color(0.75, 0.7, 0.62))
	head.add_child(_money)
	_history = RichTextLabel.new()
	_history.bbcode_enabled = true
	_history.fit_content = false
	_history.scroll_following = true
	_history.custom_minimum_size = Vector2(0, 66)
	_history.add_theme_font_size_override("normal_font_size", 14)
	_history.add_theme_color_override("default_color", Color(0.7, 0.66, 0.6))
	v.add_child(_history)
	_line = RichTextLabel.new()
	_line.bbcode_enabled = true
	_line.fit_content = true
	_line.custom_minimum_size = Vector2(0, 50)
	_line.add_theme_font_size_override("normal_font_size", 21)
	_line.add_theme_color_override("default_color", Color(0.96, 0.92, 0.84))
	v.add_child(_line)
	_field = LineEdit.new()
	_field.placeholder_text = "Say something, then Enter.  Esc leaves."
	_field.add_theme_font_size_override("font_size", 17)
	_field.max_length = 300
	_field.text_submitted.connect(_on_submit)
	v.add_child(_field)
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", Color(0.55, 0.52, 0.48))
	_hint.text = "F3 debug   F10 model settings   Shift+F10 cycle local / cloud / auto"
	v.add_child(_hint)
	_build_job_card()
	visible = false


func _build_job_card() -> void:
	_job = PanelContainer.new()
	_job.set_anchors_preset(Control.PRESET_CENTER)
	_job.offset_left = -240
	_job.offset_right = 240
	_job.offset_top = -200
	_job.offset_bottom = -40
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.09, 0.07, 0.95)
	sb.border_color = Color("#e0a050")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	_job.add_theme_stylebox_override("panel", sb)
	add_child(_job)
	var v := VBoxContainer.new()
	_job.add_child(v)
	_job_title = Label.new()
	_job_title.add_theme_font_size_override("font_size", 19)
	_job_title.add_theme_color_override("font_color", Color("#e0a050"))
	v.add_child(_job_title)
	_job_text = Label.new()
	_job_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_job_text.custom_minimum_size = Vector2(440, 0)
	v.add_child(_job_text)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(h)
	var no := Button.new()
	no.text = "Not now"
	no.pressed.connect(func(): _answer(false))
	h.add_child(no)
	var yes := Button.new()
	yes.text = "Take the job"
	yes.pressed.connect(func(): _answer(true))
	h.add_child(yes)
	_job.visible = false


func open(name_text: String, greeting: String) -> void:
	npc_name = name_text
	_name.text = name_text.to_upper()
	_lines.clear()
	_history.text = ""
	visible = true
	set_line(greeting)
	focus()


func close() -> void:
	visible = false
	_job.visible = false


func focus() -> void:
	if _field != null and visible:
		_field.grab_focus()


func set_mood(m: String) -> void:
	_mood.text = "   " + m


func set_money(credits: int, tab: int) -> void:
	_money.text = "credits %d   tab %d" % [credits, tab]


## The streamed subtitle (replaced as more words arrive).
func set_line(text: String, thinking: bool = false) -> void:
	_line.text = ("[i]" + text + "[/i]") if thinking else text


## Move the current line into the history scroll.
func commit_line() -> void:
	var t := _line.text
	if t != "":
		_add_history("[color=#e0a050]%s:[/color] %s" % [npc_name, t])


func add_player_line(text: String) -> void:
	_add_history("[color=#9ad0c8]You:[/color] " + text.replace("[", "("))


func _add_history(bb: String) -> void:
	_lines.append(bb)
	while _lines.size() > 8:
		_lines.pop_front()
	_history.text = "\n".join(_lines)


func set_input_enabled(on: bool) -> void:
	_field.editable = on
	if on:
		focus()


func show_job(job: Dictionary) -> void:
	_job_id = str(job.get("id", ""))
	_job_title.text = str(job.get("title", "A job"))
	_job_text.text = "%s\n\nPays %d credits." % [str(job.get("text", "")), int(job.get("pays", 0))]
	_job.visible = true


func job_open() -> bool:
	return _job.visible


func _answer(yes: bool) -> void:
	_job.visible = false
	job_answered.emit(_job_id, yes)
	focus()


func _on_submit(text: String) -> void:
	if text.strip_edges() == "":
		return
	_field.text = ""
	submitted.emit(text)


func _input_event_esc(event: InputEvent) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE


func _input(event: InputEvent) -> void:
	if visible and _input_event_esc(event):
		get_viewport().set_input_as_handled()
		leave_requested.emit()
