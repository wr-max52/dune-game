extends GutTest
## Issue #58: T-89, the ship salesman in the pit. He stocks every ship that flies
## in the atmosphere (not the Remnant's space-only fighters), says hello once a run
## and offers the tutorial (it explains the weapons the player already carries),
## nothing hurts him, and a ship bought from him lands on the empty pad, can be
## boarded like any parked ship, is kept in the save, and sells back at resale.

const TownDemo := preload("res://scenes/town_demo.gd")
const TownDecor := preload("res://src/systems/world/town_decor.gd")


func before_each() -> void:
	WorldState.reset()
	WorldState.set_flag("ships_unlocked")      # issue #64: the story unlocks the ships
	ShipSalesman.greeted = false


func after_each() -> void:
	WorldState.reset()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _town() -> Node:
	var t = TownDemo.new()
	t.use_look = false
	t.npc_brains = false
	add_child_autofree(t)
	return t


# ---- data -------------------------------------------------------------------

func test_stock_is_every_ship_that_flies_in_the_atmosphere() -> void:
	var t = _town()
	var s: ShipSalesman = t.salesman
	assert_not_null(s, "T-89 is in the town")
	var stock := s.stock()
	for id in ["interceptor", "courier", "gunship", "freighter"]:
		assert_true(stock.has(id), "%s is for sale" % id)
	assert_false(stock.has("remnant_fighter"), "space-only fighters are not")
	assert_eq(s.price(stock[0]), stock.map(s.price).min(), "cheapest first")
	assert_lt(s.resale("courier"), s.price("courier"), "he buys back for less")
	assert_eq(s.npc_name(), "T-89")


func test_tutorial_explains_the_weapons_the_player_already_has() -> void:
	var t = _town()
	var pages: Array = t.salesman.tutorial_pages()
	assert_gt(pages.size(), 3)
	var all := " ".join(pages)
	for word in ["pistol", "blade", "rifle", "holster", "board"]:
		assert_true(all.to_lower().contains(word), "the tutorial mentions %s" % word)


# ---- hello and tutorial ------------------------------------------------------

func test_greets_once_and_runs_the_tutorial() -> void:
	var t = _town()
	var s: ShipSalesman = t.salesman
	await wait_physics_frames(3)
	assert_false(s.menu.is_open(), "a headless run never greets on its own")
	s.greet()
	assert_true(ShipSalesman.greeted, "once per run")
	assert_true(s.menu.is_open())
	assert_true(s.said.begins_with(str(s.cfg.greeting)), "hello first")
	assert_eq(s.menu.options.size(), 2, "then the tutorial offer: yes or no")
	assert_true(t._player.locked, "the player stands still while he talks")
	s.menu.choose("yes")
	var pages: int = s.tutorial_pages().size()
	for i in pages - 1:
		assert_eq(s.page, i)
		assert_true(s.said.contains(str(s.tutorial_pages()[i])))
		s.menu.choose("next")
	assert_eq(s.page, pages - 1, "last page")
	s.menu.choose("done")
	assert_eq(s.page, -1)
	assert_false(s.menu.is_open())
	await wait_physics_frames(2)
	assert_false(t._player.locked, "free to walk again")


func test_skip_the_tutorial() -> void:
	var t = _town()
	var s: ShipSalesman = t.salesman
	s.greet()
	s.menu.choose("no")
	assert_eq(s.page, -1)
	assert_eq(s.said, str(s.lines.skipped))
	s.talk()
	assert_true(s.menu.options.any(func(o): return o.id == "tutorial"), "he offers it again any time")
	s.menu.choose("tutorial")
	assert_eq(s.page, 0)
	s.menu.choose("skip")
	assert_eq(s.page, -1)


func test_nothing_hurts_him() -> void:
	var t = _town()
	var s: ShipSalesman = t.salesman
	var n: Node = s.body
	assert_not_null(n)
	while n != null:
		assert_false(n.has_method("apply_damage") or n.has_method("apply_damage_from"),
			"%s takes no damage" % n.name)
		n = n.get_parent()
	assert_null(s.body.find_child("Muzzle", true, false), "and he carries no gun")
	var to_spawn := Vector2(t.town.spawn_pos().x - s.pos.x, t.town.spawn_pos().z - s.pos.z).length()
	assert_lt(to_spawn, 12.0, "he stands near where you start")


