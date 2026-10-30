class_name FlightSimHud
extends Control
## The chase view's head-up display (issue #181), in place of the old text read-out
## in the top left. Drawn lines, the way a flight sim's HUD is:
##   - a pitch ladder round the reticle that rolls with the ship (a rung every 10
##     degrees, the horizon the long one, dashed below it),
##   - a heading tape along the top,
##   - a speed tape on the left and an altitude tape on the right, the value boxed
##     in the middle; ground clearance and climb rate under the altitude,
##   - throttle and the Shift ability's meter bottom left, hull and shield beside them,
##   - the ship's name and flight state in the top left corner.
## No logic: FlightHud hands it `values` (show_values) and redraws it.

const LADDER_STEP := 10            ## degrees between rungs
const PX_PER_DEG := 7.0            ## ladder spacing on screen
const LADDER_SPAN := 190.0         ## px above and below the centre the ladder shows
const HEADING_SPAN := 30.0         ## degrees either side of the nose on the tape
const HEADING_PX := 6.0            ## px per degree on the heading tape
const TAPE_H := 280.0
const SPEED_PX := 2.0              ## px per m/s on the speed tape
const ALT_PX := 0.12               ## px per metre on the altitude tape

var values: Dictionary = {}
var vessel_name := ""


func _ready() -> void:
	name = "SimHud"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## The player's HUD colour (F11 > HUD) at alpha `a`.
static func ink(a: float = 0.95) -> Color:
	var c := RetroUI.accent
	c.a = a
	return c


func _v(key: String, fallback: float = 0.0) -> float:
	return float(values.get(key, fallback))


