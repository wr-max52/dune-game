extends GutTest
## Issue #45: the planet generator, pure. Every town size from 1 to 100 passes the
## town validator; sizes scale the way the issue says (50 = the port, 100 = 5x,
## 1 = a cantina, a guard at its door and a merchant out back); every planet type
## builds; the style kit reads presets and plain words; a new planet is a config
## file and nothing else.

const CoreContent := preload("res://src/systems/dataload/core_content.gd")
const TownLayout := preload("res://src/systems/world/town_layout.gd")

var cc


func before_all() -> void:
	cc = CoreContent.new()
	cc.load_from()


func after_each() -> void:
	PlanetGen.clear_cache()
	GameFlow.reset()


func _town(size: int, seed: int = 1) -> TownLayout:
	var t := TownLayout.new()
	t.load_from_dict(TownGen.generate("t%d_%d" % [size, seed], size, seed))
	return t


func test_every_size_from_1_to_100_is_a_valid_town() -> void:
	var bad := PackedStringArray()
	for s in range(1, 101):
		for seed in [1, 45]:
			var errs := _town(s, seed).validate()
			if not errs.is_empty():
				bad.append("size %d seed %d: %s" % [s, seed, errs[0]])
	assert_eq(bad.size(), 0, str(bad.slice(0, 5)))


func test_size_scales_like_the_issue_says() -> void:
	var g := TownGen.new()
	assert_almost_eq(g.area_factor(50), 1.0, 0.001, "50 is the port's scale")
	assert_almost_eq(g.area_factor(100), 5.0, 0.01, "100 is 5x")
	var a50: Dictionary = _town(50).data.bounds
	var a100: Dictionary = _town(100).data.bounds
	var area := func(b): return (float(b.max[0]) - float(b.min[0])) * (float(b.max[1]) - float(b.min[1]))
	assert_between(area.call(a50), 25000.0, 40000.0, "about the port's 200 x 150")
	assert_between(area.call(a100) / area.call(a50), 4.0, 6.0)
	assert_gt(_town(100).boxes().size(), _town(50).boxes().size() * 3)


func test_size_1_is_a_cantina_a_guard_and_a_merchant_out_back() -> void:
	var t := _town(1)
	var counts: Dictionary = t.data.counts
	assert_eq(int(counts.guards), 1)
	assert_eq(int(counts.merchants), 1)
	assert_eq(int(counts.residents), 0)
	assert_eq(int(counts.bays), 1, "and a bay to land on")
	assert_false(t.get_box("bar_counter").is_empty(), "a cantina")
	assert_false(t.get_marker("cantina_owner").is_empty())
	var guards := t.markers_with_role("trooper_post")
	assert_eq(guards.size(), 1)
	assert_lt(_v(guards[0].pos).distance_to(t.marker_pos("cantina_door")), 5.0, "at the cantina door")
	var vendor := t.get_marker("vendor_1")
	assert_lt(float(vendor.pos[0]), float(t.get_box("cantina_wall_w").min[0]), "out back, behind the cantina")
	assert_eq(t.boxes().filter(func(b): return str(b.get("look", "")).begins_with("hut")).size(), 0, "no houses")
	assert_false(t.get_box("ship").is_empty())
	assert_false(t.get_marker("player_spawn").is_empty())


func test_big_towns_have_everything() -> void:
	var t := _town(60)
	assert_gt(t.markers_with_role("trooper_post").size(), 4)
	assert_false(t.get_box("barracks_hall").is_empty())
	assert_false(t.get_box("watchtower").is_empty())
	assert_gt(t.boxes().filter(func(b): return str(b.get("look", "")) == "stall").size(), 8)
	assert_gt(t.routes().size(), 3, "residents strolling")
	assert_eq(t.data.garrison.klaxon_marker, "trooper_tower")


