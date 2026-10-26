class_name SwordCombo
extends RefCounted
## The energy sword's moves (M11): a 3-hit light chain, a guard and a block. Pure.
##
## Stamina, block and the timed deflect stay in EnergyBlade (M3) so the duelist and
## the player share one rule set; this class adds the choreography: which swing,
## how far through it, where the sword is (chest space), when it can hit, and the
## input buffer that chains swing 1 -> 2 -> 3.
##
## Keyframes: pos = the sword's guard in chest space, dir = the way the blade
## points, twist = degrees of chest yaw. Model faces +Z; its right is -X.

const EnergyBlade := preload("res://src/systems/combat/energy_blade.gd")

enum Mode { GUARD, SWING, BLOCK }

const GUARD := { "pos": Vector3(-0.1, -0.1, 0.32), "dir": Vector3(0.22, 0.86, 0.46), "twist": 0.0 }
## First person: the guard sits low on the right so the blade frames the view
## instead of crossing it. Swings and the block use the same keys in both views.
const GUARD_FPV := { "pos": Vector3(-0.2, -0.06, 0.4), "dir": Vector3(-0.32, 0.88, 0.36), "twist": 0.0 }
const BLOCK := { "pos": Vector3(-0.04, 0.06, 0.4), "dir": Vector3(0.92, 0.36, 0.12), "twist": 12.0 }

## Each swing: duration, the [start, end] fraction it can hit, and its keys.
const SWINGS := [
	{ "name": "forehand", "duration": 0.5, "active": [0.34, 0.66], "heavy": false, "keys": [
		[0.0, GUARD],
		[0.3, { "pos": Vector3(-0.34, 0.14, 0.1), "dir": Vector3(-0.72, 0.52, -0.45), "twist": -32.0 }],
		[0.48, { "pos": Vector3(-0.06, -0.02, 0.5), "dir": Vector3(-0.1, 0.12, 1.0), "twist": 0.0 }],
		[0.7, { "pos": Vector3(0.24, -0.14, 0.3), "dir": Vector3(0.86, -0.16, 0.42), "twist": 34.0 }],
		[1.0, GUARD]] },
	{ "name": "backhand", "duration": 0.5, "active": [0.34, 0.66], "heavy": false, "keys": [
		[0.0, GUARD],
		[0.28, { "pos": Vector3(0.22, -0.2, 0.22), "dir": Vector3(0.8, -0.36, 0.3), "twist": 30.0 }],
		[0.48, { "pos": Vector3(-0.02, 0.02, 0.52), "dir": Vector3(0.1, 0.3, 1.0), "twist": 0.0 }],
		[0.7, { "pos": Vector3(-0.3, 0.2, 0.24), "dir": Vector3(-0.76, 0.6, 0.2), "twist": -30.0 }],
		[1.0, GUARD]] },
	{ "name": "overhead", "duration": 0.62, "active": [0.38, 0.7], "heavy": true, "keys": [
		[0.0, GUARD],
		[0.32, { "pos": Vector3(-0.05, 0.38, 0.08), "dir": Vector3(0.0, 0.55, -0.85), "twist": -8.0 }],
		[0.52, { "pos": Vector3(-0.04, 0.08, 0.52), "dir": Vector3(0.0, 0.35, 1.0), "twist": 0.0 }],
		[0.74, { "pos": Vector3(-0.04, -0.3, 0.42), "dir": Vector3(0.0, -0.66, 0.8), "twist": 4.0 }],
		[1.0, GUARD]] },
]

var blade                       ## EnergyBlade
var mode := Mode.GUARD
var swing_index := 0
var t := 0.0                    ## seconds into the current swing
var queued := false
var queue_from := 0.35          ## fraction of a swing after which a press chains
var hits_this_swing := {}       ## target instance id -> true (one hit per swing)
var swings_started := 0


func _init(blade_cfg: Dictionary) -> void:
	blade = EnergyBlade.new(blade_cfg)


func reset() -> void:
	mode = Mode.GUARD
	swing_index = 0
	t = 0.0
	queued = false
	blade.reset()


