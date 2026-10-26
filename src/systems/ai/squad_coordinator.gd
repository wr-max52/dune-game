extends RefCounted
## Squad coordinator (M5, deferred from M4). Pure and headless-testable. It keeps a
## squad of troopers from all standing in the open: it assigns each member a DISTINCT
## cover node (nearest unclaimed node per member), so 4 troopers spread out instead of
## stacking on one node. This is the "simple squad coordinator so 4 troopers do not all
## stand in the open" from the spec, on top of the single-unit cover logic in M2.
##
## The node layer applies the result: each trooper moves to its assigned node.

var cover_nodes: Array = []   ## each: {position: Vector3}
var reach_radius := 1.0
var _claimed: Array = []       ## cover-node index claimed so far this frame

## Assign a distinct, nearest cover node to each of `count` troopers. Returns the
## assignment array: index member -> cover-node index (-1 if a member has no node).
## A member that is already on a node does not take another; the nearest free node
## goes to it, so the squad spreads rather than piles on one spot.
func assign(count: int) -> Array:
	_claimed.clear()
	var assignment: Array = []
	for i in count:
		assignment.append(-1)
	for i in count:
		assignment[i] = _nearest_free()
	return assignment


## Index of the nearest cover node not yet claimed this frame, or -1 if every node
## is taken.
func _nearest_free() -> int:
	var best := -1
	var best_d := INF
	for i in cover_nodes.size():
		if _claimed.has(i):
			continue
		var self_pos: Vector3 = _member_pos(i)
		var d: float = (cover_nodes[i].position - self_pos).length_squared()
		if d < best_d:
			best_d = d
			best = i
	if best >= 0:
		_claimed.append(best)
	return best


## Positions the caller sets before each frame; one entry per squad member.
var members: Array = []
func _member_pos(i: int) -> Vector3:
	if i >= 0 and i < members.size():
		return members[i]
	return Vector3.ZERO


## How many of the squad are still out in the open (not within reach of any node)
## after they have walked to their assigned nodes. This is the number the trace and
## the test check: with enough cover, the squad is not "all in the open."
func troopers_in_open(count: int) -> int:
	var open := 0
	for i in count:
		var p: Vector3 = members[i]
		if not _near_any_node(p):
			open += 1
	return open


func _near_any_node(p: Vector3) -> bool:
	for node in cover_nodes:
		if (node.position - p).length() <= reach_radius:
			return true
	return false
