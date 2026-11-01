class_name BladeFighter
extends RefCounted
## Issue #303: how a sword fighter on foot fights (the dark master). Pure and
## headless-testable, like DuelistBrain: the caller tells it how far the target is
## each frame and carries out what it says (DarkMasterPost moves the NpcBody).
##
##   chase    out of reach: come at the target (DarkMasterPost runs from far off,
##            walks in from close)
##   strike   in reach: a rush of one to a few blows (cfg "flurry"), each a slash
##            or a swing (NativeMoves) landing part way through; a blow the target
##            blocks with their own blade staggers him
##   back_off after the rush (or reeling from a block): he steps back out of reach
##            to a few metres off (cfg "spacing_m"), facing the target
##   circle   then sidesteps round the target a moment (cfg "back_off_s") before
##            coming again; a target who steps into his reach meanwhile is cut at
##   leap     far above or below him (a roof), or a long way off: one bound, down
##            or across, to just short of the target
##   guard    between blows his blade turns most bolts from the front aside, and
##            some of the target's cuts
##
## Numbers: content/core/npcs/dark_master.json "blade".

var cfg: Dictionary = {}
var mode := "guard"           ## "guard" | "chase" | "strike" | "back_off" | "circle" | "stagger" | "leap"
var side := 1.0               ## which way he circles: 1 or -1
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
var _flurry := 0              ## blows left in this rush
var _spacing := 5.5           ## how far off he backs this time (m)
var _hang_left := 0.0         ## seconds left circling before he comes again
var _back_left := 0.0         ## seconds he may spend stepping back (a wall stops him)
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


## A random value in a [min, max] pair from the config.
func _range(key: String, lo: float, hi: float) -> float:
	var r = cfg.get(key, [lo, hi])
	if r is Array and r.size() >= 2:
		return _rng.randf_range(float(r[0]), float(r[1]))
	return float(r)


func spacing() -> float:
	return _spacing


## One frame. `dist`: flat metres to the target; `rise`: the target's height
## above him (negative below). Returns what to do this frame:
##   { act: "chase"|"hold"|"leap"|"back_off"|"circle", start: move to play now or
##     "", strike: true when a blow lands now (DarkMasterPost checks reach and the
##     target's block), side: which way to circle }
func update(dt: float, dist: float, rise: float) -> Dictionary:
	_cd = maxf(0.0, _cd - dt)
	_leap_cd = maxf(0.0, _leap_cd - dt)
	if _stagger_left > 0.0:
		_stagger_left -= dt
		if _stagger_left > 0.0:
			mode = "stagger"
		else:
			_back_off()
		return _out("hold")
	if _leap_left > 0.0:
		_leap_left -= dt
		if _leap_left <= 0.0:
			mode = "guard"
			_cd = minf(_cd, n("land_cd", 0.35))
		return _out("leap" if _leap_left > 0.0 else "hold")
	if _strike_left >= 0.0:
		_strike_left -= dt
		if _strike_left < 0.0:
			_strike_left = -1.0
			if _flurry > 0:
				mode = "guard"        # more to come in this rush
			else:
				_back_off()
			return _out("hold", "", true)
		return _out("hold")
	var high := absf(rise) > n("climb", 1.8)
	if mode in ["back_off", "circle"]:
		if dist <= reach() and not high and _cd <= 0.0:
			_flurry = 1               # you stepped in: one cut, then off again
			return _blow()
		if high or dist > _spacing + n("lose_m", 5.0):
			mode = "guard"            # you got away: come again
		elif mode == "back_off":
			_back_left -= dt
			if dist < _spacing and _back_left > 0.0:
				return _out("back_off")
			mode = "circle"
		if mode == "circle":
			_hang_left -= dt
			if _hang_left > 0.0:
				return _out("circle")
			mode = "guard"
	if dist <= reach() and not high:
		mode = "guard"
		if _cd > 0.0:
			return _out("hold")
		if _flurry <= 0:
			_flurry = int(round(_range("flurry", 1, 3)))
		return _blow()
	if _leap_cd <= 0.0 and dist <= n("leap_max", 24.0) and (high or dist >= n("leap_min", 9.0)):
		_leap_cd = n("leap_cooldown_s", 5.0)
		_leap_left = leap_seconds()
		leaps += 1
		mode = "leap"
		return _out("leap")
	mode = "chase"
	return _out("chase")


func _out(act: String, start := "", strike := false) -> Dictionary:
	return { "act": act, "start": start, "strike": strike, "side": side }


## The next blow of the rush starts now. A quick follow-up while the rush lasts,
## a longer breath after its last blow.
func _blow() -> Dictionary:
	var moves: Array = cfg.get("moves", ["slash", "swing"])
	move = str(moves[_next % moves.size()])
	_next += 1
	blows += 1
	_flurry = maxi(0, _flurry - 1)
	_cd = n("flurry_cd_s", 0.55) if _flurry > 0 else n("cooldown_s", 0.9)
	_strike_left = NativeMoves.length(move) * float(NativeMoves.STRIKE.get(move, 0.5))
	mode = "strike"
	return _out("hold", move)


## Out of reach to a few metres off, then round you a moment.
func _back_off() -> void:
	_flurry = 0
	_spacing = _range("spacing_m", 4.5, 6.5)
	_hang_left = _range("back_off_s", 0.8, 1.8)
	_back_left = n("back_off_max_s", 1.6)
	side = 1.0 if _rng.randf() < 0.5 else -1.0
	mode = "back_off"


## The blow landed on a target who was blocking with their blade: he reels, then
## backs off.
func on_parried() -> void:
	parried += 1
	_strike_left = -1.0
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
