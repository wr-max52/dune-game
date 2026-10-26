extends GutTest
## The player's rigged smuggler model (SkinnedBody over the CharacterKit joints).
## Model: assets/characters/smuggler/smuggler.glb, made by tools/look/prep_character.gd.

const BodyAnimator := preload("res://src/systems/anim/body_animator.gd")

var avatar: PlayerAvatar


func before_each() -> void:
	avatar = PlayerAvatar.new()
	add_child_autofree(avatar)


func test_player_wears_the_rigged_model() -> void:
	assert_not_null(avatar.skin, "player_smuggler has a model in characters.json")
	assert_not_null(avatar.skin.skeleton)
	for jn in BodyAnimator.JOINTS:
		assert_true(avatar.skin.bone_of.has(jn), "joint mapped to a bone: " + jn)


func test_primitives_are_hidden_but_joints_stay() -> void:
	for m in PlayerAvatar._meshes_under(avatar.body):
		if not avatar.skin.model.is_ancestor_of(m):
			assert_false((m as GeometryInstance3D).visible, "primitive hidden: " + str(m.get_path()))
	assert_true(avatar.body.has_meta("holster_grip"), "holster grip still there for the draw")


func test_model_stands_on_the_ground_at_kit_height() -> void:
	var aabb := SkinnedBody._aabb(avatar.skin.model, Transform3D())   # body space
	assert_almost_eq(aabb.position.y, 0.0, 0.02, "soles on y = 0")
	assert_between(aabb.end.y, 1.7, 2.2, "about a person tall, hat included")


func test_walking_moves_the_leg_bones() -> void:
	var skel := avatar.skin.skeleton
	var thigh: int = avatar.skin.bone_of.l_hip
	var lo := INF
	var hi := -INF
	for i in 40:
		avatar.animate(1.0 / 30.0, { "velocity": Vector3(0, 0, 4.0), "grounded": true })
		var swing := rad_to_deg(skel.get_bone_pose_rotation(thigh).get_euler().x)
		lo = minf(lo, swing)
		hi = maxf(hi, swing)
	assert_gt(hi - lo, 15.0, "the thigh swings through the gait")


func test_joint_rotation_turns_its_bone_by_the_same_amount() -> void:
	var skel := avatar.skin.skeleton
	var knee: int = avatar.skin.bone_of.r_knee
	var j: Node3D = avatar.joints.r_knee
	j.rotation = Vector3.ZERO
	avatar.skin.sync(avatar.body)
	var rest := skel.get_bone_global_pose(knee).basis.orthonormalized()
	j.rotation = Vector3(deg_to_rad(40), 0, 0)
	avatar.skin.sync(avatar.body)
	var bent := skel.get_bone_global_pose(knee).basis.orthonormalized()
	var angle := (rest.inverse() * bent).get_rotation_quaternion().get_angle()
	assert_almost_eq(rad_to_deg(angle), 40.0, 1.0)