func test_out_of_board_reach_of_every_ship() -> void:
	var t = _town()
	var s: ShipSalesman = t.salesman
	t._player.global_position = s.pos + Vector3(0, 0.05, 0)
	assert_eq(t.pilot.nearest_berth(), -1, "E beside him talks to him, never boards a ship")


# ---- buying a ship -------------------------------------------------------------

func test_buy_fills_the_empty_pad_and_flies() -> void:
	var t = _town()
	var s: ShipSalesman = t.salesman
	var pilot: ShipPilot = t.pilot
	var before := pilot.berths.size()
	WorldState.credits = 100
	assert_eq(s.buy("courier"), "cant_afford")
	assert_eq(WorldState.hangar, "")
	WorldState.credits = 5000
	assert_eq(s.buy("remnant_fighter"), "", "not for sale")
	assert_eq(s.buy("courier"), "bought")
	assert_eq(WorldState.credits, 5000 - s.price("courier"))
	assert_eq(WorldState.hangar, "courier")
	assert_eq(pilot.berths.size(), before + 1, "a new berth")
	var pad: Dictionary = t.town.get_box("spare_pad")
	var v: Node3D = s.bought_ship
	assert_almost_eq(v.global_position.x, (float(pad.min[0]) + float(pad.max[0])) * 0.5, 0.5, "on the spare pad")
	assert_almost_eq(v.global_position.z, (float(pad.min[2]) + float(pad.max[2])) * 0.5, 0.5)
	assert_eq(s.buy("gunship"), "taken", "one ship on the pad at a time")
	# Board it.
	var c: float = pilot.berths[before].clearance
	t._player.global_position = Vector3(v.global_position.x + 3.0, v.global_position.y - c, v.global_position.z)
	assert_eq(pilot.nearest_berth(), before)
	assert_true(pilot.board())
	assert_eq(pilot.ship_id, "courier")
	assert_eq(s.sell(), -1, "not while you sit in it")
	assert_true(pilot.exit_ship())
	var credits := WorldState.credits
	assert_eq(s.sell(), s.resale("courier"))
	assert_eq(WorldState.credits, credits + s.resale("courier"))
	assert_eq(WorldState.hangar, "")
	assert_eq(pilot.berths.size(), before, "its berth is gone")
	assert_eq(pilot.berth, 0, "back to the pit's own ship")
	assert_eq(s.buy("gunship"), "bought", "the pad is free again")


func test_shop_menu_lists_ships_then_sell_back() -> void:
	var t = _town()
	var s: ShipSalesman = t.salesman
	WorldState.credits = 5000
	s.talk()
	assert_eq(s.menu.options.size(), s.stock().size() + 1, "every ship, and the tutorial")
	s.menu.choose("buy:interceptor")
	assert_eq(WorldState.hangar, "interceptor")
	s.talk()
	assert_true(s.menu.options.any(func(o): return o.id == "sell"))
	s.menu.choose("sell")
	assert_eq(WorldState.hangar, "")


func test_bought_ship_is_saved() -> void:
	WorldState.hangar = "gunship"
	var d := WorldState.to_save()
	WorldState.reset()
	assert_eq(WorldState.hangar, "")
	WorldState.from_save(d)
	assert_eq(WorldState.hangar, "gunship")
	var t = _town()
	assert_not_null(t.salesman.bought_ship, "parked on the pad when the town loads")
	assert_eq(t.pilot.berths[-1].ship_id, "gunship")


func test_decor_parks_a_bought_ship_on_the_pad() -> void:
	var d = TownDemo.new()
	d.use_look = true
	d.lookdev_mode = true
	add_child_autofree(d)
	var pad: Dictionary = d.town.get_box("spare_pad")
	var n: int = d.decor.parked_ships.size()
	var ship: Node3D = d.decor.park_ship("freighter", pad)
	assert_not_null(ship)
	assert_eq(str(ship.get_meta("ship_id")), "freighter")
	assert_eq(d.decor.parked_ships.size(), n + 1)
	var a: AABB = TownDecor.visual_aabb(ship)
	assert_almost_eq(a.get_center().x, (float(pad.min[0]) + float(pad.max[0])) * 0.5, 0.3)
	assert_almost_eq(a.get_center().z, (float(pad.min[2]) + float(pad.max[2])) * 0.5, 0.3)
