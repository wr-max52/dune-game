class_name EndCard
extends CanvasLayer
## Issue #214: the story's end card. The fleet is beaten and the story is at its
## "end" chapter: the Remnant leave the moon, in words that depend on whether the
## general lived (content/core/story/main.json "end_card"). Closing it ends the
## chapter and Oda has her last word (the "free" chapter). Never in a headless
## run (tests call text() and close()).
##
## It waits for nothing else to be pausing the game (the AI notice on launch, the
## new game menu, the dev settings): opened behind one of those it took their
## pause for the game's own, and Carry on left the game paused for good.

var _panel: Control


static func text() -> String:
	var c: Dictionary = Story.data().get("end_card", {})
	return str(c.get("general_dead" if WorldState.has_flag("general_dead") else "general_alive", ""))


## Close the card: the story goes on.
static func close() -> void:
	if Story.chapter() == "end":
		Story.event("end_closed")


func _ready() -> void:
	name = "EndCard"
	layer = 28
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_dt: float) -> void:
	if _panel == null and Story.chapter() == "end" and not get_tree().paused \
			and DisplayServer.get_name() != "headless":
		_open()


func _open() -> void:
	var c: Dictionary = Story.data().get("end_card", {})
	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.015, 0.01, 0.92)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(shade)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.offset_left = -380
	v.offset_right = 380
	v.offset_top = -160
	v.offset_bottom = 160
	v.add_theme_constant_override("separation", 22)
	_panel.add_child(v)
	var title := Label.new()
	title.text = str(c.get("title", "THE END"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color("#e0a050"))
	v.add_child(title)
	var body := Label.new()
	body.text = text()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(760, 0)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_theme_font_size_override("font_size", 20)
	body.add_theme_color_override("font_color", Color(0.95, 0.92, 0.86))
	v.add_child(body)
	var b := Button.new()
	b.text = str(c.get("button", "Carry on"))
	b.custom_minimum_size = Vector2(200, 48)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(_done)
	v.add_child(b)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	b.grab_focus()


func _done() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	close()
	_panel.queue_free()
	_panel = null
