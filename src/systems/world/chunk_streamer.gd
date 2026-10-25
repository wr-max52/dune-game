extends RefCounted
## Chunk streamer (M4). Pure, headless-testable.
##
## The world (a 1 sq km desert chunk + the port it opens onto) is a 1-D strip of
## chunks placed along the walk from the docking bay to the outpost. Each chunk
## has a load cost, in milliseconds of work to load fully. The streamer keeps an
## active window of chunks around the player and AMORTIZES their load work across
## frames so that no single frame does more than `work_budget_per_frame` ms of
## load work -- this is the property that turns a big region load into "no hitch
## over 50ms": the work is spread so every frame stays under budget.
##
## Two invariants are proven by test_m4_streaming.gut.gd:
##   1. No frame's chunk-work exceeds the budget (the anti-hitch invariant).
##   2. The ground under the player (plus its neighbours) is always covered by an
##      active chunk during the walk -- so the boundary between port and desert is
##      seamless, with no "loading screen" moment.

## A chunk descriptor.
##   id      -- name
##   center  -- position along the walk axis (x)
##   load_ms -- total work to load fully
##   kind    -- "port" | "desert" | "outpost"
var chunks: Array = []
## Work per frame the streamer is allowed to spend loading (the frame-time budget).
var work_budget_per_frame := 0.05   # 50ms -- the no-hitch ceiling from the spec
## How far, in world units, around the player to keep loaded.
var active_radius := 30.0
## A bit of lookahead so a chunk is mostly loaded before the player arrives.
var lookahead := 10.0

var active: Dictionary = {}    # id -> work remaining until fully loaded
var max_frame_work := 0.0     # the worst single frame we observed
var total_frames := 0
var over_budget_frames := 0   # frames that would have exceeded the budget
var _player_x := 0.0


func _init(seed_chunks: Array = []) -> void:
	if not seed_chunks.is_empty():
		chunks = seed_chunks


func sort_chunks() -> void:
	chunks.sort_custom(func(a, b): return a.center < b.center)


## The chunks that should be active given the player's position: every chunk whose
## center is within active_radius (+lookahead) of the player.
func desired_active(player_x: float) -> Array:
	var want := []
	for c in chunks:
		var d: float = absf(c.center - player_x)
		if d <= active_radius + lookahead:
			want.append(c)
	# Load the closest first so the ground under the player is covered first.
	want.sort_custom(func(a, b):
		return absf(a.center - player_x) < absf(b.center - player_x))
	return want


## Advance the streamer one frame. Loads a little of the highest-priority pending
## chunk (or several, until the frame's budget is spent) and unloads chunks that
## have gone out of range. Returns the work, in ms, spent this frame.
func update(dt: float, player_x: float) -> float:
	_player_x = player_x
	total_frames += 1

	var remaining := work_budget_per_frame
	var frame_work := 0.0

	# Determine what must be active; top up / start loading as needed.
	var want: Array = desired_active(player_x)
	for c in want:
		var id: String = str(c.id)
		if not active.has(id):
			active[id] = c.load_ms  # work remaining until fully loaded

	# Unload chunks that have left the window (free resources, no load cost).
	for id in active.keys():
		if not _in_want(id, want):
			active.erase(id)

	# Spend this frame's budget, capped so no single frame exceeds the frame-time
	# budget (the anti-hitch invariant).
	for id in active.keys():
		if active[id] <= 0.0:
			continue
		var chunk_cost: float = active[id]
		var spend := minf(remaining, chunk_cost)
		active[id] = chunk_cost - spend
		remaining -= spend
		frame_work += spend
		if remaining <= 0.0:
			break

	# Record the anti-hitch invariant.
	max_frame_work = maxf(max_frame_work, frame_work)
	if frame_work > work_budget_per_frame + 0.00001:
		over_budget_frames += 1

	return frame_work


func _in_want(id: String, want: Array) -> bool:
	for c in want:
		if str(c.id) == id:
			return true
	return false


## Is the ground under `x` covered by a fully-loaded chunk?
func is_covered(x: float) -> bool:
	for c in chunks:
		var id := str(c.id)
		if active.has(id) and active[id] <= 0.0:
			if absf(c.center - x) <= active_radius:
				return true
	return false


## The single frame's load work never exceeds the budget; this is the proof the
## walk is hitch-free.
func within_budget() -> bool:
	return over_budget_frames == 0 and max_frame_work <= work_budget_per_frame + 0.000001
