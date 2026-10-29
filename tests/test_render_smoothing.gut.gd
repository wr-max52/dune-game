extends GutTest
## Render smoothing: characters move on 60 Hz physics ticks but may be drawn at 120 Hz.
## The live path needs a renderer (headless keeps physics positions exactly), so these
## tests cover the pure parts: the origin lerp and its resets, the avatar's basis
## composition, and that headless stays a no-op.

const PlayerBody := preload("res://src/systems/player/character_body.gd")


func _body() -> Node3D:
	var b := PlayerBody.new()
	add_child_autofree(b)
	return b


func test_lerp_origin_at_fraction_0_half_1() -> void:
	var a := Vector3(1, 0, 0)
	var b := Vector3(3, 2, -4)
	assert_true(PlayerBody.lerp_origin(a, b, 0.0).is_equal_approx(a), "fraction 0 is the previous tick")
	assert_true(PlayerBody.lerp_origin(a, b, 0.5).is_equal_approx(Vector3(2, 1, -2)), "fraction 0.5 is the midpoint")
	assert_true(PlayerBody.lerp_origin(a, b, 1.0).is_equal_approx(b), "fraction 1 is this tick")
	assert_true(PlayerBody.lerp_origin(a, b, -0.3).is_equal_approx(a), "fraction clamps low")
	assert_true(PlayerBody.lerp_origin(a, b, 1.7).is_equal_approx(b), "fraction clamps high")


func test_recorded_ticks_feed_render_origin_at() -> void:
	var p := _body()
	p.record_origin(Vector3(0, 0, 0), 10)
	p.record_origin(Vector3(0.1, 0, 0), 11)
	assert_true(p.render_origin_at(0.0).is_equal_approx(Vector3.ZERO))
	assert_true(p.render_origin_at(0.5).is_equal_approx(Vector3(0.05, 0, 0)))
	assert_true(p.render_origin_at(1.0).is_equal_approx(Vector3(0.1, 0, 0)))


func test_first_tick_has_no_smear() -> void:
	var p := _body()
	p.record_origin(Vector3(5, 0, 5), 3)
	assert_true(p.render_origin_at(0.0).is_equal_approx(Vector3(5, 0, 5)), "no history: previous == current")


func test_big_step_is_a_teleport() -> void:
	var p := _body()
	p.record_origin(Vector3.ZERO, 1)
	p.record_origin(Vector3(1.9, 0, 0), 2)
	assert_true(p.render_origin_at(0.0).is_equal_approx(Vector3.ZERO), "a 1.9 m step is ordinary motion")
	p.record_origin(Vector3(40, 0, 0), 3)
	assert_true(p.render_origin_at(0.0).is_equal_approx(Vector3(40, 0, 0)), "a 38 m step is a teleport: no smear")
	assert_false(PlayerBody.is_teleport(Vector3.ZERO, Vector3(1.9, 0, 0)))
	assert_true(PlayerBody.is_teleport(Vector3.ZERO, Vector3(2.1, 0, 0)))


func test_gap_in_ticks_resets() -> void:
	var p := _body()
	p.record_origin(Vector3.ZERO, 1)
	p.record_origin(Vector3(0.1, 0, 0), 2)
	# Process-disabled for a while (piloting a ship), back on a nearby spot.
	p.record_origin(Vector3(0.5, 0, 0), 300)
	assert_true(p.render_origin_at(0.0).is_equal_approx(Vector3(0.5, 0, 0)), "restart after the gap")


func test_align_to_ground_resets_history() -> void:
	var p := _body()
	p.record_origin(Vector3.ZERO, 1)
	p.record_origin(Vector3(0.1, 0, 0), 2)
	p.global_position = Vector3(30, 0, 0)
	p.align_to_ground()
	assert_true(p.render_origin_at(0.0).is_equal_approx(Vector3(30, 0, 0)))
	assert_true(p.render_origin_at(1.0).is_equal_approx(Vector3(30, 0, 0)))


func test_physics_tick_records_origin() -> void:
	var p := _body()
	p._physics_process(1.0 / 60.0)
	assert_true(p.render_origin_at(1.0).is_equal_approx(p.global_position), "a tick leaves history at the body")


