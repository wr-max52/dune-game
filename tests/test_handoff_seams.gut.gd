extends GutTest
## The moon handoff should not be noticed: the old scene is freed a little at a
## time (SceneReaper), the new ball's first far mesh is computed before the switch
## (PlanetTerrain.prewarm_far) and is the one the scene would have made, and up in
## space a planet's own ambient fill gives way to the plain preset's so both
## scenes are lit alike.


func after_each() -> void:
	PlanetTerrain.clear_prewarmed()
	SceneReaper.flush()
	GameFlow.reset()


func _tree(n: int) -> Node:
	var root := Node3D.new()
	var parent: Node = root
	for i in n:
		var c := Node3D.new()
		parent.add_child(c)
		if i % 10 == 9:
			parent = c          # some depth too
	return root


func test_reaper_frees_a_scene_over_frames_leaves_first() -> void:
	var scene := _tree(400)
	var ref: WeakRef = weakref(scene)
	SceneReaper.reap(scene)
	await wait_physics_frames(2)
	var reaper := get_tree().root.get_node_or_null("SceneReaper") as SceneReaper
	assert_not_null(reaper, "one reaper under the root")
	reaper.budget_ms = 0.0     # one node a frame at most: proves it spreads
	var before := reaper.freed
	await wait_process_frames(3)
	assert_true(ref.get_ref() != null, "not all in one go")
	assert_between(reaper.freed - before, 1, 6, "a few a frame")
	reaper.budget_ms = 2.0
	for i in 200:
		if ref.get_ref() == null:
			break
		await wait_process_frames(1)
	assert_null(ref.get_ref(), "all gone in the end")
	assert_eq(SceneReaper.pending(), 0)


func test_prewarmed_far_chunks_are_the_ones_the_scene_makes() -> void:
	var planet := PlanetGen.build("grit_station")
	assert_true(PlanetTerrain.prewarm_far(planet), "prewarm started")
	assert_false(PlanetTerrain.prewarm_far(planet), "once per planet")
	var pt := PlanetTerrain.for_planet(planet)
	autofree(pt)
	var cells := mini(pt.far_coarse_cells, pt.far_cells / 4)
	var got: Array = PlanetTerrain._take_prewarmed(pt.cache_key, cells)
	assert_eq(got.size(), 6 * pt.far_chunks * pt.far_chunks)
	for k in [0, 5, got.size() - 1]:
		var fresh: Dictionary = pt._far_chunk(k, cells)
		assert_eq(got[k].arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array, fresh.arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array,
			"chunk %d as the scene would make it" % k)
	assert_false(PlanetTerrain.is_prewarmed(pt.cache_key), "used once")


func test_the_scene_takes_the_prewarm() -> void:
	var planet := PlanetGen.build("grit_station")
	PlanetTerrain.prewarm_far(planet)
	var pt := PlanetTerrain.for_planet(planet)
	add_child_autofree(pt)
	pt.build_staged(true)
	assert_false(PlanetTerrain.is_prewarmed(pt.cache_key), "taken by the build")
	assert_eq(pt._far_instances.size(), 6 * pt.far_chunks * pt.far_chunks)
	pt.finish_jobs()


func test_a_scene_without_prewarm_still_builds() -> void:
	var pt := PlanetTerrain.for_planet(PlanetGen.build("grit_station"))
	add_child_autofree(pt)
	pt.build_staged(true)
	assert_eq(pt._far_instances.size(), 6 * pt.far_chunks * pt.far_chunks)
	pt.finish_jobs()


func test_ambient_eases_to_the_plain_preset_in_space() -> void:
	var look := LookEnvironment.new()
	add_child_autofree(look)
	var plain := float(look.presets[look.default_preset].ambient.energy)
	for id in look.presets:
		look.presets[id] = TownDemoMerge.merge(look.presets[id], { "ambient": { "energy": plain * 0.5 } })
	look.apply()
	look.set_ambient_energy_scale(1.6)
	assert_almost_eq(look.env.ambient_light_energy, plain * 0.5 * 1.6, 0.0001, "down here: its own")
	look.set_space_level(1.0)
	assert_almost_eq(look.env.ambient_light_energy, plain, 0.0001, "in space: the plain preset's")
	look.set_space_level(0.5)
	assert_almost_eq(look.env.ambient_light_energy, lerpf(plain * 0.8, plain, 0.5), 0.0001)


class TownDemoMerge:
	static func merge(base: Dictionary, over: Dictionary) -> Dictionary:
		var out := base.duplicate(true)
		for k in over:
			out[k] = merge(out[k], over[k]) if out.get(k) is Dictionary and over[k] is Dictionary else over[k]
		return out
