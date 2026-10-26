extends GutTest
## M10: ship looks. Every ship's look id resolves to an entry in content/look/ships.json
## and builds a visible ship with engine glows, noses point down -Z like the flight
## model, an unknown look still builds something visible, and a look with a "scene"
## path uses that model instead of the stand-in -- the hook for real designs later.

const CoreScript := preload("res://src/systems/dataload/core_content.gd")
const ShipNode := preload("res://src/systems/flight/ship_node.gd")
const FlightModel := preload("res://src/systems/flight/flight_model.gd")

var kit: ShipKit


func before_each() -> void:
	kit = ShipKit.new()


func _meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out


## Local-space bounds of every mesh under `root`.
func _bounds(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in _meshes(root):
		var xf: Transform3D = root.global_transform.affine_inverse() * mi.global_transform
		var b: AABB = xf * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func test_every_ship_look_resolves() -> void:
	var content = CoreScript.new()
	content.load_from()
	for sid in content.ships:
		var look := str(content.get_ship(sid).look)
		assert_true(kit.has_look(look), "%s look '%s' exists in ships.json" % [sid, look])


func test_every_look_builds_with_engines_and_a_forward_nose() -> void:
	for id in kit.look_ids():
		var ship := kit.build(id)
		add_child_autofree(ship)
		assert_eq(ship.get_meta("look_id"), id)
		assert_eq(ship.get_meta("source"), "kit", "%s uses the stand-in" % id)
		assert_gt(_meshes(ship).size(), 5, "%s has real geometry" % id)
		var engines := ship.get_node_or_null("Engines")
		assert_not_null(engines, "%s has an Engines node" % id)
		assert_gt(engines.get_child_count(), 0, "%s has engine glows" % id)
		var b := _bounds(ship)
		var length := float(kit.looks[id].get("length", 1.0))
		assert_lt(b.position.z, -length * 0.3, "%s nose reaches toward -Z" % id)
		for g in engines.get_children():
			assert_gt((g as Node3D).position.z, 0.0, "%s engines sit at the back (+Z)" % id)


func test_unknown_look_still_builds_something_visible() -> void:
	var ship := kit.build("no_such_look")
	add_child_autofree(ship)
	assert_gt(_meshes(ship).size(), 0, "a missing look falls back to a stand-in")


func test_scene_path_swaps_in_a_real_model() -> void:
	# Build a tiny "model", save it, point a look at it: the kit must use it as-is.
	var model := Node3D.new()
	model.name = "Imported"
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	model.add_child(mi)
	mi.owner = model
	var packed := PackedScene.new()
	packed.pack(model)
	model.free()
	var path := "user://m10_test_model.tscn"
	assert_eq(ResourceSaver.save(packed, path), OK)
	var custom := ShipKit.new(null, { "looks": { "custom": { "scene": path, "frame": "dart" } } })
	var ship := custom.build("custom")
	add_child_autofree(ship)
	assert_eq(ship.get_meta("source"), "scene", "the model replaced the stand-in")
	assert_not_null(ship.get_node_or_null("Model"), "the model is mounted under the root")
	assert_null(ship.get_node_or_null("Body"), "no stand-in geometry was built")
	assert_not_null(ship.get_node_or_null("Engines"), "the root contract still holds")


func test_missing_model_falls_back_to_the_stand_in() -> void:
	var custom := ShipKit.new(null, { "looks": { "custom": { "scene": "res://nope/missing.glb", "frame": "blade" } } })
	var ship := custom.build("custom")
	add_child_autofree(ship)
	assert_eq(ship.get_meta("source"), "kit", "a bad model path never leaves a ship invisible")


func test_bolt_styles_build() -> void:
	for style in ["player", "hostile", "missile"]:
		var b := kit.build_bolt(style)
		add_child_autofree(b)
		assert_eq(_meshes(b).size(), 1, "%s bolt has one glow mesh" % style)


func test_ship_node_follows_the_flight_model() -> void:
	var node = ShipNode.new()
	add_child_autofree(node)
	node.setup(kit, "interceptor", 1, "player")
	var f = FlightModel.new({})
	f.position = Vector3(10, 20, 30)
	f.face(Vector3(1, 0, 0))
	node.sync(f, true)
	assert_almost_eq(node.global_position.distance_to(f.position), 0.0, 0.0001, "position copied")
	assert_almost_eq((-node.global_transform.basis.z).dot(f.forward()), 1.0, 0.0001, "facing copied")
	node.sync(f, false)
	assert_false(node.visible, "a destroyed ship is hidden")