func test_headless_is_a_noop() -> void:
	assert_false(PlayerBody.smoothing_active(), "GUT runs headless")
	var p := _body()
	p.record_origin(Vector3.ZERO, 1)
	p.record_origin(Vector3(0.1, 0, 0), 2)
	p.global_position = Vector3(0.1, 0, 0)
	assert_true(p.render_origin().is_equal_approx(p.global_position), "headless draws exactly where physics left it")


func test_local_offset_puts_the_child_at_the_render_origin() -> void:
	var parent_basis := Basis(Vector3.UP, 1.1)
	var parent_pos := Vector3(10, 0, 4)
	var render := Vector3(9.9, 0, 4.05)
	var off := PlayerBody.local_offset(parent_basis, render, parent_pos)
	assert_true((parent_pos + parent_basis * off).is_equal_approx(render), "world origin of the child == render origin")
	assert_true(PlayerBody.local_offset(parent_basis, parent_pos, parent_pos).is_zero_approx(), "no offset when they coincide")


func test_avatar_world_facing_ignores_parent_yaw() -> void:
	var tilt := PlanetSphere.tilt_to(Vector3(0.3, 0.9, 0.2).normalized())
	for tilt_b in [Basis.IDENTITY, tilt]:
		var yaw := 0.8
		var world_a: Basis = Basis(Vector3.UP, 0.4) * PlayerAvatar.compose_basis(Basis(Vector3.UP, 0.4), tilt_b, yaw)
		var world_b: Basis = Basis(Vector3.UP, -2.3) * PlayerAvatar.compose_basis(Basis(Vector3.UP, -2.3), tilt_b, yaw)
		assert_true(world_a.is_equal_approx(tilt_b * Basis(Vector3.UP, yaw)), "world facing is tilt * facing")
		assert_true(world_a.is_equal_approx(world_b), "same world facing whatever the parent's yaw")


func test_smoothed_yaw_takes_the_short_way_round() -> void:
	assert_almost_eq(PlayerAvatar.smoothed_yaw(0.0, 1.0, 0.5), 0.5, 0.0001)
	assert_almost_eq(PlayerAvatar.smoothed_yaw(0.2, 0.9, 0.0), 0.2, 0.0001)
	assert_almost_eq(PlayerAvatar.smoothed_yaw(0.2, 0.9, 1.0), 0.9, 0.0001)
	var mid := PlayerAvatar.smoothed_yaw(PI - 0.1, -PI + 0.1, 0.5)
	assert_almost_eq(absf(mid), PI, 0.0001, "across the +-PI seam it does not swing through zero")


func test_avatar_basis_tracks_interpolated_facing_with_a_turned_parent() -> void:
	var p := _body()
	p.rotation.y = 1.3
	var a := PlayerAvatar.new()
	p.add_child(a)
	a.animate(1.0 / 60.0, {"velocity": Vector3.ZERO, "cam_yaw": 0.0})
	a._facing_prev = 0.0
	a._facing_curr = 0.6
	a.facing_yaw = 0.6
	var yaw := PlayerAvatar.smoothed_yaw(a._facing_prev, a._facing_curr, 0.5)
	p.rotation.y = -0.7                      # the rig rewrote the parent's yaw this frame
	a.basis = PlayerAvatar.compose_basis(p.global_basis.orthonormalized(), a._last_tilt, yaw)
	assert_true((p.global_basis * a.basis).is_equal_approx(Basis(Vector3.UP, 0.3)),
		"the body faces the interpolated yaw in the world, not the parent's")


func test_reset_render_smoothing_restores_rest_position_and_facing() -> void:
	var p := _body()
	var a := PlayerAvatar.new()
	p.add_child(a)
	a.position = Vector3(0.1, 0, -0.2)
	a.facing_yaw = 1.0
	a._facing_prev = 0.2
	a.reset_render_smoothing()
	assert_eq(a.position, Vector3.ZERO)
	assert_eq(a._facing_prev, 1.0)
	assert_eq(a._facing_curr, 1.0)
