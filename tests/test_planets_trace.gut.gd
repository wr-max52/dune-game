extends GutTest
## Issue #45: the trip the issue asks for, from the headless trace
## (scenes/planets_trace.gd, real physics, the real town scene): port -> space ->
## the asteroid station (a size-1 town on a platform, its own cantina owner) ->
## out through the shield, over the edge, into the glass -> home.

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
	assert_eq(t.get("ARRIVAL_MODE"), "travel")
	assert_eq(t.get("FLOWN_SHIP"), t.get("PORT_SHIP"))


func test_a_size_1_asteroid_town() -> void:
	assert_eq(t.get("STATION_TOWN"), "grit_station_town")
	_true("STATION_TOWN_VALID")
	assert_eq(int(t.get("STATION_TOWN_SIZE", 0)), 1)
	assert_eq(t.get("STATION_GROUND"), "platform")
	_true("STATION_PLATFORM")
	assert_eq(t.get("STATION_TERRAIN"), "false", "no dunes under a station")
	assert_eq(t.get("STATION_STYLE"), "metallic")
	_true("STATION_CANTINA")
	assert_eq(int(t.get("STATION_GUARDS", 0)), 1, "a single Remnant guard")
	_true("GUARD_AT_CANTINA_DOOR")
	_true("MERCHANT_OUT_BACK")
	assert_eq(int(t.get("STATION_BUILDINGS", 9)), 0, "nothing else")
	assert_ne(str(t.get("STATION_NAME", "")), "")
	assert_eq(t.get("STATION_NAME"), t.get("STATION_NAME_IN_PORT_SKY"), "one name everywhere")
	assert_ne(str(t.get("STATION_TOWN_NAME", "")), "")


func test_its_own_cantina_owner() -> void:
	assert_eq(t.get("STATION_OWNER_CARD"), "npcs/station_owner_card.json")
	assert_eq(t.get("STATION_OWNER_LOOK"), "cantina_owner_station", "a variation of Oda")


func test_you_arrive_flying_the_same_ship() -> void:
	_true("ARRIVED_PILOTING")
	assert_eq(t.get("ARRIVED_STATE"), "FLYING")
	assert_eq(t.get("ARRIVED_SHIP"), t.get("PORT_SHIP"))
	assert_between(int(t.get("ARRIVED_ALTITUDE", 0)), 300, 700, "in its sky, below its edge of space")
	assert_eq(int(t.get("STATION_SPACE_ALTITUDE", 0)), 700, "a small rock: space starts low")
	assert_eq(t.get("STATION_NEIGHBOURS"), "port_desert", "and home is in its sky")


func test_land_on_the_bay_and_walk_the_deck() -> void:
	_true("REACHED_BAY")
	_true("LAND_ON_BAY")
	assert_eq(t.get("LANDED_STATE"), "PARKED")
	_true("LANDED_ON_DECK")
	assert_lt(float(t.get("LANDED_FROM_BAY_M", 99)), 12.0, "on its bay")
	_true("EXIT_AT_STATION")
	_true("ON_DECK")


func test_the_shield_is_walkable_and_the_edge_kills() -> void:
	_true("THROUGH_THE_SHIELD", "the gate is open")
	_true("FELL_OFF")
	assert_eq(int(t.get("FALLS", 0)), 1)
	_true("WOKE_BY_BAY")
	assert_eq(int(t.get("FALL_LOGGED", 0)), 1)


func test_the_glass_is_solid() -> void:
	_true("GLASS_HOLDS", "to people")
	_true("SHIP_HITS_GLASS", "and to ships")
	assert_gt(int(t.get("GLASS_PANES", 0)), 4)


func test_and_home_again() -> void:
	assert_gt(float(t.get("FLEW_HOME_S", -1)), 0.0)
	assert_eq(t.get("PLANET_AFTER_RETURN"), "port_desert")
	assert_eq(t.get("HOME_AGAIN_TOWN"), "port_town")
	_true("HOME_AGAIN_PILOTING")
	_true("HOME_AGAIN_FROM_STATION_SIDE", "arriving from where the station is")
	_true("STATION_NAME_SAME")


func test_no_frame_over_budget() -> void:
	assert_lt(float(t.get("WORST_MS", 999)), 50.0)
