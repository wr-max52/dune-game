extends GutTest
## Issue #121: a no-fade handoff builds the destination over several frames.
## StagedBuild runs a scene's build plan in order under a per-frame budget;
## AltitudeDetail hides groups added after the tier is set; a handoff-mode town
## built in stages ends up the same as one built all at once, and the ship
## carries on exactly as it was handed over.

const HANDOFF_POS := Vector3(1400, 2300, -900)
const HANDOFF_SPEED := 250.0
const HANDOFF_THROTTLE := 0.8


func after_each() -> void:
	GameFlow.reset()


# ---------------------------------------------------------------- the runner

func _sleep_step(ran: Array, step_name: String, ms: float) -> Callable:
	return func():
		OS.delay_usec(int(ms * 1000.0))
		ran.append(step_name)
		return true


func test_runner_keeps_order_and_budget() -> void:
	var ran: Array = []
	var sb := StagedBuild.new()
	sb.budget_ms = 5.0
	for i in 8:
		sb.add("s%d" % i, _sleep_step(ran, "s%d" % i, 2.0))
	add_child_autofree(sb)
	var frames := 0
	while not sb.done and frames < 100:
		sb.run_frame()
		frames += 1
	assert_true(sb.done)
	assert_eq(ran, ["s0", "s1", "s2", "s3", "s4", "s5", "s6", "s7"], "in plan order")
	assert_gt(sb.frames_used, 2, "spread over frames")
	# A frame stops once over budget: at most budget + one more step.
	assert_lt(sb.worst_frame_ms, 5.0 + 2.0 + 3.0, "never far past the budget")
	assert_eq(sb.history.size(), 8)


func test_one_long_step_runs_whole_on_its_own_frame() -> void:
	var ran: Array = []
	var sb := StagedBuild.new()
	sb.budget_ms = 4.0
	sb.add("a", _sleep_step(ran, "a", 1.0))
	sb.add("long", _sleep_step(ran, "long", 20.0))
	sb.add("b", _sleep_step(ran, "b", 1.0))
	add_child_autofree(sb)
	while not sb.done:
		sb.run_frame()
	assert_eq(ran, ["a", "long", "b"])
	assert_gte(float(sb.step_ms["long"]), 19.0, "a step is never cut short")


func test_poll_steps_wait_without_blocking_order() -> void:
	var ran: Array = []
	var polls := [0]
	var sb := StagedBuild.new()
	sb.add("first", _sleep_step(ran, "first", 0.1))
	sb.add_poll("wait", func(_left):
		polls[0] += 1
		return polls[0] >= 4)
	sb.add("after", _sleep_step(ran, "after", 0.1))
	add_child_autofree(sb)
	var frames := 0
	while not sb.done and frames < 50:
		sb.run_frame()
		frames += 1
		if not sb.done and polls[0] < 4:
			assert_false(ran.has("after"), "nothing after a poll runs before it finishes")
	assert_true(sb.done)
	assert_eq(polls[0], 4, "polled once a frame until it said done")
	assert_eq(ran, ["first", "after"])


func test_a_failed_step_stops_the_build_cleanly() -> void:
	var ran: Array = []
	var sb := StagedBuild.new()
	sb.add("ok", _sleep_step(ran, "ok", 0.1))
	sb.add("bad", func(): return null)
	sb.add("never", _sleep_step(ran, "never", 0.1))
	add_child_autofree(sb)
	watch_signals(sb)
	for i in 5:
		sb.run_frame()
	assert_eq(sb.failed_step, "bad")
	assert_false(sb.done)
	assert_eq(ran, ["ok"], "the rest is skipped")
	assert_signal_emitted(sb, "failed")


func test_run_all_is_one_frame_in_order() -> void:
	var ran: Array = []
	var sb := StagedBuild.new()
	for i in 4:
		sb.add("s%d" % i, _sleep_step(ran, "s%d" % i, 2.0))
	var polls := [0]
	sb.add_poll("p", func(_left):
		polls[0] += 1
		return polls[0] >= 3)
	sb.run_all()
	assert_true(sb.done)
	assert_eq(ran, ["s0", "s1", "s2", "s3"])
	assert_eq(sb.frames_used, 1)
	sb.free()


# ---------------------------------------------------------------- altitude detail

func test_groups_added_late_take_the_current_tier() -> void:
	var d := AltitudeDetail.new()
	d.setup({ "hysteresis": 50.0, "tiers": [{ "above": 500.0, "off": [], "hide": ["people"] }] })
	var early := Node3D.new()
	d.add_group("people", [early])
	d.update_for(2000.0)
	assert_false(early.visible, "registered first, hidden by the climb")
	var late := Node3D.new()
	var props := Node3D.new()
	d.add_group("people", [late, early])
	d.add_group("props", [props])
	assert_false(late.visible, "built while high up: hidden at once")
	assert_eq(late.process_mode, Node.PROCESS_MODE_DISABLED, "and not running")
	assert_true(props.visible, "a group the tier does not hide is left alone")
	assert_eq(d.groups.people.size(), 2, "a node is only added once")
	d.update_for(0.0)
	assert_true(late.visible, "back on the way down")
	assert_eq(late.process_mode, Node.PROCESS_MODE_INHERIT)
	for n in [early, late, props]:
		n.free()
	d.free()


