extends RefCounted
## Fighter pilot AI (M10). Pure and headless-testable, like the M2 trooper brain: it
## looks at its own flight model and a target, picks a dogfight action, and writes a
## flight command plus trigger requests. The dogfight director applies them, so an
## AI ship and the player fly through the same flight model and guns.
##
## The same brain also flies the player's autopilot in the headless trace -- the M5
## "bot and human share one implementation" rule.
##
## Every number comes from a pilot profile (content/core/pilots/*.json), so a new
## pilot personality is a data file, not code.
##
## Actions:
##   PATROL  -- no target: cruise back toward the arena centre
##   PURSUE  -- target beyond engage range: close the distance, boost if far
##   ATTACK  -- in range: fly the lead point and fire inside the aim cone
##   BREAK   -- too close or just hit: hard turn away at full throttle
##   EXTEND  -- after a break: open distance before turning back in
##   RETURN  -- outside the arena: head back to the centre

const LeadSolver := preload("res://src/systems/flight/lead_solver.gd")

enum Action { PATROL, PURSUE, ATTACK, BREAK, EXTEND, RETURN }

var profile: Dictionary = {}
var flight                      ## the ship's flight model (flight_model.gd)
var state := Action.PATROL

## Situation the director sets each frame.
var has_target := false
var target_pos := Vector3.ZERO
var target_vel := Vector3.ZERO
var arena_center := Vector3.ZERO
var arena_radius := 1500.0
var bolt_speed := 300.0         ## primary weapon projectile speed, for the lead
var weapon_range := 900.0
var missile_locked := false
var has_missiles := false
## How much bigger this fight is than the profile's distances (a space fight's
## range_scale, content/core/flow/space_fight.json); 1.0 in the air.
var reach := 1.0

## Outputs the director reads after update().
var command := { "pitch": 0.0, "yaw": 0.0, "roll": 0.0, "throttle": 0.6, "boost": false }
var fire_primary := false
var fire_secondary := false
var aim_point := Vector3.ZERO   ## where the AI is pointing its nose

var _rng := RandomNumberGenerator.new()
var _break_left := 0.0
var _break_dir := Vector3.ZERO
var _hit_pending := false
var _missile_pending := false
var _aim_jitter := Vector3.ZERO
var _jitter_left := 0.0


func _init(pilot_profile: Dictionary = {}, flight_model = null, rng_seed: int = 1) -> void:
	profile = pilot_profile
	flight = flight_model
	_rng.seed = rng_seed


func p(key: String, fallback: float) -> float:
	return float(profile.get(key, fallback))


## A profile distance (metres), times reach.
func d(key: String, fallback: float) -> float:
	return p(key, fallback) * reach


## Called by the director when this ship takes a hit.
func notify_hit() -> void:
	_hit_pending = true


## Called by the director when a seeker is launched at this ship. A pilot evades by
## breaking hard: a seeker turns slower than a fighter, so a well-timed break makes
## it overshoot.
func notify_missile() -> void:
	_missile_pending = true


func distance_to_target() -> float:
	return (target_pos - flight.position).length() if has_target else INF


## Decide this frame's action and fill the outputs. Returns the Action.
func update(dt: float) -> int:
	fire_primary = false
	fire_secondary = false
	var pos: Vector3 = flight.position

	var hit := _hit_pending
	_hit_pending = false
	var missile := _missile_pending
	_missile_pending = false

	if (pos - arena_center).length() > arena_radius and state != Action.BREAK:
		state = Action.RETURN
		_steer_to(arena_center, 1.0, true)
		return state
	if state == Action.RETURN:
		state = Action.PURSUE if has_target else Action.PATROL

	if not has_target:
		state = Action.PATROL
		_steer_to(arena_center + Vector3(0, 0, -200) * reach, 0.6, false)
		return state

	var dist := distance_to_target()

	match state:
		Action.BREAK:
			_break_left -= dt
			_steer_to(pos + _break_dir * 400.0 * reach, 1.0, true)
			if _break_left <= 0.0:
				state = Action.EXTEND
			return state
		Action.EXTEND:
			var away := (pos - target_pos).normalized()
			_steer_to(pos + (away + flight.forward()).normalized() * 400.0 * reach, 1.0, false)
			if dist >= d("extend_distance", 400.0):
				state = Action.PURSUE
			return state

	# PURSUE / ATTACK / PATROL fall through to a fresh decision.
	var too_close := dist < d("break_distance", 90.0)
	var spooked := hit and _rng.randf() < p("break_on_hit", 0.3)
	var evading := missile and _rng.randf() < p("evade_missile", 0.5)
	if too_close or spooked or evading:
		_start_break()
		_steer_to(pos + _break_dir * 400.0 * reach, 1.0, true)
		return state

	if dist > d("engage_range", 650.0):
		state = Action.PURSUE
		_steer_to(target_pos + target_vel * 0.5, 1.0, dist > d("engage_range", 650.0) * 1.8)
		return state

	state = Action.ATTACK
	var lead := LeadSolver.intercept(pos, flight.velocity(), target_pos, target_vel, bolt_speed)
	_jitter_left -= dt
	if _jitter_left <= 0.0:
		var e := p("aim_error", 0.03)
		_aim_jitter = Vector3(_rng.randf_range(-e, e), _rng.randf_range(-e, e), _rng.randf_range(-e, e))
		_jitter_left = 0.4
	var aim_dir: Vector3 = (lead.dir as Vector3 + _aim_jitter).normalized()
	_steer_to(pos + aim_dir * dist, p("attack_throttle", 0.7), false)
	var off := LeadSolver.angle_deg(flight.forward(), aim_dir)
	fire_primary = off <= p("aim_cone_deg", 6.0) and dist <= weapon_range
	fire_secondary = has_missiles and missile_locked and bool(profile.get("missile_use", false))
	return state


func _start_break() -> void:
	state = Action.BREAK
	_break_left = p("break_time", 1.6)
	var side := 1.0 if _rng.randf() < 0.5 else -1.0
	var lift := _rng.randf_range(-0.6, 0.6)
	_break_dir = (flight.right() * side + flight.up() * lift + flight.forward() * 0.3).normalized()


## Steer the nose toward a world point. Far off the nose the pilot banks so the
## point sits overhead and pulls (pitch is the strongest axis); near the nose it
## fine-aims with pitch and yaw directly.
func _steer_to(point: Vector3, throttle: float, boost: bool) -> void:
	aim_point = point
	var to: Vector3 = point - flight.position
	command.throttle = throttle
	command.boost = boost
	if to.length_squared() < 0.0001:
		command.pitch = 0.0
		command.yaw = 0.0
		command.roll = 0.0
		return
	var local: Vector3 = flight.basis.inverse() * to.normalized()  # x right, y up, -z ahead
	var off := acos(clampf(-local.z, -1.0, 1.0))                    # radians off the nose
	var gain := p("steer_gain", 3.0)
	if off < 0.3:
		command.pitch = clampf(local.y * gain * 2.0, -1.0, 1.0)
		command.yaw = clampf(local.x * gain * 2.0, -1.0, 1.0)
		command.roll = clampf(flight.right().y * 1.5, -1.0, 1.0)    # level the wings
	else:
		var bank := atan2(local.x, local.y)                          # 0 when the point is overhead
		command.roll = clampf(bank * 1.6, -1.0, 1.0)
		command.pitch = clampf(off * gain, -1.0, 1.0) * clampf(cos(bank) + 0.35, 0.0, 1.0)
		command.yaw = clampf(local.x * gain, -1.0, 1.0)


func state_label() -> String:
	return Action.keys()[state]
