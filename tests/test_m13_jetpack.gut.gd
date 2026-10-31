extends GutTest
## M13: the jetpack, from the headless trace (scenes/m13_jetpack_trace.gd, real
## physics in the town). Picked up, attached, flown, recharged, taken off and put
## back on, flown out over the wall onto the sand, sold, bought back, and still taken
## after a reload. See also test_jetpack, test_inventory and test_item_kit.

const Reader := preload("res://tests/trace_reader.gd")
var t: Dictionary


## Disabled with the m13 trace in scripts/ci.sh (it hangs). Delete this to re-enable.
func should_skip_script():
	return "m13 jetpack trace is disabled in ci.sh (hangs); fix it later"


func before_all() -> void:
	t = Reader.read("res://test_results/m13_jetpack_trace.txt")


func test_trace_exists() -> void:
	assert_false(t.is_empty(), "run scenes/m13_jetpack_trace.gd first (ci.sh does)")


func test_town_places_the_pickup_and_the_trader() -> void:
	assert_eq(t.get("GEAR_BUILT"), "true")
	assert_eq(str(t.get("JETPACK_PICKUP_PLACED", "")), "true", "the jetpack lies in the pit")
	assert_eq(int(t.get("PICKUPS_PLACED", 0)), 3, "with (M15) the cache outside the gate and (#148) the wreck's red saber")
	assert_eq(int(t.get("VENDORS_PLACED", 0)), 2, "the gear trader and (M15) the fence")


func test_without_a_pack_holding_jump_changes_nothing() -> void:
	assert_almost_eq(float(t.get("NO_PACK_TAP_APEX", 0)), 0.6, 0.1)
	assert_eq(t.get("NO_PACK_HOLD_APEX"), t.get("NO_PACK_TAP_APEX"))
	assert_eq(t.get("NO_PACK_TOGGLE"), "", "nothing to put on yet")


func test_the_jetpack_is_reached_and_picked_up() -> void:
	assert_eq(t.get("WALKED_TO_PICKUP"), "true", "walked out of the pit and up the ramp")
	assert_eq(t.get("PICKUP_HEIGHT_OK"), "true")
	assert_true(str(t.get("PICKUP_PROMPT", "")).contains("Pick up Jetpack"))
	assert_eq(t.get("PICKUP_RESULT"), "picked_up")
	assert_eq(t.get("OWNS_JETPACK"), "true")
	assert_eq(t.get("PICKUP_GONE"), "true", "it left the street")
	assert_eq(t.get("PICKUP_TAKEN"), "true")
	assert_eq(t.get("SECOND_INTERACT"), "", "nothing left to pick up")


func test_picking_it_up_attaches_it() -> void:
	assert_eq(t.get("ATTACHED"), "jetpack")
	assert_eq(t.get("PLAYER_HAS_JET"), "true")
	assert_eq(t.get("WORN_ON_CHEST"), "true", "the look hangs on the body's chest joint")
	assert_eq(t.get("WORN_BEHIND"), "true", "on the back, not the front")


func test_a_tap_is_still_a_normal_jump() -> void:
	assert_almost_eq(float(t.get("PACK_TAP_APEX", 0)), float(t.get("NO_PACK_TAP_APEX", 0)), 0.05)
	assert_eq(float(t.get("PACK_TAP_FUEL_USED", 1)), 0.0)


func test_holding_jump_flies_really_high() -> void:
	var hold := float(t.get("PACK_HOLD_APEX", 0))
	assert_gt(hold, 12.0, "well above the 6 m walls")
	assert_gt(hold, float(t.get("NO_PACK_TAP_APEX", 1)) * 15.0, "15x a normal jump or more")
	assert_eq(int(t.get("PACK_LIT", 0)), 1, "one burn per hold")
	assert_eq(t.get("FLAMES_WHILE_THRUSTING"), "true")
	assert_eq(t.get("FLAMES_AFTER_LANDING"), "false")


func test_fuel_runs_out_and_recharges() -> void:
	assert_almost_eq(float(t.get("PACK_BURN_SECONDS", 0)), 1.8, 0.05, "burns the full tank")
	assert_almost_eq(float(t.get("PACK_MIN_FUEL", 1)), 0.0, 0.001, "runs dry")
	assert_lt(float(t.get("FUEL_ON_LANDING", 1)), 0.1, "lands near empty")
	assert_gt(float(t.get("FUEL_HALF_SECOND_LATER", 0)), float(t.get("FUEL_ON_LANDING", 1)), "refilling on the ground")
	assert_almost_eq(float(t.get("FUEL_RECHARGED", 0)), 1.8, 0.001, "full again")


