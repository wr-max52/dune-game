extends GutTest
## M2: trooper AI that uses cover and fights back. Proves the decision logic that
## makes "1 trooper fights back with cover" true in CI, headless.

var Brain


func before_each() -> void:
	Brain = load("res://src/systems/ai/trooper_brain.gd")


func test_trooper_seals_to_nearest_cover_when_at_open() -> void:
	var b = Brain.new()
	b.cover_nodes = [
		{ "position": Vector3(10.0, 0.0, 0.0) },
		{ "position": Vector3(-2.0, 0.0, 0.0) },
	]
	b.self_position = Vector3.ZERO
	var action: int = b.update(0.01)
	assert_eq(action, int(b.Action.SEAL_COVER), "an open trooper seeks cover")
	# It should target the nearer node (-2,0,0), not (10,0,0).
	assert_eq(b.pick_nearest_cover(), 1, "picks the nearest cover node")
	var target: Vector3 = b.target_position
	assert_almost_eq(target.x, -2.0, 0.001, "targets the nearer cover position")


func test_trooper_fires_when_at_cover_with_sight() -> void:
	var b = Brain.new()
	b.cover_nodes = [{ "position": Vector3(0.0, 0.0, 0.0) }]
	b.self_position = Vector3(0.0, 0.0, 0.0)  # right on top of the node
	b.has_line_of_sight = true
	b.fire_cooldown = 0.0
	var action: int = b.update(0.01)
	assert_eq(action, int(b.Action.FIRE), "at cover with sight, the trooper fires")


func test_trooper_holds_when_no_sight() -> void:
	var b = Brain.new()
	b.cover_nodes = [{ "position": Vector3(0.0, 0.0, 0.0) }]
	b.self_position = Vector3(0.0, 0.0, 0.0)
	b.has_line_of_sight = false
	b.fire_cooldown = 0.0
	var action: int = b.update(0.01)
	assert_eq(action, int(b.Action.HELD), "out of sight, the trooper holds")


func test_trooper_respects_fire_cooldown() -> void:
	var b = Brain.new()
	b.cover_nodes = [{ "position": Vector3(0.0, 0.0, 0.0) }]
	b.self_position = Vector3(0.0, 0.0, 0.0)
	b.has_line_of_sight = true
	# Just fired: cooldown still high -> should HOLD, not fire again.
	b.fire_cooldown = b.fire_rate
	var action: int = b.update(0.01)
	assert_ne(action, int(b.Action.FIRE), "cannot fire immediately after a shot")
	assert_eq(action, int(b.Action.HELD), "holds while on cooldown")
	# Advance past the cooldown -> fires.
	b.fire_cooldown = 0.0
	var action2: int = b.update(0.01)
	assert_eq(action2, int(b.Action.FIRE), "fires once cooldown elapses")


func test_firing_sets_cooldown() -> void:
	var b = Brain.new()
	var before: float = b.fire_cooldown
	b.fire_cooldown = 0.0
	b.fire()
	assert_gt(b.fire_cooldown, 0.0, "firing starts a cooldown")
