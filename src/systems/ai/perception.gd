class_name Perception
extends RefCounted
## What an NPC sees and hears. Pure and headless-testable: the body node supplies
## positions, the result of its last line-of-sight ray and any new noises; this
## decides whether the target is in view, builds an awareness meter, and keeps a
## last known position. It never casts rays itself, it only says when it wants
## one (wants_ray), so the body can throttle them.
##
## Awareness (0..1) is the familiar stealth meter: it rises while the target is
## seen (faster up close, faster if they hold a weapon, slower if they crouch far
## off) and decays when they are not. Crossing notice_at latches "noticed"; it
## clears when awareness falls under lose_at and the target has been out of
## sight for forget_s. A heard shot does not reveal the shooter: it raises
## awareness and gives a place to look (heard_pos), which is what a brain will
## send the guard to check.
##
## Every number comes from the soldier profile's "perception" block.

var sight_range := 32.0
var fov_deg := 120.0
var close_range := 2.5        ## felt at any angle inside this, if in line of sight
var reaction_s := 0.9         ## seconds of clear view at mid range to notice
var decay_per_s := 0.25
var forget_s := 8.0
var notice_at := 1.0
var lose_at := 0.3
var crouch_sight_mult := 0.6  ## a crouched target is seen at this share of the range
var armed_rise_mult := 1.6
var hearing_range := 45.0
var heard_awareness := 0.6
var ray_hz := 5.0
var footstep_range := 6.0     ## a moving, standing target is heard inside this (crouch-walking is silent)
var footstep_awareness := 0.45
var eye_height := 1.62
var target_chest := 1.25

## Outputs, read by the body and (next push) the guard brain.
var in_cone := false          ## inside range + field of view, before the ray
var visible := false          ## in cone AND the last ray was clear
var awareness := 0.0
var noticed := false
var last_seen_pos := Vector3.INF
var since_seen := INF
var saw_weapon := false       ## the target was holding a weapon when last seen
var heard := false            ## a noise reached us this update
var heard_pos := Vector3.INF
var heard_kind := ""
var since_heard := INF
var rays_wanted := 0

var _ray_clock := 0.0
var _last_noise_id := 0


func _init(cfg: Dictionary = {}) -> void:
	for k in ["sight_range", "fov_deg", "close_range", "reaction_s", "decay_per_s",
			"forget_s", "notice_at", "lose_at", "crouch_sight_mult", "armed_rise_mult",
			"hearing_range", "heard_awareness", "ray_hz", "eye_height", "target_chest",
			"footstep_range", "footstep_awareness"]:
		if cfg.has(k):
			set(k, float(cfg[k]))
	_last_noise_id = NoiseEvents.last_id()   # do not hear what happened before we existed


## Range a target is seen at, given its stance.
func effective_range(crouched: bool) -> float:
	return sight_range * (crouch_sight_mult if crouched else 1.0)


## Inside range and the field of view (or close enough to feel at any angle).
## `forward` is the way the NPC's eyes face (flat is fine).
func cone_check(self_pos: Vector3, forward: Vector3, target_pos: Vector3, crouched: bool = false) -> bool:
	var to := target_pos - self_pos
	to.y = 0.0
	var d := to.length()
	if d <= close_range:
		return true
	if d > effective_range(crouched):
		return false
	var f := Vector3(forward.x, 0.0, forward.z)
	if f.length() < 0.001 or d < 0.001:
		return true
	var cos_half := cos(deg_to_rad(fov_deg * 0.5))
	return f.normalized().dot(to / d) >= cos_half


## Whether the body should cast a line-of-sight ray this frame: only while the
## target is in the cone, and at most ray_hz times a second.
func wants_ray(dt: float) -> bool:
	_ray_clock -= dt
	if not in_cone:
		return false
	if _ray_clock <= 0.0:
		_ray_clock = 1.0 / maxf(ray_hz, 0.1)
		rays_wanted += 1
		return true
	return false


## One frame. `s` = { self_pos, forward, target_pos, crouched, armed, los_clear,
## noises (Array from NoiseEvents.after, or omit to read NoiseEvents directly) }.
## Call cone_update first in the frame (the body does), then wants_ray, then this.
func update(dt: float, s: Dictionary) -> void:
	var self_pos: Vector3 = s.get("self_pos", Vector3.ZERO)
	var target_pos: Vector3 = s.get("target_pos", Vector3.INF)
	var crouched: bool = s.get("crouched", false)
	var has_target := target_pos != Vector3.INF
	in_cone = has_target and cone_check(self_pos, s.get("forward", Vector3.BACK), target_pos, crouched)
	visible = in_cone and bool(s.get("los_clear", false))

	since_seen += dt
	since_heard += dt
	if visible:
		var d := Vector3(target_pos.x - self_pos.x, 0.0, target_pos.z - self_pos.z).length()
		var reach := maxf(effective_range(crouched), 0.001)
		# Twice the rate up close, half the rate at the edge of sight.
		var closeness := lerpf(2.0, 0.5, clampf(d / reach, 0.0, 1.0))
		var rate := closeness / maxf(reaction_s, 0.01)
		if bool(s.get("armed", false)):
			rate *= armed_rise_mult
		awareness = minf(1.0, awareness + rate * dt)
		last_seen_pos = target_pos
		since_seen = 0.0
		saw_weapon = bool(s.get("armed", false))
	else:
		awareness = maxf(0.0, awareness - decay_per_s * dt)

	heard = false
	# Footsteps: someone walking or running close by is heard at any angle.
	var speed := float(s.get("target_speed", 0.0))
	if has_target and not crouched and speed > 1.5:
		var fd := Vector3(target_pos.x - self_pos.x, 0.0, target_pos.z - self_pos.z).length()
		if fd <= footstep_range * clampf(speed / 4.0, 0.5, 1.5):
			heard = true
			heard_pos = target_pos
			heard_kind = "steps"
			since_heard = 0.0
			awareness = maxf(awareness, footstep_awareness)
	var noises: Array = s["noises"] if s.has("noises") else NoiseEvents.after(_last_noise_id)
	for n in noises:
		_last_noise_id = maxi(_last_noise_id, int(n.id))
		var reach_m := minf(float(n.radius), hearing_range)
		if (n.pos as Vector3).distance_to(self_pos) <= reach_m:
			heard = true
			heard_pos = n.pos
			heard_kind = str(n.kind)
			since_heard = 0.0
			awareness = maxf(awareness, heard_awareness)

	if awareness >= notice_at:
		noticed = true
	elif noticed and awareness < lose_at and since_seen >= forget_s:
		noticed = false


## Just the cone part of update, so the body knows whether to cast a ray before
## it calls update with the result.
func cone_update(self_pos: Vector3, forward: Vector3, target_pos: Vector3, crouched: bool) -> void:
	in_cone = target_pos != Vector3.INF and cone_check(self_pos, forward, target_pos, crouched)


func summary() -> Dictionary:
	return {
		"in_cone": in_cone, "visible": visible, "awareness": snappedf(awareness, 0.01),
		"noticed": noticed, "heard": heard, "heard_kind": heard_kind, "saw_weapon": saw_weapon,
	}
