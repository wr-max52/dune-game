class_name CockpitDash
extends Control
## The cockpit's dash and its instruments (issue #181), painted flat. CockpitView
## keeps one in a SubViewport and draws it back in perspective, leaning away from
## you, so this draws in "panel" space: the screen's own coordinates (`screen`),
## with the panel running `margin` px past each side (the far edge is wider than
## the screen before the perspective pulls it in) and the texture starting at
## panel row `top`, drawn `scale_by` times finer.
##
## The dash is brushed metal (a light chamfer on its top edge, recessed plates for
## the instruments); each instrument sits in a bevelled bezel under glass that
## catches the light. The instruments:
##   throttle lever bar | airspeed | altimeter | attitude ball | climb | compass |
##   hull, shield and boost meters, and one lamp for the Shift ability.
##
## `lights` are the sun and any bolts going by (CockpitView.gather_lights): each
## glints on the dials' glass and puts a streak along the dash's chamfer, where its
## reflection would fall.

const METAL_TOP := Color(0.42, 0.42, 0.43, 1.0)
const METAL_LOW := Color(0.17, 0.17, 0.18, 1.0)
const CHAMFER := Color(0.78, 0.77, 0.74, 1.0)
const PLATE := Color(0.08, 0.08, 0.085, 0.85)
const DASH_RIM := Color(0.36, 0.34, 0.31, 1.0)
const BEZEL := Color(0.16, 0.16, 0.17, 1.0)
const BEZEL_LIT := Color(0.62, 0.61, 0.58, 0.9)
const BEZEL_SHADE := Color(0.02, 0.02, 0.02, 0.9)
const GLARE_SOFT := Color(1, 1, 1, 0.07)
const GLARE_BAND := Color(1, 1, 1, 0.045)
const GLARE_GLINT := Color(1, 1, 1, 0.4)
const LIGHT := Vector2(-0.7071, -0.7071)   ## where the canopy's light comes from on screen (upper left)
const FACE := Color(0.03, 0.03, 0.035, 1.0)
const NEEDLE := Color(1.0, 0.55, 0.2, 1.0)
const SKY := Color(0.22, 0.48, 0.82, 1.0)
const EARTH := Color(0.46, 0.3, 0.15, 1.0)
const LAMP_ON := Color(1.0, 0.62, 0.15, 1.0)
const LAMP_OFF := Color(0.22, 0.16, 0.1, 1.0)
const DASH_EDGE := 0.76            ## dash top at the sides, share of the screen height (before the lean)
const DASH_MID := 0.71             ## and in the middle (it rises toward the gunsight)
const CLIMB_RANGE := 50.0          ## m/s at the climb dial's stops
const ATT_DEG := 45.0              ## pitch that moves the attitude ball's horizon one radius
const LEAN := 35.0                 ## degrees the panel's face leans back from upright, for the glints
const EYE := Vector3(0.0, 0.42, 0.91)   ## from the dash toward your eye, in the camera's frame

var values: Dictionary = {}
var vessel_name := ""
var lights: Array = []              ## each { dir: Vector3 toward it, camera frame; color; power 0..1 }
var screen := Vector2(1920, 1080)
var margin := 0.0
var top := 0.0
var scale_by := 1.0                 ## texture pixels per panel pixel


func _ready() -> void:
	name = "Dash"
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _v(key: String, fallback: float = 0.0) -> float:
	return float(values.get(key, fallback))


func _draw() -> void:
	draw_set_transform(Vector2(margin, -top) * scale_by, 0.0, Vector2(scale_by, scale_by))
	_draw_dash(screen)
	_draw_instruments(screen)


## The dash's top edge at x (a gentle arch, higher in the middle, flat past the
## screen's edges).
static func dash_top(vp: Vector2, x: float) -> float:
	var u := clampf((x / maxf(vp.x, 1.0)) * 2.0 - 1.0, -1.0, 1.0)
	return vp.y * lerpf(DASH_MID, DASH_EDGE, u * u)


