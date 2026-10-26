extends GutTest
## M14: the whole loop from the headless trace (scenes/m14_flight_trace.gd, real
## physics, real scenes): board in the pit, lift off, climb out of the atmosphere
## into the space encounter, dive back down into the port's sky, fly a circuit,
## land in the desert and walk, crash and be towed home, land back on the pad.

const Reader := preload("res://tests/trace_reader.gd")
var t: Dictionary


func before_all() -> void:
	t = Reader.read("res://test_results/m14_flight_trace.txt")


func _true(k: String, why: String = "") -> void:
	assert_eq(t.get(k), "true", why if why != "" else k)


func test_trace_exists() -> void:
	assert_false(t.is_empty(), "run scenes/m14_flight_trace.gd first (ci.sh does)")


func test_the_world_is_there() -> void:
	_true("DESERT_BUILT")
	_true("GROUND_IS_THE_DESERT", "the ship lands on the same sand the player walks on")
	assert_eq(int(t.get("DESERT_EXTENT", 0)), 6000)
	assert_gt(int(t.get("LANDMARKS", 0)), 10, "the desert's mesas and hoodoos")
	assert_eq(int(t.get("OUTPOST_BUILDINGS", 0)), 3)
	assert_eq(int(t.get("OUTPOST_IN_SKY_SCENE", 0)), 3)


## The desert's walkable collider follows whoever is on foot. A ship would drag it
## around at 300 m/s, so it stops while you fly and is built ahead of a landing.
func test_the_walkable_ground_follows_the_right_thing() -> void:
	_true("COLLIDER_FOLLOWS_PLAYER_ON_FOOT")
	_true("COLLIDER_STOPS_FOLLOWING_SEATED")
	_true("REENTRY_COLLIDER_NOT_FOLLOWING")
	_true("GROUND_PREFETCHED", "built under the ship while it came down")
	_true("COLLIDER_FOLLOWS_AGAIN")
	assert_eq(int(t.get("SNAPS_ON_EXIT", 9)), 0, "no synchronous rebuild when you get out")


func test_the_pit_ship_is_boarded_not_quick_launched() -> void:
	assert_eq(t.get("PAD_QUICK_LAUNCH"), "false")
	assert_eq(t.get("SHIP_STATE_START"), "PARKED")
	_true("SHIP_AT_HOME")
	_true("CAN_BOARD_FROM_SPAWN", "you start close enough to board")
	assert_eq(t.get("CAN_BOARD_FROM_STREET"), "false")
	_true("BOARD")
	_true("PILOTING")
	_true("PLAYER_HIDDEN")
	_true("HUD_VISIBLE")
	_true("EXIT_WHILE_PARKED_WORKS")
	_true("BOARD_AGAIN")


func test_the_ship_is_solid_parked_and_not_in_flight() -> void:
	_true("PAD_BOX_RETIRED", "the static pad box would stay behind as an invisible wall")
	_true("HULL_SOLID_PARKED")
	_true("HULL_OFF_IN_FLIGHT")
	_true("HULL_SOLID_IN_DESERT")
	_true("SHIP_IS_SOLID", "walking into the parked ship stops you")


func test_liftoff_out_of_the_pit() -> void:
	_true("TAKEOFF")
	assert_between(float(t.get("LIFTOFF_SECONDS", 0)), 2.0, 6.0)
	assert_almost_eq(float(t.get("AGL_AFTER_LIFTOFF", 0)), 18.0, 0.5)
	_true("HOVERS_AT_ZERO_THROTTLE")


func test_takeoff_to_space_takes_15_to_22_seconds() -> void:
	assert_between(float(t.get("SPACE_SECONDS", 0)), 15.0, 22.0, "half-height atmosphere: about 15-22 s from takeoff to space")
	assert_eq(int(t.get("SPACE_ALTITUDE", 0)), 4000)
	assert_gt(int(t.get("TOP_SPEED_IN_CLIMB", 0)), 300, "thin air: much faster near the top")


func test_space_takes_the_hand_off() -> void:
	assert_eq(t.get("SCENE_AFTER_CLIMB"), "res://scenes/flight/dogfight_demo.tscn")
	assert_eq(t.get("FLOW_MODE"), "ascent")
	assert_eq(t.get("FLOW_ENCOUNTER"), "orbital_skirmish")
	assert_eq(t.get("SPACE_ENCOUNTER"), "orbital_skirmish", "the space battle is the pad's encounter")


func test_diving_at_the_planet_comes_back_flying() -> void:
	assert_eq(t.get("SCENE_AFTER_DIVE"), "res://scenes/town_demo.tscn")
	assert_eq(t.get("ARRIVAL_MODE"), "reentry")
	assert_eq(t.get("ARRIVAL_OUTCOME"), "left", "left before the fight was won: no payout")
	_true("REENTRY_PILOTING", "you arrive in the cockpit")
	assert_eq(t.get("REENTRY_STATE"), "FLYING")
	assert_gt(int(t.get("REENTRY_ALTITUDE", 0)), 2000)
	assert_between(float(t.get("DIVE_TO_PORT_SECONDS", 0)), 5.0, 90.0)


func test_flying_around_the_map() -> void:
	_true("CIRCUIT_OK", "over the town, out past the outpost and the hoodoos, back")
	assert_gt(int(t.get("CIRCUIT_MAX_DISTANCE", 0)), 2000, "kilometres out into the desert")
	assert_gt(int(t.get("CIRCUIT_TOP_SPEED", 0)), 100)
	assert_gt(int(t.get("CIRCUIT_MIN_AGL", 0)), 20, "never scraped the ground on the way")


func test_land_in_the_desert_and_walk() -> void:
	_true("APPROACH_OK")
	_true("CAN_LAND")
	_true("LAND")
	assert_eq(t.get("LANDED_STATE"), "PARKED")
	assert_gt(int(t.get("LANDED_DISTANCE_FROM_TOWN", 0)), 300)
	_true("LANDED_ON_GROUND")
	_true("EXIT_IN_DESERT")
	_true("PLAYER_ON_DESERT")
	_true("PLAYER_ON_TERRAIN_HEIGHT")
	_true("WALKED_ON_DESERT")
	_true("REBOARD_IN_DESERT")


func test_a_crash_tows_the_ship_home() -> void:
	_true("CRASHED")
	assert_eq(t.get("CRASHED_INTO"), "mesa_1500_1700")
	_true("TOWED_HOME")
	_true("HULL_SOLID_AFTER_TOW")
	_true("ON_FOOT_AFTER_CRASH")
	_true("BESIDE_THE_SHIP")


func test_land_back_on_the_pad() -> void:
	_true("FLEW_HOME")
	_true("LAND_ON_PAD")
	assert_lt(float(t.get("PAD_LANDING_ERROR_M", 99)), 12.0)
	_true("ON_PIT_FLOOR")
	_true("EXIT_AT_PAD")
	_true("FINAL_ON_FLOOR")
	_true("FINAL_IN_PIT")


func test_a_jetpack_over_the_wall_lands_on_the_desert() -> void:
	_true("JETPACK_OVER_WALL")
	_true("JETPACK_LANDED_ON_DESERT")
	_true("JETPACK_NO_RESCUE_NEEDED", "there is ground out there now")


func test_no_frame_over_budget() -> void:
	assert_lt(float(t.get("WORST_MS", 999)), 50.0)
