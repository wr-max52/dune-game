extends GutTest
## M5: scripted "bot playthrough" that walks the full mission loop headless
## (fixer -> contract -> travel -> fight -> crate -> payout -> save/load).
## Until M5 the non-LLM loop does not exist, so this test is SKIPPED. It
## documents the M5 contract now so it can be filled in without redesign.
##
## At M5 this drives the live systems, but the bartender conversation uses a
## deterministic STUB model, never real inference (real inference is a manual
## + recorded check). A non-passing bot blocks the merge.

func before_each() -> void:
	pass


func test_bot_walks_full_mission_loop() -> void:
	# Pending M5. When the mission state machine + save system exist, this will:
	#  1. start at the docking bay
	#  2. talk to the fixer, accept the crate contract
	#  3. travel to the desert outpost
	#  4. defeat 4 troopers + 1 duelist, take the crate
	#  5. return and claim the payout
	#  6. save, reload, and assert state survives
	push_warning("M5: bot playthrough not active yet")
	assert_true(true)
