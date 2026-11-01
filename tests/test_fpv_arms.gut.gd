extends GutTest
## First person arms (issue #65 D): black sleeves and gloves over the kit's elbow
## and wrist joints, shown only in first person, for skinned and primitive bodies.

const BodyAnimator := preload("res://src/systems/anim/body_animator.gd")

var avatar: PlayerAvatar


func _skinned() -> PlayerAvatar:
	var a := PlayerAvatar.new()
	add_child_autofree(a)
	return a


func _glove_mats(a: PlayerAvatar) -> Array:
	var out: Array = []
	for m in a._fpv.meshes():
		out.append(((m as MeshInstance3D).material_override as ShaderMaterial).get_shader_parameter("base"))
	return out


func test_both_sides_are_built_with_the_expected_nodes() -> void:
	avatar = _skinned()
	assert_not_null(avatar._fpv)
	for side in ["l", "r"]:
		assert_true(avatar.joints[side + "_elbow"].has_node("FpvArm"), side + " forearm under the elbow")
		assert_true(avatar.joints[side + "_wrist"].has_node("FpvHand"), side + " hand under the wrist")
		var hand: Node3D = avatar.joints[side + "_wrist"].get_node("FpvHand")
		for f in 4:
			assert_not_null(hand.get_node_or_null("Finger%d/Seg1/Seg2" % f), "finger %d has two segments" % f)
		assert_not_null(hand.get_node_or_null("Thumb/Seg1/Seg2"), "thumb has two segments")


func test_visible_only_in_first_person() -> void:
	avatar = _skinned()
	avatar.set_first_person(false)
	for side in ["l", "r"]:
		assert_false((avatar._fpv.roots[side] as Node3D).visible)
		assert_false((avatar._fpv.hands[side] as Node3D).visible)
	avatar.set_first_person(true)
	for side in ["l", "r"]:
		assert_true((avatar._fpv.roots[side] as Node3D).visible)
		assert_true((avatar._fpv.hands[side] as Node3D).visible)


func test_arms_cast_no_shadow() -> void:
	avatar = _skinned()
	avatar.set_first_person(true)
	assert_gt(avatar._fpv.meshes().size(), 20)
	for m in avatar._fpv.meshes():
		assert_eq((m as GeometryInstance3D).cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


func test_grip_curls_the_fingers() -> void:
	avatar = _skinned()
	var arms := avatar._fpv
	var seg: Node3D = (arms.fingers["r"][1].seg1 as Node3D)
	arms.set_grip("r", 0.0)
	var open := seg.rotation.z
	arms.set_grip("r", 1.0)
	var closed := seg.rotation.z
	assert_gt(absf(closed - open), deg_to_rad(40.0), "closing curls the knuckle")
	# The hands are mirrored: left curls the other way round Z.
	arms.set_grip("l", 1.0)
	assert_lt((arms.fingers["l"][1].seg1 as Node3D).rotation.z * closed, 0.0, "mirrored")
	arms.set_grip("r", 5.0)
	assert_eq(arms.grip["r"], 1.0, "clamped")


func test_black_by_default() -> void:
	avatar = _skinned()
	for c in _glove_mats(avatar):
		assert_lt((c as Color).v, 0.15, "near black: " + str(c))


func test_drawing_a_weapon_closes_the_right_hand() -> void:
	avatar = _skinned()
	avatar.build_weapons(["pistol_blaster"])
	avatar.set_first_person(true)
	for i in 30:
		avatar.animate(1.0 / 30.0, { "upper": BodyAnimator.UPPER_FREE })
	assert_lt(avatar._fpv.grip["r"], 0.4, "relaxed unarmed")
	avatar.current = "pistol_blaster"
	avatar.drawn = 1.0
	for i in 30:
		avatar.animate(1.0 / 30.0, { "upper": BodyAnimator.UPPER_AIM })
	assert_eq(avatar._fpv.grip["r"], 1.0, "right hand closed on the pistol")
	assert_lt(avatar._fpv.grip["l"], 0.4, "one-handed in first person: left stays relaxed")


func test_the_kits_own_arms_are_hidden_over_a_skin() -> void:
	avatar = _skinned()
	avatar.set_first_person(true)
	assert_gt(avatar._kit_arms.size(), 0)
	for m in avatar._kit_arms:
		assert_false((m as GeometryInstance3D).visible, "kit forearm hidden: " + str(m.get_path()))
	for m in avatar._arm_meshes:
		assert_false(FpvArms.owns(m), "fpv arms are not mistaken for weapon meshes")


func test_primitive_body_keeps_kit_arms_for_the_shadow_only() -> void:
	# Rebuild the avatar without the model so the kit's primitives are the body.
	avatar = PlayerAvatar.new()
	add_child_autofree(avatar)
	avatar.skin = null
	avatar._collect_meshes()
	avatar.set_first_person(true)
	assert_gt(avatar._kit_arms.size(), 0)
	for m in avatar._kit_arms:
		assert_eq((m as GeometryInstance3D).cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
	for m in avatar._other_meshes:
		assert_false(FpvArms.owns(m), "fpv arms are not body meshes")
	assert_true((avatar._fpv.hands["r"] as Node3D).visible)
	avatar.set_first_person(false)
	for m in avatar._kit_arms:
		assert_eq((m as GeometryInstance3D).cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	assert_false((avatar._fpv.hands["r"] as Node3D).visible, "third person never sees them")


func test_new_outfit_gets_new_arms() -> void:
	avatar = _skinned()
	var before := avatar._fpv
	avatar.set_first_person(true)
	avatar.set_outfit(avatar.worn_outfit())
	assert_ne(avatar._fpv, before)
	assert_true((avatar._fpv.hands["l"] as Node3D).visible)
	assert_eq(avatar.joints["l_elbow"].get_children().filter(func(n): return n.name == "FpvArm").size(), 1)


## A save that owns the red saber swaps the sword's hilt as it loads; the old
## hilt's meshes are freed, and the next V into first person cast a freed object.
func test_new_hilt_is_not_left_in_the_mesh_lists() -> void:
	avatar = _skinned()
	avatar.build_weapons(["energy_blade"])
	avatar.set_blade_color(Color.RED, "res://assets/gear/saber_hilt_dark.glb")
	for m in avatar._arm_meshes + avatar._kit_arms + avatar._other_meshes:
		assert_true(is_instance_valid(m) and (m as Node).is_inside_tree(), "every listed mesh is live")
	avatar.set_first_person(true)
	assert_true(avatar.first_person)
