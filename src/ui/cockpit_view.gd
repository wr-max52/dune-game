class_name CockpitView
extends Control
## The cockpit view (issue #181): V in a ship, the same cockpit for every ship.
## Most of the view is the canopy, glass with a faint tint; two struts frame it, and
## a dashboard runs across the bottom. Its instruments work, from the same values
## the chase view's HUD gets:
##   throttle lever bar | airspeed | altimeter | attitude ball | climb | compass |
##   hull, shield and boost meters, the edge-of-space bar, and one lamp for the
##   Shift ability (lit while it runs, dark when not).
##
## Drawn flat over the camera, not modelled: the cockpit camera is locked to the
## ship (ChaseCamera.COCKPIT), so a painted frame stays put exactly as a modelled
## one would, costs no geometry, and fits any ship. FlightHud hands it `values`
## (show_values) and redraws it.

const GLASS := Color(0.55, 0.75, 0.9, 0.06)
const STRUT := Color(0.07, 0.07, 0.08, 0.98)
const STRUT_EDGE := Color(0.32, 0.31, 0.3, 0.9)
const DASH := Color(0.1, 0.1, 0.11, 0.98)
const DASH_RIM := Color(0.36, 0.34, 0.31, 1.0)
const FACE := Color(0.03, 0.03, 0.035, 1.0)
const NEEDLE := Color(1.0, 0.55, 0.2, 1.0)
const SKY := Color(0.22, 0.48, 0.82, 1.0)
const EARTH := Color(0.46, 0.3, 0.15, 1.0)
const LAMP_ON := Color(1.0, 0.62, 0.15, 1.0)
const LAMP_OFF := Color(0.22, 0.16, 0.1, 1.0)
const DASH_EDGE := 0.76            ## dash top at the sides, share of the screen height
const DASH_MID := 0.71             ## and in the middle (it rises toward the gunsight)
const CLIMB_RANGE := 50.0          ## m/s at the climb dial's stops
const ATT_DEG := 45.0              ## pitch that moves the attitude ball's horizon one radius

var values: Dictionary = {}
var vessel_name := ""


func _ready() -> void:
	name = "Cockpit"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _v(key: String, fallback: float = 0.0) -> float:
	return float(values.get(key, fallback))


## The dash's top edge at x (a gentle arch, higher in the middle).
static func dash_top(vp: Vector2, x: float) -> float:
	var u := (x / maxf(vp.x, 1.0)) * 2.0 - 1.0
	return vp.y * lerpf(DASH_MID, DASH_EDGE, u * u)


func _draw() -> void:
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), GLASS)
	# A couple of faint streaks of glare on the glass.
	draw_line(Vector2(vp.x * 0.62, vp.y * 0.08), Vector2(vp.x * 0.7, vp.y * 0.3), Color(1, 1, 1, 0.05), 6.0)
	draw_line(Vector2(vp.x * 0.66, vp.y * 0.06), Vector2(vp.x * 0.72, vp.y * 0.22), Color(1, 1, 1, 0.035), 3.0)
	_draw_struts(vp)
	_draw_dash(vp)
	_draw_instruments(vp)


## Two struts, from the dash's shoulders up and in to the top of the canopy.
func _draw_struts(vp: Vector2) -> void:
	for side in [-1.0, 1.0]:
		var s: float = side
		var bx := vp.x * 0.5 + s * vp.x * 0.33
		var tx := vp.x * 0.5 + s * vp.x * 0.2
		var bw := vp.x * 0.022
		var tw := vp.x * 0.012
		var by := dash_top(vp, bx) + 4.0
		var poly := PackedVector2Array([Vector2(bx - bw, by), Vector2(bx + bw, by), Vector2(tx + tw, 0), Vector2(tx - tw, 0)])
		draw_colored_polygon(poly, STRUT)
		# The edge that faces the middle catches the light.
		var inner := -s
		draw_line(Vector2(bx + inner * bw, by), Vector2(tx + inner * tw, 0), STRUT_EDGE, 1.5)


