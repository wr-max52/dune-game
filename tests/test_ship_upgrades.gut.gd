extends GutTest
## Issue #207: T-89 fits boosted shields, a reinforced hull and booster speed to
## any ship you own, one of each per ship, kept in the save.

const CoreContent := preload("res://src/systems/dataload/core_content.gd")
const ShipDefense := preload("res://src/systems/flight/ship_defense.gd")
const Dogfight := preload("res://src/systems/flight/dogfight.gd")

var s: ShipSalesman
var content


func before_each() -> void:
	WorldState.reset()
	WorldState.hangar = "courier"        # bought from him: on his pad (no town, so not parked)
	WorldState.credits = 5000
	s = ShipSalesman.new()
	add_child_autofree(s)
	content = CoreContent.new()
	content.load_from()


func after_each() -> void:
	WorldState.reset()


func test_he_fits_each_upgrade_once_to_a_ship_you_own() -> void:
	assert_true(s.shop_options().any(func(o): return o.id == "fit:courier:shields"))
	assert_eq(s.fit("courier", "shields"), "fitted")
	assert_eq(WorldState.credits, 5000 - ShipUpgrades.price("shields"))
	assert_eq(s.fit("courier", "shields"), "", "one-time")
	assert_eq(s.fit("interceptor", "hull"), "", "not your ship")
	WorldState.credits = 10
	assert_eq(s.fit("courier", "boost"), "cant_afford")


func test_the_stats_change_in_the_air_and_in_space() -> void:
	var base: Dictionary = content.get_ship("courier")
	s.fit("courier", "hull")
	s.fit("courier", "boost")
	var up := ShipUpgrades.apply(base, "courier")
	assert_eq(ShipDefense.new(up).hull.max_hp, int(int(base.hull) * 1.5), "reinforced hull")
	var air := AtmoFlight.new()
	air.setup(up, null)
	assert_almost_eq(air.flight.boost_speed(), float(base.atmosphere.boost_speed) * 1.25, 0.01, "booster speed")
	var df := Dogfight.new(content)
	var me: Dictionary = df.get_ship(df.spawn_ship("courier", "player", Vector3.ZERO, Vector3.FORWARD, "", true))
	assert_almost_eq(float(me.cfg.flight.boost_speed), float(base.flight.boost_speed) * 1.25, 0.01, "in space too")
	var them: Dictionary = df.get_ship(df.spawn_ship("courier", "remnant", Vector3.ZERO, Vector3.FORWARD))
	assert_eq(them.cfg.hull, base.hull, "nobody else's courier")


func test_upgrades_are_saved_and_listed() -> void:
	s.fit("courier", "shields")
	WorldState.from_save(WorldState.to_save())
	assert_true(ShipUpgrades.has("courier", "shields"))
	assert_string_contains(ShipUpgrades.owned_lines()[0], "boosted shields")
	assert_true(Objective.log_entries().any(func(e): return e.title == Objective.line("log_ships")))


func test_the_frigate_takes_the_paint_of_its_last_upgrade() -> void:
	WorldState.hangar = "freighter"
	assert_eq(ShipUpgrades.look("freighter", "freighter"), "freighter", "stock paint")
	s.fit("freighter", "hull")
	s.fit("freighter", "boost")
	assert_eq(ShipUpgrades.look("freighter", "freighter"), "freighter_boost", "the last one fitted")
	assert_eq(ShipUpgrades.apply(content.get_ship("freighter"), "freighter").look, "freighter_boost")
	assert_eq(content.get_ship("freighter").look, "freighter", "the ship's own data stays stock")
	assert_eq(ShipUpgrades.look("remnant_freighter", "freighter_dark"), "freighter_dark", "no paint job: unchanged")
	var kit := ShipKit.new()
	var ship := kit.build("freighter")
	add_child_autofree(ship)
	kit.repaint(ship, "freighter_shields")
	assert_eq(str(ship.get_meta("look_id")), "freighter_shields")
	assert_not_null(ship.get_node_or_null("Model"), "the recoloured model is in")
