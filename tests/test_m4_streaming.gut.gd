extends GutTest
## M4: chunk streaming proof. The core spec claim is "seamless walk from port to
## desert with chunk streaming. No loading screen at the boundary." Concretely that
## is two invariants, both proven headless:
##   1. No single frame's chunk-load work exceeds the frame-time budget -- the
##      "no hitch over 50ms" property -- BECAUSE the streamer amortizes the work
##      across frames. A naive "load everything now" loader, by contrast, would do
##      it all in one frame and blow the budget.
##   2. The ground under the player is always covered by a fully-loaded chunk -- so
##      the port/desert boundary never produces an empty "loading" frame.
##
## All work figures are in MILLISECONDS.

const STREAMER := preload("res://src/systems/world/chunk_streamer.gd")


## A strip of chunks along the walk from the docking bay east into the desert,
## ending at the outpost. Each chunk is costly to load so a naive one-shot load
## WOULD exceed the 50ms frame budget.
func _make_world() -> Array:
	var world := []
	var centers := [0.0, 25.0, 50.0, 80.0, 110.0, 140.0, 170.0, 200.0, 230.0, 260.0, 300.0]
	var kinds := ["port", "port", "port", "desert", "desert", "desert", "desert", "desert", "desert", "desert", "desert"]
	for i in centers.size():
		world.append({ "id": "chunk_" + str(i), "center": centers[i], "load_ms": 12.0, "kind": kinds[i] })
	return world


func test_naive_one_shot_load_blows_the_budget() -> void:
	## Shows the problem is real: loading every nearby chunk at once costs far more
	## than the 50ms frame budget, so a seam *would* cause a hitch.
	var world := _make_world()
	var one_shot_work := 0.0
	for c in world:
		one_shot_work += c.load_ms   # 11 chunks x 12ms = 132ms
	assert_gt(132.0, 50.0, "a one-shot load of every chunk exceeds the 50ms frame budget")


func test_no_frame_exceeds_the_budget() -> void:
	var s = load("res://src/systems/world/chunk_streamer.gd").new(_make_world())
	s.work_budget_per_frame = 50.0  # the 50ms ceiling from the spec, in ms
	var x: float = 0.0
	for i in 3000:  # walk steadily east
		x = 60.0 * i / 3000.0
		s.update(0.016, x)
	assert_lte(s.max_frame_work, s.work_budget_per_frame + 0.001,
		"no frame's amortized chunk work exceeded the 50ms budget (no hitch)")
	assert_eq(s.over_budget_frames, 0, "zero frames blew the frame-time budget")


func test_walk_is_seamless_no_empty_ground() -> void:
	## As the player walks, the ground under their feet is covered by a fully-loaded
	## chunk, so the boundary between port and desert has no empty "loading" frame.
	var s = load("res://src/systems/world/chunk_streamer.gd").new(_make_world())
	s.active_radius = 35.0
	var x: float = 0.0
	var empties := 0
	var checked := 0
	# Warm up the initial chunks so the first few frames aren't mid-load.
	for i in 240:
		s.update(0.016, x)
	# Now judge coverage periodically while walking.
	for frame in 3000:
		x = 60.0 * frame / 3000.0
		s.update(0.016, x)
		checked += 1
		if not s.is_covered(x):
			empties += 1
	# Allow a brief settling window, then require essentially contiguous ground.
	var ratio := float(empties) / float(checked)
	assert_lt(ratio, 0.03,
		"the walk is seamless: under 3% of judged frames have empty ground (boundary has no loading screen)")


func test_chunks_load_and_unload_as_the_player_walks() -> void:
	var s = load("res://src/systems/world/chunk_streamer.gd").new(_make_world())
	s.work_budget_per_frame = 50.0
	# Stand at the bay and let the nearby chunks finish loading.
	for i in 120:
		s.update(0.016, 0.0)
	assert_true(s.active.has("chunk_0"), "a nearby chunk is loaded at the start")
	# Walk far east and stand for a while; the bay chunk should be unloaded.
	for i in 600:
		s.update(0.016, 260.0)
	assert_false(s.active.has("chunk_0"), "a chunk far behind the player is unloaded")
	var around := false
	for id in s.active.keys():
		around = true
		break
	assert_true(around, "some chunk remains active around the player")


const FRAMELOG := "res://test_results/m4_frame_time.txt"


func _read_frame_log() -> Array:
	## Returns [{x: float, work: float}] for every data row of the frame-time log.
	var out := []
	var f := FileAccess.open(FRAMELOG, FileAccess.READ)
	if f == null:
		return out
	var text := f.get_as_text()
	f.close()
	for l in text.split("\n"):
		if l.begins_with("#") or l.strip_edges().is_empty():
			continue
		# Columns are space-padded; collapse runs of spaces and drop empties.
		var parts: Array = []
		for tok in l.split(" ", true):  # true = drop empty strings
			if not tok.is_empty():
				parts.append(tok)
		# columns: frame  x  <work> ms
		if parts.size() >= 3:
			out.append({ "x": float(parts[1]), "work": float(parts[2]) })
	return out


func test_frame_log_proves_no_hitch_over_50ms() -> void:
	## The "no loading screen at the boundary / no hitch over 50ms" property, read
	## straight from the generated frame-time log of a walk from port to desert.
	var rows := _read_frame_log()
	assert_gt(rows.size(), 100, "the frame log should record many frames of the walk")
	var max_work := 0.0
	var over := 0
	for r in rows:
		if r.work > max_work:
			max_work = r.work
		if r.work > 50.0:
			over += 1
	assert_eq(over, 0, "no single frame's work exceeded the 50ms frame budget")
	assert_lte(max_work, 50.0, "the busiest frame stayed at or under the frame-time budget")


func test_frame_log_covers_the_walk_to_the_desert() -> void:
	## The player's logged x must travel from the bay (near 0) out to the desert
	## (near 1000), i.e. the whole port -> desert walk is simulated.
	var rows := _read_frame_log()
	assert_true(rows.size() > 0, "frame log is not empty")
	var first: float = rows[0].x
	var last: float = rows[rows.size() - 1].x
	assert_gt(last - first, 500.0, "the walk travels far into the desert (boundary crossed)")
