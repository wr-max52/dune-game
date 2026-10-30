extends GutTest
## Issue #96: the desert packs' camps. Each home-planet pack starts at its camp (a
## ring of tents round a lit firepit), stops there on every loop and keeps a few
## of its people there. Each tent has a chest of loot: take it while one of the
## pack sees you and a friendly pack turns on you. Shot down, a camp comes back a
## few in-game hours later. A friendly tent is somewhere to rest until morning.
## The chief fights hand to hand; the others swing clubs or throw rocks; none of
## them speak through the voice service.

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


func _pack(nat, friendly: bool) -> Dictionary:
	return nat.packs.filter(func(p): return bool(p.rec.friendly) == friendly)[0]


func _stand(t, at: Vector3) -> void:
	var pl = t._player
	pl.global_position = at
	pl.velocity = Vector3.ZERO
	pl.controller.velocity = Vector3.ZERO
	pl.controller.body_pos = at


func _nobody_sees(p: Dictionary) -> void:
	for m in p.members:
		(m.npc as NpcBody).perception.visible = false
		(m.npc as NpcBody).set_physics_process(false)    # the senses stay as set


func test_every_home_pack_starts_at_its_camp() -> void:
	var t = _town()
	await wait_physics_frames(3)
	var nat = t.natives
	assert_eq(nat.camps.size(), 2, "both packs have a camp")
	for p in nat.packs:
		var camp: NativeCamp = p.camp
		assert_not_null(camp)
		assert_eq(camp.tents.size(), 3, "three tents")
		assert_eq(camp.fires.size(), 1, "a firepit")
		assert_eq(p.state, "camp", "it starts by the fire")
		assert_lt((nat.leader(p) as Node3D).global_position.distance_to(camp.center), 8.0, "the chief at the camp")
		assert_eq(int(p.route_i), int(p.camp_i), "the camp is a stop on its route")
		var keepers: Array = (p.members as Array).filter(func(m): return bool(m.keeper))
		assert_eq(keepers.size(), 3, "three stay at the camp")
		assert_false(keepers.any(func(m): return int(m.slot) == 0), "never the chief")


func test_a_pack_leaves_camp_then_comes_back_to_it() -> void:
	var t = _town()
	await wait_physics_frames(3)
	var nat = t.natives
	nat.set_physics_process(false)
	var p: Dictionary = nat.packs[0]
	p.camp_t = 0.0
	nat._tick_pack(p, DT, Vector3.INF)
	assert_eq(p.state, "travel", "the stop is over: on along the route")
	assert_eq(int(p.route_i), (int(p.camp_i) + 1) % p.route.size())
	# Back round the loop: the chief reaches the camp again.
	p.route_i = p.camp_i
	var lead: NpcBody = nat.leader(p)
	lead.global_position = (p.camp as NativeCamp).center
	nat._goal_for(p, nat._lead_entry(p, nat.alive(p)), Vector3.INF)
	assert_eq(p.state, "camp", "it stops at the camp again")
	assert_gt(float(p.camp_t), 1.0)


func test_keepers_stay_while_the_pack_walks() -> void:
	var t = _town()
	await wait_physics_frames(3)
	var nat = t.natives
	nat.set_physics_process(false)
	var p: Dictionary = nat.packs[0]
	p.state = "travel"
	p.route_i = (int(p.camp_i) + 1) % p.route.size()
	var camp: NativeCamp = p.camp
	for i in 60 * 20:
		nat._tick_pack(p, DT, Vector3.INF)
	assert_gt((nat.leader(p) as Node3D).global_position.distance_to(camp.center), 15.0, "the pack has walked off")
	for m in p.members:
		if bool(m.keeper):
			assert_lt((m.npc as Node3D).global_position.distance_to(camp.center), 7.0, "a keeper is still by the fire")


func test_the_chief_clubs_and_the_throwers_throw_rocks() -> void:
	var t = _town()
	await wait_physics_frames(3)
	var nat = t.natives
	var throwers := 0
	for p in nat.packs:
		var lead: Dictionary = nat._lead_entry(p, nat.alive(p))
		assert_false(bool(lead.thrower), "the chief never throws")
		assert_eq(str(lead.weapon.id), "club")
		for m in p.members:
			var npc: NpcBody = m.npc
			assert_false(bool(npc.profile.get("voiced", true)), "no voice service")
			if bool(m.thrower):
				throwers += 1
				assert_eq(str(m.weapon.id), "rock")
				assert_true(bool(npc.weapon_cfg.get("bolt_matte", false)), "a dark rock, no glow")
				assert_lt(float(npc.weapon_cfg.get("bolt_length", 1.0)), 0.3, "small and short")
	assert_gt(throwers, 0)


func test_a_swing_lands_partway_through() -> void:
	var t = _town()
	await wait_physics_frames(3)
	var nat = t.natives
	nat.set_physics_process(false)
	var p: Dictionary = _pack(nat, false)
	var m: Dictionary = nat._lead_entry(p, nat.alive(p))
	var npc: NpcBody = m.npc
	var at := npc.global_position + npc.forward() * 1.2
	_stand(t, at)
	m.cd = 0.0
	var hits0: int = nat.hits
	nat._fight(p, m, DT, at)
	assert_eq(npc.action, "swing", "the club goes up")
	assert_eq(nat.hits, hits0, "not landed yet")
	for i in 40:
		nat._fight(p, m, DT, at)
	assert_eq(nat.hits, hits0 + 1, "then it lands")


