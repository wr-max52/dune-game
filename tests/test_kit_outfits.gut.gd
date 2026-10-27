extends GutTest
## The player and the guards wear kit pieces: one model with several pieces of every
## part on one skeleton (assets/characters/kit/parts.glb, tools/look/fit_parts.gd,
## dress). Each part shows one chosen piece (CharacterKit._wear_outfit, "pieces").

const PARTS := ["head", "torso", "legs"]

var kit: CharacterKit


func before_each() -> void:
	kit = CharacterKit.new(LookMaterials.new())


func _meshes(c: Node3D) -> Array:
	var skin: SkinnedBody = c.get_meta("skin")
	var names := []
	for mi in skin.model.find_children("*", "MeshInstance3D", true, false):
		names.append(String(mi.name))
	names.sort()
	return names


func test_player_and_guards_wear_their_own_pieces() -> void:
	for pair in [["player_smuggler", "player"], ["remnant_trooper", "guard"], ["remnant_commander", "guard"]]:
		var c := kit.build(pair[0])
		assert_true(c.has_meta("skin"), pair[0] + " has a kit model")
		if c.has_meta("skin"):
			assert_eq(_meshes(c), [pair[1] + "_head", pair[1] + "_legs", pair[1] + "_torso"], pair[0] + " keeps only its pieces")
		c.free()


func test_pieces_mix_across_outfits() -> void:
	var c := kit.build("player_smuggler", "", { "head": "guard", "torso": "player", "legs": "guard" })
	assert_eq(c.get_meta("outfit"), { "head": "guard", "torso": "player", "legs": "guard" })
	assert_eq(_meshes(c), ["guard_head", "guard_legs", "player_torso"])
	var skin: SkinnedBody = c.get_meta("skin")
	for mi: MeshInstance3D in skin.model.find_children("*", "MeshInstance3D", true, false):
		assert_eq(mi.get_node(mi.skeleton), skin.skeleton, String(mi.name) + " shares the one skeleton")
	c.free()


func test_every_listed_piece_exists() -> void:
	for arch in ["player_smuggler", "remnant_trooper", "remnant_commander"]:
		var model: Dictionary = kit.palettes[arch].model
		assert_true(ResourceLoader.exists(str(model.scene)), "kit model for " + arch)
		for part in PARTS:
			for choice in model.parts[part]:
				var pc := str(choice).split(":", true, 1)
				if pc.size() == 2:
					assert_true(ResourceLoader.exists(str(model.colors) % (pc[0] + "_" + pc[1])), "texture for " + str(choice))
