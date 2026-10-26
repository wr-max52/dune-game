extends Node3D
## A launch pad in a port scene. When the player is on it, a prompt shows; press
## `interact` (E) to fade out and fly the pad's encounter (see GameFlow).
##
## In range = inside `radius` on the ground plane and within `height` vertically.
## Distance-based on purpose (no Area3D): it is headless-testable without physics
## frames, and the pad is a circle anyway.
##
## The pad also owns a tiny HUD layer (prompt + toast) so the port scene can show
## "back in port" messages without its own UI.

signal launch_started(pad: Dictionary)

@export var auto_launch := false   ## true: launch the moment the player steps on
@export var fade_time := -1.0      ## < 0: use launch_pads.json; 0: instant (tests)

var spec: Dictionary = {}
var player: Node3D
var in_range := false
var launching := false

var _hud: CanvasLayer
var _prompt: Label
var _toast: Label
var _toast_left := 0.0
var _fade: ColorRect


func configure(pad_spec: Dictionary, target: Node3D) -> void:
	spec = pad_spec
	player = target
	name = "LaunchPad_" + str(spec.get("id", "pad"))
	position = GameFlow.vec(spec.get("center", [0, 0, 0]))


func _ready() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "PadHUD"
	_hud.layer = 5
	add_child(_hud)
	_prompt = _make_label(-120.0)
	_prompt.text = GameFlow.label("prompt")
	_prompt.visible = false
	_toast = _make_label(-170.0)
	_toast.visible = false
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_fade)


func _make_label(from_bottom: float) -> Label:
	var l := Label.new()
	l.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	l.offset_left = -260.0
	l.offset_right = 260.0
	l.offset_top = from_bottom
	l.offset_bottom = from_bottom + 32.0
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	_hud.add_child(l)
	return l


func is_player_in_range() -> bool:
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		return false
	var p := player.global_position
	var c := global_position
	var flat := Vector2(p.x - c.x, p.z - c.z).length()
	return flat <= float(spec.get("radius", 30.0)) and absf(p.y - c.y) <= float(spec.get("height", 6.0))


func toast(text: String, secs: float = 4.0) -> void:
	if _toast == null or text == "":
		return
	_toast.text = text
	_toast.visible = true
	_toast_left = secs


func _process(dt: float) -> void:
	if _toast_left > 0.0:
		_toast_left -= dt
		if _toast_left <= 0.0:
			_toast.visible = false
	if launching:
		return
	in_range = is_player_in_range()
	_prompt.visible = in_range
	if in_range and (auto_launch or _interact_pressed()):
		launch()


func _interact_pressed() -> bool:
	return InputMap.has_action("interact") and Input.is_action_just_pressed("interact")


## Fade to black, then hand off to GameFlow. Returns false if already launching.
func launch() -> bool:
	if launching:
		return false
	launching = true
	_prompt.text = GameFlow.label("launching")
	_prompt.visible = true
	launch_started.emit(spec)
	var t := fade_time if fade_time >= 0.0 else GameFlow.setting("fade_time", 0.6)
	if t <= 0.0 or not is_inside_tree():
		_go()
		return true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, t)
	tw.tween_callback(_go)
	return true


func _go() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameFlow.launch(get_tree() if is_inside_tree() else null, spec)
