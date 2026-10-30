class_name SwordCombo
extends RefCounted
## The energy sword's moves (M11): swipes, a combo, a guard and a block. Pure.
##
## Stamina, block and the timed deflect stay in EnergyBlade (M3) so the duelist and
## the player share one rule set; this class adds the choreography: which swing,
## how far through it, where the sword is (chest space), when it can hit, and the
## input that picks the next swing:
##   one click     a swipe, alternating left and right (left again after a rest)
##   double click  the combo: left, right, then a centre chop down the middle
## A click late in a swipe buffers the next one, so clicking in a rhythm flows.
##
## Keyframes: pos = the sword's guard in chest space, dir = the way the blade
## points, twist = degrees of chest yaw. Model faces +Z; its right is -X. A "left"
## swipe cuts across to your left (from the right shoulder), a "right" one back.
## Keys are joined by a smooth curve (no stop at each key), and a chained swing
## blends in from wherever the blade was, so a flurry flows.

const EnergyBlade := preload("res://src/systems/combat/energy_blade.gd")

enum Mode { GUARD, SWING, BLOCK }
enum { LEFT, RIGHT, CENTER }

const GUARD := { "pos": Vector3(-0.1, -0.1, 0.32), "dir": Vector3(0.22, 0.86, 0.46), "twist": 0.0 }
## First person: the guard sits low on the right so the blade frames the view
## instead of crossing it, high enough that the hilt and the right hand show (the
## left, on the pommel, comes into view as soon as it swings or blocks).
const GUARD_FPV := { "pos": Vector3(-0.15, 0.01, 0.44), "dir": Vector3(-0.26, 0.88, 0.4), "twist": 0.0 }
const BLOCK := { "pos": Vector3(-0.04, 0.06, 0.4), "dir": Vector3(0.92, 0.36, 0.12), "twist": 12.0 }
## Issue #229: a level block across the view crossed the arms (the left hand sits
## past the right on the hilt); from the eye it is a diagonal, hilt low right.
const BLOCK_FPV := { "pos": Vector3(-0.13, 0.02, 0.44), "dir": Vector3(0.62, 0.76, 0.18), "twist": 4.0 }

## Two clicks this close together (seconds) are a double click: the combo.
const DOUBLE_CLICK := 0.3
## After this long back in guard the next swipe is a left one again.
const SIDE_RESET := 0.8
## Seconds a chained swing takes to blend in from where the blade was.
const BLEND := 0.09