func _draw_dash(vp: Vector2) -> void:
	var pts := PackedVector2Array()
	var n := 32
	for i in n + 1:
		var x := vp.x * float(i) / float(n)
		pts.append(Vector2(x, dash_top(vp, x)))
	var rim := pts.duplicate()
	pts.append(Vector2(vp.x, vp.y))
	pts.append(Vector2(0, vp.y))
	draw_colored_polygon(pts, DASH)
	draw_polyline(rim, DASH_RIM, 3.0)


func _draw_instruments(vp: Vector2) -> void:
	var font := RetroUI.font()
	var fs := RetroUI.size("flight_gauge", 17)
	var row := lerpf(vp.y * DASH_EDGE, vp.y, 0.5) + 4.0
	var r := minf(vp.y * 0.072, vp.x * 0.048)
	var max_spd := maxf(1.0, _v("max_speed", 300.0))
	# Throttle: a lever slot.
	_bar_v(Vector2(vp.x * 0.12, row), r * 1.6, _v("throttle"), "THR", font, fs)
	_dial(Vector2(vp.x * 0.22, row), r, _v("speed") / max_spd, 10,
		"SPD", "%d" % int(_v("speed")), font, fs)
	_altimeter(Vector2(vp.x * 0.335, row), r, _v("altitude"), font, fs)
	_attitude(Vector2(vp.x * 0.5, row - r * 0.1), r * 1.25, _v("pitch"), _v("roll"))
	_dial(Vector2(vp.x * 0.665, row), r, (_v("climb") + CLIMB_RANGE) / (CLIMB_RANGE * 2.0), 10,
		"CLIMB", "%+d" % int(_v("climb")), font, fs)
	_compass(Vector2(vp.x * 0.78, row), r, _v("heading"), font, fs)
	# Right panel: hull, shield, boost meter, the ability lamp.
	var px := vp.x * 0.86
	var pw := vp.x * 0.1
	var py := row - r
	_bar_h(Vector2(px, py), pw, _v("hull") / maxf(1.0, _v("hull_max", 1.0)), "HULL", font, fs)
	if _v("shield_max") > 0.0:
		_bar_h(Vector2(px, py + fs + 14), pw, _v("shield") / _v("shield_max"), "SHLD", font, fs)
	_bar_h(Vector2(px, py + (fs + 14) * 2.0), pw, _v("boost"), "BOOST", font, fs)
	var on := bool(values.get("ability_on", false))
	var lamp := Vector2(px + 12.0, py + (fs + 14) * 3.0 + 14.0)
	_lamp(lamp, 9.0, on)
	draw_string(font, lamp + Vector2(18, fs * 0.35), str(values.get("ability", "boost")).to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 4, LAMP_ON if on else Color(0.6, 0.55, 0.5, 0.9))
	# The edge-of-space bar, upright at the panel's right edge.
	_bar_v(Vector2(px + pw + 18.0, row), r * 1.6, _v("space_fraction"), "SPACE", font, fs)
	if vessel_name != "":
		draw_string(font, Vector2(0, vp.y - 10.0), vessel_name.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, vp.x, fs - 5,
			Color(0.62, 0.58, 0.52, 0.8))


## A round dial: 270 degrees of scale from bottom left through the top to bottom
## right, `ticks` divisions, the needle at `frac` (0..1) of the way round.
func _dial(c: Vector2, r: float, frac: float, ticks: int, label: String, readout: String, font: Font, fs: int) -> void:
	_face(c, r)
	var start := deg_to_rad(135.0)
	var sweep := deg_to_rad(270.0)
	for i in ticks + 1:
		var a := start + sweep * float(i) / float(ticks)
		var d := Vector2.from_angle(a)
		draw_line(c + d * r * 0.78, c + d * r * 0.92, Color(0.85, 0.82, 0.75), 1.5)
	_needle(c, r * 0.8, start + sweep * clampf(frac, 0.0, 1.0))
	_dial_text(c, r, label, readout, font, fs)


