extends GutTest
## Issue #187: who holds each place (territory.gd, pure). An outpost flips to the
## locals, runs short, is supplied, is retaken; the gate's checkpoint and the
## fence change with it; holding them all drives the Remnant off and hands the
## locals the barracks; the story's end does too; it all survives a save.

const CoreScript := preload("res://src/systems/dataload/core_content.gd")
const NEAR := "remnant_outpost_near"


func before_each() -> void:
	WorldState.new_game(WorldState.FREEPLAY)


func after_all() -> void:
	WorldState.reset()


func test_everything_starts_with_the_remnant() -> void:
	for id in Territory.places():
		assert_eq(Territory.owner(str(id)), Territory.REMNANT, str(id))
	assert_true(Story.town_garrison())
	assert_eq(Territory.lost(), 0)


func test_clearing_an_outpost_flips_it_and_it_is_retaken() -> void:
	var before := int(WorldState.standing.locals)
	Territory.take(NEAR)
	assert_eq(Territory.owner(NEAR), Territory.LOCALS)
	assert_true(WorldState.has_flag("locals_hold_outpost"))
	assert_gt(int(WorldState.standing.locals), before, "the locals like it")
	assert_false(Territory.short(NEAR), "a fresh hold is not short")
	# The hold runs down: short, then gone.
	Territory.tick(Territory.n("hold_s", 900.0) - Territory.n("supply_warn_s", 420.0) + 1.0)
	assert_true(Territory.short(NEAR))
	assert_true(WorldState.has_flag("outpost_short"))
	Territory.tick(Territory.n("supply_warn_s", 420.0))
	assert_eq(Territory.owner(NEAR), Territory.REMNANT, "retaken when the hold runs out")
	assert_true(WorldState.has_flag("outpost_retaken"))
	assert_false(WorldState.has_flag("locals_hold_outpost"))


func test_the_locals_guards_dying_hands_it_back() -> void:
	Territory.take(NEAR)
	Territory.guards_lost(NEAR)
	Territory.tick(0.1)
	assert_eq(Territory.owner(NEAR), Territory.REMNANT)


func test_a_supply_run_from_oda_fills_the_hold() -> void:
	Territory.take(NEAR)
	assert_false(WorldState.open_jobs("confidant").any(func(j): return str(j.id) == Territory.SUPPLY_JOB),
		"no supply job while the locals are well off")
	Territory.tick(Territory.n("hold_s", 900.0) - 60.0)
	var jobs := WorldState.open_jobs("confidant").filter(func(j): return str(j.id) == Territory.SUPPLY_JOB)
	assert_eq(jobs.size(), 1, "on the board once they run short")
	assert_string_contains(str(jobs[0].text), Story.outpost_label(NEAR))
	assert_true(WorldState.accept_job(Territory.SUPPLY_JOB))
	assert_eq(Territory.supply_out(), NEAR)
	assert_eq(Objective.current().get("target", ""), "outpost:" + NEAR, "the pointer points at it")
	var cr := WorldState.credits
	assert_eq(Territory.deliver("remnant_outpost_far"), 0, "only where they are going")
	var pay := Territory.deliver(NEAR)
	assert_gt(pay, 0)
	assert_eq(WorldState.credits, cr + pay)
	assert_almost_eq(Territory.hold_left(NEAR), Territory.n("hold_s", 900.0), 0.01)
	assert_eq(Territory.supply_out(), "")
	assert_false(WorldState.jobs_taken.has(Territory.SUPPLY_JOB), "and the job can come round again")


func test_the_gate_and_the_fence_change_with_control() -> void:
	var cc = CoreScript.new()
	cc.load_from()
	var c := Checkpoint.new(cc.get_soldier("gate_guard").get("checkpoint", {}))
	var papers := c.bribe_price("papers", false)
	assert_eq(c.band_for(10, false, false, false), "papers")
	var item: Dictionary = cc.get_item("holocrystals")
	var fence := { "buys": [str(item.get("kind", ""))], "buy_rate": 0.5 }
	var price := Inventory.sell_price(item, fence)
	for i in int(Territory.cfg().get("gate", {}).get("strict_from", 3)):
		Territory.take(str(Story.OUTPOSTS[i]))
	c.strict = Territory.gate_strict()
	c.bribe_mult = Territory.bribe_mult()
	assert_eq(c.band_for(10, false, false, false), "search", "enough outposts lost: the gate is edgier")
	assert_gt(c.bribe_price("papers", false), papers, "and dearer")
	assert_gt(Inventory.sell_price(item, fence), price, "the fence pays more")
	assert_eq(Territory.summary().size(), Territory.places().size())


func test_holding_every_outpost_drives_the_remnant_off() -> void:
	for id in Story.OUTPOSTS:
		Territory.take(str(id))
	assert_true(WorldState.has_flag(Territory.DRIVEN_OFF))
	assert_eq(Territory.owner(Territory.BARRACKS), Territory.LOCALS, "the locals take the barracks too")
	assert_false(Story.town_garrison())
	Territory.tick(100000.0)
	assert_eq(Territory.lost(), Story.OUTPOSTS.size(), "nothing is retaken after that")


func test_the_story_ending_hands_the_locals_the_barracks() -> void:
	WorldState.set_flag("remnant_fleet_beaten")
	assert_eq(Territory.owner(Territory.BARRACKS), Territory.LOCALS)
	assert_eq(Territory.owner(NEAR), Territory.REMNANT, "the outposts are still to fight for")


func test_control_is_saved() -> void:
	Territory.take(NEAR)
	Territory.tick(100.0)
	var d := WorldState.to_save()
	WorldState.reset()
	assert_eq(Territory.owner(NEAR), Territory.REMNANT)
	WorldState.from_save(JSON.parse_string(JSON.stringify(d)))
	assert_eq(Territory.owner(NEAR), Territory.LOCALS)
	assert_almost_eq(Territory.hold_left(NEAR), Territory.n("hold_s", 900.0) - 100.0, 0.01)
