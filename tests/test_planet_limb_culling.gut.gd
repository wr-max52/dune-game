extends GutTest
## Pure horizon math tests. Terrain patch bounds are cached from generated far meshes;
## these cases ensure uncertain, near-surface, and margin patches stay visible.

const Terrain := preload("res://src/systems/look/planet_terrain.gd")


func _direction_at(degrees: float) -> Vector3:
	var angle := deg_to_rad(degrees)
	return Vector3(sin(angle), cos(angle), 0.0)


func test_camera_on_surface_envelope_keeps_all_patches_visible() -> void:
	var camera := Vector3.UP * 5000.0
	assert_true(Terrain.far_patch_visible(camera, Vector3.DOWN, PI, 5100.0, 5.0))


func test_orbit_culls_only_the_opposite_side_after_safety_margin() -> void:
	var camera := Vector3.UP * 11000.0
	var bound := 5100.0
	var horizon_degrees := rad_to_deg(acos(bound / camera.length()))
	assert_true(Terrain.far_patch_visible(camera, Vector3.UP, deg_to_rad(10.0), bound, 5.0))
	assert_false(Terrain.far_patch_visible(camera, Vector3.DOWN, deg_to_rad(10.0), bound, 5.0))
	var inside_margin := _direction_at(horizon_degrees + 5.0 + 10.0 - 1.0)
	var outside_margin := _direction_at(horizon_degrees + 5.0 + 10.0 + 1.0)
	assert_true(Terrain.far_patch_visible(camera, inside_margin, deg_to_rad(10.0), bound, 5.0), "near-limb patches stay visible")
	assert_false(Terrain.far_patch_visible(camera, outside_margin, deg_to_rad(10.0), bound, 5.0), "only fully hidden patches are culled")


func test_culling_works_for_rotated_orbits_and_above_surface_cameras() -> void:
	var camera := Vector3(2.0, -3.0, 4.0).normalized() * 12000.0
	var facing := camera.normalized()
	assert_true(Terrain.far_patch_visible(camera, facing, deg_to_rad(8.0), 5100.0, 5.0))
	assert_false(Terrain.far_patch_visible(camera, -facing, deg_to_rad(8.0), 5100.0, 5.0))
	var lower_orbit := Vector3(0.0, 7000.0, 0.0)
	assert_false(Terrain.far_patch_visible(lower_orbit, Vector3.DOWN, deg_to_rad(8.0), 5100.0, 5.0))