func test_a_chest_holds_what_the_town_buys_and_fills_again() -> void:
	var t = _town()
	await wait_physics_frames(3)
	var nat = t.natives
	var p: Dictionary = _pack(nat, true)
	var table: Array = (p.camp as NativeCamp).cfg.loot
	var allowed: Array = table.map(func(e): return str(e.item))
	var items: Dictionary = nat.chest_items(p, 0)
	assert_false(items.is_empty(), "something in it")
	for k in items:
		assert_has(allowed, k)
	assert_eq(JSON.stringify(nat.chest_items(p, 0)), JSON.stringify(items), "the same until it is emptied")
	_nobody_sees(p)
	var got: Dictionary = nat.take_chest(p, 0)
	assert_eq(JSON.stringify(got), JSON.stringify(items))
	for k in got:
		assert_eq(WorldState.inventory.count(k), int(got[k]))
	assert_true(nat.chest_items(p, 0).is_empty(), "empty now")
	assert_true(bool(p.rec.friendly), "nobody saw: still friendly")
	WorldState.game_hours += float((p.camp as NativeCamp).cfg.restock_hours) + 0.1
	assert_false(nat.chest_items(p, 0).is_empty(), "full again some hours on")


func test_seen_stealing_turns_a_friendly_pack() -> void:
	var t = _town()
	await wait_physics_frames(3)
	var nat = t.natives
	var p: Dictionary = _pack(nat, true)
	_nobody_sees(p)
	(p.members[2].npc as NpcBody).perception.visible = true
	nat.take_chest(p, 1)
	assert_false(bool(p.rec.friendly), "they saw it")
	assert_eq(p.state, "attack")
	assert_false(bool(p.rec.locked), "not for good: nobody died")


func test_a_wrecked_camp_comes_back_hours_later() -> void:
	var t = _town()
	await wait_physics_frames(3)
	var nat = t.natives
	var p: Dictionary = _pack(nat, false)
	var camp: NativeCamp = p.camp
	for tt in camp.tents:
		(tt.body as NativeCamp.TentBody).apply_damage_from(1000.0, null)
	assert_true(camp.is_wrecked)
	assert_true(camp.tents.all(func(x): return (x.walls as Array).all(func(c): return c.disabled)), "no walls left standing")
	var st: Dictionary = WorldState.native_camp(str(p.id))
	assert_gte(float(st.wrecked_h), 0.0, "remembered")
	assert_true(WorldState.to_save().native_camps.has(str(p.id)), "and saved")
	nat._check_camps(Vector3.INF)
	assert_true(camp.is_wrecked, "not straight away")
	WorldState.game_hours += float(camp.cfg.return_hours) + 0.1
	nat._check_camps(camp.center)
	assert_true(camp.is_wrecked, "not while you stand in it")
	nat._check_camps(Vector3.INF)
	assert_false(camp.is_wrecked, "back up")
	assert_false(bool(camp.tents[0].down))


func test_rest_in_a_friendly_tent_until_morning() -> void:
	var t = _town()
	await wait_physics_frames(3)
	var nat = t.natives
	nat.set_physics_process(false)
	var hostile: Dictionary = _pack(nat, false)
	_stand(t, (hostile.camp as NativeCamp).tents[0].inside)
	assert_true(nat.rest_tent().is_empty(), "not in a hostile pack's tent")
	var p: Dictionary = _pack(nat, true)
	_stand(t, (p.camp as NativeCamp).tents[0].inside)
	assert_false(nat.rest_tent().is_empty(), "a friendly tent")
	t._player.health.hp = 20
	var h0 := WorldState.game_hours
	var ok = await nat.rest(0.0)
	assert_true(ok)
	assert_eq(t._player.health.hp, t._player.health.max_hp, "healed")
	assert_gt(WorldState.game_hours - h0, 4.0, "the night went by")
	assert_eq(nat.rests, 1)
	assert_false(t._player.locked, "on your feet again")


func test_camps_stand_on_level_ground() -> void:
	var t = _town()
	await wait_physics_frames(3)
	var nat = t.natives
	for p in nat.packs:
		var camp: NativeCamp = p.camp
		assert_lt(camp._unevenness(camp.center), 0.05, "%s: the sand under the tents and the fire is levelled" % p.id)
		for t2 in camp.tents:
			assert_true(camp.director.steer.blocked((t2.xf as Transform3D).origin, camp.up), "packs steer round the tents")


func test_no_physics_where_the_sand_has_no_collider() -> void:
	var t = _town()
	await wait_physics_frames(3)
	var nat = t.natives
	nat.set_physics_process(false)
	var p: Dictionary = nat.packs[0]
	var npc: NpcBody = nat.leader(p)
	# The player beside the pack, but the collider still back in town (as on a run
	# out to it, before the collider catches up): the pack keeps sliding.
	var ppos: Vector3 = npc.global_position + NativeSteer._side(nat.up_at(npc.global_position)) * 10.0
	assert_false(nat._has_floor(npc.global_position), "no collider out at the camp yet")
	nat._tick_pack(p, DT, ppos)
	assert_eq(npc.process_mode, Node.PROCESS_MODE_DISABLED, "slid, not dropped through the sand")
	t.terrain.snap_to(ppos)
	assert_true(nat._has_floor(npc.global_position), "the collider has come")
	nat._tick_pack(p, DT, ppos)
	assert_ne(npc.process_mode, Node.PROCESS_MODE_DISABLED, "then it walks with physics")