## An altimeter: one turn of the needle per 1000 m, the full height in figures.
func _altimeter(c: Vector2, r: float, alt: float, font: Font, fs: int) -> void:
	_face(c, r)
	for i in 10:
		var d := Vector2.from_angle(-PI * 0.5 + TAU * float(i) / 10.0)
		draw_line(c + d * r * 0.78, c + d * r * 0.92, Color(0.85, 0.82, 0.75), 1.5)
	_needle(c, r * 0.8, -PI * 0.5 + TAU * fposmod(alt, 1000.0) / 1000.0)
	_dial_text(c, r, "ALT", "%d" % int(alt), font, fs)


## The attitude ball: sky over ground, the horizon dropping as the nose comes up and
## turning against the roll, a fixed wings mark in the middle.
func _attitude(c: Vector2, r: float, pitch: float, roll: float) -> void:
	draw_circle(c, r + 4.0, Color(0.2, 0.19, 0.18))
	draw_circle(c, r, SKY)
	var h := horizon(r, pitch, roll)
	var ground := clip_half_plane(circle_points(r, 48), h.normal, h.offset)
	if ground.size() >= 3:
		for i in ground.size():
			ground.set(i, ground[i] + c)
		draw_colored_polygon(ground, EARTH)
	if absf(h.offset) < r:
		var half := sqrt(r * r - h.offset * h.offset)
		var mid: Vector2 = c + h.normal * h.offset
		var along: Vector2 = h.normal.orthogonal()
		draw_line(mid - along * half, mid + along * half, Color(1, 1, 1, 0.9), 2.0)
	# Pitch marks every 10 degrees either side of the horizon.
	for k in [-20.0, -10.0, 10.0, 20.0]:
		var o: float = h.offset - k * r / ATT_DEG
		if absf(o) < r * 0.85:
			var mid2: Vector2 = c + h.normal * o
			var w := r * (0.18 if absf(k) < 15.0 else 0.3)
			draw_line(mid2 - h.normal.orthogonal() * w, mid2 + h.normal.orthogonal() * w, Color(1, 1, 1, 0.7), 1.0)
	draw_arc(c, r, 0.0, TAU, 48, Color(0.05, 0.05, 0.05), 3.0)
	var wing := Color(1.0, 0.7, 0.2)
	draw_line(c + Vector2(-r * 0.5, 0), c + Vector2(-r * 0.15, 0), wing, 3.0)
	draw_line(c + Vector2(r * 0.15, 0), c + Vector2(r * 0.5, 0), wing, 3.0)
	draw_circle(c, 3.0, wing)


## Where the attitude ball's horizon is: ground is every point p (from the ball's
## centre) with p.dot(normal) >= offset. Nose up pushes it down (offset grows);
## rolling right turns it the other way on screen.
static func horizon(r: float, pitch: float, roll: float) -> Dictionary:
	return {
		"normal": Vector2(0, 1).rotated(-deg_to_rad(roll)),
		"offset": clampf(pitch / ATT_DEG, -1.5, 1.5) * r,
	}


