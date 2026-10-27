extends GutTest
## M9 addendum D5: the decor layer is visual only. It must not add collision, must
## dress every box it has a rule for, keep its lamps tracked and few, and stay out
## of market and character art.

const TownDemo := preload("res://scenes/town_demo.gd")
const TownDecor := preload("res://src/systems/world/town_decor.gd")

## Boxes the addendum's table deliberately leaves greybox (gate lintel: overhead
## in the perimeter zone has no row).
const SKIPPED_IDS := ["gate_lintel"]


func after_each() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _demo(look_on: bool) -> Node:
	var d = TownDemo.new()
	d.use_look = look_on
	d.lookdev_mode = true        # no player, no pad: just the town
	add_child_autofree(d)
	return d


func _count(node: Node, cls: String) -> int:
	var n := 1 if node.is_class(cls) else 0
	for c in node.get_children():
		n += _count(c, cls)
	return n


func _all(node: Node, cls: String, out: Array) -> Array:
	if node.is_class(cls):
		out.append(node)
	for c in node.get_children():
		_all(c, cls, out)
	return out


func test_decor_adds_no_collision() -> void:
	var on = _demo(true)
	var off = _demo(false)
	assert_eq(_count(on.get_node("Town"), "StaticBody3D"), 126, "one body per box with look on")
	assert_eq(_count(off.get_node("Town"), "StaticBody3D"), 126, "and with look off")
	assert_eq(_count(on.decor, "CollisionObject3D"), 0, "decor has no colliders")
	assert_eq(_count(on.decor, "CollisionShape3D"), 0, "decor has no shapes")


func test_every_box_has_a_material_when_look_on() -> void:
	var d = _demo(true)
	for b in d.town.boxes():
		var body: Node = d.get_node("Town/" + str(b.id))
		var mi: MeshInstance3D = body.get_node("Mesh")
		if SKIPPED_IDS.has(str(b.id)):
			assert_null(mi.material_override, "%s keeps greybox on purpose" % b.id)
		else:
			assert_not_null(mi.material_override, "%s is dressed" % b.id)


func test_lamps_are_tracked_and_capped() -> void:
	var d = _demo(true)
	var omnis := _all(d, "OmniLight3D", [])
	assert_gt(omnis.size(), 0, "the town has lamps")
	assert_lte(omnis.size(), 12, "no more than 12 omni lights")
	for l in omnis:
		assert_true(d.look._lamps.has(l), "%s is tracked by LookEnvironment" % l.name)


func test_no_market_or_character_art() -> void:
	var d = _demo(true)
	var cloth := 0
	for mi in _all(d.decor, "MeshInstance3D", []):
		var m = mi.material_override
		if m is StandardMaterial3D and m.backlight_enabled:   # LookMaterials.cloth
			cloth += 1
			assert_eq(mi.get_meta("decor", ""), "banner", "%s is cloth but not a banner" % mi.name)
	assert_eq(cloth, 2, "exactly the two watchtower banners")
	for n in _all(d, "Node3D", []):
		assert_false(n.get_script() == CharacterKit, "no CharacterKit nodes")
		assert_false(str(n.name).begins_with("Hooded"), "no hooded figures")
	# Markers stay capsules.
	for v in d.get_node("Markers").get_children():
		assert_true((v as MeshInstance3D).mesh is CapsuleMesh, "%s is a capsule" % v.name)


func test_presets_switch() -> void:
	var d = _demo(true)
	var ys: Array = []
	for p in ["golden", "noon", "dusk"]:
		d.set_preset(p)
		assert_eq(d.look.current, p)
		ys.append(d.look.sun_dir.y)
	assert_ne(ys[0], ys[1], "golden to noon moves the sun")
	assert_ne(ys[1], ys[2], "noon to dusk moves the sun")


func test_town_shots_load() -> void:
	var d = _demo(true)
	for id in ["gate_approach", "plaza", "cantina_bar", "top_down",
			"gate_to_desert", "desert_look_back", "north_wall_outside", "desert_aerial"]:
		assert_true(d.show_shot(id), "shot %s exists" % id)


func test_port_ship_is_the_flight_ship_and_fits_its_box() -> void:
	var d = _demo(true)
	assert_eq(d.decor.parked_ships.size(), 1, "one ship parked in the pit")
	var ship: Node3D = d.decor.parked_ships[0]
	# Same model as the dogfight: the player ship's look from the pad's encounter.
	var content = preload("res://src/systems/dataload/core_content.gd").new()
	content.load_from()
	var enc: Dictionary = content.encounters[str(GameFlow.pad("town_pit").encounter)]
	var look_id := str(content.ships[str(enc.player.ship)].look)
	assert_eq(str(ship.get_meta("look_id")), look_id, "port ship uses the flight look")
	# The collision box matches the model, so there are no invisible walls.
	var box: Dictionary = d.town.get_box("ship")
	var bmin := Vector3(float(box.min[0]), float(box.min[1]), float(box.min[2]))
	var bmax := Vector3(float(box.max[0]), float(box.max[1]), float(box.max[2]))
	var a: AABB = TownDecor.visual_aabb(ship)
	for k in 3:
		assert_almost_eq(a.position[k], bmin[k], 0.4, "model min %d fits the box" % k)
		assert_almost_eq(a.end[k], bmax[k], 0.4, "model max %d fits the box" % k)
	var mi: MeshInstance3D = d.get_node("Town/ship/Mesh")
	assert_false(mi.visible, "the greybox stand-in is hidden")
	var has_shape := false
	for c in d.get_node("Town/ship").get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
			has_shape = true
	assert_true(has_shape, "collision stays")
