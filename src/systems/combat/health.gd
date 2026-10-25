extends RefCounted
## Health (M2). Pure: stores hp, takes damage, reports death. Both the player and
## the trooper own one. Provably correct in CI.

signal on_death

var hp: int
var max_hp: int
var _alive := true

func _init(start_hp: int = 100) -> void:
	max_hp = start_hp
	hp = start_hp


func apply_damage(amount: float) -> void:
	if _alive == false:
		return
	hp = int(maxf(0.0, hp - amount))
	if hp <= 0:
		_alive = false
		on_death.emit()


func is_alive() -> bool:
	return _alive


func heal(amount: int) -> void:
	hp = int(minf(float(max_hp), hp + amount))