## Each swing: duration, the [start, end] fraction it can hit, the fraction after
## which a buffered next swing takes over (chain_at), and its keys. Left and right
## are mirror images, high to low, so a flurry draws an X.
## fpv_keys (issue #229): the same swing seen from the eye. The third person keys
## wind up behind the shoulder and whip the chest round, so from the eye the blade
## vanished behind the camera and the hilt smeared across the lens. These wind up
## in view (upper right, or overhead), cut as a diagonal sweep across the view at
## about the same reach (the hits come from where the blade is), and twist a
## third as much. Same timing and active windows.
const SWINGS := [
	{ "name": "left", "duration": 0.42, "active": [0.32, 0.64], "chain_at": 0.74, "heavy": false, "keys": [
		[0.0, GUARD],
		[0.24, { "pos": Vector3(-0.36, 0.24, 0.04), "dir": Vector3(-0.62, 0.6, -0.5), "twist": -38.0 }],
		[0.36, { "pos": Vector3(-0.3, 0.16, 0.34), "dir": Vector3(-0.64, 0.4, 0.66), "twist": -24.0 }],
		[0.48, { "pos": Vector3(-0.02, 0.02, 0.56), "dir": Vector3(0.04, 0.02, 1.0), "twist": 0.0 }],
		[0.62, { "pos": Vector3(0.3, -0.14, 0.32), "dir": Vector3(0.88, -0.3, 0.36), "twist": 36.0 }],
		[0.8, { "pos": Vector3(0.24, -0.18, 0.22), "dir": Vector3(0.74, -0.34, 0.1), "twist": 30.0 }],
		[1.0, GUARD]], "fpv_keys": [
		[0.0, GUARD_FPV],
		[0.22, { "pos": Vector3(-0.27, 0.2, 0.36), "dir": Vector3(-0.42, 0.88, 0.2), "twist": -12.0 }],
		[0.36, { "pos": Vector3(-0.2, 0.16, 0.46), "dir": Vector3(-0.3, 0.7, 0.65), "twist": -8.0 }],
		[0.48, { "pos": Vector3(-0.03, 0.06, 0.52), "dir": Vector3(0.5, 0.42, 0.76), "twist": 0.0 }],
		[0.62, { "pos": Vector3(0.14, -0.08, 0.44), "dir": Vector3(0.86, -0.12, 0.5), "twist": 10.0 }],
		[0.8, { "pos": Vector3(0.1, -0.06, 0.42), "dir": Vector3(0.78, -0.18, 0.6), "twist": 6.0 }],
		[1.0, GUARD_FPV]] },
	{ "name": "right", "duration": 0.42, "active": [0.32, 0.64], "chain_at": 0.74, "heavy": false, "keys": [
		[0.0, GUARD],
		[0.24, { "pos": Vector3(0.28, 0.24, 0.08), "dir": Vector3(0.62, 0.6, -0.5), "twist": 36.0 }],
		[0.36, { "pos": Vector3(0.24, 0.16, 0.36), "dir": Vector3(0.64, 0.4, 0.66), "twist": 22.0 }],
		[0.48, { "pos": Vector3(-0.04, 0.02, 0.56), "dir": Vector3(-0.04, 0.02, 1.0), "twist": 0.0 }],
		[0.62, { "pos": Vector3(-0.34, -0.14, 0.3), "dir": Vector3(-0.88, -0.3, 0.36), "twist": -38.0 }],
		[0.8, { "pos": Vector3(-0.3, -0.18, 0.2), "dir": Vector3(-0.74, -0.34, 0.1), "twist": -32.0 }],
		[1.0, GUARD]], "fpv_keys": [
		[0.0, GUARD_FPV],
		[0.22, { "pos": Vector3(0.06, 0.2, 0.38), "dir": Vector3(0.42, 0.88, 0.2), "twist": 10.0 }],
		[0.36, { "pos": Vector3(0.02, 0.16, 0.46), "dir": Vector3(0.3, 0.7, 0.65), "twist": 6.0 }],
		[0.48, { "pos": Vector3(-0.08, 0.06, 0.52), "dir": Vector3(-0.5, 0.42, 0.76), "twist": 0.0 }],
		[0.62, { "pos": Vector3(-0.24, -0.08, 0.42), "dir": Vector3(-0.86, -0.12, 0.5), "twist": -10.0 }],
		[0.8, { "pos": Vector3(-0.22, -0.06, 0.4), "dir": Vector3(-0.78, -0.18, 0.6), "twist": -6.0 }],
		[1.0, GUARD_FPV]] },
	{ "name": "center", "duration": 0.58, "active": [0.44, 0.7], "chain_at": 1.0, "heavy": true, "keys": [
		[0.0, GUARD],
		[0.3, { "pos": Vector3(-0.06, 0.42, 0.02), "dir": Vector3(-0.04, 0.42, -0.9), "twist": -6.0 }],
		[0.42, { "pos": Vector3(-0.05, 0.46, 0.0), "dir": Vector3(0.0, 0.22, -0.97), "twist": -4.0 }],
		[0.54, { "pos": Vector3(-0.04, 0.16, 0.56), "dir": Vector3(0.0, 0.5, 0.86), "twist": 2.0 }],
		[0.68, { "pos": Vector3(-0.03, -0.26, 0.5), "dir": Vector3(0.0, -0.62, 0.78), "twist": 4.0 }],
		[0.82, { "pos": Vector3(-0.03, -0.3, 0.46), "dir": Vector3(0.0, -0.68, 0.72), "twist": 3.0 }],
		[1.0, GUARD]], "fpv_keys": [
		[0.0, GUARD_FPV],
		[0.3, { "pos": Vector3(-0.07, 0.3, 0.36), "dir": Vector3(-0.05, 0.96, -0.26), "twist": -2.0 }],
		[0.42, { "pos": Vector3(-0.06, 0.34, 0.36), "dir": Vector3(-0.02, 0.86, -0.5), "twist": -1.0 }],
		[0.54, { "pos": Vector3(-0.05, 0.16, 0.5), "dir": Vector3(0.0, 0.62, 0.78), "twist": 1.0 }],
		[0.68, { "pos": Vector3(-0.04, -0.16, 0.48), "dir": Vector3(0.0, -0.5, 0.86), "twist": 1.0 }],
		[0.82, { "pos": Vector3(-0.04, -0.2, 0.44), "dir": Vector3(0.0, -0.58, 0.8), "twist": 1.0 }],
		[1.0, GUARD_FPV]] },
]
const COMBO := [LEFT, RIGHT, CENTER]

