extends RefCounted
## Lead solver (M10). Pure math: where to aim a projectile so it meets a moving
## target. The fighter AI aims with it, and the HUD can draw the same point as a lead
## marker, so the player and the AI see one answer.
##
## Projectiles inherit the shooter's velocity (see ship_loadout.gd), so the solve is
## done in the shooter's frame: relative position and relative velocity.


## Returns { valid, time, point, dir }:
##   point -- where the target will be when the projectile arrives (world space)
##   dir   -- the unit direction to fire, relative to the shooter
##   time  -- seconds to impact
## When no intercept exists (the target is faster and opening), valid is false and
## point/dir fall back to the target's current position.
static func intercept(shooter_pos: Vector3, shooter_vel: Vector3, target_pos: Vector3,
		target_vel: Vector3, projectile_speed: float) -> Dictionary:
	var r := target_pos - shooter_pos
	var v := target_vel - shooter_vel
	var s := maxf(projectile_speed, 0.001)
	var a := v.dot(v) - s * s
	var b := 2.0 * r.dot(v)
	var c := r.dot(r)
	var t := -1.0
	if absf(a) < 0.000001:
		if absf(b) > 0.000001:
			t = -c / b
	else:
		var disc := b * b - 4.0 * a * c
		if disc >= 0.0:
			var sq := sqrt(disc)
			var t1 := (-b - sq) / (2.0 * a)
			var t2 := (-b + sq) / (2.0 * a)
			var lo := minf(t1, t2)
			var hi := maxf(t1, t2)
			t = lo if lo > 0.0 else hi
	if t <= 0.0:
		var fallback := r.normalized() if r.length_squared() > 0.0 else Vector3.FORWARD
		return { "valid": false, "time": 0.0, "point": target_pos, "dir": fallback }
	var rel := r + v * t
	return {
		"valid": true,
		"time": t,
		"point": target_pos + target_vel * t,
		"dir": rel.normalized(),
	}


## Angle in degrees between a facing and a direction.
static func angle_deg(facing: Vector3, dir: Vector3) -> float:
	if facing.length_squared() == 0.0 or dir.length_squared() == 0.0:
		return 180.0
	return rad_to_deg(facing.normalized().angle_to(dir.normalized()))
