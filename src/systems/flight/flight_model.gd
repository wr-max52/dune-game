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
## Axes follow Godot: forward is -Z, up is +Y, right is +X.
## Command signs: pitch +1 = nose up, yaw +1 = turn right, roll +1 = roll right.

var cfg: Dictionary
var position := Vector3.ZERO
var basis := Basis.IDENTITY
var speed := 0.0
var throttle := 0.5
var boost_left := 0.0
var boosting := false
var command := { "pitch": 0.0, "yaw": 0.0, "roll": 0.0, "throttle": 0.5, "boost": false }


func _init(flight_cfg: Dictionary = {}) -> void:
	cfg = flight_cfg
	boost_left = boost_time()
	speed = cruise_speed(throttle)


# ---- tuning (data-driven, with safe defaults) ------------------------------

func min_speed() -> float:
	return float(cfg.get("min_speed", 10.0))


func max_speed() -> float:
	return float(cfg.get("max_speed", 40.0))


func boost_speed() -> float:
	return float(cfg.get("boost_speed", max_speed() * 1.5))


func accel() -> float:
	return float(cfg.get("accel", 25.0))


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
	return forward() * speed


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
	return boost_speed() if boosting else cruise_speed(throttle)


## Integrate one frame. dt is seconds.
func step(dt: float) -> void:
	throttle = float(command.throttle)

	# Boost drains while held, recharges otherwise. An empty meter ends the boost.
	boosting = bool(command.boost) and boost_left > 0.0
	if boosting:
		boost_left = maxf(0.0, boost_left - dt)
	else:
		boost_left = minf(boost_time(), boost_left + boost_recharge() * dt)

	# Speed eases toward the target instead of snapping.
	speed = move_toward(speed, target_speed(), accel() * dt)

	# Rotate in the ship's own frame. Boost trades turn rate for speed.
	var turn := boost_turn_scale() if boosting else 1.0
	var b := basis
	b = b * Basis(Vector3.RIGHT, float(command.pitch) * pitch_rate() * turn * dt)
	b = b * Basis(Vector3.UP, -float(command.yaw) * yaw_rate() * turn * dt)
	b = b * Basis(Vector3.BACK, -float(command.roll) * roll_rate() * dt)
	basis = b.orthonormalized()

	position += forward() * speed * dt


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