var blade                       ## EnergyBlade
var mode := Mode.GUARD
var swing_index := 0
var t := 0.0                    ## seconds into the current swing
var chain: Array = []           ## swings still to play after this one (indices)
var combo := false              ## the current swing is part of the double-click combo
var next_side := LEFT           ## what the next single click swipes
var queue_from := 0.35          ## fraction of a swipe after which a click buffers the next
var hits_this_swing := {}       ## target instance id -> true (one hit per swing)
var swings_started := 0
var combos_started := 0

var _since_press := INF
var _rest := 0.0                ## seconds back in guard
var _from: Dictionary = {}      ## the blade's pose when a chained swing began
var _blend := 1.0               ## 0..1 through that blend (1 = none)
var _fp := false                ## posing for first person (set by pose())


func _init(blade_cfg: Dictionary) -> void:
	blade = EnergyBlade.new(blade_cfg)


func reset() -> void:
	mode = Mode.GUARD
	swing_index = 0
	t = 0.0
	chain.clear()
	combo = false
	next_side = LEFT
	_since_press = INF
	_blend = 1.0
	blade.reset()


func swing_def() -> Dictionary:
	return SWINGS[swing_index]


func progress() -> float:
	if mode != Mode.SWING:
		return 0.0
	return clampf(t / float(swing_def().duration), 0.0, 1.0)


## Attack pressed. Starts a swing (true), or buffers the next one (false). A second
## click inside DOUBLE_CLICK turns whatever is happening into the combo.
func attack() -> bool:
	var double := _since_press <= DOUBLE_CLICK
	_since_press = 0.0
	if mode == Mode.BLOCK:
		return false
	if mode == Mode.SWING:
		if combo:
			return false
		if double:
			return _start_combo()
		if progress() >= queue_from and chain.is_empty():
			chain = [next_side]
		return false
	return _start(next_side)


## The combo: left, right, centre. A left swipe already under way is its first cut;
## anything else hands over to a fresh left one.
func _start_combo() -> bool:
	var started := false
	if swing_index != LEFT:
		if not _start(LEFT):
			return false
		started = true
	combo = true
	combos_started += 1
	chain = COMBO.slice(1)
	return started


func _start(i: int) -> bool:
	var heavy: bool = SWINGS[i].heavy
	var ok: bool
	if mode == Mode.SWING:
		ok = blade.chain_attack(heavy)
	else:
		ok = blade.heavy_attack() if heavy else blade.light_attack()
	if not ok:
		return false
	if mode == Mode.SWING:
		_from = _raw_pose()
		_blend = 0.0
	else:
		_blend = 1.0
	mode = Mode.SWING
	swing_index = i
	t = 0.0
	chain.clear()
	combo = false
	hits_this_swing.clear()
	swings_started += 1
	next_side = RIGHT if i == LEFT else LEFT
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


## True through the cut itself, a little either side of when it can hit: the blade
## leaves a trail (SwordTrail).
func cutting() -> bool:
	if mode != Mode.SWING:
		return false
	var a: Array = swing_def().active
	var p := progress()
	return p >= float(a[0]) - 0.1 and p <= float(a[1]) + 0.1


func damage() -> int:
	return blade.heavy_damage() if swing_def().heavy else blade.light_damage()


