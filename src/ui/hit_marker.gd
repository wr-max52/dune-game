class_name HitMarker
extends Control
## The hit marker (issue #65): four short diagonal ticks around screen centre, an X
## with a gap in the middle. It pops when the player deals damage, fades in ~0.22 s,
## and is white for a hit, bigger and red for a kill.
##
## It is its own child of the HUD layer, not part of the crosshair, so it still shows
## when the crosshair is hidden (aimed down sights). It is centred on the viewport by
## anchors, so it follows resizes. `advance(dt)` is the clock (called from _process);
## tests call it directly instead of waiting for frames.

const LIFE := 0.22             ## seconds from pop to gone
const GAP := 6.0               ## px from centre to the inner end of a tick
const LEN := 8.0               ## px length of a tick (kill: bigger)
const KILL_SCALE := 1.5
const POP := 0.25              ## extra scale at the instant of the hit, easing to 1

var _left := 0.0
var _kill := false


func _ready() -> void:
	name = "HitMarker"
	set_anchors_preset(Control.PRESET_CENTER)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


## Pop the marker. A new hit restarts it (a rifle burst keeps it lit); a kill is
## never downgraded to a plain hit while the kill marker is still up.
func show_hit(kill: bool) -> void:
	_kill = kill or (_kill and _left > 0.0)
	_left = LIFE
	visible = true
	queue_redraw()


func advance(dt: float) -> void:
	if _left <= 0.0:
		return
	_left = maxf(0.0, _left - dt)
	visible = _left > 0.0
	queue_redraw()


func _process(dt: float) -> void:
	advance(dt)


## 1 at the pop, 0 when gone.
func alpha() -> float:
	return clampf(_left / LIFE, 0.0, 1.0)


func is_kill() -> bool:
	return _kill and _left > 0.0


func is_showing() -> bool:
	return _left > 0.0


## Overall size factor right now: a kill is bigger, and every hit pops then settles.
func current_scale() -> float:
	var s := KILL_SCALE if _kill else 1.0
	return s * (1.0 + POP * alpha() * alpha())


func current_color() -> Color:
	var c := Color(1.0, 0.18, 0.14) if _kill else Color(1, 1, 1)
	c.a = alpha()
	return c


func _draw() -> void:
	if _left <= 0.0:
		return
	var s := current_scale()
	var col := current_color()
	for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var dir: Vector2 = d.normalized()
		draw_line(dir * GAP * s, dir * (GAP + LEN) * s, col, 2.0, true)
