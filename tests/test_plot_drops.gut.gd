extends GutTest
## Issue #251: the port's drops split between the plot's sides. Oda and the
## fence send you out of town (the desert past either gate) and the fence buys
## the goods; the general sends you after the stashes inside the town (the
## alleys, the roofs), calls it repossession, and the goods go to him. The
## pointer goes to near the drop itself, not to the gate.

const CoreContent := preload("res://src/systems/dataload/core_content.gd")
const ODA := "j_smuggle_run"
const GENERAL := "j_general_repossess"
const OUT_OF_TOWN := ["east_desert", "back_desert"]
const IN_TOWN := ["alleys", "rooftops"]

var content


func before_each() -> void:
	GameFlow.reset()
	WorldState.new_game(WorldState.STORY)
	Story.skip_to("smuggle_1")
	content = CoreContent.new()
	content.load_from()


func after_all() -> void:
	WorldState.reset()


func _offered(id: String) -> Dictionary:
	for j in WorldState.open_jobs("stranger"):
		if str(j.id) == id:
			return j
	return {}


func _brain(card: String) -> NpcBrain:
	return NpcBrain.new(null, "res://content/core/npcs/%s.json" % card)


## Take the job and pick its drop up. Returns the drop.
func _take(id: String) -> Dictionary:
	assert_true(WorldState.accept_job(id), "%s can be taken" % id)
	var drop := WorldState.smuggle_drop()
	assert_true(WorldState.inventory.pick_up(drop))
	return drop


func _sell_to_fence(drop: Dictionary) -> void:
	var fence: Dictionary = content.get_vendor("fence")
	for i in int(drop.count):
		WorldState.credits += WorldState.inventory.sell(str(drop.item), content.get_item(str(drop.item)), fence)
	WorldState.on_contraband_sold()


func test_oda_and_the_fence_give_the_run_out_of_town_in_talk() -> void:
	var j := _offered(ODA)
	assert_false(j.is_empty())
	for card in ["cantina_owner_card", "fence_card"]:
		var b := _brain(card)
		assert_true(b.gives(j), "%s gives the out-of-town run" % card)
		assert_true((b.card.get("actions", []) as Array).has("offer_job"), "%s offers it in talk, with offer_job" % card)
		assert_false(b.gives(_offered(GENERAL)), "%s never gives the general's" % card)
	assert_false(_brain("general_card").gives(j), "the general never sends you to the fence")


func test_the_general_gives_the_stashes_in_town() -> void:
	var j := _offered(GENERAL)
	assert_false(j.is_empty(), "the general has work once the story reaches the first run")
	assert_true(_brain("general_card").gives(j))
	assert_false(str(j.text).contains("%"), "the text is filled in")
	assert_string_contains(str(j.text).to_lower(), "repossess")
	assert_true(str(j.text).contains(str(WorldState.smuggle_offers[GENERAL].hint)), "he says where")
	var goods := (WorldState.board().filter(func(b): return b.id == ODA)[0].goods as Array).map(func(g): return g.item)
	assert_true(goods.has(str(WorldState.smuggle_offers[GENERAL].item)), "the same goods as the fence's run")


func test_hostile_to_the_remnant_no_repossession() -> void:
	WorldState.standing["imperial_remnant"] = -60
	assert_true(_offered(GENERAL).is_empty())


func test_each_side_keeps_to_its_own_areas() -> void:
	for run in 6:
		assert_false(_offered(ODA).is_empty())
		assert_has(OUT_OF_TOWN, str(WorldState.smuggle_offers[ODA].area), "Oda's run %d is out of town" % run)
		_sell_to_fence(_take(ODA))
		assert_false(_offered(GENERAL).is_empty())
		var g := str(WorldState.smuggle_offers[GENERAL].area)
		assert_has(IN_TOWN, g, "the general's run %d is inside the town" % run)
		_take(GENERAL)
		assert_gt(WorldState.hand_over_contraband(3), 0, "he takes his run's goods")


func test_both_offers_hold_and_only_one_drop_is_out() -> void:
	var oda := _offered(ODA)
	var gen := _offered(GENERAL)
	assert_eq(str(_offered(ODA).text), str(oda.text), "reading again keeps her offer")
	assert_eq(str(_offered(GENERAL).text), str(gen.text), "and his")
	assert_true(WorldState.accept_job(GENERAL))
	assert_string_contains(str(gen.text), str(WorldState.smuggle.hint), "the drop is the one he described")
	assert_has(IN_TOWN, str(WorldState.smuggle.area))
	assert_true(_offered(ODA).is_empty(), "one drop at a time")
	assert_false(WorldState.accept_job(ODA))


