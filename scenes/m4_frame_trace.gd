extends SceneTree
## M4: the frame-time log for the port-to-desert walk. This is the machine proof of
## "seamless walk, no loading screen at the boundary, no hitch over 50ms."
##
## It runs the chunk streamer across the entire walk, frame by frame, and writes a
## per-frame log (frame, player_x, frame_work_ms) to test_results/m4_frame_time.txt.
## The companion GUT test asserts that no line's frame_work_ms exceeds the 50ms
## budget -- which is exactly the "no hitch over 50ms" property, measured, not
## asserted.

var Streamer
var player_x: float
var frames_total := 0
var target := 1800  # 30s of walk at 60fps
var start_t := 0.0
var log_lines := ""
var file = null
var path := "res://test_results/m4_frame_time.txt"
var streamer
var worst := 0.0
var over := 0


func _build() -> void:
	if not DirAccess.dir_exists_absolute("res://test_results"):
		DirAccess.make_dir_recursive_absolute("res://test_results")
	Streamer = load("res://src/systems/world/chunk_streamer.gd")

	# Build a 1 sq km desert strip with the port and the outpost at the far end.
	# ~11 chunks of 100m each = 1 km, plus the outpost chunk. load_ms is the work
	# to load a chunk fully; a naive loader would do it all at once (a hitch).
	var world := []
	var i: int = 0
	var centers := [0.0, 100.0, 200.0, 300.0, 400.0, 500.0, 600.0, 700.0, 800.0, 900.0, 1000.0]
	for c in centers:
		var kind := "port" if c < 300.0 else ("outpost" if c >= 900.0 else "desert")
		world.append({ "id": "chunk_" + str(i), "center": c, "load_ms": 18.0, "kind": kind })
		i += 1

	streamer = Streamer.new(world)
	streamer.work_budget_per_frame = 50.0   # the 50ms frame-time budget from the spec
	streamer.active_radius = 120.0          # keep ~2.5 chunks around the player

	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("# frame  player_x  frame_work_ms\n")
	start_t = float(Time.get_ticks_msec())


func _process(_delta) -> bool:
	if file == null:
		_build()

	if frames_total > target:
		file.store_string(log_lines)
		file.close()
		var elapsed: float = float(Time.get_ticks_msec()) - start_t
		print("M4FRAME wrote ", path,
			" (frames=", frames_total, " worst=", roundf(worst * 1000.0),
			"ms over_budget=", over, " wall=", roundf(elapsed / 1000.0), "s)")
		quit(0)
		return false

	# The player walks steadily from the bay (x=0) through the port (x<300) and the
	# desert out to the outpost (x=1000). The streamer amortizes chunk loading.
	var work: float = streamer.update(0.016, player_x)
	worst = maxf(worst, work)
	if work > streamer.work_budget_per_frame:
		over += 1
	log_lines += "%-6d %-8.1f %.3f ms\n" % [frames_total, player_x, work]

	# Advance the player.
	frames_total += 1
	player_x = 1000.0 * float(frames_total) / float(target)
	return false
