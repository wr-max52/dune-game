class_name FlightHud
extends CanvasLayer
## The cockpit read-out in the port's sky (M14): speed, throttle, boost, altitude
## above the ground and above sea level, climb rate, a centre reticle, the control
## prompt and a toast. No logic: ShipPilot fills it in. There is no "edge of
## space" read-out: the sky just darkens as you climb, and space is the same sky.

const INK := Color(0.95, 0.92, 0.85, 0.95)
const DIM := Color(0.95, 0.92, 0.85, 0.55)
const WARN := Color(1.0, 0.45, 0.3, 0.95)

var readout: Label
var prompt: Label
var toast_label: Label
var gauge: Control
var boost := 1.0
var vessel_name := ""            ## issue #15: shown above the read-out
var target: Dictionary = {}       ## issue #76: an enemy in the air (AtmoFighter.hud_target), or {}
var _toast_left := 0.0
var _fade: ColorRect


func _init() -> void:
	name = "FlightHud"
	layer = 5


func _ready() -> void:
	readout = Label.new()
	readout.position = Vector2(18, 54)
	_style(readout)
	readout.add_theme_font_size_override("font_size", RetroUI.size("flight_readout", 24))   # issue #71
	add_child(readout)
	prompt = _center_label(-90.0)
	RetroUI.prompt(prompt)
	toast_label = _center_label(-150.0)
	toast_label.add_theme_font_size_override("font_size", RetroUI.size("flight_toast", 26))
	toast_label.size.y = 40
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


## values: speed, throttle (0..1), boost (0..1), agl, altitude, climb, state,
## and (issue #55) hull, hull_max, shield
func show_values(v: Dictionary) -> void:
	if readout == null:
		return
	var spd := float(v.get("speed", 0.0))
	var hull := ""
	if v.has("hull"):
		hull = "HULL   %4d / %d   SHLD %3d\n" % [int(v.hull), int(v.get("hull_max", 0)), int(v.get("shield", 0))]
	readout.text = ("%s\n" % vessel_name.to_upper() if vessel_name != "" else "") + hull + "SPEED  %4d m/s   %5d km/h\nTHR    %3d%%      BOOST %3d%%\nALT    %6d m    AGL %5d m\nCLIMB  %+5d m/s\n%s" % [
		int(spd), int(spd * 3.6), int(float(v.get("throttle", 0.0)) * 100.0), int(float(v.get("boost", 0.0)) * 100.0),
		int(float(v.get("altitude", 0.0))), int(maxf(0.0, float(v.get("agl", 0.0)))), int(float(v.get("climb", 0.0))),
		str(v.get("state", ""))]
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
	_draw_target()


## Issue #76: the space fight's target box and lead pip, for an enemy in the air: a
## box on it (with its hull under it), the dot where to aim, and an arrow at the
## screen's edge pointing to it when it is behind or off screen.
func _draw_target() -> void:
	if target.is_empty():
		return
	var cam := gauge.get_viewport().get_camera_3d()
	if cam == null:
		return
	var col := Color(1.0, 0.35, 0.25, 0.95)
	var tp: Vector3 = target.pos
	var vp := gauge.get_viewport_rect().size
	var on_screen := not cam.is_position_behind(tp)
	var sp := cam.unproject_position(tp) if on_screen else Vector2.ZERO
	if on_screen and Rect2(Vector2.ZERO, vp).has_point(sp):
		gauge.draw_rect(Rect2(sp - Vector2(18, 18), Vector2(36, 36)), col, false, 1.5)
		var hp := clampf(float(target.get("hull", 1.0)), 0.0, 1.0)
		gauge.draw_rect(Rect2(sp + Vector2(-18, 22), Vector2(36, 4)), Color(0, 0, 0, 0.5))
		gauge.draw_rect(Rect2(sp + Vector2(-18, 22), Vector2(36 * hp, 4)), col)
		var font := ThemeDB.fallback_font
		var fs := RetroUI.size("flight_gauge", 17) - 3
		gauge.draw_string(font, sp + Vector2(24, -8), "%d m" % int(target.get("dist", 0.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		if bool(target.get("lead_ok", false)) and not cam.is_position_behind(target.lead):
			gauge.draw_circle(cam.unproject_position(target.lead), 5.0, Color(1.0, 0.85, 0.4, 0.9))
		return
	# Off screen: an arrow on a ring round the reticle, toward it.
	var c := vp * 0.5
	var local := cam.global_transform.basis.inverse() * (tp - cam.global_position)
	var dir := Vector2(local.x, -local.y)
	if dir.length() < 0.001:
		dir = Vector2(0, 1)
	dir = dir.normalized()
	var at := c + dir * minf(vp.x, vp.y) * 0.38
	var side := Vector2(-dir.y, dir.x)
	gauge.draw_colored_polygon(PackedVector2Array([at + dir * 14.0, at - dir * 6.0 + side * 9.0, at - dir * 6.0 - side * 9.0]), col)

