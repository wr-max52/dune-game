extends RefCounted
## Starfighter flight model (M10). Pure and headless-testable, like the M1 character
## controller: it owns position, orientation, speed, throttle and the boost meter,
## and is stepped with a flight command. No Node3D, so the headless dogfight trace,
## the fighter AI, and a human pilot all fly the exact same model. The ship node
## (ship_node.gd) only copies the result onto a transform.
##
## Arcade flight, not Newtonian: the ship always moves along its nose. Every number
## comes from the ship's "flight" block in content/core/ships/*.json.
##
## Shift fires the ship's ability (issue #43), the "ability" block in "flight":
##   boost  -- (the default) speed up to boost_speed, turning slower
##   drift  -- keep sliding the way you were going while the nose turns faster
##             (turn_scale), so you can swing round and shoot behind you
##   brake  -- air brake: bleed speed hard down to brake_speed (never under
##             min_speed) and turn faster
## Every ability drains the same meter (boost_time, boost_recharge).
##
## Axes follow Godot: forward is -Z, up is +Y, right is +X.
## Command signs: pitch +1 = nose up, yaw +1 = turn right, roll +1 = roll right.

var cfg: Dictionary
var position := Vector3.ZERO
var basis := Basis.IDENTITY
var speed := 0.0
var throttle := 0.5
var boost_left := 0.0
var boosting := false             ## the ability is running this frame (any kind)
var drift_dir := Vector3.ZERO      ## where a drift is carrying the ship
var command := { "pitch": 0.0, "yaw": 0.0, "roll": 0.0, "throttle": 0.5, "boost": false }
## M14: multipliers the atmosphere sets each frame (thin air is faster, climbing
## is slower). 1.0 in space, so the dogfight flies exactly as before.
var speed_scale := 1.0
var accel_scale := 1.0


func _init(flight_cfg: Dictionary = {}) -> void:
	cfg = flight_cfg
	boost_left = boost_time()
	speed = cruise_speed(throttle)


# ---- tuning (data-driven, with safe defaults) ------------------------------

func min_speed() -> float:
	return float(cfg.get("min_speed", 10.0)) * speed_scale


func max_speed() -> float:
	return float(cfg.get("max_speed", 40.0)) * speed_scale


func boost_speed() -> float:
	return float(cfg.get("boost_speed", float(cfg.get("max_speed", 40.0)) * 1.5)) * speed_scale


func accel() -> float:
	return float(cfg.get("accel", 25.0)) * accel_scale


func pitch_rate() -> float:
	return float(cfg.get("pitch_rate", 1.5))


func yaw_rate() -> float:
	return float(cfg.get("yaw_rate", 1.0))


func roll_rate() -> float:
	return float(cfg.get("roll_rate", 3.0))


func boost_time() -> float:
	return float(cfg.get("boost_time", 2.0))


func boost_recharge() -> float:
	## Seconds of boost regained per second when not boosting.
	return float(cfg.get("boost_recharge", 0.5))


func boost_turn_scale() -> float:
	return float(cfg.get("boost_turn_scale", 0.6))


## The Shift ability: "boost", "drift" or "brake".
func ability() -> String:
	return str(cfg.get("ability", {}).get("kind", "boost"))


func ability_turn_scale() -> float:
	match ability():
		"drift":
			return float(cfg.get("ability", {}).get("turn_scale", 1.8))
		"brake":
			return float(cfg.get("ability", {}).get("turn_scale", 2.2))
	return boost_turn_scale()


func cruise_speed(t: float) -> float:
	return lerpf(min_speed(), max_speed(), clampf(t, 0.0, 1.0))


# ---- frame ------------------------------------------------------------------

func forward() -> Vector3:
	return -basis.z


func up() -> Vector3:
	return basis.y


func right() -> Vector3:
	return basis.x


func velocity() -> Vector3:
	return (drift_dir if boosting and ability() == "drift" else forward()) * speed


func transform() -> Transform3D:
	return Transform3D(basis, position)


## Point the nose along `dir` (world space), keeping `up_hint` roughly up.
func face(dir: Vector3, up_hint: Vector3 = Vector3.UP) -> void:
	if dir.length_squared() < 0.000001:
		return
	var d := dir.normalized()
	var u := up_hint
	if absf(d.dot(u.normalized())) > 0.99:
		u = Vector3.BACK
	basis = Basis.looking_at(d, u)


# ---- control ----------------------------------------------------------------

func set_command(pitch: float, yaw: float, roll: float, throttle_v: float, boost: bool) -> void:
	command.pitch = clampf(pitch, -1.0, 1.0)
	command.yaw = clampf(yaw, -1.0, 1.0)
	command.roll = clampf(roll, -1.0, 1.0)
	command.throttle = clampf(throttle_v, 0.0, 1.0)
	command.boost = boost


func set_command_dict(c: Dictionary) -> void:
	set_command(float(c.get("pitch", 0.0)), float(c.get("yaw", 0.0)), float(c.get("roll", 0.0)),
		float(c.get("throttle", throttle)), bool(c.get("boost", false)))


## The speed the ship is heading toward this frame.
func target_speed() -> float:
	if not boosting:
		return cruise_speed(throttle)
	match ability():
		"drift":
			return speed
		"brake":
			return maxf(min_speed(), float(cfg.get("ability", {}).get("brake_speed", 0.0)) * speed_scale)
	return boost_speed()


## Integrate one frame. dt is seconds.
func step(dt: float) -> void:
	throttle = float(command.throttle)

	# Boost drains while held, recharges otherwise. An empty meter ends the boost.
	var was := boosting
	boosting = bool(command.boost) and boost_left > 0.0
	if boosting and not was:
		drift_dir = forward()
	if boosting:
		boost_left = maxf(0.0, boost_left - dt)
	else:
		boost_left = minf(boost_time(), boost_left + boost_recharge() * dt)

	# Speed eases toward the target instead of snapping.
	var rate := accel() * (3.0 if boosting and ability() == "brake" else 1.0)
	speed = move_toward(speed, target_speed(), rate * dt)

	# Rotate in the ship's own frame. Boost trades turn rate for speed; drift and
	# brake turn faster.
	var turn := ability_turn_scale() if boosting else 1.0
	var b := basis
	b = b * Basis(Vector3.RIGHT, float(command.pitch) * pitch_rate() * turn * dt)
	b = b * Basis(Vector3.UP, -float(command.yaw) * yaw_rate() * turn * dt)
	b = b * Basis(Vector3.BACK, -float(command.roll) * roll_rate() * dt)
	basis = b.orthonormalized()

	if boosting and ability() == "drift":
		# The slide slowly gives way to the nose, so a long drift still comes round.
		drift_dir = drift_dir.slerp(forward(), minf(1.0, dt * 0.8)).normalized()
	position += velocity() * dt


# ---- save -------------------------------------------------------------------

func to_dict() -> Dictionary:
	var q := basis.get_rotation_quaternion()
	return {
		"position": [position.x, position.y, position.z],
		"rotation": [q.x, q.y, q.z, q.w],
		"speed": speed,
		"throttle": throttle,
		"boost_left": boost_left,
	}


func from_dict(d: Dictionary) -> void:
	var p: Array = d.get("position", [0, 0, 0])
	position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	var r: Array = d.get("rotation", [0, 0, 0, 1])
	basis = Basis(Quaternion(float(r[0]), float(r[1]), float(r[2]), float(r[3])))
	speed = float(d.get("speed", speed))
	throttle = float(d.get("throttle", throttle))
	command.throttle = throttle
	boost_left = float(d.get("boost_left", boost_left))
