extends GutTest
## Issue #45: the trip the issue asks for, from the headless trace
## (scenes/planets_trace.gd, real physics, the real town scene): port -> space ->
## the asteroid station (issue #99: no fade, a real ball, a sealed round station:
## ring wall, dome, gate shield, windowed hallway to the pit; its own Oda) -> Z
## lands you in the pit -> out through the gate, down the hallway into the pit,
## onto the rock and round the ball, into the glass -> home, no fade either way.

const Reader := preload("res://tests/trace_reader.gd")
var t: Dictionary


func before_all() -> void:
	t = Reader.read("res://test_results/planets_trace.txt")


func _true(k: String, why: String = "") -> void:
	assert_eq(t.get(k), "true", why if why != "" else k)


func test_trace_exists() -> void:
	assert_false(t.is_empty(), "run scenes/planets_trace.gd first (ci.sh does)")


func test_the_station_hangs_in_the_ports_sky() -> void:
	assert_eq(t.get("HOME_PLANET"), "port_desert")
	assert_eq(t.get("HOME_TOWN"), "port_town", "the port is still the hand-built town")
	assert_eq(t.get("HOME_NEIGHBOURS"), "grit_station")
	assert_ne(str(t.get("STATION_NAME_IN_PORT_SKY", "")), "")
	assert_between(float(t.get("STATION_DISTANCE_FROM_PAD_KM", 0)), 8.0, 20.0, "a nearby hop")


func test_flying_into_it_travels() -> void:
	assert_gt(float(t.get("FLEW_TO_STATION_S", -1)), 0.0, "reached it")
	assert_lt(float(t.get("FLEW_TO_STATION_S", 999)), 120.0)
	assert_eq(t.get("TRAVEL_STARTED"), "grit_station")
	assert_eq(t.get("SCENE_AFTER_TRAVEL"), "res://scenes/town_demo.tscn", "the same scene, another planet")
	assert_eq(t.get("PLANET_AFTER_TRAVEL"), "grit_station")
	assert_eq(t.get("ARRIVAL_MODE"), "handoff", "no fade: the station's scene took over in mid-flight")
	assert_eq(t.get("FLOWN_SHIP"), t.get("PORT_SHIP"))


func test_a_size_1_asteroid_town() -> void:
	assert_eq(t.get("STATION_TOWN"), "grit_station_town")
	_true("STATION_TOWN_VALID")
	assert_eq(int(t.get("STATION_TOWN_SIZE", 0)), 1)
	assert_eq(t.get("STATION_GROUND"), "ball", "a real ball, like the home planet")
	_true("STATION_ROCK")
	_true("STATION_TERRAIN", "its rock is a PlanetTerrain all the way round")
	assert_eq(t.get("STATION_STYLE"), "metallic")
	_true("STATION_CANTINA")
	assert_eq(int(t.get("STATION_GUARDS", 0)), 1, "a single Remnant guard")
	_true("GUARD_AT_CANTINA_DOOR")
	_true("MERCHANT_IN_FRONT", "the merchant is in front of the cantina")
	_true("STATION_STAGE", "the cantina has a stage")
	assert_gte(int(t.get("STATION_ROAMERS", 0)), 3, "locals walking the street")
	assert_gte(int(t.get("STATION_LOCALS", 0)), 4, "and the merchant")
	_true("STATION_PIT_OUTSIDE", "the landing pit is outside the walls")
	assert_eq(int(t.get("STATION_BUILDINGS", 9)), 0, "nothing else")
	assert_ne(str(t.get("STATION_NAME", "")), "")
	assert_eq(t.get("STATION_NAME"), t.get("STATION_NAME_IN_PORT_SKY"), "one name everywhere")
	assert_ne(str(t.get("STATION_TOWN_NAME", "")), "")


func test_its_own_oda() -> void:
	assert_eq(t.get("STATION_OWNER_CARD"), "", "no hand-written card")
	assert_eq(t.get("STATION_OWNER_PLANET"), "grit_station")
	assert_eq(t.get("STATION_OWNER_ID"), "cantina_owner_grit_station", "her own brain")
	assert_true(str(t.get("STATION_OWNER_NAME", "")).begins_with("Oda "), "a new Oda")
	assert_ne(t.get("STATION_OWNER_NAME"), "Oda Vell")
	_true("STATION_OWNER_KNOWS_PLANET", "the planet's name is in her prompt")
	assert_eq(t.get("STATION_OWNER_LOOK"), "cantina_owner_station", "a variation of Oda")


func test_you_arrive_flying_the_same_ship() -> void:
	_true("ARRIVED_PILOTING")
	assert_eq(t.get("ARRIVED_STATE"), "FLYING")
	assert_eq(t.get("ARRIVED_SHIP"), t.get("PORT_SHIP"))
	assert_between(int(t.get("ARRIVED_ALTITUDE", 0)), 2300, 2800, "where the handoff happened, in its space")
	assert_eq(int(t.get("STATION_SPACE_ALTITUDE", 0)), 700, "a small rock: space starts low")
	assert_eq(t.get("STATION_NEIGHBOURS"), "port_desert", "and home is in its sky")


func test_z_lands_you_in_the_pit() -> void:
	_true("NEAR_BAY")
	_true("BAY_LAND", "Z near the bay")
	assert_eq(t.get("LANDED_STATE"), "PARKED")
	_true("LANDED_IN_PIT")
	assert_lt(float(t.get("LANDED_FROM_BAY_M", 99)), 1.0, "on its own pad")
	_true("EXIT_AT_STATION")
	_true("IN_PIT")


func test_the_station_is_sealed() -> void:
	assert_gt(float(t.get("STATION_RING_M", 0)), 20.0, "a round wall round the town")
	_true("THROUGH_THE_SHIELD", "the gate's shield is walked through")
	_true("HALL_HOLDS", "the hallway's windows are solid")
	_true("INTO_PIT_THROUGH_SHIELD", "down the hallway, out through its round shield")
	_true("GLASS_HOLDS", "the dome holds people")
	_true("SHIP_HITS_GLASS", "and ships")
	assert_gt(int(t.get("DOME_TRIS", 0)), 100, "a dome")


func test_a_real_ball() -> void:
	assert_eq(int(t.get("ROCK_BALL_RADIUS", 0)), 1500)
	_true("WALK_ON_ROCK", "the asteroid is ground")
	_true("WALK_ROUND_THE_BALL", "all the way round")
	assert_lt(float(t.get("FAR_SIDE_UP_Y", 1)), -0.5, "up turns with it")


func test_and_home_again() -> void:
	assert_gt(float(t.get("FLEW_HOME_S", -1)), 0.0)
	assert_eq(t.get("PLANET_AFTER_RETURN"), "port_desert")
	assert_eq(t.get("HOME_AGAIN_TOWN"), "port_town")
	_true("HOME_AGAIN_PILOTING")
	_true("HOME_AGAIN_FROM_STATION_SIDE", "arriving from where the station is")
	_true("STATION_NAME_SAME")


func test_no_frame_over_budget() -> void:
	assert_lt(float(t.get("WORST_MS", 999)), 50.0)