func test_the_same_seed_is_the_same_town() -> void:
	assert_eq(JSON.stringify(TownGen.generate("a", 40, 9)), JSON.stringify(TownGen.generate("a", 40, 9)))
	assert_ne(JSON.stringify(TownGen.generate("a", 40, 9).boxes), JSON.stringify(TownGen.generate("a", 40, 10).boxes))


func test_every_planet_type_builds() -> void:
	var types: Dictionary = PlanetGen.types().types
	assert_eq(types.size(), 7)
	for type in types:
		var p := PlanetGen.make({ "id": "test_" + type, "type": type, "town_size": 12, "seed": 2 }, cc)
		assert_eq(p.type, type)
		assert_false(p.town.is_empty(), type)
		var t := TownLayout.new()
		t.load_from_dict(p.town)
		assert_eq(t.validate().size(), 0, type)
		assert_true(p.ground in ["terrain", "platform"], type)
		assert_gt(float(p.world.atmosphere.space_altitude), 0.0, type)
		if p.ground == "platform":
			assert_true((types[type] as Dictionary).has("surface"), type)
			assert_ne(str(types[type].fall_text), "", type + " says how you died")


func test_the_port_is_unchanged() -> void:
	var p := PlanetGen.build("port_desert", cc)
	assert_eq(p.town_id, "port_town", "the hand-built town")
	assert_eq(p.town.boxes.size(), cc.get_location("port_town").boxes.size())
	assert_eq(p.world.id, "port_desert", "the hand-built world")
	assert_eq(p.ground, "terrain")
	assert_true(TownStyle.parse(p.style).is_identity(), "the port's own look")
	assert_eq(PlanetGen.home_id(), "port_desert")


func test_the_asteroid_station() -> void:
	var p := PlanetGen.build("grit_station", cc)
	assert_eq(p.type, "asteroid")
	assert_eq(p.size, 1)
	assert_eq(p.ground, "platform")
	assert_eq(p.style, "metallic")
	assert_eq(p.encounter, "", "quiet sky over the station")
	assert_eq(p.town.markers.filter(func(m): return m.id == "cantina_owner")[0].card, "npcs/station_owner_card.json")
	assert_eq(p.world.naming.town, "town_station", "a station's name, not a desert town's")
	var n: Array = p.neighbours
	assert_eq(n.size(), 1)
	assert_eq(n[0].id, "port_desert", "you can fly home")
	var home := PlanetGen.build("port_desert", cc)
	assert_eq(home.neighbours.map(func(x): return x.id), ["grit_station"], "and the port sees the station")
	assert_eq(home.neighbours[0].at, Vector3(9000, 5200, -6500))


func test_a_new_planet_is_only_a_config() -> void:
	var p := PlanetGen.make({ "id": "frost_reach", "name": "Frost Reach", "type": "snow", "town_size": 18,
		"style": "pale blue glossy ceramic with gold trim", "near": "port_desert", "at": [-12000, 6000, 4000] }, cc)
	assert_eq(p.type, "snow")
	assert_eq(p.town_id, "frost_reach_town")
	var book := NameBook.new()
	assert_eq(PlanetGen.display_name(p, book), "Frost Reach", "its own name, reserved")
	assert_false(book.name_for("planet", "planet:another") == "Frost Reach")
	var st := TownStyle.parse(p.style)
	assert_eq(st.unknown.size(), 0, str(st.unknown))
	assert_eq(p.neighbours[0].id, "port_desert")


func test_style_presets() -> void:
	assert_true(TownStyle.parse("desert").is_identity())
	assert_true(TownStyle.parse("").is_identity())
	var m := TownStyle.parse("metallic")
	assert_true(m.metal_walls)
	assert_gt(m.metallic, 0.5)
	assert_not_null(m.accent)
	var s := TownStyle.parse("snowy")
	assert_true(s.snow)
	assert_gt((s.wall(Color("#d8c2a0"))).v, 0.85, "white walls")
	var p := TownStyle.parse("pastel")
	assert_eq(p.palette.size(), 6)
	var walls := {}
	for c in [Color("#d8c2a0"), Color("#c9a77c"), Color("#b9a48a"), Color("#e0d0b0"), Color("#a08060")]:
		walls[p.wall(c).to_html()] = true
	assert_gt(walls.size(), 1, "buildings in different colours")


