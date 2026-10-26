class_name FlightHud
extends CanvasLayer
## The cockpit read-out in the port's sky (M14): speed, throttle, boost, altitude
## above the ground and above sea level, climb rate, a bar that fills toward the
## edge of space, a centre reticle, the control prompt and a toast. No logic:
## ShipPilot fills it in.

const INK := Color(0.95, 0.92, 0.85, 0.95)
const DIM := Color(0.95, 0.92, 0.85, 0.55)
const SPACE := Color(0.55, 0.75, 1.0, 0.95)
const WARN := Color(1.0, 0.45, 0.3, 0.95)

var readout: Label
var prompt: Label
var toast_label: Label
var gauge: Control
var space_label := "EDGE OF SPACE"
var space_fraction := 0.0
var space_altitude := 8000.0
var boost := 1.0
var vessel_name := ""            ## issue #15: shown above the read-out
var _toast_left := 0.0
var _fade: ColorRect


func _init() -> void:
	name = "FlightHud"
	layer = 5


func _ready() -> void:
	readout = Label.new()
	readout.position = Vector2(18, 14)
	_style(readout)
	add_child(readout)
	prompt = _center_label(-90.0)
	toast_label = _center_label(-130.0)
	toast_label.visible = false
	gauge = Control.new()
	gauge.name = "Gauge"
	gauge.set_anchors_preset(Control.PRESET_FULL_RECT)
	gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gauge.draw.connect(_draw_gauge)
	add_child(gauge)
	_fade = ColorRect.new()
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	visible = false


func _style(l: Label) -> void:
	l.add_theme_color_override("font_color", INK)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _center_label(from_bottom: float) -> Label:
	var l := Label.new()
	l.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	l.position = Vector2(-420, from_bottom)
	l.size = Vector2(840, 28)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style(l)
	add_child(l)
	return l


## values: speed, throttle (0..1), boost (0..1), agl, altitude, climb, space_fraction, state
func show_values(v: Dictionary) -> void:
	if readout == null:
		return
	var spd := float(v.get("speed", 0.0))
	readout.text = ("%s\n" % vessel_name.to_upper() if vessel_name != "" else "") + "SPEED  %4d m/s   %5d km/h\nTHR    %3d%%      BOOST %3d%%\nALT    %6d m    AGL %5d m\nCLIMB  %+5d m/s\n%s" % [
		int(spd), int(spd * 3.6), int(float(v.get("throttle", 0.0)) * 100.0), int(float(v.get("boost", 0.0)) * 100.0),
		int(float(v.get("altitude", 0.0))), int(maxf(0.0, float(v.get("agl", 0.0)))), int(float(v.get("climb", 0.0))),
		str(v.get("state", ""))]
	space_fraction = float(v.get("space_fraction", 0.0))
	boost = float(v.get("boost", 0.0))
	gauge.queue_redraw()


func set_prompt(text: String) -> void:
	if prompt != null:
		prompt.text = text


func toast(text: String, secs: float = 3.0) -> void:
	if toast_label == null or text == "":
		return
	toast_label.text = text
	toast_label.visible = true
	_toast_left = secs


func set_fade(a: float) -> void:
	if _fade != null:
		_fade.color.a = clampf(a, 0.0, 1.0)


func _process(dt: float) -> void:
	if _toast_left > 0.0:
		_toast_left -= dt
		if _toast_left <= 0.0:
			toast_label.visible = false


func _draw_gauge() -> void:
	var vp := gauge.get_viewport_rect().size
	var c := vp * 0.5
	# Reticle: where the nose points (the chase camera looks along it).
	gauge.draw_arc(c, 12.0, 0.0, TAU, 24, DIM, 1.5)
	gauge.draw_line(c + Vector2(-26, 0), c + Vector2(-16, 0), DIM, 1.5)
	gauge.draw_line(c + Vector2(16, 0), c + Vector2(26, 0), DIM, 1.5)
	# Edge-of-space bar on the right edge.
	var h := vp.y * 0.5
	var x := vp.x - 34.0
	var top := c.y - h * 0.5
	gauge.draw_rect(Rect2(Vector2(x, top), Vector2(10, h)), Color(0, 0, 0, 0.45))
	var fill := h * clampf(space_fraction, 0.0, 1.0)
	gauge.draw_rect(Rect2(Vector2(x, top + h - fill), Vector2(10, fill)), SPACE)
	gauge.draw_rect(Rect2(Vector2(x, top), Vector2(10, h)), DIM, false, 1.0)
	var font := ThemeDB.fallback_font
	gauge.draw_string(font, Vector2(x - 120, top - 8), space_label, HORIZONTAL_ALIGNMENT_RIGHT, 130, 12, SPACE)
	gauge.draw_string(font, Vector2(x - 120, top + 8), "%d m" % int(space_altitude), HORIZONTAL_ALIGNMENT_RIGHT, 110, 11, DIM)
