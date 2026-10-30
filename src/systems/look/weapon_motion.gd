extends RefCounted
## First person weapon motion (issue #229): what makes a gun feel held, not glued
## to the screen. Pure (no nodes), so it is tested headless.
##
## - Sway: turning drags the gun a little behind the view, then it springs back.
## - Bob: walking and running move it in a small figure eight (the camera never
##   bobs; only the gun does).
## - Jump and land: it lifts on take-off and dips on landing, harder from higher.
## - Breathing: a slow rise and fall when still.
## - Wall: a gun pushed into a wall pulls back and tips its muzzle up.
## offset(ads) is a chest-space transform to put before the weapon's own; aiming
## scales it all down, and the ADS pose replaces it entirely once fully aimed, so
## the sight still lands on the screen centre.

const SWAY_K := 140.0              ## spring stiffness (critically damped)
const SWAY_GAIN := 0.022           ## radians of lag per radian/second of turn
const SWAY_MAX := 0.07
const BOB_STEP := 1.75             ## radians of bob phase per metre walked
const BOB_X := 0.011
const BOB_Y := 0.009
const LAND_K := 110.0
const WALL_REACH := 0.85           ## metres in front of the eye a gun needs

var sway := Vector2.ZERO           ## yaw, pitch lag (radians)
var _sway_v := Vector2.ZERO
var phase := 0.0
var bob_amount := 0.0              ## 0..1, eased toward the speed's
var land := 0.0                    ## > 0 dipped, < 0 lifted
var _land_v := 0.0
var wall := 0.0                    ## 0..1 pulled back from a wall
var time := 0.0
var _was_grounded := true


## look_vel: (yaw, pitch) radians per second of the view. speed: metres per second
## on the ground. vy: vertical velocity. wall_dist: how far ahead the view hits
## something (INF for nothing).
func step(dt: float, look_vel: Vector2, speed: float, grounded: bool, vy: float,
		wall_dist: float = INF) -> void:
	time += dt
	var target := (-look_vel * SWAY_GAIN).clamp(Vector2(-SWAY_MAX, -SWAY_MAX), Vector2(SWAY_MAX, SWAY_MAX))
	var d := 2.0 * sqrt(SWAY_K)
	_sway_v += ((target - sway) * SWAY_K - _sway_v * d) * dt
	sway += _sway_v * dt

	var want := clampf(speed / 6.0, 0.0, 1.0) if grounded else 0.0
	bob_amount = move_toward(bob_amount, want, dt * 4.0)
	phase = fmod(phase + speed * BOB_STEP * dt, TAU * 2.0) if grounded else phase

	if grounded and not _was_grounded and vy < -1.5:
		_land_v += clampf(-vy * 0.35, 0.6, 3.0)          # a dip, harder from higher
	elif not grounded and _was_grounded and vy > 0.5:
		_land_v -= 0.9                                     # take-off lift
	_was_grounded = grounded
	var ld := 2.0 * sqrt(LAND_K) * 0.7                     # a touch under-damped: settles with a bounce
	_land_v += (-land * LAND_K - _land_v * ld) * dt
	land += _land_v * dt

	var w := clampf((WALL_REACH - wall_dist) / 0.45, 0.0, 1.0) if wall_dist < INF else 0.0
	wall = move_toward(wall, w, dt * 5.0)


## Chest-space offset; `ads` 0..1 (eased) scales it toward nothing.
func offset(ads: float = 0.0) -> Transform3D:
	var k := 1.0 - 0.85 * clampf(ads, 0.0, 1.0)
	var b := bob_amount * k
	var pos := Vector3(
		sin(phase) * BOB_X * b,
		-absf(sin(phase)) * BOB_Y * b + sin(time * 1.3) * 0.0022 * k - land * 0.03 * k,
		0.0)
	var rot := Vector3(
		-sway.y * k + sin(time * 1.3 + 1.0) * 0.004 * k + land * 0.05 * k,   # +X tips the muzzle down
		sway.x * k,
		sin(phase) * 0.02 * b + sway.x * 0.4 * k)
	# Against a wall: back toward the body and down (wall_local tips it up).
	var ws := wall * wall * (3.0 - 2.0 * wall)
	pos += Vector3(-0.02, -0.06, -0.2) * ws * k
	return Transform3D(Basis.from_euler(rot), pos)


## Against a wall the muzzle tips up about the gun's own grip (`grip`, the gun's
## space), not the chest: put after the weapon's transform.
func wall_local(grip: Vector3, ads: float = 0.0) -> Transform3D:
	var ws := wall * wall * (3.0 - 2.0 * wall) * (1.0 - 0.85 * clampf(ads, 0.0, 1.0))
	if ws <= 0.0:
		return Transform3D.IDENTITY
	var r := Basis(Vector3.RIGHT, -deg_to_rad(40.0) * ws)
	return Transform3D(Basis(), grip) * Transform3D(r, Vector3.ZERO) * Transform3D(Basis(), -grip)


## The gun is pulled back from a wall too far to shoot straight.
func blocked() -> bool:
	return wall > 0.6
