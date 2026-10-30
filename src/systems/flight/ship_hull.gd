class_name ShipHull
extends StaticBody3D
## The box a ship carries round with it (issue #55): you bump into it parked, and
## bolts hit it parked or flying. bolt.gd calls apply_damage on whatever it hits;
## this passes the damage to `on_damage` (ShipPilot), which decides if it counts.
##
## Issue #181: the owner stamps `damage_usec` when it does count a hit, and sets
## `dead` once the ship is down, so HitFeedback can tell a hit that hurt it (and a
## kill) from one it shrugged off, as it does for NPCs.

var on_damage: Callable
var damage_usec := 0             ## clock time of the last hit the owner counted
var dead := false


func apply_damage(amount: float) -> void:
	apply_damage_from(amount, null)


## Issue #64: who shot it matters (another ship can destroy a parked one).
func apply_damage_from(amount: float, shooter: Node) -> void:
	if on_damage.is_valid():
		on_damage.call(amount, shooter)


## The owner counted the hit that just landed.
func took_damage() -> void:
	damage_usec = Time.get_ticks_usec()
