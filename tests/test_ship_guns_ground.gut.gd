extends GutTest
## Issue #64: a ship's cannon in the atmosphere. Its bolts burst where they land
## (the ground too), so strafing kills people on the ground, and a parked ship
## shot by another ship is destroyed for good: it blows up, nobody can board it,
## and the save remembers.

const TownDemo := preload("res://scenes/town_demo.gd")
const BoltScene := preload("res://scenes/entities/bolt.tscn")


func before_each() -> void:
	WorldState.reset()
	WorldState.set_flag("ships_unlocked")


func after_each() -> void:
	WorldState.reset()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _town() -> Node:
	var t = TownDemo.new()
	t.use_look = false
	t.npc_brains = false
	add_child_autofree(t)
	return t


func test_cannon_has_splash() -> void:
	var cc = preload("res://src/systems/dataload/core_content.gd").new()
	cc.load_from()
	var w: Dictionary = cc.weapons.ship_cannon
	assert_gt(float(w.splash_radius), 2.0)
	assert_gt(float(w.splash_damage), float(w.damage), "a burst hurts more than a graze")


func test_a_bolt_landing_beside_a_trooper_kills_them() -> void:
	var t = _town()
	await wait_physics_frames(2)
	var g = t.npc("trooper_yard_a")
	assert_not_null(g)
	var hp0: float = g.health.hp
	var hull := ShipHull.new()
	t.add_child(hull)
	for i in 4:
		var b = BoltScene.instantiate()
		b.shooter = hull
		b.damage = 9.0
		b.splash_radius = 3.5
		b.splash_damage = 22.0
		t.add_child(b)
		b.global_position = g.global_position + Vector3(1.5, 0.2, 0)
		b.apply_to(null)               # it hit the ground beside them
		await wait_physics_frames(1)
	assert_lt(g.health.hp, hp0, "the burst hurts them")
	assert_true(g.dead, "four bursts kill a trooper")


func test_a_bolt_bursts_on_the_ground_under_it() -> void:
	var t = _town()
	await wait_physics_frames(2)
	var b = BoltScene.instantiate()
	b.direction = Vector3.DOWN
	b.speed = 100.0
	b.range_m = 500.0
	b.splash_radius = 3.0
	b.ground_at = func(_x: float, _z: float) -> float: return 50.0
	t.add_child(b)
	b.global_position = Vector3(500, 60, 500)
	for i in 10:
		await wait_physics_frames(1)
	assert_false(is_instance_valid(b) and b._alive, "it burst on the ground")


func test_parked_ship_destroyed_by_another_ship_for_good() -> void:
	var t = _town()
	await wait_physics_frames(2)
	var pilot: ShipPilot = t.pilot
	var v := Node3D.new()
	t.add_child(v)
	v.global_position = pilot.home + Vector3(30, 0, 0)
	var i := pilot.add_berth(v, "courier", "ship_2")
	var other: ShipHull = pilot.berths[0].hull
	pilot.berths[i].hull.apply_damage_from(5.0, null)
	assert_false(pilot.berths[i].destroyed, "a stray bolt from no ship does nothing")
	pilot.berths[i].hull.apply_damage_from(99999.0, other)
	assert_true(pilot.berths[i].destroyed, "another ship's guns destroy it")
	assert_false(v.visible, "it is gone")
	assert_true(WorldState.ships_destroyed.has("ship_2"), "for good")
	t._player.global_position = v.global_position
	await wait_physics_frames(1)
	assert_ne(pilot.nearest_berth(), i, "nobody can board it")
	# Next time the town is built (or the save loads) it is still gone.
	var saved := WorldState.to_save()
	WorldState.from_save(JSON.parse_string(JSON.stringify(saved)))
	var v2 := Node3D.new()
	t.add_child(v2)
	var j := pilot.add_berth(v2, "courier", "ship_2")
	assert_true(pilot.berths[j].destroyed, "it does not respawn")


func test_the_ship_you_fly_is_not_a_parked_target() -> void:
	var t = _town()
	await wait_physics_frames(2)
	var pilot: ShipPilot = t.pilot
	var v := Node3D.new()
	t.add_child(v)
	var i := pilot.add_berth(v, "courier", "ship_2")
	assert_false(pilot._parked_target(i, pilot.berths[i].hull), "a ship never shoots itself")
