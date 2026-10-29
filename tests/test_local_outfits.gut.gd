extends GutTest
## Locals wear one rigged model split into head, torso and legs, and each part gets
## its own colour (CharacterKit._wear_outfit). Model: assets/characters/local/local.glb
## (tools/look/prep_character.gd, split); colours: tools/look/recolor_parts.gd.

const PARTS := ["head", "torso", "legs"]

var kit: CharacterKit


func before_each() -> void:
	kit = CharacterKit.new(LookMaterials.new())


func _part(c: Node3D, part: String) -> MeshInstance3D:
	var skin: SkinnedBody = c.get_meta("skin")
	return skin.model.find_child(part, true, false) as MeshInstance3D


func test_local_wears_the_split_model() -> void:
	var c := kit.build("local")
	assert_true(c.has_meta("skin"), "local has a model in characters.json")
	if c.has_meta("skin"):
		var skin: SkinnedBody = c.get_meta("skin")
		for p in PARTS:
			var mi := _part(c, p)
			assert_not_null(mi, "part mesh: " + p)
			if mi != null:
				assert_not_null(mi.skin, p + " is skinned")
				assert_eq(mi.get_node(mi.skeleton), skin.skeleton, p + " shares the one skeleton")
	c.free()


func test_every_listed_colour_has_a_texture() -> void:
	var model: Dictionary = kit.palettes.local.model
	for p in model.parts:
		for color in model.parts[p]:
			if color != "sand":
				assert_true(ResourceLoader.exists(str(model.colors) % color), "texture for " + color)


func test_outfit_picks_each_parts_colour() -> void:
	var c := kit.build("local", "", { "head": "blue", "torso": "red", "legs": "sand" })
	assert_eq(c.get_meta("outfit"), { "head": "blue", "torso": "red", "legs": "sand" })
	var head := _part(c, "head").get_surface_override_material(0) as BaseMaterial3D
	var torso := _part(c, "torso").get_surface_override_material(0) as BaseMaterial3D
	assert_string_contains(head.albedo_texture.resource_path, "local_blue")
	assert_string_contains(torso.albedo_texture.resource_path, "local_red")
	assert_null(_part(c, "legs").get_surface_override_material(0), "sand is the model's own texture")
	c.free()


func test_locals_share_materials_per_colour() -> void:
	var a := kit.build("local", "", { "head": "yellow" })
	var b := kit.build("local", "", { "torso": "yellow" })
	assert_same(_part(a, "head").get_surface_override_material(0), _part(b, "torso").get_surface_override_material(0))
	a.free()
	b.free()


func test_random_locals_mix_parts() -> void:
	kit.rng.seed = 11
	var seen := {}
	var mixed := 0
	for i in 20:
		var c := kit.build("local")
		var o: Dictionary = c.get_meta("outfit")
		seen[str(o)] = true
		if o.head != o.torso or o.torso != o.legs:
			mixed += 1
		c.free()
	assert_gt(seen.size(), 12, "twenty locals are mostly different")
	assert_gt(mixed, 10, "parts are picked on their own")


func test_cantina_dancer_layers_local_white_top_and_owner_legs() -> void:
	var c := kit.build("cantina_dancer", "", {
		"head": "lighter", "torso": "lighter", "legs": "cantina_owner:slate",
	})
	assert_true(c.has_meta("skins"), "the composite appearance keeps both rigged layers")
	if c.has_meta("skins"):
		var skins: Array = c.get_meta("skins")
		assert_eq(skins.size(), 2)
		var local_skin: SkinnedBody = skins[0]
		var legs_skin: SkinnedBody = skins[1]
		var local_legs := local_skin.model.find_child("legs", true, false) as MeshInstance3D
		var owner_legs := legs_skin.model.find_child("cantina_owner_legs", true, false) as MeshInstance3D
		assert_not_null(local_skin.model.find_child("head", true, false))
		assert_not_null(local_skin.model.find_child("torso", true, false))
		assert_false(local_legs.visible, "the original local legs are hidden")
		assert_true(owner_legs.visible, "cantina-owner legs replace them")
		var head_mat := (local_skin.model.find_child("head", true, false) as MeshInstance3D).get_surface_override_material(0) as BaseMaterial3D
		assert_string_contains(head_mat.albedo_texture.resource_path, "local_lighter")
		var legs_mat := owner_legs.get_surface_override_material(0) as BaseMaterial3D
		assert_string_contains(legs_mat.albedo_texture.resource_path, "cantina_owner_legs_slate")
	c.free()