## Where light from `to_light` (a unit vector toward it, in the camera's frame:
## x right, y up, -z ahead) glints on a domed glass set in the leaning panel: x, y
## its offset from the glass's middle as a share of the radius (y down the screen),
## and z how strongly, 0..1. The dome's curve reaches about 65 degrees off the
## panel's face, so a light well ahead and above still glints on its far edge; one
## below the dash or dead ahead does not.
static func glint(to_light: Vector3) -> Vector3:
	var lean := deg_to_rad(LEAN)
	var normal := Vector3(0.0, sin(lean), cos(lean))
	var h := (to_light.normalized() + EYE.normalized()).normalized()
	return Vector3(h.x, -h.dot(Vector3(0.0, cos(lean), -sin(lean))), smoothstep(0.42, 0.8, h.dot(normal)))


## A soft round light: `col` in the middle fading to nothing at radius r.
static func halo(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	if col.a <= 0.003 or r < 1.0:
		return
	var clear := Color(col, 0.0)
	var n := 24
	for i in n:
		var a := c + Vector2.from_angle(TAU * float(i) / float(n)) * r
		var b := c + Vector2.from_angle(TAU * float(i + 1) / float(n)) * r
		ci.draw_polygon(PackedVector2Array([c, a, b]), PackedColorArray([col, clear, clear]))


## The dash: brushed metal, lighter at the top where the canopy's light falls, with
## a bright chamfer along its edge and a row of rivets under it.
func _draw_dash(vp: Vector2) -> void:
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var n := 40
	var crest := vp.y * DASH_MID
	for i in n + 1:
		var x := lerpf(-margin, vp.x + margin, float(i) / float(n))
		pts.append(Vector2(x, dash_top(vp, x)))
	var rim := pts.duplicate()
	pts.append(Vector2(vp.x + margin, vp.y))
	pts.append(Vector2(-margin, vp.y))
	for p in pts:
		cols.append(METAL_TOP.lerp(METAL_LOW, clampf((p.y - crest) / maxf(vp.y - crest, 1.0), 0.0, 1.0)))
	draw_polygon(pts, cols)
	# Brushing: faint horizontal streaks, the same every frame.
	for i in 190:
		var y := lerpf(crest, vp.y, _hash(i, 1))
		var span := dash_span(vp, y, margin)
		if span.y - span.x < 4.0:
			continue
		var a := lerpf(span.x, span.y, _hash(i, 2) * 0.6)
		var b := lerpf(a, span.y, 0.3 + _hash(i, 3) * 0.7)
		var lit := _hash(i, 4) > 0.45
		draw_line(Vector2(a, y), Vector2(b, y), Color(1, 1, 1, 0.035) if lit else Color(0, 0, 0, 0.08), 1.0)
	# A sheen under the edge, then the chamfer catching the light, then its shadow.
	_arch_band(vp, n, 6.0, vp.y * 0.045, Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.0))
	_arch_band(vp, n, 0.0, 3.0, CHAMFER, CHAMFER.darkened(0.3))
	_arch_band(vp, n, 3.0, 6.0, Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.0))
	_dash_shine(vp)
	draw_polyline(rim, Color(0.05, 0.05, 0.05, 0.9), 1.0, true)
	for i in 15:
		var x := vp.x * (float(i) + 1.0) / 16.0
		_rivet(Vector2(x, dash_top(vp, x) + 11.0), 2.5)


## A band that follows the dash's top edge, from d0 to d1 px under it, shaded from
## c0 at its top to c1 at its bottom.
func _arch_band(vp: Vector2, n: int, d0: float, d1: float, c0: Color, c1: Color) -> void:
	for i in n:
		var xa := lerpf(-margin, vp.x + margin, float(i) / float(n))
		var xb := lerpf(-margin, vp.x + margin, float(i + 1) / float(n))
		var ya := dash_top(vp, xa)
		var yb := dash_top(vp, xb)
		draw_polygon(PackedVector2Array([Vector2(xa, ya + d0), Vector2(xb, yb + d0), Vector2(xb, yb + d1), Vector2(xa, ya + d1)]),
			PackedColorArray([c0, c0, c1, c1]))


