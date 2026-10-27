class_name ShipHull
extends StaticBody3D
## The box a ship carries round with it (issue #55): you bump into it parked, and
## bolts hit it parked or flying. bolt.gd calls apply_damage on whatever it hits;
## this passes the damage to `on_damage` (ShipPilot), which decides if it counts.

var on_damage: Callable


func apply_damage(amount: float) -> void:
	if on_damage.is_valid():
		on_damage.call(amount)