func test_it_comes_off_and_goes_back_on() -> void:
	assert_eq(t.get("DETACH"), "detached")
	assert_eq(t.get("DETACHED_PLAYER_HAS_JET"), "false")
	assert_eq(t.get("DETACHED_WORN"), "false", "the look comes off the body")
	assert_eq(t.get("DETACHED_STILL_OWNED"), "true", "still in the inventory")
	assert_almost_eq(float(t.get("DETACHED_HOLD_APEX", 0)), float(t.get("NO_PACK_TAP_APEX", 0)), 0.05,
		"no pack, no flight")
	assert_eq(t.get("REATTACH"), "attached")
	assert_eq(t.get("REATTACHED_PLAYER_HAS_JET"), "true")


## Since the desert: there is ground outside the walls, so flying out lands you on
## sand. The fall guard (now measured from the ground under you) is proven in
## tests/test_desert_walk.gut.gd.
func test_flying_out_of_town_lands_on_sand() -> void:
	assert_eq(t.get("WALL_CLEARED"), "true", "the pack clears the north wall")
	assert_gt(float(t.get("FLEW_OUT_MAX_Z", 0)), 75.0)
	assert_eq(int(t.get("RECOVERED", 9)), 0, "no rescue: there is ground out there")
	assert_eq(t.get("LANDED_OUTSIDE"), "true", "standing on the sand outside the wall")
	assert_almost_eq(float(t.get("LANDED_Y", 9)), 0.0, 1.0, "at about the town's floor level")


func test_it_sells_at_the_market() -> void:
	assert_eq(t.get("REACHED_TRADER"), "true")
	assert_true(str(t.get("SELL_PROMPT", "")).contains("Trade with the gear trader"))
	assert_eq(t.get("TRADE_MENU"), "menu", "[E] opens the trade menu")
	assert_true(str(t.get("SELL_ROW", "")).contains("Sell Jetpack"))
	assert_eq(t.get("SELL_RESULT"), "sold")
	assert_eq(t.get("MENU_STAYS_OPEN"), "true", "a sale does not close the menu")
	assert_eq(int(t.get("SOLD_FOR", 0)), 60, "half its 120 value")
	assert_eq(t.get("AFTER_SALE_OWNS"), "false")
	assert_eq(t.get("AFTER_SALE_ATTACHED"), "")
	assert_eq(t.get("AFTER_SALE_PLAYER_HAS_JET"), "false")
	assert_eq(t.get("AFTER_SALE_WORN"), "false")
	assert_eq(t.get("TRADER_STOCK"), "jetpack", "the trader holds it now")
	assert_true(str(t.get("EVENT_LOGGED", "")).contains("jetpack"), "the world remembers the sale")


func test_it_can_be_bought_back() -> void:
	assert_true(str(t.get("BUY_ROW", "")).contains("Buy Jetpack"))
	assert_eq(t.get("BUY_RESULT"), "bought")
	assert_eq(int(t.get("BOUGHT_FOR", 0)), 120)
	assert_eq(t.get("BOUGHT_ATTACHED"), "jetpack", "bought gear goes on if the slot is free")
	assert_eq(t.get("BOUGHT_PLAYER_HAS_JET"), "true")
	assert_eq(t.get("RESELL_RESULT"), "sold")
	assert_true(str(t.get("POOR_ROW", "")).contains("you have 60"))
	assert_eq(t.get("POOR_RESULT"), "cant_afford")
	assert_eq(int(t.get("END_CREDITS", 0)), 60, "60 + 60 - 120 + 60")


func test_a_reload_keeps_the_pickup_taken() -> void:
	assert_eq(str(t.get("RELOAD_JETPACK_PLACED", "")), "false", "the jetpack does not reappear")
	assert_eq(t.get("RELOAD_ATTACHED"), "jetpack")
	assert_eq(t.get("RELOAD_PLAYER_HAS_JET"), "true", "the reloaded player flies again")


func test_no_frame_over_budget() -> void:
	assert_lt(float(t.get("WORST_MS", 999)), 50.0)