## The lights on the dash: each one's reflection runs along the chamfer as a
## bright streak with a soft sheen on the metal under it, across from where the
## light is (left for a light to your left), fading out to either side. The
## chamfer is rounded, so anything above the dash's edge catches some of it.
func _dash_shine(vp: Vector2) -> void:
	for l in lights:
		var g := glint(l.dir)
		var a: float = float(l.power) * smoothstep(-0.15, 0.25, (l.dir as Vector3).normalized().y)
		if a <= 0.01:
			continue
		var col: Color = (l.color as Color).lerp(Color.WHITE, 0.35)
		var mid := vp.x * 0.5 + g.x * vp.x * 0.75
		var w := vp.x * 0.11
		var k := 12
		for i in k:
			var xa := mid - w + 2.0 * w * float(i) / float(k)
			var xb := mid - w + 2.0 * w * float(i + 1) / float(k)
			var fa := pow(1.0 - absf(xa - mid) / w, 2.0)
			var fb := pow(1.0 - absf(xb - mid) / w, 2.0)
			var ya := dash_top(vp, xa)
			var yb := dash_top(vp, xb)
			draw_polygon(PackedVector2Array([Vector2(xa, ya), Vector2(xb, yb), Vector2(xb, yb + 3.0), Vector2(xa, ya + 3.0)]),
				PackedColorArray([Color(col, a * fa * 0.8), Color(col, a * fb * 0.8), Color(col, a * fb * 0.5), Color(col, a * fa * 0.5)]))
			draw_polygon(PackedVector2Array([Vector2(xa, ya + 6.0), Vector2(xb, yb + 6.0), Vector2(xb, yb + vp.y * 0.06), Vector2(xa, ya + vp.y * 0.06)]),
				PackedColorArray([Color(col, a * fa * 0.18), Color(col, a * fb * 0.18), Color(col, 0.0), Color(col, 0.0)]))


## Where the dash covers row y: x from .x to .y (empty above the arch's crown; the
## whole panel, `margin` px past either side, under its ends).
static func dash_span(vp: Vector2, y: float, margin := 0.0) -> Vector2:
	var t := (y / maxf(vp.y, 1.0) - DASH_MID) / (DASH_EDGE - DASH_MID)
	if t >= 1.0:
		return Vector2(-margin, vp.x + margin)
	if t <= 0.0:
		return Vector2(vp.x * 0.5, vp.x * 0.5)
	var u := sqrt(t)
	return Vector2(vp.x * (1.0 - u) * 0.5, vp.x * (1.0 + u) * 0.5)


## A steady pseudo-random 0..1 for (i, k), so the brushing does not crawl.
static func _hash(i: int, k: int) -> float:
	return fposmod(sin(float(i) * 12.9898 + float(k) * 78.233) * 43758.5453, 1.0)


func _rivet(c: Vector2, r: float) -> void:
	draw_circle(c, r + 1.0, Color(0, 0, 0, 0.5))
	draw_circle(c, r, Color(0.42, 0.42, 0.43))
	draw_circle(c + LIGHT * r * 0.35, r * 0.4, Color(0.85, 0.85, 0.82, 0.8))


## A recessed plate the instruments sit in: darker than the dash, its top lip in
## shadow and its bottom lip catching the light, a screw in each corner.
func _plate(r: Rect2) -> void:
	draw_rect(r, PLATE)
	draw_line(r.position, Vector2(r.end.x, r.position.y), Color(0, 0, 0, 0.8), 2.0)
	draw_line(r.position, Vector2(r.position.x, r.end.y), Color(0, 0, 0, 0.6), 1.5)
	draw_line(Vector2(r.position.x, r.end.y), r.end, Color(0.7, 0.69, 0.66, 0.5), 1.5)
	draw_line(Vector2(r.end.x, r.position.y), r.end, Color(0.7, 0.69, 0.66, 0.35), 1.0)
	for corner in [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]:
		var p: Vector2 = corner
		_rivet(p + (r.get_center() - p).sign() * 7.0, 2.0)


