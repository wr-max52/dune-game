extends GutTest
## The general in the barracks yard: he and his guard are garrison troopers, so
## they can be shot and they fight on the town alarm; killed there he stays dead,
## and Oda's bounty goes on someone else. Headless (no look layer, so no droid).

const TownDemo := preload("res://scenes/town_demo.gd")


func before_each() -> void:
	WorldState.new_game(WorldState.STORY)
	Story.skip_to("smuggle_1")


func after_each() -> void:
	WorldState.reset()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _town() -> Node:
	var t = TownDemo.new()
	t.use_look = false
	t.npc_brains = true
	add_child_autofree(t)
	return t


func test_the_barracks_squad_are_garrison_troopers_who_fight_on_the_alarm() -> void:
	var t = _town()
	var gp: GeneralPost = t.general_post
	assert_eq(GeneralPost.station(), "barracks")
	assert_true(gp.body is NpcBody, "a soldier, not a prop")
	assert_true(gp.guard is NpcBody)
	assert_eq((gp.body as NpcBody).display_name, gp.npc_name())
	assert_true(t.garrison.brains.has(gp.body), "in the town's garrison")
	assert_true(t.garrison.brains.has(gp.guard))
	assert_true(gp._can_talk(), "at peace he talks")
	t.garrison._raise("test")
	t.garrison._order_brains()
	assert_eq(t.garrison.brains[gp.body].state, GuardBrain.State.COMBAT, "the alarm: he fights")
	assert_eq(t.garrison.brains[gp.guard].state, GuardBrain.State.COMBAT)
	assert_false(gp._can_talk(), "no talking in a fight")


func test_killed_at_the_barracks_he_stays_dead_and_the_bounty_goes_elsewhere() -> void:
	var t = _town()
	var gp: GeneralPost = t.general_post
	var corpse: NpcBody = gp.body
	var guard: NpcBody = gp.guard
	corpse.apply_damage(99999.0)
	assert_true(corpse.dead)
	assert_true(WorldState.has_flag("general_dead"))
	assert_true(t.respawn_rule(corpse).is_empty(), "he never comes back")
	gp._place()
	assert_null(gp.body)
	assert_true(is_instance_valid(corpse), "the body stays where it fell")
	assert_true(is_instance_valid(guard) and not guard.dead, "his guard fights on")
	Story.skip_to("bounty")
	WorldState.standing.imperial_remnant = -40
	WorldState.job("j_bounty")
	assert_false(bool(WorldState.bounty.get("general", false)), "the contract is on an officer")
	assert_ne(str(WorldState.bounty.name), gp.npc_name())
	assert_string_contains(EndCard.text(), "general dead")


func test_a_contract_rolled_on_him_goes_to_an_officer_when_he_dies_first() -> void:
	Story.skip_to("bounty")
	WorldState.standing.imperial_remnant = -15
	WorldState.job("j_bounty")
	assert_true(bool(WorldState.bounty.get("general", false)))
	WorldState.on_general_killed()
	assert_true(WorldState.accept_job("j_bounty"))
	assert_false(bool(WorldState.bounty.get("general", false)))
	assert_eq(str(WorldState.bounty.state), "out")
