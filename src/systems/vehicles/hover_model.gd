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
##
## Issue #95: the Grav Lifter (a "hover" block in the config, from the mechanic's
## upgrades). lift() hops it off the ground, and once it stops rising it hangs,
## gravity off and sinking slowly, for float_s seconds. Then it falls as usual,
## and the lifter needs recharge_s before it works again.
##
## Issue #77: on the home planet's ball "up" turns with the ground. The heading is
## a direction slid along the ground as it drives (so straight stays straight round
## the curve), and heights are measured along up (`_level`: the distance from the
## planet's centre). On a flat world both are exactly the old yaw and y.

var cfg: Dictionary = {}
var ground: WorldGround
var position := Vector3.ZERO
var yaw: float:                      ## radians about the ground's up; 0 faces -Z (on the plateau)
	get:
		var l := _tilt().inverse() * _fwd
		return atan2(-l.x, -l.z)
	set(v):
		_fwd = _tilt() * Vector3(-sin(v), 0.0, -cos(v))
var _fwd := Vector3.FORWARD          ## heading, along the ground
var speed := 0.0                     ## along the nose, m/s (negative = reversing)
var vy := 0.0                        ## vertical speed, m/s
var airborne := false
var boost_left := 0.0
var hp := 0
var max_hp := 0
var events: Array = []               ## this step's: { type, ... }
var air_time := 0.0                  ## of the current (or last) jump
var top_height := 0.0                ## highest clearance over the ground on the last jump
var float_left := 0.0                ## issue #95: seconds of hang the Grav Lifter has left this lift
var lift_cooldown := 0.0             ## issue #95: until the Grav Lifter can fire again

var _pending: Array = []             ## events from between steps (lift), for the next step()
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
	return _fwd


func up() -> Vector3:
	return ground.up_at(position) if ground != null else Vector3.UP


func _tilt() -> Basis:
	return PlanetSphere.tilt_to(up())


func transform() -> Transform3D:
	return Transform3D(Basis.looking_at(_fwd, up()), position)


## How high a point is, measured along up: y on a flat world, the distance from
## the centre on the ball.
func _level(at: Vector3) -> float:
	var sp: PlanetSphere = ground.sphere() if ground != null else null
	return (at - sp.center).length() if sp != null else at.y


## Move by `d` metres along up.
func _lift(d: float) -> void:
	position += up() * d


## The ground's level under the speeder (see _level).
func ground_height() -> float:
	if ground == null:
		return 0.0
	return _level(position) - ground.height_above(position)


## Clearance between the hover line and the ground below (0 when riding).
func height_over_ground() -> float:
	return _level(position) - p("hover_height", 1.05) - ground_height()


func alive() -> bool:
	return hp > 0


## Boost is lit this step (the throttle open, the key held, boost left).
func boosting() -> bool:
	return bool(_cmd.boost) and float(_cmd.throttle) > 0.1 and boost_left > 0.0


## Issue #95: a Grav Lifter is fitted.
func has_lifter() -> bool:
	return cfg.get("hover") is Dictionary


func lifter() -> Dictionary:
	return cfg.get("hover", {}) if has_lifter() else {}


func lift_ready() -> bool:
	return has_lifter() and lift_cooldown <= 0.0 and hp > 0


# ---- control --------------------------------------------------------------------------

## Put it down at `at` (on the ground there), facing `yaw_rad`.
func place(at: Vector3, yaw_rad: float) -> void:
	position = at
	yaw = yaw_rad
	speed = 0.0
	vy = 0.0
	airborne = false
	_lift(ground_height() + p("hover_height", 1.05) - _level(position))
	_last_ride = NAN
	_ground_rate = 0.0


## throttle -1..1 (back..forward), steer -1..1 (left..right).
func set_command(throttle: float, steer: float, boost: bool = false) -> void:
	_cmd = { "throttle": clampf(throttle, -1.0, 1.0), "steer": clampf(steer, -1.0, 1.0), "boost": boost }


## Issue #95: fire the Grav Lifter. On the ground it hops; in the air it starts
## the hang at once. False if there is no lifter or it is recharging.
func lift() -> bool:
	if not lift_ready():
		return false
	var h := lifter()
	if not airborne:
		airborne = true
		vy = float(h.get("hop_vy", 6.5))
		air_time = 0.0
		top_height = 0.0
	float_left = float(h.get("float_s", 1.2))
	lift_cooldown = float(h.get("recharge_s", 4.0))
	_pending.append({ "type": "lift", "vy": vy })     # reported by the next step()
	return true


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
	events = _pending
	_pending = []
	if hp <= 0:
		return events
	lift_cooldown = maxf(0.0, lift_cooldown - dt)
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
	_fwd = _fwd.rotated(up(), -float(_cmd.steer) * turn * dt)


func _move(dt: float) -> void:
	var to: Vector3 = position + forward() * speed * dt
	if ground != null:
		var hit_id := ground.hit(to, p("body_radius", 1.3))
		if hit_id != "":
			events.append({ "type": "bump", "what": hit_id, "speed": speed })
			speed = -speed * p("bump_bounce", 0.25)        # bounced off: no damage
			return
	var lv := _level(position)
	position = to
	_lift(lv - _level(position))       # along the ground: the hover settles the height
	# Slide the heading along with it, so it stays flat to the ground here.
	var u := up()
	_fwd = (_fwd - u * _fwd.dot(u)).normalized()


func _hover(dt: float) -> void:
	var ride := ground_height() + p("hover_height", 1.05)
	var rate := 0.0 if is_nan(_last_ride) else (ride - _last_ride) / maxf(dt, 0.0001)
	_last_ride = ride
	if airborne:
		if float_left > 0.0 and vy <= 0.0:
			# The Grav Lifter's hang: gravity off, a slow sink.
			float_left = maxf(0.0, float_left - dt)
			vy = -float(lifter().get("float_sink", 0.4))
		else:
			vy -= p("gravity", 9.0) * dt
		_lift(vy * dt)
		air_time += dt
		top_height = maxf(top_height, _level(position) - ride)
		if _level(position) <= ride:
			events.append({ "type": "landed", "fall_speed": -vy, "air_time": air_time, "top": top_height })
			_lift(ride - _level(position))
			vy = 0.0
			airborne = false
			float_left = 0.0
		return
	var before := _level(position)
	if before - ride > p("launch_gap", 0.45):
		# The ground fell away faster than we can follow: off the edge, carrying
		# the climb the ground was giving it (up a ramp, that is the jump).
		airborne = true
		vy = maxf(vy, _ground_rate)
		air_time = 0.0
		top_height = before - ride
		events.append({ "type": "launch", "vy": vy, "speed": speed })
		vy -= p("gravity", 9.0) * dt
		_lift(vy * dt)
		return
	_ground_rate = rate
	var y := lerpf(before, ride, clampf(dt * p("follow_rate", 14.0), 0.0, 1.0))
	if ride > y:
		y = maxf(y, ride - 0.25)   # never sink into a rise
	_lift(y - before)
	vy = (y - before) / maxf(dt, 0.0001)
