extends RefCounted
## Fall damage (issue #274). Pure: how much a landing at a given downward speed
## hurts. The player's body (character_body.gd) measures the speed and applies the
## damage; every number comes from content/core/flow/falls.json.

const PATH := "res://content/core/flow/falls.json"

static var _cfg: Dictionary = {}


## The tuning (read once).
static func cfg() -> Dictionary:
	if _cfg.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_cfg = parsed
		if _cfg.is_empty():
			push_warning("FallDamage: could not read ", PATH)
	return _cfg


## Damage for touching down at `speed` m/s straight down. 0 at or under the safe
## speed, then a straight line up to lethal_damage at lethal_speed (and past it).
static func damage(speed: float, c: Dictionary) -> int:
	var safe := float(c.get("safe_speed", 16.0))
	var lethal := maxf(float(c.get("lethal_speed", 40.0)), safe + 0.001)
	if speed <= safe:
		return 0
	return ceili(float(c.get("lethal_damage", 100)) * (speed - safe) / (lethal - safe))


## The fastest anyone falls (0 = no cap).
static func terminal_speed(c: Dictionary) -> float:
	return float(c.get("terminal_speed", 0.0))
