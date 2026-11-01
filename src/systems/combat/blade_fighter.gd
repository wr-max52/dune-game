class_name BladeFighter
extends RefCounted
## Issue #303: how a sword fighter on foot fights (the dark master). Pure and
## headless-testable, like DuelistBrain: the caller tells it how far the target is
## each frame and carries out what it says (DarkMasterPost moves the NpcBody).
##
##   chase    out of reach: run at the target
##   strike   in reach: a slash or a swing (NativeMoves), the blow landing part way
##            through; a blow the target blocks with their own blade staggers him
##   leap     far above or below him (a roof), or a long way off: one bound, down
##            or across, to just short of the target
##   guard    between blows his blade turns most bolts from the front aside, and
##            some of the target's cuts
##
## Numbers: content/core/npcs/dark_master.json "blade".

var cfg: Dictionary = {}
var mode := "guard"           ## "guard" | "chase" | "strike" | "stagger" | "leap"
var move := ""                ## the blow under way ("slash" / "swing")
var blows := 0                ## blows started (tests)
var landed := 0               ## blows that reached the target
var parried := 0              ## blows the target's block turned (he staggers)
var deflected := 0            ## bolts and cuts his guard turned aside
var leaps := 0

var _cd := 0.0                ## seconds before the next blow
var _strike_left := -1.0      ## seconds before the blow under way lands (-1 = none)
var _stagger_left := 0.0
var _leap_left := 0.0
var _leap_cd := 0.0
var _next := 0                ## which of the moves comes next
var _rng := RandomNumberGenerator.new()


func _init(c: Dictionary = {}, rng_seed: int = 303) -> void:
	cfg = c
	_rng.seed = rng_seed


func n(key: String, fallback: float) -> float:
	return float(cfg.get(key, fallback))


func reach() -> float:
	return n("reach", 2.3)


func leap_seconds() -> float:
	return n("leap_s", 0.75)


## One frame. `dist`: flat metres to the target; `rise`: the target's height
## above him (negative below). Returns what to do this frame:
##   { act: "chase"|"hold"|"leap", start: move to play now or "", strike: true when
##     a blow lands now (DarkMasterPost checks reach and the target's block) }
func update(dt: float, dist: float, rise: float) -> Dictionary:
	_cd = maxf(0.0, _cd - dt)
	_leap_cd = maxf(0.0, _leap_cd - dt)
	if _stagger_left > 0.0:
		_stagger_left -= dt
		mode = "stagger" if _stagger_left > 0.0 else "guard"
		return { "act": "hold", "start": "", "strike": false }
	if _leap_left > 0.0:
		_leap_left -= dt
		if _leap_left <= 0.0:
			mode = "guard"
			_cd = minf(_cd, n("land_cd", 0.35))
		return { "act": "leap" if _leap_left > 0.0 else "hold", "start": "", "strike": false }
	if _strike_left >= 0.0:
		_strike_left -= dt
		if _strike_left < 0.0:
			_strike_left = -1.0
			mode = "guard"
			return { "act": "hold", "start": "", "strike": true }
		return { "act": "hold", "start": "", "strike": false }
	var high := absf(rise) > n("climb", 1.8)
	if dist <= reach() and not high:
		mode = "guard"
		if _cd > 0.0:
			return { "act": "hold", "start": "", "strike": false }
		var moves: Array = cfg.get("moves", ["slash", "swing"])
		move = str(moves[_next % moves.size()])
		_next += 1
		blows += 1
		_cd = n("cooldown_s", 0.9)
		_strike_left = NativeMoves.length(move) * float(NativeMoves.STRIKE.get(move, 0.5))
		mode = "strike"
		return { "act": "hold", "start": move, "strike": false }
	if _leap_cd <= 0.0 and dist <= n("leap_max", 24.0) and (high or dist >= n("leap_min", 9.0)):
		_leap_cd = n("leap_cooldown_s", 5.0)
		_leap_left = leap_seconds()
		leaps += 1
		mode = "leap"
		return { "act": "leap", "start": "", "strike": false }
	mode = "chase"
	return { "act": "chase", "start": "", "strike": false }


## The blow landed on a target who was blocking with their blade: he reels.
func on_parried() -> void:
	parried += 1
	_stagger_left = n("stagger_s", 0.8)
	mode = "stagger"


func on_landed() -> void:
	landed += 1


## A hit on him: what gets through. `front`: it came from in front of him;
## `by_blade`: a cut, not a bolt. Mid-blow, staggered or in the air he is open.
func guard(amount: float, front: bool, by_blade: bool) -> float:
	if mode in ["strike", "stagger", "leap"] or not front:
		return amount * (n("blade_taken", 1.0) if by_blade else 1.0)
	var chance := n("parry_chance", 0.35) if by_blade else n("deflect_chance", 0.7)
	if _rng.randf() < chance:
		deflected += 1
		return 0.0
	return amount * (n("blade_taken", 1.0) if by_blade else 1.0)


## Where a bound from `from` toward `to` comes down: just short of the target.
func leap_target(from: Vector3, to: Vector3) -> Vector3:
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var d := flat.length()
	if d < 0.01:
		return to
	return to - flat / d * minf(d, reach() * 0.8)


## The bound's position `t` (0..1) of the way from `from` to `to`, `arc` m high.
static func leap_point(from: Vector3, to: Vector3, t: float, arc: float) -> Vector3:
	t = clampf(t, 0.0, 1.0)
	return from.lerp(to, t) + Vector3.UP * (4.0 * arc * t * (1.0 - t))
