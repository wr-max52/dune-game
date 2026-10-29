extends GutTest
## Locals wear the kit's "local" pieces (head, torso and legs, fitted onto the base
## body with the rest of the library: tools/look/fit_parts.gd, dress), and each part
## gets its own colour (CharacterKit._wear_outfit). Colours: tools/look/recolor_parts.gd.

const PARTS := ["head", "torso", "legs"]

var kit: CharacterKit


func before_each() -> void:
	kit = CharacterKit.new(LookMaterials.new())


func _part(c: Node3D, part: String) -> MeshInstance3D:
	var skin: SkinnedBody = c.get_meta("skin")
	return skin.model.find_child("local_" + part, true, false) as MeshInstance3D


func test_local_wears_the_kit_pieces() -> void:
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
		assert_eq(skin.model.find_children("*", "MeshInstance3D", true, false).size(), 3, "only the worn pieces are left")
	c.free()


func test_every_listed_colour_has_a_texture() -> void:
	var model: Dictionary = kit.palettes.local.model
	for p in model.parts:
		for choice in model.parts[p]:
			var pc := str(choice).split(":")
			if pc.size() == 2:
				assert_true(ResourceLoader.exists(str(model.colors) % ("%s_%s" % [pc[0], pc[1]])), "texture for " + choice)


func test_outfit_picks_each_parts_colour() -> void:
	var c := kit.build("local", "", { "head": "local:blue", "torso": "local:red", "legs": "local" })
	assert_eq(c.get_meta("outfit"), { "head": "local:blue", "torso": "local:red", "legs": "local" })
	var head := _part(c, "head").get_surface_override_material(0) as BaseMaterial3D
	var torso := _part(c, "torso").get_surface_override_material(0) as BaseMaterial3D
	assert_string_contains(head.albedo_texture.resource_path, "local_blue")
	assert_string_contains(torso.albedo_texture.resource_path, "local_red")
	assert_null(_part(c, "legs").get_surface_override_material(0), "no colour is the piece's own texture")
	c.free()


func test_locals_share_materials_per_colour() -> void:
	var a := kit.build("local", "", { "head": "local:yellow" })
	var b := kit.build("local", "", { "torso": "local:yellow" })
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


func test_locals_are_in_the_character_builder() -> void:
	var cat := PlayerOutfit.catalog()
	for p in PARTS:
		assert_true(cat[p].has("local"), "the builder offers the local " + p)
		assert_eq(cat[p].get("local", []), ["blue", "darker", "lighter", "red", "yellow"], p + " colours")


## Issue: the jacket collar was cut onto the player's head, the owner's breathing
## hoses onto her upper body (fit_parts.gd, dress move). Each now stays with its piece.
func test_seams_keep_collar_on_the_jacket_and_hoses_on_the_helmet() -> void:
	var p := kit.build("player_smuggler")
	var jacket := _box(p, "player_torso")
	var skin: SkinnedBody = p.get_meta("skin")
	var arr := (skin.model.find_child("player_head", true, false) as MeshInstance3D).mesh.surface_get_arrays(0)
	p.free()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var ring := 0
	var chin := 0
	for t in range(0, idx.size(), 3):
		var c := (v[idx[t]] + v[idx[t + 1]] + v[idx[t + 2]]) / 3.0
		if c.y < 0.69:
			if c.z < 0.06:
				ring += 1
			else:
				chin += 1
	assert_eq(ring, 0, "the collar ring is not left on the head")
	assert_gt(chin, 20, "the bandana's chin stays on the head")
	var o := kit.build("cantina_owner")
	var helmet := _box(o, "cantina_owner_head")
	var tunic := _box(o, "cantina_owner_torso")
	o.free()
	assert_gt(jacket.end.y, 0.7, "the collar stands up from the jacket")
	assert_lt(tunic.end.y, 0.68, "no hoses reach up from the tunic")
	assert_gt(helmet.size.x, 0.38, "the hoses hang off the helmet")


func _box(c: Node3D, mesh: String) -> AABB:
	var skin: SkinnedBody = c.get_meta("skin")
	return (skin.model.find_child(mesh, true, false) as MeshInstance3D).mesh.get_aabb()


func test_cantina_dancer_renders_player_body_owner_legs_and_guard_head() -> void:
	var c := kit.build("cantina_dancer", "", {
		"head": "guard:desert", "torso": "player:sand", "legs": "cantina_owner:slate",
	})
	assert_true(c.has_meta("skin"), "the dancer wears the rigged kit model")
	var skin: SkinnedBody = c.get_meta("skin")
	var meshes := skin.model.find_children("*", "MeshInstance3D", true, false)
	assert_eq(meshes.size(), 3, "exactly head, torso and legs are left")
	for want in ["guard_head", "player_torso", "cantina_owner_legs"]:
		var mi := skin.model.find_child(want, true, false) as MeshInstance3D
		assert_not_null(mi, want)
		if mi != null:
			assert_true(mi.visible and mi.mesh != null and mi.mesh.get_surface_count() > 0, want + " renders")
			assert_not_null(mi.skin, want + " is skinned")
	c.free()
