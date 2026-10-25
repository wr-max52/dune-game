extends RefCounted
## Trooper AI decision logic (M2). Pure and headless-testable: it decides whether
## the trooper is sealing into cover or firing, given reach-arrival, sight, fire
## timing. The node applies the result (move toward target, aim, fire).
##
## This is "1 trooper that uses cover and fights back." The squad coordinator
## (4 troopers not all standing in the open) is M4; this single unit is M2.

enum Action {
	SEAL_COVER,   ## moving to a cover node
	FIRE,         ## at a cover node, on cooldown or firing
	HELD,         ## at a cover node but out of sight / on cooldown, holding
}

var state := Action.SEAL_COVER
var cover_nodes: Array = []  ## each: {position: Vector3}
var self_position := Vector3.ZERO
var target_position := Vector3.ZERO
var has_line_of_sight := true
var fire_cooldown := 0.0
var fire_rate := 0.6
var reach_radius := 1.0


func pick_nearest_cover() -> int:
	## Index of the closest cover node to self, or -1 if none.
	var best := -1
	var best_d := INF
	for i in cover_nodes.size():
		var node: Dictionary = cover_nodes[i]
		var d: float = (node.position - self_position).length_squared()
		if d < best_d:
			best_d = d
			best = i
	return best


func _at_cover() -> bool:
	var idx := pick_nearest_cover()
	if idx < 0:
		return false
	return (cover_nodes[idx].position - self_position).length() < reach_radius


func wants_fire() -> bool:
	## Whether the trooper would fire THIS instant if it can.
	return state == Action.FIRE and fire_cooldown <= 0.0 and has_line_of_sight


func fire() -> void:
	## Called by the node when wants_fire() is true. Records a bolt + cooldown.
	fire_cooldown = fire_rate


func update(dt: float) -> int:
	## Decide the trooper's action this frame. Returns the chosen Action.
	if fire_cooldown > 0.0:
		fire_cooldown = maxf(0.0, fire_cooldown - dt)

	if not _at_cover():
		## Not at cover yet: head to the nearest node.
		var idx := pick_nearest_cover()
		if idx >= 0:
			target_position = cover_nodes[idx].position
		state = Action.SEAL_COVER
		return state

	## At a cover node: fire when we have sight and off cooldown, else hold.
	if has_line_of_sight and fire_cooldown <= 0.0:
		state = Action.FIRE
	else:
		state = Action.HELD
	return state