static func circle_points(r: float, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		out.append(Vector2.from_angle(TAU * float(i) / float(n)) * r)
	return out


## The part of a convex polygon where p.dot(n) >= d (one Sutherland-Hodgman pass).
static func clip_half_plane(poly: PackedVector2Array, n: Vector2, d: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var count := poly.size()
	for i in count:
		var a := poly[i]
		var b := poly[(i + 1) % count]
		var da := a.dot(n) - d
		var db := b.dot(n) - d
		if da >= 0.0:
			out.append(a)
		if (da >= 0.0) != (db >= 0.0):
			out.append(a.lerp(b, da / (da - db)))
	return out


## A compass card that turns under a fixed mark at the top.
func _compass(c: Vector2, r: float, heading: float, font: Font, fs: int) -> void:
	_face(c, r)
	for i in 12:
		var deg := i * 30
		var a := deg_to_rad(float(deg) - heading) - PI * 0.5
		var d := Vector2.from_angle(a)
		draw_line(c + d * r * 0.82, c + d * r * 0.94, Color(0.85, 0.82, 0.75), 1.5)
		if deg % 90 == 0:
			var p := c + d * r * 0.6
			draw_string(font, p + Vector2(-12, fs * 0.3), FlightSimHud.compass_label(deg), HORIZONTAL_ALIGNMENT_CENTER,
				24, fs - 4, NEEDLE if deg == 0 else Color(0.9, 0.87, 0.8))
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 0.98), c + Vector2(-6, -r * 0.8), c + Vector2(6, -r * 0.8)]), NEEDLE)
	draw_string(font, c + Vector2(-r, r + fs + 2.0), "HDG %03d" % posmod(int(round(heading)), 360),
		HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs - 4, Color(0.75, 0.72, 0.66))


func _face(c: Vector2, r: float) -> void:
	draw_circle(c, r + 4.0, Color(0.2, 0.19, 0.18))
	draw_circle(c, r, FACE)


func _needle(c: Vector2, length: float, angle: float) -> void:
	var d := Vector2.from_angle(angle)
	draw_line(c - d * length * 0.15, c + d * length, NEEDLE, 3.0)
	draw_circle(c, 4.0, Color(0.6, 0.58, 0.55))


func _dial_text(c: Vector2, r: float, label: String, readout: String, font: Font, fs: int) -> void:
	draw_string(font, c + Vector2(-r, r * 0.45), readout, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs - 3, Color(0.95, 0.92, 0.85))
	draw_string(font, c + Vector2(-r, r + fs + 2.0), label, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs - 4, Color(0.75, 0.72, 0.66))


## An upright bar centred on `c`, filled from the bottom.
func _bar_v(c: Vector2, h: float, frac: float, label: String, font: Font, fs: int) -> void:
	var r := Rect2(c + Vector2(-8, -h * 0.5), Vector2(16, h))
	draw_rect(r, FACE)
	var f := h * clampf(frac, 0.0, 1.0)
	draw_rect(Rect2(Vector2(r.position.x, r.end.y - f), Vector2(16, f)), NEEDLE)
	draw_rect(r, DASH_RIM, false, 1.5)
	draw_string(font, c + Vector2(-40, h * 0.5 + fs + 2.0), label, HORIZONTAL_ALIGNMENT_CENTER, 80, fs - 4, Color(0.75, 0.72, 0.66))


func _bar_h(top_left: Vector2, w: float, frac: float, label: String, font: Font, fs: int) -> void:
	draw_string(font, top_left + Vector2(0, fs - 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 5, Color(0.75, 0.72, 0.66))
	var r := Rect2(top_left + Vector2(0, fs - 2), Vector2(w, 7))
	draw_rect(r, FACE)
	var f := clampf(frac, 0.0, 1.0)
	draw_rect(Rect2(r.position, Vector2(w * f, 7)), NEEDLE if f > 0.3 else Color(1.0, 0.25, 0.18))
	draw_rect(r, DASH_RIM, false, 1.0)


## The Shift ability's lamp: lit (with a glow) while it runs, dark when not.
func _lamp(c: Vector2, r: float, on: bool) -> void:
	draw_circle(c, r + 3.0, Color(0.2, 0.19, 0.18))
	if on:
		draw_circle(c, r * 2.2, Color(LAMP_ON.r, LAMP_ON.g, LAMP_ON.b, 0.18))
		draw_circle(c, r, LAMP_ON)
		draw_circle(c - Vector2(r, r) * 0.3, r * 0.35, Color(1, 0.95, 0.8, 0.9))
	else:
		draw_circle(c, r, LAMP_OFF)
