extends RefCounted
## Weapon state machine (M2). Pure and headless-testable: it owns ammo, fire
## timing, and reload, and is driven each frame with the time step plus whether
## the trigger is being pulled. It returns a Result each frame, and the weapon
## node is free to spawn a visible bolt when it gets SHOT.
##
## This separation means "two working blasters with visible bolts, recoil, and
## reload" is provable in CI by GUT tests -- no rendered bolts required.

var config: Dictionary   # from content/core/weapons/*.json
var ammo: int
var _fire_cd_left := 0.0
var _reloading := false
var _reload_left := 0.0

enum Result {
	NONE,
	SHOT,
	RELOAD_START,
	RELOAD_DONE,
}


func _init(cfg: Dictionary) -> void:
	config = cfg
	ammo = int(cfg.get("mag", 10))


func can_fire() -> bool:
	return not _reloading and _fire_cd_left <= 0.0 and ammo > 0


func fire_cooldown() -> float:
	return float(config.get("rate", 0.2))


func start_firing(dt: float, start: bool) -> int:
	## Advance firing and return a Result. SHOT means a bolt should be spawned.
	if _reloading:
		_reload_left -= dt
		if _reload_left <= 0.0:
			_reloading = false
			ammo = int(config.get("mag", 10))
			return Result.RELOAD_DONE
		return Result.NONE

	if _fire_cd_left > 0.0:
		_fire_cd_left -= dt

	if start and can_fire():
		ammo -= 1
		_fire_cd_left = fire_cooldown()
		return Result.SHOT

	# Trigger held: attempt a reload whenever we are not on the fire cooldown and
	# not already reloading (covers the empty-magazine and manual-reload cases).
	if start and not _reloading and _fire_cd_left <= 0.0:
		return start_reloading()

	return Result.NONE


func start_reloading() -> int:
	if _reloading or ammo == int(config.get("mag", 10)):
		return Result.NONE
	_reloading = true
	_reload_left = float(config.get("reload_time", 1.5))
	return Result.RELOAD_START


func is_reloading() -> bool:
	return _reloading


func recoil() -> float:
	return float(config.get("recoil", 0.0))