## Advance. Returns events: "swing:<name>", "swing_end", "block_broken".
func update(dt: float) -> Array:
	var ev: Array = []
	_since_press += dt
	var was_blocking := mode == Mode.BLOCK
	blade.update(dt)
	if was_blocking and not blade.is_blocking():
		mode = Mode.GUARD
		ev.append("block_broken")
	if mode == Mode.SWING:
		t += dt
		_blend = minf(1.0, _blend + dt / BLEND)
		var p := progress()
		if not chain.is_empty() and p >= float(swing_def().chain_at):
			var rest: Array = chain.slice(1)
			var in_combo := combo
			if _start(int(chain[0])):
				chain = rest
				combo = in_combo
				ev.append("swing:" + str(swing_def().name))
				return ev
			chain.clear()
		if p >= 1.0:
			mode = Mode.GUARD
			chain.clear()
			combo = false
			_rest = 0.0
			ev.append("swing_end")
	elif mode == Mode.GUARD:
		_rest += dt
		if _rest >= SIDE_RESET:
			next_side = LEFT
	return ev


## Where the sword is right now: { pos, dir, twist } in chest space. First person
## has its own keys (fpv_keys, GUARD_FPV, BLOCK_FPV).
func pose(first_person: bool = false) -> Dictionary:
	_fp = first_person
	return _raw_pose()


## The swing's own pose, blended in from where the blade was when it chained.
func _raw_pose() -> Dictionary:
	match mode:
		Mode.BLOCK:
			return BLOCK_FPV if _fp else BLOCK
		Mode.SWING:
			var p := sample(swing_index, progress(), _fp)
			if _blend < 1.0 and not _from.is_empty():
				p = mix(_from, p, _blend * _blend * (3.0 - 2.0 * _blend))
			return p
	return GUARD_FPV if _fp else GUARD


static func mix(a: Dictionary, b: Dictionary, f: float) -> Dictionary:
	f = clampf(f, 0.0, 1.0)
	return {
		"pos": (a.pos as Vector3).lerp(b.pos, f),
		"dir": (a.dir as Vector3).normalized().slerp((b.dir as Vector3).normalized(), f),
		"twist": lerpf(float(a.twist), float(b.twist), f),
	}


## The pose `p` (0..1) through swing `i`: a curve through its keys (Hermite, each
## key's tangent from its neighbours), at rest on the first and last key.
static func sample(i: int, p: float, first_person := false) -> Dictionary:
	var keys: Array = SWINGS[i].get("fpv_keys", SWINGS[i].keys) if first_person else SWINGS[i].keys
	var n := keys.size()
	for k in range(1, n):
		var t1: float = keys[k][0]
		if p <= t1 or k == n - 1:
			var t0: float = keys[k - 1][0]
			var h := maxf(t1 - t0, 0.0001)
			var f := clampf((p - t0) / h, 0.0, 1.0)
			var out := {}
			for c: String in ["pos", "dir", "twist"]:
				out[c] = _hermite(_key(keys, k - 1, c), _key(keys, k, c),
					_tangent(keys, k - 1, c) * h, _tangent(keys, k, c) * h, f)
			out.dir = (out.dir as Vector3).normalized()
			return out
	return GUARD


static func _key(keys: Array, k: int, c: String):
	var v = keys[k][1][c]
	return (v as Vector3).normalized() if c == "dir" else v


## How fast channel `c` moves through key k (per unit of progress); still at the ends.
static func _tangent(keys: Array, k: int, c: String):
	if k <= 0 or k >= keys.size() - 1:
		return _key(keys, k, c) * 0.0
	return (_key(keys, k + 1, c) - _key(keys, k - 1, c)) / maxf(float(keys[k + 1][0]) - float(keys[k - 1][0]), 0.0001)


static func _hermite(p0, p1, m0, m1, f: float):
	var f2 := f * f
	var f3 := f2 * f
	return p0 * (2.0 * f3 - 3.0 * f2 + 1.0) + m0 * (f3 - 2.0 * f2 + f) \
		+ p1 * (-2.0 * f3 + 3.0 * f2) + m1 * (f3 - f2)


## Chest-space transform of the sword for a pose: +Y along the blade.
static func pose_transform(p: Dictionary) -> Transform3D:
	var y: Vector3 = (p.dir as Vector3).normalized()
	var hint := Vector3.UP if absf(y.y) < 0.9 else Vector3.BACK
	var x := hint.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Transform3D(Basis(x, y, z), p.pos)
