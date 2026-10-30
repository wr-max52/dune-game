extends GutTest
## Issue #96: native peoples and wild animals as data. The home planet's packs
## come from its own config; every generated planet gets its own people and
## animals from its type, the way the planet generator gives it everything else;
## platform and ball planets get none. Food is bought without end at the food
## stall, which buys quartz.

const CoreContent := preload("res://src/systems/dataload/core_content.gd")
var cc


func before_all() -> void:
	cc = CoreContent.new()
	cc.load_from()


func after_each() -> void:
	PlanetGen.clear_cache()
	WorldState.reset()


func test_the_home_planet_has_one_friendly_and_one_hostile_pack() -> void:
	var p := PlanetGen.build("port_desert", cc)
	var n: Dictionary = p.natives
	assert_eq(n.people.id, "dune_nomads")
	var att: Array = n.packs.map(func(x): return str(x.attitude))
	assert_true(att.has("friendly") and att.has("hostile"))
	for pk in n.packs:
		assert_between(int(pk.size), 10, 20, "10 to 20 to a pack")
		assert_gt((pk.route as Array).size(), 1, "a route to walk")
	assert_eq(n.fauna[0].species, "sand_pig")


func test_the_dune_people_are_primitive() -> void:
	var s := NativesData.species("dune_nomads")
	var all: Array = (s.weapons.melee as Array) + (s.weapons.thrown as Array)
	for w in all:
		assert_false(str(w.id).contains("blaster") or str(w.id).contains("rifle"), "melee and thrown only")
	assert_eq(s.trade.wants, ["food"], "they want food")
	assert_eq(s.trade.gives, "quartz")
	assert_almost_eq(float(s.body.child_scale), 0.6, 0.001, "children are the same bodies at 60%")
	assert_almost_eq(float(s.hostile.survive_s), 60.0, 0.1, "issue #211: a minute to win a hostile pack over")


func test_generated_planets_get_their_own_people() -> void:
	var a := PlanetGen.make({ "id": "dune_a", "type": "sand", "town_size": 10, "seed": 3 }, cc)
	var b := PlanetGen.make({ "id": "dune_b", "type": "sand", "town_size": 10, "seed": 4 }, cc)
	assert_false(a.natives.is_empty(), "a sand planet gets natives from its type")
	assert_ne(a.natives.people.id, "dune_nomads", "never the home planet's people")
	assert_ne(a.natives.people.id, b.natives.people.id, "each planet its own")
	assert_gte(a.natives.packs.size(), 2)
	assert_eq(JSON.stringify(PlanetGen.make({ "id": "dune_a", "type": "sand", "town_size": 10, "seed": 3 }, cc).natives.packs),
		JSON.stringify(a.natives.packs), "the same planet, the same packs")
	assert_false(a.natives.fauna.is_empty(), "and animals")


func test_no_natives_where_nobody_could_live() -> void:
	for type in ["water", "lava", "gas", "asteroid"]:
		var p := PlanetGen.make({ "id": "t_" + type, "type": type, "town_size": 5, "seed": 2 }, cc)
		assert_true(p.natives.is_empty(), type)
	var off := PlanetGen.make({ "id": "quiet", "type": "sand", "town_size": 5, "natives": false }, cc)
	assert_true(off.natives.is_empty(), "a planet can say none")


func test_food_never_runs_out_and_quartz_sells() -> void:
	var stall: Dictionary = cc.vendors.get("food_stall", {})
	var food: Dictionary = cc.get_item("food")
	var inv := Inventory.new()
	for i in 5:
		assert_gt(inv.buy("food", food, stall, 100), 0)
	assert_eq(inv.count("food"), 5)
	inv.add("quartz", 1)
	assert_gt(inv.sell("quartz", cc.get_item("quartz"), stall), 0, "the stall buys quartz")


func test_reputation_is_per_pack() -> void:
	var a := WorldState.native_pack("a", "friendly")
	var b := WorldState.native_pack("b", "hostile")
	a.rep = 5
	assert_eq(int(WorldState.native_pack("b").rep), 0)
	assert_false(bool(b.friendly))
	WorldState.change_standing("imperial_remnant", 50)
	assert_false(bool(WorldState.native_pack("b").friendly), "Remnant standing changes nothing")
