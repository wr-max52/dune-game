extends GutTest
## M13: item looks. Every item's look builds a visible item with hidden flames,
## the worn placement sits behind the chest, flames toggle, an unknown look still
## builds something, and a look with a "scene" path uses that model instead of the
## stand-in -- the hook for a real jetpack design later.

const CoreScript := preload("res://src/systems/dataload/core_content.gd")

var kit: ItemKit


func before_each() -> void:
	kit = ItemKit.new()


func _meshes(n: Node) -> Array:
	return PlayerAvatar._meshes_under(n)


func test_every_item_look_builds_with_flames_hidden() -> void:
	var content = CoreScript.new()
	content.load_from()
	for id in content.items:
		var look := str(content.get_item(id).get("look", id))
		var item := kit.build(look)
		add_child_autofree(item)
		assert_eq(item.get_meta("source"), "kit", "%s uses the stand-in" % id)
		assert_gt(_meshes(item).size(), 6, "%s has real geometry" % id)
		var flames := item.get_node_or_null("Flames")
		assert_not_null(flames, "%s has a Flames node" % id)
		assert_false(flames.visible, "flames start hidden")


func test_flames_toggle() -> void:
	var item := kit.build("jetpack")
	add_child_autofree(item)
	ItemKit.set_flames(item, true, 1.0)
	assert_true(item.get_node("Flames").visible)
	ItemKit.set_flames(item, false)
	assert_false(item.get_node("Flames").visible)


func test_worn_pack_sits_behind_the_chest() -> void:
	var xf := kit.on_back_transform("jetpack")
	assert_lt(xf.origin.z, 0.0, "the back is -Z on the body (models face +Z)")


func test_unknown_look_still_builds_something_visible() -> void:
	var item := kit.build("no_such_look")
	add_child_autofree(item)
	assert_gt(_meshes(item).size(), 0)


func test_scene_path_swaps_in_a_real_model() -> void:
	var model := Node3D.new()
	model.name = "Imported"
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	model.add_child(mi)
	mi.owner = model
	var packed := PackedScene.new()
	packed.pack(model)
	model.free()
	var path := "user://m13_test_pack.tscn"
	assert_eq(ResourceSaver.save(packed, path), OK)
	var custom := ItemKit.new(null, { "looks": { "custom": { "scene": path } } })
	var item := custom.build("custom")
	add_child_autofree(item)
	assert_eq(item.get_meta("source"), "scene", "the model replaced the stand-in")
	assert_not_null(item.get_node_or_null("Model"))
	assert_null(item.get_node_or_null("Body"), "no stand-in geometry was built")
	assert_not_null(item.get_node_or_null("Flames"), "the contract still holds")


func test_missing_model_falls_back_to_the_stand_in() -> void:
	var custom := ItemKit.new(null, { "looks": { "custom": { "scene": "res://nope/pack.glb" } } })
	var item := custom.build("custom")
	add_child_autofree(item)
	assert_eq(item.get_meta("source"), "kit", "a bad model path never leaves the pack invisible")