func _draw() -> void:
	var vp := get_viewport_rect().size
	var c := vp * 0.5
	var font := RetroUI.font()
	var fs := RetroUI.size("flight_gauge", 17)
	_draw_ladder(c, _v("pitch"), _v("roll"), font, fs)
	_draw_heading(Vector2(c.x, 30.0), _v("heading"), font, fs)
	var off := minf(vp.x * 0.3, 420.0)
	_draw_tape(Vector2(c.x - off, c.y), _v("speed"), 10.0, 5, SPEED_PX, false, "M/S", font, fs)
	_draw_tape(Vector2(c.x + off, c.y), _v("altitude"), 100.0, 5, ALT_PX, true, "ALT", font, fs)
	var below := Vector2(c.x + off + 6.0, c.y + TAPE_H * 0.5 + fs + 8.0)
	draw_string(font, below, "AGL %5d" % int(maxf(0.0, _v("agl"))), HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 2, ink(0.8))
	draw_string(font, below + Vector2(0, fs + 2), "VS  %+5d" % int(_v("climb")), HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 2, ink(0.8))
	_draw_bars(vp, font, fs)
	var top := Vector2(18.0, 54.0 + fs)
	if vessel_name != "":
		draw_string(font, top, vessel_name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink())
		top.y += fs + 4.0
	draw_string(font, top, str(values.get("state", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 2, ink(0.7))


## The ladder in its own rolled frame: rung `a` sits (pitch - a) degrees below the
## centre, so the horizon drops as the nose comes up.
func _draw_ladder(c: Vector2, pitch: float, roll: float, font: Font, fs: int) -> void:
	draw_set_transform(c, -deg_to_rad(roll), Vector2.ONE)
	var col := ink(0.85)
	var first := int(ceil((pitch - LADDER_SPAN / PX_PER_DEG) / LADDER_STEP)) * LADDER_STEP
	var a := maxi(first, -90)
	while a <= 90:
		var y := (pitch - float(a)) * PX_PER_DEG
		if y < -LADDER_SPAN:
			break
		if a == 0:
			draw_line(Vector2(-230, y), Vector2(-46, y), col, 2.0)
			draw_line(Vector2(46, y), Vector2(230, y), col, 2.0)
		else:
			var tick := 8.0 if a > 0 else -8.0          # end ticks point at the horizon
			for side in [-1.0, 1.0]:
				var x0: float = 46.0 * side
				var x1: float = 128.0 * side
				if a > 0:
					draw_line(Vector2(x0, y), Vector2(x1, y), col, 1.5)
				else:
					draw_dashed_line(Vector2(x0, y), Vector2(x1, y), col, 1.5, 8.0)
				draw_line(Vector2(x1, y), Vector2(x1, y + tick), col, 1.5)
			var label := str(absi(a))
			draw_string(font, Vector2(136, y + fs * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 3, col)
			draw_string(font, Vector2(-136 - 40, y + fs * 0.35), label, HORIZONTAL_ALIGNMENT_RIGHT, 40, fs - 3, col)
		a += LADDER_STEP
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_heading(at: Vector2, heading: float, font: Font, fs: int) -> void:
	var col := ink(0.85)
	var half := HEADING_SPAN * HEADING_PX
	draw_line(at + Vector2(-half, 18), at + Vector2(half, 18), ink(0.5), 1.0)
	var d := int(floor((heading - HEADING_SPAN) / 5.0)) * 5
	while float(d) <= heading + HEADING_SPAN:
		var x := (float(d) - heading) * HEADING_PX
		if absf(x) <= half:
			var deg := posmod(d, 360)
			var major := deg % 10 == 0
			draw_line(at + Vector2(x, 18), at + Vector2(x, 18 - (10.0 if major else 5.0)), col, 1.5)
			if deg % 30 == 0:
				draw_string(font, at + Vector2(x - 20, 4), compass_label(deg), HORIZONTAL_ALIGNMENT_CENTER, 40, fs - 3, col)
		d += 5
	# The current heading, boxed under the tape, with a caret at it.
	var box := Rect2(at + Vector2(-30, 24), Vector2(60, fs + 6))
	draw_rect(box, Color(0, 0, 0, 0.5))
	draw_rect(box, col, false, 1.5)
	draw_string(font, box.position + Vector2(0, fs + 1), "%03d" % posmod(int(round(heading)), 360),
		HORIZONTAL_ALIGNMENT_CENTER, box.size.x, fs - 1, ink())
	draw_colored_polygon(PackedVector2Array([at + Vector2(0, 19), at + Vector2(-5, 24), at + Vector2(5, 24)]), col)


## N, E, S, W at the quarters, else the heading in tens (03, 06, ...).
static func compass_label(deg: int) -> String:
	match posmod(deg, 360):
		0:
			return "N"
		90:
			return "E"
		180:
			return "S"
		270:
			return "W"
	return "%02d" % (posmod(deg, 360) / 10)


## A vertical tape: higher values up, a tick every `step`, a number every
## `label_every` ticks, the value boxed at the centre. `right` puts the ticks on its
## left edge (the altitude tape faces in toward the reticle, as the speed tape does).
func _draw_tape(c: Vector2, value: float, step: float, label_every: int, ppu: float, right: bool,
		caption: String, font: Font, fs: int) -> void:
	var col := ink(0.85)
	var half := TAPE_H * 0.5
	var dir := -1.0 if right else 1.0              # which way the ticks point (toward the centre)
	draw_line(c + Vector2(0, -half), c + Vector2(0, half), ink(0.5), 1.0)
	var lo := value - half / ppu
	var i := int(ceil(lo / step))
	while float(i) * step <= value + half / ppu:
		var v := float(i) * step
		i += 1
		if v < 0.0 and not right:
			continue                                  # no speed under zero
		var y := c.y - (v - value) * ppu
		var major := (i - 1) % label_every == 0
		draw_line(Vector2(c.x, y), Vector2(c.x + dir * (12.0 if major else 6.0), y), col, 1.5)
		if major and absf(y - c.y) > fs:
			var lx := c.x - 70.0 - 6.0 if not right else c.x + 6.0
			draw_string(font, Vector2(lx, y + fs * 0.35), str(int(v)),
				HORIZONTAL_ALIGNMENT_RIGHT if not right else HORIZONTAL_ALIGNMENT_LEFT, 70, fs - 3, col)
	var bw := 84.0
	var box := Rect2(Vector2(c.x - bw - 4.0 if not right else c.x + 4.0, c.y - fs * 0.5 - 4.0), Vector2(bw, fs + 8.0))
	draw_rect(box, Color(0, 0, 0, 0.55))
	draw_rect(box, ink(), false, 1.5)
	draw_string(font, box.position + Vector2(0, fs + 2.0), str(int(round(value))), HORIZONTAL_ALIGNMENT_CENTER, bw, fs, ink())
	var cap_x := c.x - 70.0 if not right else c.x
	draw_string(font, Vector2(cap_x, c.y - half - 8.0), caption, HORIZONTAL_ALIGNMENT_CENTER, 70, fs - 3, ink(0.7))


## Throttle and the Shift ability's meter (lit while it runs) as upright bars, hull
## and shield as flat ones beside them.
func _draw_bars(vp: Vector2, font: Font, fs: int) -> void:
	var base := Vector2(30.0, vp.y - 48.0)
	var h := 120.0
	_vbar(base, h, _v("throttle"), "THR", ink(0.9), font, fs)
	var on := bool(values.get("ability_on", false))
	var ab := str(values.get("ability", "boost")).to_upper()
	_vbar(base + Vector2(46, 0), h, _v("boost"), ab.substr(0, 5), ink(1.0) if on else ink(0.55), font, fs)
	var hx := base + Vector2(110, -h)
	var hull_max := maxf(1.0, _v("hull_max", 1.0))
	_hbar(hx, 180.0, _v("hull") / hull_max, "HULL  %d" % int(_v("hull")), font, fs)
	var smax := _v("shield_max")
	if smax > 0.0:
		_hbar(hx + Vector2(0, fs + 22), 180.0, _v("shield") / smax, "SHLD  %d" % int(_v("shield")), font, fs)


func _vbar(bottom_left: Vector2, h: float, frac: float, label: String, fill: Color, font: Font, fs: int) -> void:
	var r := Rect2(bottom_left + Vector2(0, -h), Vector2(14, h))
	draw_rect(r, Color(0, 0, 0, 0.45))
	var f := h * clampf(frac, 0.0, 1.0)
	draw_rect(Rect2(bottom_left + Vector2(0, -f), Vector2(14, f)), fill)
	draw_rect(r, ink(0.6), false, 1.0)
	draw_string(font, bottom_left + Vector2(-12, fs + 2), label, HORIZONTAL_ALIGNMENT_CENTER, 38, fs - 5, ink(0.75))


func _hbar(top_left: Vector2, w: float, frac: float, label: String, font: Font, fs: int) -> void:
	draw_string(font, top_left + Vector2(0, fs - 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 4, ink(0.8))
	var r := Rect2(top_left + Vector2(0, fs), Vector2(w, 6))
	draw_rect(r, Color(0, 0, 0, 0.45))
	var f := clampf(frac, 0.0, 1.0)
	var col := ink(0.9) if f > 0.3 else Color(1.0, 0.35, 0.25, 0.95)
	draw_rect(Rect2(r.position, Vector2(w * f, 6)), col)
	draw_rect(r, ink(0.6), false, 1.0)