func test_the_general_pays_for_his_contraband_and_the_story_waits() -> void:
	var drop := _take(GENERAL)
	var fence: Dictionary = content.get_vendor("fence")
	var fence_pays := int(drop.count) * Inventory.sell_price(content.get_item(str(drop.item)), fence)
	var want := roundi(1.5 * fence_pays)
	assert_gt(want, fence_pays, "he outbids the fence")
	assert_eq(WorldState.repossession_pay(), want, "half again what the fence would have paid")
	assert_eq(int(WorldState.job(GENERAL).pays), want, "and the card said so")
	var c0 := WorldState.credits
	var r0 := int(WorldState.standing.imperial_remnant)
	assert_eq(WorldState.hand_over_contraband(3), want)
	assert_eq(WorldState.credits, c0 + want)
	assert_eq(int(WorldState.standing.imperial_remnant), r0 + 3, "the Remnant likes it")
	assert_false(WorldState.carrying_contraband())
	assert_eq(Story.chapter(), "smuggle_1", "his run is not Oda's: the story waits for hers")
	assert_eq(WorldState.repossession_pay(), 0, "nothing left to hand over")
	assert_false(_offered(ODA).is_empty(), "the next drop can be lined up")


func test_the_general_takes_nothing_from_odas_run() -> void:
	_take(ODA)
	assert_eq(WorldState.repossession_pay(), 0)
	assert_eq(WorldState.hand_over_contraband(3), 0)
	assert_true(WorldState.carrying_contraband())


func test_odas_run_still_moves_the_story() -> void:
	_sell_to_fence(_take(ODA))
	assert_ne(Story.chapter(), "smuggle_1", "her first run sold: the story goes on")


func test_the_pointer_goes_near_the_drop_then_to_whoever_takes_it() -> void:
	assert_true(WorldState.accept_job(ODA))
	var drop := WorldState.smuggle_drop()
	assert_eq(str(Objective.current().target), "drop:" + str(drop.marker), "near the drop, not the gate")
	var near: Array = WorldState.smuggle.near
	var r := Vector2(float(near[0]), float(near[1])).length()
	assert_lte(r, 20.0, "within 20 m of it")
	assert_gt(r, 1.0, "but not on it: the last metres are a search")
	assert_true(WorldState.inventory.pick_up(drop))
	assert_eq(str(Objective.current().target), "marker:" + str(content.get_vendor("fence").marker), "Oda's goods go to the fence")
	_sell_to_fence(drop)
	assert_true(WorldState.accept_job(GENERAL))
	assert_string_contains(str(Objective.current().text), "contraband")
	assert_true(WorldState.inventory.pick_up(WorldState.smuggle_drop()))
	assert_eq(str(Objective.current().target), "npc:general", "his go to him")
	assert_true(Objective.log_entries().any(func(e): return str(e.text).contains("General Vask")), "the log says who takes it")


func test_a_drop_saved_before_the_split_still_goes_to_the_fence() -> void:
	WorldState.smuggle = { "run": 3, "item": "holocrystals", "count": 2, "area": "east_desert", "hint": "out in the sand",
		"marker": "desert_exit", "offset": [28, 0, -22], "ground": true, "out": true, "location": "port_town" }
	assert_eq(WorldState.smuggle_to(), "fence")
	assert_eq(WorldState.smuggle_goods_text(), "2 cases of holocrystals")
	assert_true(_offered(ODA).is_empty(), "the old drop is still out")


func test_his_job_card_matches_what_he_says() -> void:
	WorldState.standing.imperial_remnant = 0
	var b := _brain("general_card")
	b._ids = { "jobs": ["j_general_droids", GENERAL] }
	var v := { "kept": [{ "type": "offer_job", "id": GENERAL }], "dropped": [] }
	b._match_job_offer(v, "Five droids. I need them.")
	assert_eq(str(v.kept[0].id), "j_general_droids", "talking droids: the droid job's card")
	v = { "kept": [{ "type": "offer_job", "id": GENERAL }], "dropped": [] }
	b._match_job_offer(v, "Smugglers stashed contraband on a roof. Repossess it.")
	assert_eq(str(v.kept[0].id), GENERAL, "the right card stays")
	b._ids = { "jobs": [GENERAL] }
	v = { "kept": [{ "type": "offer_job", "id": GENERAL }], "dropped": [] }
	b._match_job_offer(v, "Five droids. I need them.")
	assert_true((v.kept as Array).is_empty(), "the droid job is not on offer: no wrong card")
	assert_eq(str(b.canned_reply("any droid work?").actions[0].id), "j_general_droids")