func test_groups_added_at_full_detail_are_untouched() -> void:
	var d := AltitudeDetail.new()
	d.setup({ "tiers": [{ "above": 500.0, "hide": ["people"] }] })
	var n := Node3D.new()
	n.visible = false                 # hidden for its own reasons
	d.add_group("people", [n])
	assert_false(n.visible, "registering never shows a node")
	n.free()
	d.free()


# ---------------------------------------------------------------- a staged town

func _arrive(staged: bool) -> Node:
	WorldState.reset()
	GameFlow.reset()
	GameFlow.change_scene = func(_p: String) -> void: pass
	GameFlow.planet_id = "grit_station"
	GameFlow.flown_ship = "interceptor"
	var b := Basis.looking_at((-HANDOFF_POS).normalized(), Vector3.UP)
	GameFlow.arrival = { "mode": "handoff", "from": "port_desert", "to": "grit_station", "ship": "interceptor",
		"name": "", "pad": "", "hour": 10.0, "preset": "",
		"handoff": { "position": HANDOFF_POS, "basis": b, "speed": HANDOFF_SPEED, "throttle": HANDOFF_THROTTLE } }
	var demo = load("res://scenes/town_demo.gd").new()
	demo.use_look = true            # the far mesh and the people: what staging is for
	demo.with_body = false          # the player's body and the bar are slow and not what is tested
	demo.with_bar = false
	demo.npc_brains = false
	demo.staged_handoff = staged
	add_child_autofree(demo)
	return demo


func _names(demo: Node) -> Array:
	var out: Array = []
	for c in demo.get_children():
		out.append(str(c.name).rstrip("0123456789@"))
	out.sort()
	return out


func test_a_staged_handoff_ends_like_a_whole_build() -> void:
	var whole = _arrive(false)
	assert_false(whole.staging)
	assert_true(whole.staged.done, "a normal build is done on its first frame")
	var whole_names := _names(whole)
	var whole_far: int = whole.terrain.far_root.get_child_count()
	var whole_people: int = whole.detail.groups.get("people", []).size()
	var whole_npcs: int = whole.npcs.size() + whole.locals.size() + whole.stage_performers.size()
	whole.queue_free()
	await wait_frames(3)

	var demo = _arrive(true)
	assert_true(demo.staging)
	assert_false(demo.staged.done, "only the shell on the first frame")
	var pt: PlanetTerrain = demo.terrain
	assert_eq(pt.far_root.get_child_count(), 96, "the whole ball is there at once, no hole")
	assert_lt(pt.far_detail_cells, pt.far_cells, "coarse at first")
	assert_null(pt.town_body, "the town collider is still on its worker")
	assert_not_null(demo.pilot, "the ship flies from the first frame")
	assert_true(demo.pilot.piloting)
	assert_eq(demo.npcs.size() + demo.locals.size(), 0, "people come later")
	# The ship as carried, exactly once.
	assert_almost_eq(demo.pilot.atmo.position().distance_to(HANDOFF_POS), 0.0, 0.001)
	assert_almost_eq(demo.pilot.atmo.speed(), HANDOFF_SPEED, 0.001)
	assert_almost_eq(demo.pilot._throttle, HANDOFF_THROTTLE, 0.0001)
	var frames := 0
	var prev: Vector3 = demo.pilot.atmo.position()
	var worst_jump := 0.0
	while not demo.staged.done and frames < 3000:
		await get_tree().physics_frame
		frames += 1
		var now: Vector3 = demo.pilot.atmo.position()
		worst_jump = maxf(worst_jump, now.distance_to(prev) / maxf(demo.pilot.atmo.speed() / 60.0, 0.01))
		prev = now
	assert_true(demo.staged.done, "the staged build finishes")
	assert_eq(demo.staged.failed_step, "")
	assert_lt(worst_jump, 1.5, "the ship never jumps while the rest is built")
	assert_true(demo.pilot.piloting, "still flying")
	assert_eq(_names(demo), whole_names, "the same scene as a whole build")
	assert_eq(pt.far_root.get_child_count(), whole_far)
	assert_eq(pt.far_detail_cells, pt.far_cells, "full detail once settled")
	assert_eq(pt.far_detail_cells, 64)
	assert_true(pt.far_refined)
	assert_not_null(pt.town_body, "the town collider is in")
	assert_eq(demo.npcs.size() + demo.locals.size() + demo.stage_performers.size(), whole_npcs, "the same people")
	assert_eq(demo.detail.groups.get("people", []).size(), whole_people, "all registered for detail")
	assert_true(demo.detail.hidden_groups().has("people"), "high up: people held off")
	var npcs: Node3D = demo.get_node_or_null("Npcs")
	assert_true(npcs != null and not npcs.visible, "and the ones built late stay hidden")


func test_staging_off_builds_a_handoff_whole() -> void:
	var demo = _arrive(false)
	assert_false(demo.staging, "the export flag switches it off")
	assert_true(demo.staged.done)
	assert_eq(demo.staged.shell_ms, 0.0, "nothing split off")
	assert_eq((demo.terrain as PlanetTerrain).far_detail_cells, 64)
	assert_almost_eq(demo.pilot.atmo.position().distance_to(HANDOFF_POS), 0.0, 0.001)
