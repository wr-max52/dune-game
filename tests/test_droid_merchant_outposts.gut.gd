extends GutTest
## Issue #93: the scattered relays stay few, compact, mapped to the home planet,
## and carry antennae visibly taller than their huts.

const CONTENT := preload("res://src/systems/dataload/core_content.gd")
const POST_IDS := ["droid_post_wash", "droid_post_ridge", "droid_post_basin"]


func test_three_compact_relay_landmarks_have_tall_arrays() -> void:
	var cc = CONTENT.new()
	cc.load_from()
	var world: Dictionary = cc.world_for_town("port_town")
	var landmarks: Array = world.get("landmarks", [])
	var found := {}
	var coords: Array[Vector2] = []
	for lm in landmarks:
		var id := str(lm.get("location", ""))
		if not POST_IDS.has(id):
			continue
		found[id] = true
		coords.append(Vector2(float(lm.at[0]), float(lm.at[2])))
		var loc: Dictionary = cc.get_location(id)
		assert_eq(loc.get("kind"), "droid_merchant_outpost", "%s is a merchant relay" % id)
		assert_eq(loc.get("buildings").size(), 3, "%s keeps a small footprint with a separate table" % id)
		assert_true(loc.buildings.any(func(b): return str(b.get("id", "")) == "merchant_table"),
			"%s has a small display table" % id)
		assert_gt(float(loc.get("look", {}).get("antenna_height", 0.0)), 8.0,
			"%s has a tall roof array" % id)
		assert_true(loc.get("points", {}).has("merchant"), "%s has a merchant position" % id)
	assert_eq(found.size(), 3, "exactly three scattered relay sites are mapped")
	assert_eq(coords.size(), 3)
	for i in coords.size():
		for j in range(i + 1, coords.size()):
			assert_gt(coords[i].distance_to(coords[j]), 1000.0, "relay sites are separated")
