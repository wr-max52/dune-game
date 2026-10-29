extends GutTest
## The far-tick LOD of the native packs and the sand pigs: out of the player's sight
## they step once in a few ticks with the time of the ticks in between, so they cover
## the same ground; near, spooked or fleeing they run at the full rate.

const TownDemo := preload("res://scenes/town_demo.gd")
const DT := 1.0 / 60.0


func before_each() -> void:
	WorldState.reset()


func after_each() -> void:
	WorldState.reset()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _town() -> Node:
	var t = TownDemo.new()
	t.use_look = false
	t.npc_brains = false
	add_child_autofree(t)
	return t


func _snapshot(p: Dictionary) -> Dictionary:
	var pos: Array = []
	for m in p.members:
		pos.append((m.npc as Node3D).global_position)
	return { "pos": pos, "route_i": p.route_i, "heading": p.heading }


func _restore(p: Dictionary, snap: Dictionary) -> void:
	for i in p.members.size():
		var m: Dictionary = p.members[i]
		(m.npc as Node3D).global_position = snap.pos[i]
		m.erase("far_acc")
		m.erase("far_n")
	p.route_i = snap.route_i
	p.heading = snap.heading


func _run_pack(nat, p: Dictionary, ticks: int) -> Array:
	for i in ticks:
		nat._tick_pack(p, DT, Vector3.INF)       # nobody to see them: all far
	var out: Array = []
	for m in p.members:
		out.append((m.npc as Node3D).global_position)
	return out


func test_far_pack_covers_the_same_ground_at_a_quarter_the_ground_queries() -> void:
	var t = _town()
	await wait_physics_frames(3)
	var nat = t.natives
	assert_not_null(nat, "the town has natives")
	nat.set_physics_process(false)
	var p: Dictionary = nat.packs[0]
	var snap := _snapshot(p)
	var ticks := 240                             # 4 s: not enough to reach the first route point
	nat.far_stride = 1
	var full := _run_pack(nat, p, ticks)
	var full_route_i = p.route_i
	_restore(p, snap)
	nat.far_stride = 4
	# On one tick only a quarter of the members step.
	nat._tick_pack(p, DT, Vector3.INF)
	var moved := 0
	for i in p.members.size():
		if (p.members[i].npc as Node3D).global_position.distance_to(snap.pos[i]) > 0.0001:
			moved += 1
	assert_lte(moved, ceili(p.members.size() / 4.0), "a quarter of the members step on a tick")
	_restore(p, snap)
	var lod := _run_pack(nat, p, ticks)
	assert_eq(p.route_i, full_route_i, "the same route progress")
	var speed := float(nat.people.get("pack", {}).get("travel_speed", 1.6))
	for i in p.members.size():
		var d_full: float = (full[i] as Vector3).distance_to(snap.pos[i])
		var d_lod: float = (lod[i] as Vector3).distance_to(snap.pos[i])
		assert_almost_eq(d_lod, d_full, 0.35, "member %d covers the same distance" % i)
	var lead_moved: float = (lod[0] as Vector3).distance_to(snap.pos[0])
	assert_almost_eq(lead_moved, speed * ticks * DT, 0.35, "the leader walks at travel_speed")
	assert_lt((lod[0] as Vector3).distance_to(full[0]), 0.35, "and ends where it would have")


func test_near_members_are_not_throttled() -> void:
	var t = _town()
	await wait_physics_frames(3)
	var nat = t.natives
	nat.set_physics_process(false)
	var p: Dictionary = nat.packs[0]
	for m in p.members:
		m.erase("far_n")
	# The player stands at the leader: no member is far, so none takes the LOD path.
	var ppos: Vector3 = (nat.leader(p) as Node3D).global_position
	nat._tick_pack(p, DT, ppos)
	for m in p.members:
		assert_false(m.has("far_n"), "near members never count far ticks")


# ---------------------------------------------------------------- pigs

func _pig(seed_n: int, target: Node3D) -> SandPig:
	var ground := WorldGround.new()
	ground.setup({}, null, null)
	var pig := SandPig.new()
	pig.target = target
	add_child_autofree(pig)
	pig.setup({ "walk_speed": 1.4, "run_speed": 6.5, "wander_radius": 40.0, "flee_range": 18.0 }, ground,
		Vector3(0, 0, 0), seed_n)
	pig.set_physics_process(false)
	return pig


func _target(at: Vector3) -> CharacterBody3D:
	var script := GDScript.new()          # a body with the player's `piloting` flag
	script.source_code = "extends CharacterBody3D\nvar piloting := false\n"
	script.reload()
	var b := CharacterBody3D.new()
	b.set_script(script)
	add_child_autofree(b)
	b.global_position = at
	return b


func test_a_far_pig_covers_the_same_ground() -> void:
	var tg := _target(Vector3(500, 0, 0))
	var a := _pig(7, tg)
	var b := _pig(7, tg)
	a.lod_stride = 1
	b.lod_stride = 4
	var path_a := 0.0
	var path_b := 0.0
	var last_a := a.global_position
	var last_b := b.global_position
	for i in 60 * 40:
		a._physics_process(DT)
		b._physics_process(DT)
		path_a += a.global_position.distance_to(last_a)
		path_b += b.global_position.distance_to(last_b)
		last_a = a.global_position
		last_b = b.global_position
	assert_gt(path_a, 10.0, "the pig wanders")
	assert_almost_eq(path_b, path_a, path_a * 0.2, "the LOD pig covers about the same distance")
	assert_lt(a.global_position.distance_to(b.global_position), 12.0, "and stays in the same part of its range")


func test_a_far_pig_steps_once_in_a_few_ticks() -> void:
	var tg := _target(Vector3(500, 0, 0))
	var pig := _pig(3, tg)
	pig.lod_stride = 4
	pig._rest = 0.0
	pig._goal = Vector3(30, 0, 0)
	var steps := 0
	var last := pig.global_position
	for i in 40:
		pig._physics_process(DT)
		if pig.global_position.distance_to(last) > 0.0001:
			steps += 1
		last = pig.global_position
	assert_between(steps, 9, 11, "ten steps in forty ticks")


func test_a_hurt_pig_flees_at_the_full_rate_even_when_far() -> void:
	var tg := _target(Vector3(500, 0, 0))
	var pig := _pig(5, tg)
	pig.lod_stride = 4
	for i in 8:
		pig._physics_process(DT)
	pig.apply_damage_from(1.0, tg)
	assert_gt(pig._flee, 0.0, "spooked")
	var moves := 0
	var last := pig.global_position
	for i in 12:
		pig._physics_process(DT)
		if pig.global_position.distance_to(last) > 0.0001:
			moves += 1
		last = pig.global_position
	assert_eq(moves, 12, "it runs every tick")


func test_a_runner_coming_close_spooks_a_lod_pig_at_once() -> void:
	var tg := _target(Vector3(500, 0, 0))
	var pig := _pig(2, tg)
	pig.lod_stride = 4
	for i in 8:
		pig._physics_process(DT)
	assert_eq(pig._flee, 0.0)
	tg.global_position = pig.global_position + Vector3(10, 0, 0)
	tg.velocity = Vector3(8, 0, 0)
	pig._physics_process(DT)
	assert_gt(pig._flee, 0.0, "within a tick of a runner coming in range")