func swing_def() -> Dictionary:
	return SWINGS[swing_index]


func progress() -> float:
	if mode != Mode.SWING:
		return 0.0
	return clampf(t / float(swing_def().duration), 0.0, 1.0)


## Attack pressed. Starts a swing, or buffers the next one in the chain.
func attack() -> bool:
	if mode == Mode.SWING:
		if progress() >= queue_from and swing_index < SWINGS.size() - 1:
			queued = true
		return false
	if mode == Mode.BLOCK:
		return false
	return _start(0)


func _start(i: int) -> bool:
	var ok: bool = blade.heavy_attack() if SWINGS[i].heavy else blade.light_attack()
	if not ok:
		return false
	mode = Mode.SWING
	swing_index = i
	t = 0.0
	queued = false
	hits_this_swing.clear()
	swings_started += 1
	return true


func set_block(on: bool) -> void:
	if on and mode == Mode.GUARD:
		blade.start_block()
		if blade.is_blocking():
			mode = Mode.BLOCK
	elif not on and mode == Mode.BLOCK:
		blade.end_block()
		mode = Mode.GUARD


## True while the current swing can hit.
func is_active() -> bool:
	if mode != Mode.SWING:
		return false
	var a: Array = swing_def().active
	var p := progress()
	return p >= float(a[0]) and p <= float(a[1])


func damage() -> int:
	return blade.heavy_damage() if swing_def().heavy else blade.light_damage()


## Advance. Returns events: "swing:<name>", "swing_end", "block_broken".
func update(dt: float) -> Array:
	var ev: Array = []
	var was_blocking := mode == Mode.BLOCK
	blade.update(dt)
	if was_blocking and not blade.is_blocking():
		mode = Mode.GUARD
		ev.append("block_broken")
	if mode == Mode.SWING:
		t += dt
		if t >= float(swing_def().duration):
			var next := swing_index + 1
			if queued and next < SWINGS.size() and _start(next):
				ev.append("swing:" + str(swing_def().name))
			else:
				mode = Mode.GUARD
				swing_index = 0
				queued = false
				ev.append("swing_end")
	return ev


## Where the sword is right now: { pos, dir, twist } in chest space.
func pose(first_person: bool = false) -> Dictionary:
	match mode:
		Mode.BLOCK:
			return BLOCK
		Mode.SWING:
			var p := sample(swing_index, progress())
			if first_person:
				# Ease out of / back into the low first-person guard at the ends.
				var e := 1.0 - absf(progress() * 2.0 - 1.0)
				var w := clampf(1.0 - e * 4.0, 0.0, 1.0)
				p = { "pos": (p.pos as Vector3).lerp(GUARD_FPV.pos, w), "dir": (p.dir as Vector3).normalized().slerp((GUARD_FPV.dir as Vector3).normalized(), w), "twist": p.twist }
			return p
	return GUARD_FPV if first_person else GUARD


static func sample(i: int, p: float) -> Dictionary:
	var keys: Array = SWINGS[i].keys
	for k in range(1, keys.size()):
		var t1: float = keys[k][0]
		if p <= t1 or k == keys.size() - 1:
			var t0: float = keys[k - 1][0]
			var a: Dictionary = keys[k - 1][1]
			var b: Dictionary = keys[k][1]
			var f := clampf((p - t0) / maxf(t1 - t0, 0.0001), 0.0, 1.0)
			f = f * f * (3.0 - 2.0 * f)          # ease in and out of every key
			return {
				"pos": (a.pos as Vector3).lerp(b.pos, f),
				"dir": (a.dir as Vector3).normalized().slerp((b.dir as Vector3).normalized(), f),
				"twist": lerpf(a.twist, b.twist, f),
			}
	return GUARD


## Chest-space transform of the sword for a pose: +Y along the blade.
static func pose_transform(p: Dictionary) -> Transform3D:
	var y: Vector3 = (p.dir as Vector3).normalized()
	var hint := Vector3.UP if absf(y.y) < 0.9 else Vector3.BACK
	var x := hint.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Transform3D(Basis(x, y, z), p.pos)