func test_style_words() -> void:
	var r := TownStyle.parse("red matte metal")
	assert_eq(r.unknown.size(), 0)
	assert_true(r.metal_walls)
	assert_almost_eq(r.roughness, 0.95, 0.001, "matte")
	assert_gt((r.main as Color).r, (r.main as Color).g * 1.5, "red")
	var b := TownStyle.parse("pale blue glossy ceramic with gold trim")
	assert_eq(b.unknown.size(), 0)
	assert_false(b.metal_walls)
	assert_almost_eq(b.roughness, 0.25, 0.001)
	assert_gt((b.main as Color).b, (b.main as Color).r)
	assert_gt((b.accent as Color).r, (b.accent as Color).b, "gold trim")
	var odd := TownStyle.parse("purple sparkly metal")
	assert_eq(Array(odd.unknown), ["sparkly"], "an unknown word is reported, not fatal")
	assert_true(odd.metal_walls)


func test_styled_materials_change_and_the_port_does_not() -> void:
	var plain := LookMaterials.new()
	var styled := LookMaterials.new()
	styled.style = TownStyle.parse("red matte metal")
	var a := plain.plaster(0.0, 1.0, LookMaterials.CLOTH_TEAL)
	var b := styled.plaster(0.0, 1.0, LookMaterials.CLOTH_TEAL)
	assert_eq(a.shader, LookMaterials.PLASTER)
	assert_eq(b.shader, LookMaterials.HULL, "metal walls")
	var ident := LookMaterials.new()
	ident.style = TownStyle.parse("desert")
	var c := ident.plaster(0.0, 1.0, LookMaterials.CLOTH_TEAL)
	assert_eq(c.get_shader_parameter("plaster"), a.get_shader_parameter("plaster"), "desert = the port, unchanged")
	var snow := LookMaterials.new()
	snow.style = TownStyle.parse("snowy")
	assert_gt((snow.paving().get_shader_parameter("plaster") as Color).v, 0.85)


func test_game_flow_travel() -> void:
	var went := []
	GameFlow.change_scene = func(p): went.append(p)
	assert_eq(GameFlow.current_planet_id(), "port_desert")
	GameFlow.travel(null, "grit_station", "courier", "Tonve II")
	assert_eq(GameFlow.current_planet_id(), "grit_station")
	assert_eq(GameFlow.flown_ship, "courier")
	assert_eq(GameFlow.arrival.mode, "travel")
	assert_eq(GameFlow.arrival.from, "port_desert")
	assert_eq(went, ["res://scenes/town_demo.tscn"], "the same scene: a planet is data")
	assert_true(GameFlow.arrival_text(GameFlow.arrival).contains("Tonve II"))
	GameFlow.reset()
	assert_eq(GameFlow.current_planet_id(), "port_desert")


func test_the_station_owner_is_her_own_person() -> void:
	var card: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/core/npcs/station_owner_card.json"))
	var oda: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/core/npcs/cantina_owner_card.json"))
	assert_eq(card.keys().size(), oda.keys().size(), "every field Oda's card has")
	assert_eq(card.id, "station_owner")
	assert_ne(card.name, oda.name)
	assert_true(str(card.people).contains("Oda"), "she knows her sister")
	var looks: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/look/characters.json")).archetypes
	assert_eq(looks.cantina_owner_station.base, "cantina_owner", "Oda's body, re-tinted")
	assert_true(looks.cantina_owner_station.model.has("tint"))
	assert_true(NameBook.new().is_taken(card.name), "her name is reserved")


static func _v(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
