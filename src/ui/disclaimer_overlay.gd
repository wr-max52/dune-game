class_name DisclaimerOverlay
extends CanvasLayer
## Issue #29: the notice shown when the game starts, before anything else: some
## characters are AI, not real people. The game is paused behind it until the
## player accepts (the button, Enter or Space). Once per run of the game
## (Disclaimers.launch_shown), never in a headless run (tests and traces).
## Text from content/core/llm/disclaimers.json.

signal accepted

var _panel: PanelContainer
var _button: Button
var _was_paused := false


## Show it if this run has not shown it yet. Returns the overlay, or null.
static func show_once(parent: Node) -> DisclaimerOverlay:
	if Disclaimers.launch_shown or DisplayServer.get_name() == "headless":
		return null
	Disclaimers.launch_shown = true
	var o := DisclaimerOverlay.new()
	parent.add_child(o)
	return o


func _ready() -> void:
	name = "DisclaimerOverlay"
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	var d := Disclaimers.launch()
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.015, 0.01, 0.9)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -380
	_panel.offset_right = 380
	_panel.offset_top = -210
	_panel.offset_bottom = 210
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.06, 0.05, 0.98)
	sb.border_color = Color("#c9a35e")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		sb.set_content_margin(side, 28)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	_panel.add_child(v)
	var title := Label.new()
	title.text = str(d.get("title", "Before you play"))
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color("#e0a050"))
	v.add_child(title)
	var body := Label.new()
	body.text = str(d.get("text", ""))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(700, 0)
	body.add_theme_font_size_override("font_size", 20)
	body.add_theme_color_override("font_color", Color(0.95, 0.92, 0.86))
	v.add_child(body)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(row)
	_button = Button.new()
	_button.text = str(d.get("button", "I understand"))
	_button.add_theme_font_size_override("font_size", 22)
	_button.custom_minimum_size = Vector2(200, 48)
	_button.pressed.connect(accept)
	row.add_child(_button)
	_was_paused = get_tree().paused
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_button.grab_focus()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		get_viewport().set_input_as_handled()
		accept()


func accept() -> void:
	if not is_inside_tree():
		return
	get_tree().paused = _was_paused
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	accepted.emit()
	queue_free()