func _draw_instruments(vp: Vector2) -> void:
	var font := RetroUI.font()
	var fs := RetroUI.size("flight_gauge", 17)
	var row := lerpf(vp.y * DASH_EDGE, vp.y, 0.5) + 4.0
	var r := minf(vp.y * 0.072, vp.x * 0.048)
	var max_spd := maxf(1.0, _v("max_speed", 300.0))
	var plate_top := row - r * 1.5
	var plate_bottom := minf(vp.y - 4.0, row + r + fs + 10.0)
	_plate(Rect2(vp.x * 0.09, plate_top, vp.x * 0.06, plate_bottom - plate_top))
	_plate(Rect2(vp.x * 0.165, plate_top, vp.x * 0.67, plate_bottom - plate_top))
	_plate(Rect2(vp.x * 0.848, plate_top, vp.x * 0.124, plate_bottom - plate_top))
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
	# The ship's name on a little plate over the instruments (the yoke's hub hides
	# the bottom of the dash).
	if vessel_name != "":
		var tw := font.get_string_size(vessel_name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 5).x + 24.0
		var tag := Rect2(vp.x * 0.5 - tw * 0.5, plate_top - fs - 8.0, tw, fs + 2.0)
		_plate(tag)
		draw_string(font, Vector2(tag.position.x, tag.end.y - 5.0), vessel_name.to_upper(), HORIZONTAL_ALIGNMENT_CENTER,
			tw, fs - 5, Color(0.72, 0.68, 0.6, 0.9))


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
	_glass(c, r)


## An altimeter: one turn of the needle per 1000 m, the full height in figures.
func _altimeter(c: Vector2, r: float, alt: float, font: Font, fs: int) -> void:
	_face(c, r)
	for i in 10:
		var d := Vector2.from_angle(-PI * 0.5 + TAU * float(i) / 10.0)
		draw_line(c + d * r * 0.78, c + d * r * 0.92, Color(0.85, 0.82, 0.75), 1.5)
	_needle(c, r * 0.8, -PI * 0.5 + TAU * fposmod(alt, 1000.0) / 1000.0)
	_dial_text(c, r, "ALT", "%d" % int(alt), font, fs)
	_glass(c, r)


## The attitude ball: sky over ground, the horizon dropping as the nose comes up and
## turning against the roll, a fixed wings mark in the middle.
func _attitude(c: Vector2, r: float, pitch: float, roll: float) -> void:
	_bezel(c, r)
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
	_glass(c, r)


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
	_glass(c, r)


func _face(c: Vector2, r: float) -> void:
	_bezel(c, r)
	draw_circle(c, r, FACE)


## A turned metal ring round a face: lit on the side toward the light, in shadow
## on the other.
func _bezel(c: Vector2, r: float) -> void:
	var w := maxf(4.0, r * 0.08)
	draw_circle(c, r + w + 1.0, Color(0, 0, 0, 0.6))
	draw_circle(c, r + w, BEZEL)
	var lit := LIGHT.angle()
	draw_arc(c, r + w * 0.55, lit - 1.1, lit + 1.1, 24, BEZEL_LIT, w * 0.5, true)
	draw_arc(c, r + w * 0.55, lit + PI - 1.1, lit + PI + 1.1, 24, BEZEL_SHADE, w * 0.5, true)


## Glass over a round face: a dark lip where it meets the bezel, a soft sheen over
## the side toward the light, a fainter streak across the middle, and a hard glint
## where the light catches the curve; then the sun's and any bolts' glints.
func _glass(c: Vector2, r: float) -> void:
	draw_arc(c, r - 1.5, 0.0, TAU, 48, Color(0, 0, 0, 0.5), 3.0, true)
	var disc := circle_points(r * 0.97, 40)
	_fill_at(clip_half_plane(disc, LIGHT, r * 0.3), c, GLARE_SOFT)
	_fill_at(clip_half_plane(clip_half_plane(disc, LIGHT, -r * 0.18), -LIGHT, r * 0.04), c, GLARE_BAND)
	var lit := LIGHT.angle()
	draw_arc(c, r * 0.86, lit - 0.45, lit + 0.3, 16, GLARE_GLINT, maxf(1.5, r * 0.03), true)
	draw_circle(c + LIGHT.rotated(0.45) * r * 0.66, maxf(1.5, r * 0.035), Color(1, 1, 1, 0.5))
	_glints(c, r)


