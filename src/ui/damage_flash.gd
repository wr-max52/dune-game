class_name DamageFlash
extends Control
## Being hit in a ship (issue #181): a red glow round the edge of the screen. It is
## full for HOLD seconds, then fades slowly out over FADE. Another hit lights it
## again from full.
##
## Its own child of the flight HUD, over everything but the black fade, and the
## full rect by anchors, so it follows resizes. `advance(dt)` is the clock (called
## from _process); tests call it directly instead of waiting for frames.

const HOLD := 1.0              ## seconds at full after a hit
const FADE := 1.6              ## seconds from full to gone
const PEAK := 0.6              ## alpha at the very edge while lit
const DEPTH := 0.14            ## how far in it reaches, as a share of the shorter side
const BANDS := 14
const RED := Color(0.92, 0.07, 0.04)

var flashes := 0               ## hits that lit it (traces, tests)
var _t := -1.0                 ## seconds since the last hit; < 0 = gone


func _ready() -> void:
	name = "DamageFlash"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func flash() -> void:
	_t = 0.0
	flashes += 1
	visible = true
	queue_redraw()


func advance(dt: float) -> void:
	if _t < 0.0:
		return
	_t += dt
	if _t >= HOLD + FADE:
		_t = -1.0
		visible = false
	queue_redraw()


func _process(dt: float) -> void:
	advance(dt)


## 1 while held, easing slowly to 0 over the fade (slow at both ends).
func alpha() -> float:
	if _t < 0.0:
		return 0.0
	if _t <= HOLD:
		return 1.0
	return 1.0 - smoothstep(0.0, 1.0, (_t - HOLD) / FADE)


func is_showing() -> bool:
	return alpha() > 0.0


## Rings from the edge inward, each fainter than the last.
func _draw() -> void:
	var a := alpha()
	if a <= 0.0:
		return
	var vp := size
	var th := minf(vp.x, vp.y) * DEPTH / float(BANDS)
	for i in BANDS:
		var k := 1.0 - float(i) / float(BANDS)
		var col := RED
		col.a = PEAK * a * k * k
		var o := th * i
		var w := vp.x - o * 2.0
		var h := vp.y - o * 2.0
		draw_rect(Rect2(o, o, w, th), col)
		draw_rect(Rect2(o, vp.y - o - th, w, th), col)
		draw_rect(Rect2(o, o + th, th, h - th * 2.0), col)
		draw_rect(Rect2(vp.x - o - th, o + th, th, h - th * 2.0), col)
