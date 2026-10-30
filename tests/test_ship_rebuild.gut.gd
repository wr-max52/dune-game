extends GutTest
## Issue #206: in a story save the ship you land in is a wreck. T-89 rebuilds it
## for 500, or 1 credit once you tell him you can't stand the Remnant; then it is
## yours to fly. No free keys in the pit.

var s: ShipSalesman


func before_each() -> void:
	WorldState.new_game(WorldState.STORY)
	s = ShipSalesman.new()          # on his own: no town, no body
	add_child_autofree(s)


func after_each() -> void:
	WorldState.reset()


func test_talking_quotes_the_rebuild_and_offers_the_quest() -> void:
	assert_string_contains(s._repair_line(), "500")
	assert_eq(Quests.state("rebuild_ship"), "open")
	assert_true(s.shop_options().any(func(o): return o.id == "rebuild"))


func test_500_credits_rebuild_it() -> void:
	assert_eq(s.rebuild(), "cant_afford", "60 cr is not enough")
	WorldState.credits = 600
	assert_eq(s.rebuild(), "rebuilt")
	assert_eq(WorldState.credits, 100)
	assert_true(WorldState.owns_ship())
	assert_eq(Quests.state("rebuild_ship"), "done")
	assert_eq(s.rebuild(), "", "only once")


func test_a_comrade_pays_1_credit() -> void:
	assert_true(s.comrade())
	assert_eq(s.rebuild_price(), 1)
	assert_false(s.shop_options().any(func(o): return o.id == "comrade"), "said once")
	assert_eq(s.rebuild(), "rebuilt")
	assert_eq(WorldState.credits, 59)


func test_only_your_own_ship_flies_and_it_stays_yours() -> void:
	assert_false(ShipPilot.berth_open({}, 0), "a wreck")
	assert_false(ShipPilot.berth_open({}, 1), "no free keys")
	assert_true(ShipPilot.berth_open({ "owned": true }, 2), "bought from T-89")
	WorldState.credits = 600
	s.rebuild()
	WorldState.from_save(WorldState.to_save())
	assert_true(ShipPilot.berth_open({}, 0), "rebuilt, and saved")
	assert_false(ShipPilot.berth_open({}, 1))
	WorldState.new_game(WorldState.FREEPLAY)
	assert_true(ShipPilot.berth_open({}, 1), "freeplay keys as today")
	assert_false(ShipSalesman.needs_rebuild())