## Each light's reflection in a round glass: a soft bloom, a hot point, and away
## from the middle a short streak bent round the dome.
func _glints(c: Vector2, r: float) -> void:
	for l in lights:
		var g := glint(l.dir)
		var a: float = float(l.power) * g.z
		if a <= 0.01:
			continue
		var col: Color = (l.color as Color).lerp(Color.WHITE, 0.5)
		var off := Vector2(g.x, g.y) * r * 0.85
		if off.length() > r * 0.85:
			off = off.normalized() * r * 0.85
		halo(self, c + off, r * 0.55, Color(col, a * 0.35))
		if off.length() > r * 0.2:
			draw_arc(c, off.length(), off.angle() - 0.32, off.angle() + 0.32, 12, Color(col, a * 0.55), maxf(1.5, r * 0.04), true)
		draw_circle(c + off, maxf(1.5, r * 0.055), Color(col, minf(1.0, a)))


## Glass over a flat window (the bars): a sheen on its top half and a bright top
## lip, which the lights brighten and tint.
func _glass_rect(r: Rect2) -> void:
	draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.45)), Color(1, 1, 1, 0.08))
	draw_line(r.position + Vector2(1, 1), Vector2(r.end.x - 1, r.position.y + 1), Color(1, 1, 1, 0.3), 1.0)
	for l in lights:
		var a: float = float(l.power) * glint(l.dir).z
		if a > 0.01:
			var col: Color = (l.color as Color).lerp(Color.WHITE, 0.5)
			draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.45)), Color(col, a * 0.12))
			draw_line(r.position + Vector2(1, 1), Vector2(r.end.x - 1, r.position.y + 1), Color(col, a * 0.5), 1.0)


func _fill_at(poly: PackedVector2Array, at: Vector2, col: Color) -> void:
	if poly.size() < 3:
		return
	for i in poly.size():
		poly.set(i, poly[i] + at)
	draw_colored_polygon(poly, col)


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
	_glass_rect(r)
	draw_rect(r, DASH_RIM, false, 1.5)
	draw_string(font, c + Vector2(-40, h * 0.5 + fs + 2.0), label, HORIZONTAL_ALIGNMENT_CENTER, 80, fs - 4, Color(0.75, 0.72, 0.66))


func _bar_h(top_left: Vector2, w: float, frac: float, label: String, font: Font, fs: int) -> void:
	draw_string(font, top_left + Vector2(0, fs - 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 5, Color(0.75, 0.72, 0.66))
	var r := Rect2(top_left + Vector2(0, fs - 2), Vector2(w, 7))
	draw_rect(r, FACE)
	var f := clampf(frac, 0.0, 1.0)
	draw_rect(Rect2(r.position, Vector2(w * f, 7)), NEEDLE if f > 0.3 else Color(1.0, 0.25, 0.18))
	_glass_rect(r)
	draw_rect(r, DASH_RIM, false, 1.0)


## The Shift ability's lamp: lit (with a glow) while it runs, dark when not.
func _lamp(c: Vector2, r: float, on: bool) -> void:
	_bezel(c, r)
	if on:
		draw_circle(c, r * 2.2, Color(LAMP_ON.r, LAMP_ON.g, LAMP_ON.b, 0.18))
		draw_circle(c, r, LAMP_ON)
		draw_circle(c - Vector2(r, r) * 0.3, r * 0.35, Color(1, 0.95, 0.8, 0.9))
	else:
		draw_circle(c, r, LAMP_OFF)
