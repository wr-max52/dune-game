extends GutTest
## M5: squad coordinator. Proves the "4 troopers do not all stand in the open"
## requirement: given N cover nodes, each member gets a DISTINCT node, so the squad
## spreads instead of stacking. Headless and deterministic.

var Squad


func before_each() -> void:
	Squad = load("res://src/systems/ai/squad_coordinator.gd")


func test_four_troopers_get_four_distinct_nodes() -> void:
	var s = Squad.new()
	s.cover_nodes = [
		{ "position": Vector3(0.0, 0.0, 0.0) },
		{ "position": Vector3(10.0, 0.0, 0.0) },
		{ "position": Vector3(20.0, 0.0, 0.0) },
		{ "position": Vector3(30.0, 0.0, 0.0) },
	]
	# All four start in the open, off to one side.
	s.members = [
		Vector3(-50.0, 0.0, 0.0),
		Vector3(-50.0, 0.0, 0.0),
		Vector3(-50.0, 0.0, 0.0),
		Vector3(-50.0, 0.0, 0.0),
	]
	var assignment: Array = s.assign(4)
	# Four distinct node indices -> nobody shares a node.
	var seen: Array = []
	for i in 4:
		assert_true(assignment[i] >= 0, "trooper %d got a node" % i)
		assert_false(seen.has(assignment[i]), "trooper %d's node is unique" % i)
		seen.append(assignment[i])
	assert_eq(seen.size(), 4, "all four indices are distinct")


func test_each_member_walks_to_a_cover_node() -> void:
	var s = Squad.new()
	s.cover_nodes = [
		{ "position": Vector3(0.0, 0.0, 0.0) },
		{ "position": Vector3(1.0, 0.0, 0.0) },
		{ "position": Vector3(2.0, 0.0, 0.0) },
		{ "position": Vector3(3.0, 0.0, 0.0) },
	]
	s.members = [
		Vector3(0.0, 0.0, 0.0),
		Vector3(1.0, 0.0, 0.0),
		Vector3(2.0, 0.0, 0.0),
		Vector3(3.0, 0.0, 0.0),
	]
	s.assign(4)
	# After walking to their nodes, none is left out in the open.
	assert_eq(s.troopers_in_open(4), 0, "no trooper is left in the open")


func test_more_members_than_nodes_leaves_some_open() -> void:
	# 4 troopers but only 2 cover nodes: two must stay in the open. This is the
	# honest case the coordinator cannot avoid, and the test records it.
	var s = Squad.new()
	s.cover_nodes = [
		{ "position": Vector3(0.0, 0.0, 0.0) },
		{ "position": Vector3(1.0, 0.0, 0.0) },
	]
	s.members = [
		Vector3(0.0, 0.0, 0.0),
		Vector3(1.0, 0.0, 0.0),
		Vector3(50.0, 0.0, 50.0),
		Vector3(50.0, 0.0, 50.0),
	]
	s.assign(4)
	# The two in the open get no node; the other two get a distinct node each.
	assert_eq(s.troopers_in_open(4), 2, "two troopers remain in the open with only two nodes")
