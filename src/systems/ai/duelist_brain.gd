extends RefCounted
## Duelist enemy brain (M3). Pure and headless-testable. A duelist parries the
## player's strikes (timed deflection via the same EnergyBlade), presses when it
## can reach the player, and defensively retreats when out of reach.
##
## This is the "melee duelist that blocks, parries, and pressures" of M3. The
## brain owns one EnergyBlade so it can intercept the player's bolts exactly the
## way the playable character does.

const EnergyBlade := preload("res://src/systems/combat/energy_blade.gd")

enum Stance {
	PRESS,    ## move in and open the attack
	DEFEND,   ## hold and watch
	PARRY,    ## active parry: a strike was reflected this frame
	EXHAUSTED,
}

var blade
var stance := Stance.DEFEND

# World snapshot the node fills in before update().
var enemy_pos := Vector3.ZERO
var player_pos := Vector3.ZERO
var player_is_attacking := false
var reach := 1.2          ## melee reach

const PARRY_WINDOW := 0.2  ## how long a parry stays "active"
const PARRY_CD := PARRY_WINDOW
var _parry_cd := 0.0
var _parry_active := 0.0  ## remaining time a parry is "active"
var _pressure_cd := 0.0   ## periodic pressure timer

func _init(cfg: Dictionary) -> void:
	blade = EnergyBlade.new(cfg)
	stance = Stance.DEFEND


func update(dt: float) -> int:
	# Tick the standing timers first.
	_parry_cd = maxf(0.0, _parry_cd - dt)
	_parry_active = maxf(0.0, _parry_active - dt)
	if _pressure_cd > 0.0:
		_pressure_cd -= dt

	var gap: float = (player_pos - enemy_pos).length()

	# Priority one: a strike in reach is parried. A fresh block starts the deflect
	# window so an incoming bolt can actually be reflected this same frame.
	if player_is_attacking and gap <= reach and _parry_cd <= 0.0:
		blade.start_block()
		var res: int = blade.intercept_bolt()
		if res == int(blade.BoltResult.DEFLECTED):
			stance = Stance.PARRY
			_parry_active = PARRY_WINDOW
			_parry_cd = PARRY_CD
		else:
			stance = Stance.DEFEND
		blade.update(dt)
		return stance

	# Otherwise decide posture from the gap.
	if gap <= reach and _pressure_cd <= 0.0:
		stance = Stance.PRESS
		_pressure_cd = 1.0
	else:
		stance = Stance.DEFEND

	blade.update(dt)
	return stance


## Resolve an incoming bolt the way the play layer would.
func intercept() -> int:
	return blade.intercept_bolt()


func is_parrying() -> bool:
	return _parry_active > 0.0
