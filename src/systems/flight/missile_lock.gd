extends RefCounted
## Missile lock (M10). Pure: a seeker can only launch once its target has stayed
## inside the lock cone and range for lock_time seconds. Losing the target bleeds the
## lock off twice as fast as it builds; switching targets starts over.
##
## Tuning comes from the seeker weapon's data (lock_time, lock_cone_deg, lock_range).

const LeadSolver := preload("res://src/systems/flight/lead_solver.gd")

var lock_time := 1.5
var cone_deg := 20.0
var lock_range := 1000.0
var target_id := -1
var progress := 0.0


func configure(weapon_cfg: Dictionary) -> void:
	lock_time = float(weapon_cfg.get("lock_time", lock_time))
	cone_deg = float(weapon_cfg.get("lock_cone_deg", cone_deg))
	lock_range = float(weapon_cfg.get("lock_range", weapon_cfg.get("range", lock_range)))


func reset() -> void:
	target_id = -1
	progress = 0.0


## Advance the lock. `to_target` is the vector from the shooter to the target.
func update(dt: float, id: int, facing: Vector3, to_target: Vector3) -> void:
	if id != target_id:
		target_id = id
		progress = 0.0
	if id < 0:
		return
	var in_cone := LeadSolver.angle_deg(facing, to_target) <= cone_deg
	var in_range := to_target.length() <= lock_range
	if in_cone and in_range:
		progress = minf(lock_time, progress + dt)
	else:
		progress = maxf(0.0, progress - dt * 2.0)


func is_locked() -> bool:
	return target_id >= 0 and progress >= lock_time


## 0..1 for a HUD meter.
func fraction() -> float:
	return clampf(progress / maxf(lock_time, 0.001), 0.0, 1.0)
