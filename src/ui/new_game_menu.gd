class_name NewGameMenu
extends CanvasLayer
## Issue #200: New Game asks Story or Free Roam. Shown once, on a first launch
## (no save yet), after the AI notice (DisclaimerOverlay) is accepted; never in a
## headless run. Picking one starts that game in its own save slot
## (DevSettingsPanel.new_game) and the town reloads. Later new games, and playing
## the other save, are in F11 > Game.

const CHOICES := [
	[WorldState.STORY, "Story",
		"You land broke in a wreck, in a port the Remnant runs. Pistol only, nobody's friend yet, and you play the smuggler."],
	[WorldState.FREEPLAY, "Free Roam",
		"The town as it is: drops and bounties on repeat, the port's ships, any character you like. The rifle and the blade are in your pack."],
]

var settings: DevSettingsPanel
var _first: Button


## Show it if the town found no save. Returns the menu, or null.
static func show_if_fresh(demo: Node, panel: DevSettingsPanel) -> NewGameMenu:
	if DisplayServer.get_name() == "headless" or demo.get("bar") == null or not demo.bar.fresh:
		return null
	var m := NewGameMenu.new()
	m.settings = panel
	demo.add_child(m)
	return m


func _ready() -> void:
	name = "NewGameMenu"
	layer = 29
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var notice := get_parent().get_node_or_null("DisclaimerOverlay")
	if notice != null and not notice.is_queued_for_deletion():
		notice.accepted.connect(_open)
	else:
		_open()


func _open() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.015, 0.01, 0.9)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -380
	panel.offset_right = 380
	panel.offset_top = -200
	panel.offset_bottom = 200
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.06, 0.05, 0.98)
	sb.border_color = Color("#c9a35e")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		sb.set_content_margin(side, 28)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	panel.add_child(v)
	var title := Label.new()
	title.text = "New game"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color("#e0a050"))
	v.add_child(title)
	for c in CHOICES:
		var b := Button.new()
		b.text = c[1]
		b.add_theme_font_size_override("font_size", 22)
		b.custom_minimum_size = Vector2(200, 48)
		b.pressed.connect(pick.bind(c[0]))
		var about := Label.new()
		about.text = c[2]
		about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		about.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		about.add_theme_font_size_override("font_size", 18)
		about.add_theme_color_override("font_color", Color(0.95, 0.92, 0.86))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		row.add_child(b)
		row.add_child(about)
		v.add_child(row)
		if _first == null:
			_first = b
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_first.grab_focus()


## Start a new game in `mode` (the town reloads).
func pick(mode: String) -> void:
	if not is_inside_tree():
		return
	settings.new_game(mode)
	queue_free()
