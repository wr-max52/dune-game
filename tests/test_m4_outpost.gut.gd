extends GutTest
## M4: the outpost that lives in the desert chunk. The data layer (content/core)
## describes its 3 buildings and 1 crate objective; this test proves the data is
## well-shaped and that the chunk streamer can place the outpost as a chunk.

const STREAMER := preload("res://src/systems/world/chunk_streamer.gd")
const CONTENT := preload("res://src/systems/dataload/core_content.gd")


func before_each() -> void:
	pass


func test_outpost_has_three_buildings_and_a_crate() -> void:
	var cc = CONTENT.new()
	cc.load_from()
	var outpost = cc.get_location("outpost")
	assert_not_null(outpost, "the outpost location loads from content/core")
	assert_eq(outpost.get("buildings").size(), 3, "outpost has 3 buildings")
	assert_true(outpost.has("crate"), "outpost has a crate objective")
	var guards = outpost.get("guards", {})
	assert_eq(guards.get("troopers", 0), 4, "4 troopers guard the outpost")
	assert_eq(guards.get("duelist", 0), 1, "1 duelist guards the outpost")


func test_chunk_streamer_places_the_outpost_as_a_chunk() -> void:
	var world := []
	var i: int = 0
	for c in [0.0, 100.0, 200.0, 300.0, 400.0, 500.0, 600.0, 700.0, 800.0, 900.0, 1000.0]:
		var kind := "port" if c < 300.0 else ("outpost" if c >= 900.0 else "desert")
		world.append({ "id": "chunk_" + str(i), "center": c, "load_ms": 18.0, "kind": kind })
		i += 1
	var s := STREAMER.new(world)
	s.work_budget_per_frame = 50.0
	s.active_radius = 120.0
	# Walk the full bay-to-outpost path.
	for f in 1800:
		var x: float = 1000.0 * float(f) / float(1800)
		s.update(0.016, x)
	# The outpost chunk (x=1000) should have been requested active at the end.
	assert_true(s.active.has("chunk_10"), "the outpost chunk was requested active at the far end of the walk")
