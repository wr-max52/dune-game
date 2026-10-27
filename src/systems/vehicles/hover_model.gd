class_name HoverModel
extends RefCounted
## A speeder's movement (issue #42). Pure and headless-testable, like AtmoFlight:
## the scene node reads input and draws, this decides.
##
## It rides `hover_height` above whatever WorldGround says is under it (the sand,
## a floor, the top of a ramp), easing toward that height at `follow_rate`. When
## the ground drops away faster than that in one step (more than `launch_gap`: the
## end of a ramp, a dune crest at speed) it leaves the ground with the vertical
## speed it had and flies ballistic until it comes down. There is no jump button:
## ramps and crests do the jumping, and low gravity makes it float like the light
## sled it is.
##
## Buildings stop it (WorldGround.hit) with a small bounce. Nothing it does to
## itself hurts it: no fall or crash damage. Only gunfire does, through
## apply_damage(), which the node's hull passes on from bolts.
##
## Numbers: content/core/vehicles/speeder.json.

var cfg: Dictionary = {}
var ground: WorldGround
var position := Vector3.ZERO
var yaw := 0.0                       ## radians about +Y; 0 faces -Z
var speed := 0.0                     ## along the nose, m/s (negative = reversing)
var vy := 0.0                        ## vertical speed, m/s
var airborne := false
var boost_left := 0.0
var hp := 0
var max_hp := 0
var events: Array = []               ## this step's: { type, ... }
var air_time := 0.0                  ## of the current (or last) jump
var top_height := 0.0                ## highest clearance over the ground on the last jump

var _cmd := { "throttle": 0.0, "steer": 0.0, "boost": false }
var _last_ride := NAN                ## the ride height last step (NAN: none yet)
var _ground_rate := 0.0              ## how fast the ground under it was rising, m/s


func _init(config: Dictionary = {}, world_ground: WorldGround = null) -> void:
	cfg = config
	ground = world_ground
	max_hp = int(cfg.get("health", 120))
	hp = max_hp
	boost_left = p("boost_time", 3.5)


static func load_config(id: String = "speeder") -> Dictionary:
	var f := FileAccess.open("res://content/core/vehicles/%s.json" % id, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func p(key: String, fallback: float) -> float:
	return float(cfg.get(key, fallback))


# ---- queries ------------------------------------------------------------------------

func forward() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func transform() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), position)


func ground_height() -> float:
	if ground == null:
		return 0.0
	return ground.ground_at(position.x, position.z, position.y)


## Clearance between the hover line and the ground below (0 when riding).
func height_over_ground() -> float:
	return position.y - p("hover_height", 1.05) - ground_height()


func alive() -> bool:
	return hp > 0


# ---- control --------------------------------------------------------------------------

## Put it down at `at` (on the ground there), facing `yaw_rad`.
func place(at: Vector3, yaw_rad: float) -> void:
	position = at
	yaw = yaw_rad
	speed = 0.0
	vy = 0.0
	airborne = false
	position.y = ground_height() + p("hover_height", 1.05)
	_last_ride = NAN
	_ground_rate = 0.0


## throttle -1..1 (back..forward), steer -1..1 (left..right).
func set_command(throttle: float, steer: float, boost: bool = false) -> void:
	_cmd = { "throttle": clampf(throttle, -1.0, 1.0), "steer": clampf(steer, -1.0, 1.0), "boost": boost }


## Gunfire. Returns true if this shot destroyed it.
func apply_damage(amount: float) -> bool:
	if hp <= 0:
		return false
	hp = maxi(0, hp - int(ceil(amount)))
	events.append({ "type": "hit", "damage": amount, "hp": hp })
	if hp == 0:
		events.append({ "type": "destroyed", "at": position })
		return true
	return false


# ---- frame ------------------------------------------------------------------------------

## Advance one step. Returns this step's events.
func step(dt: float) -> Array:
	events = []
	if hp <= 0:
		return events
	_drive(dt)
	_move(dt)
	_hover(dt)
	return events


func _drive(dt: float) -> void:
	var throttle: float = _cmd.throttle
	var boosting := bool(_cmd.boost) and throttle > 0.1 and boost_left > 0.0
	if boosting:
		boost_left = maxf(0.0, boost_left - dt)
	else:
		boost_left = minf(p("boost_time", 3.5), boost_left + dt * p("boost_recharge", 0.45))
	var target := 0.0
	if throttle > 0.0:
		target = throttle * (p("boost_speed", 52.0) if boosting else p("max_speed", 36.0))
	elif throttle < 0.0:
		target = throttle * p("reverse_speed", 9.0)
	var rate := p("accel", 16.0)
	if throttle == 0.0:
		rate = p("coast_drag", 6.0)
	elif signf(target) != signf(speed) and absf(speed) > 0.5:
		rate = p("brake", 34.0)
	if not airborne:
		speed = move_toward(speed, target, rate * dt)
	# Turning: quicker when slow, a little in the air.
	var k := clampf(absf(speed) / maxf(p("max_speed", 36.0), 1.0), 0.0, 1.0)
	var turn := deg_to_rad(lerpf(p("turn_rate_deg", 110.0), p("turn_rate_fast_deg", 62.0), k))
	if airborne:
		turn *= p("air_turn_scale", 0.35)
	yaw -= float(_cmd.steer) * turn * dt


func _move(dt: float) -> void:
	var to: Vector3 = position + forward() * speed * dt
	if ground != null:
		var hit_id := ground.hit(to, p("body_radius", 1.3))
		if hit_id != "":
			events.append({ "type": "bump", "what": hit_id, "speed": speed })
			speed = -speed * p("bump_bounce", 0.25)        # bounced off: no damage
			return
	position.x = to.x
	position.z = to.z


func _hover(dt: float) -> void:
	var ride := ground_height() + p("hover_height", 1.05)
	var rate := 0.0 if is_nan(_last_ride) else (ride - _last_ride) / maxf(dt, 0.0001)
	_last_ride = ride
	if airborne:
		vy -= p("gravity", 9.0) * dt
		position.y += vy * dt
		air_time += dt
		top_height = maxf(top_height, position.y - ride)
		if position.y <= ride:
			events.append({ "type": "landed", "fall_speed": -vy, "air_time": air_time, "top": top_height })
			position.y = ride
			vy = 0.0
			airborne = false
		return
	var before := position.y
	if before - ride > p("launch_gap", 0.45):
		# The ground fell away faster than we can follow: off the edge, carrying
		# the climb the ground was giving it (up a ramp, that is the jump).
		airborne = true
		vy = maxf(vy, _ground_rate)
		air_time = 0.0
		top_height = before - ride
		events.append({ "type": "launch", "vy": vy, "speed": speed })
		vy -= p("gravity", 9.0) * dt
		position.y += vy * dt
		return
	_ground_rate = rate
	position.y = lerpf(before, ride, clampf(dt * p("follow_rate", 14.0), 0.0, 1.0))
	if ride > position.y:
		position.y = maxf(position.y, ride - 0.25)   # never sink into a rise
	vy = (position.y - before) / maxf(dt, 0.0001)
