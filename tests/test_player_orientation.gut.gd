extends GutTest
## Issue #128: hard position changes must immediately replace the old ground frame.

const PlayerBody := preload("res://src/systems/player/character_body.gd")


func test_align_to_ground_rebuilds_the_frame_for_each_arrival() -> void:
	var previous = PlanetSphere.current
	var first := PlanetSphere.new(5000.0)
	var second := PlanetSphere.new(5200.0)
	PlanetSphere.current = first
	var player := PlayerBody.new()
	add_child_autofree(player)

	player.global_position = first.surface_at(2600.0, 0.0)
	player.velocity = Vector3(2.0, 3.0, -1.0)
	player.align_to_ground(true)
	var first_tilt := first.tilt_at(player.global_position)
	assert_true(player.tilt.is_equal_approx(first_tilt), "ball arrival uses the local radial up")
	assert_true(player.up_direction.is_equal_approx(first_tilt.y), "CharacterBody uses that up immediately")
	assert_true(player.velocity.is_zero_approx(), "a hard arrival clears world velocity")
	assert_true(player.controller.velocity.is_zero_approx(), "controller velocity is cleared too")
	assert_true(player.controller.body_pos.is_equal_approx(player.global_position), "controller starts at arrival")

	PlanetSphere.current = second
	player.global_position = second.surface_at(-1800.0, 1100.0)
	player.align_to_ground()
	var second_tilt := second.tilt_at(player.global_position)
	assert_true(player.tilt.is_equal_approx(second_tilt), "planet swap uses the new sphere, not stale tilt")
	assert_false(player.tilt.is_equal_approx(first_tilt), "the new location has a distinct ground frame")

	PlanetSphere.current = null
	player.global_position = Vector3(0.0, 0.05, 0.0)
	player.align_to_ground()
	assert_true(player.tilt.is_equal_approx(Basis.IDENTITY), "flat-ground arrival removes spherical tilt")
	assert_true(player.up_direction.is_equal_approx(Vector3.UP), "flat body up is restored immediately")
	assert_true(player._capsule().basis.is_equal_approx(Basis.IDENTITY), "capsule is upright on the plateau")
	PlanetSphere.current = previous


func test_avatar_full_basis_resets_after_returning_to_flat_ground() -> void:
	var previous = PlanetSphere.current
	PlanetSphere.current = null
	var player := PlayerBody.new()
	add_child_autofree(player)
	player.rotation.y = 0.7
	var avatar := PlayerAvatar.new()
	player.add_child(avatar)
	avatar.facing_yaw = 0.35

	player.tilt = PlanetSphere.tilt_to(Vector3(0.8, 0.4, 0.45).normalized())
	avatar.animate(1.0 / 60.0, {"velocity": Vector3.ZERO})
	assert_false(avatar.basis.is_equal_approx(Basis(Vector3.UP, avatar.facing_yaw)),
		"the first pose is tilted with the planet")

	player.tilt = Basis.IDENTITY
	player.align_to_ground()
	var expected := player.global_basis.orthonormalized().inverse() * Basis(Vector3.UP, avatar.facing_yaw)
	assert_true(avatar.basis.is_equal_approx(expected), "arrival immediately replaces pitch and roll as well as yaw")
	avatar.animate(1.0 / 60.0, {"velocity": Vector3.ZERO})
	assert_true((player.global_basis * avatar.basis).is_equal_approx(Basis(Vector3.UP, avatar.facing_yaw)),
		"avatar's world basis is level after the transition")
	PlanetSphere.current = previous
