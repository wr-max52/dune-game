class_name GearHud
extends CanvasLayer
## Gear HUD (M13): a jetpack fuel meter (only while one is attached), an
## interaction prompt ("[E] Pick up Jetpack") and a short toast. No game logic:
## GearController sets what it shows.

const INK := Color(0.95, 0.92, 0.85, 0.95)
const FUEL := Color(1.0, 0.69, 0.4, 0.95)
const FUEL_LOW := Color(1.0, 0.36, 0.25, 0.95)
const TRACK := Color(0.08, 0.07, 0.06, 0.6)

var prompt: Label
var toast_label: Label
var meter: Control
var fuel_label := "JET"
var fuel := 1.0
var thrusting := false
var _toast_left := 0.0


func _init() -> void:
	name = "GearHud"
	layer = 4


func _ready() -> void:
	prompt = _label(-210.0)
	RetroUI.prompt(prompt)
	toast_label = _label(-250.0)
	toast_label.visible = false
	meter = Control.new()
	meter.name = "FuelMeter"
	meter.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	meter.position = Vector2(-110, -64)
	meter.size = Vector2(220, 22)
	meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meter.visible = false
	meter.draw.connect(_draw_meter)
	add_child(meter)


func _label(from_bottom: float) -> Label:
	var l := Label.new()
	l.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	l.position = Vector2(-300, from_bottom)
	l.size = Vector2(600, 28)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", INK)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func set_prompt(text: String) -> void:
	if prompt != null:
		prompt.text = text
		prompt.visible = text != ""


func toast(text: String, secs: float = 3.0) -> void:
	if toast_label == null or text == "":
		return
	toast_label.text = text
	toast_label.visible = true
	_toast_left = secs


## frac 0..1; visible = a jetpack is attached.
func set_fuel(frac: float, visible_now: bool, burning: bool) -> void:
	fuel = frac
	thrusting = burning
	if meter != null:
		meter.visible = visible_now
		meter.queue_redraw()


func _process(dt: float) -> void:
	if _toast_left > 0.0:
		_toast_left -= dt
		if _toast_left <= 0.0:
			toast_label.visible = false


func _draw_meter() -> void:
	var w := meter.size.x
	var bar := Rect2(Vector2(34, 7), Vector2(w - 34, 8))
	meter.draw_string(ThemeDB.fallback_font, Vector2(0, 16), fuel_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, INK)
	meter.draw_rect(bar, TRACK)
	var col := FUEL_LOW if fuel < 0.25 else FUEL
	if thrusting:
		col = col.lightened(0.25)
	meter.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(fuel, 0.0, 1.0), bar.size.y)), col)
	meter.draw_rect(bar, Color(INK, 0.5), false, 1.0)
