extends Node3D
## Ship node (M10). The visible half of a dogfight ship: it holds the look the
## ShipKit built and copies the pure flight model's transform onto itself each
## frame. It decides nothing -- the dogfight director owns movement, guns and
## damage -- so a ship looks the same whether a human, the AI or the headless bot
## flies it.

var ship_id := -1          ## runtime id in the dogfight director
var team := ""
var visual: Node3D
var _engines: Node3D


func setup(kit: ShipKit, look_id: String, id: int, team_name: String) -> void:
	ship_id = id
	team = team_name
	name = "Ship%d" % id
	visual = kit.build(look_id)
	add_child(visual)
	_engines = visual.get_node_or_null("Engines")


## Copy the flight model onto this node; engine glow follows speed and boost, the
## flames the throttle.
func sync(flight, alive: bool) -> void:
	visible = alive
	if not alive:
		return
	global_transform = flight.transform()
	ShipKit.throttle_flames(visual, flight.throttle, flight.boosting, get_process_delta_time())
	if _engines != null:
		var top: float = maxf(flight.max_speed(), 0.001)
		var glow := clampf(flight.speed / top, 0.25, 1.6)
		if flight.boosting:
			glow *= 1.3
		for g in _engines.get_children():
			if g is MeshInstance3D and g.material_override is StandardMaterial3D:
				g.material_override.emission_energy_multiplier = 5.0 * glow
