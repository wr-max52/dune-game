extends SceneTree
## Desert walk trace (headless, real physics). The town is seated on the desert:
## the player walks from the pit, out of the gate and 700 m into the dunes (the
## collider re-centres under them on the way), turns round and walks back in;
## stands on the sand outside the north wall; and falling through the world out in
## the desert is still caught. Writes test_results/desert_walk_trace.txt (key=value)
## for tests/test_desert_walk.gut.gd.
##
## Run: godot --headless --fixed-fps 60 --path . -s res://scenes/desert_walk_trace.gd

const OUT := "res://test_results/desert_walk_trace.txt"
const FAR_X := 700.0

var demo
var player
var terrain: DesertTerrain
var lines := PackedStringArray()
var worst_ms := 0.0
var _last := 0
var _frames := 0
var _airborne := 0          ## frames off the ground while walking the desert
var _ground_err := 0.0      ## worst |feet - ground| while on the ground in the desert
var _err_at := Vector3.ZERO


func _initialize() -> void:
	WorldState.reset()
	demo = load("res://scenes/town_demo.gd").new()
	demo.npc_brains = false   # M15: guards hold their posts; this trace is about something else
	demo.use_look = false              # greybox: the collider is the same
	get_root().add_child(demo)
	_run()


func _process(_d: float) -> bool:
	var now := Time.get_ticks_usec()
	if _last > 0 and _frames > 30:
		worst_ms = maxf(worst_ms, (now - _last) / 1000.0)
	_last = now
	_frames += 1
	return false


func out(k: String, v) -> void:
	lines.append("%s=%s" % [k, str(v)])


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func place(p: Vector3) -> void:
	player.global_position = p + Vector3(0, 0.05, 0)
	player.velocity = Vector3.ZERO
	player.controller.velocity = Vector3.ZERO
	player.controller.body_pos = player.global_position


## Sprint toward `to` (xz). Returns frames taken, or -1 if it never got there.
## `audit` = also count air frames and the feet-to-ground error on the way.
func walk_to(to: Vector3, reach: float = 0.8, max_frames: int = 9000, audit: bool = false) -> int:
	for i in max_frames:
		var p: Vector3 = player.global_position
		var d := Vector2(to.x - p.x, to.z - p.z)
		if d.length() <= reach:
			player.set_command(Vector2.ZERO, false, false, false)
			await frames(2)
			return i
		player.rotation.y = 0.0
		player.set_command(d.normalized(), true, false, false)
		await physics_frame
		if audit:
			if player.is_on_floor():
				var q: Vector3 = player.global_position
				var e := absf(q.y - terrain.ground_at(q.x, q.z))
				if e > _ground_err:
					_ground_err = e
					_err_at = q
			else:
				_airborne += 1
	player.set_command(Vector2.ZERO, false, false, false)
	return -1


func _run() -> void:
	await frames(10)
	player = demo._player
	terrain = demo.terrain
	out("TERRAIN", terrain != null)
	if terrain == null:
		_write()
		return

	# ---- the pit is still a pit: the spawn on its floor is not pushed up
	await frames(30)
	out("SPAWN_Y", snappedf(player.global_position.y, 0.01))
	out("SPAWN_ON_FLOOR", player.is_on_floor())

	# ---- up the ramp and out of the gate (the town's own route points)
	var route: Array = demo.town.route_points_3d("cantina_to_gate")
	place(demo.town.marker_pos("cantina_door"))
	await frames(5)
	var ok := true
	for pt in route:
		ok = ok and await walk_to(pt, 0.8, 3000) >= 0
	out("REACHED_GATE", ok)
	var exit: Vector3 = demo.town.marker_pos("desert_exit")
	out("REACHED_DESERT_EXIT", await walk_to(exit) >= 0)
	# A collider re-centre that lands just before this can hop the player a few cm
	# (KNOWN_ISSUES); let them settle before asking, and record how long it took.
	var settle := 0
	while not player.is_on_floor() and settle < 30:
		await physics_frame
		settle += 1
	out("EXIT_SETTLE_FRAMES", settle)
	out("EXIT_ON_FLOOR", player.is_on_floor())

	# ---- 700 m out into the dunes and back, never falling, never stuck
	var rec0 := terrain.recenters
	var lowest := INF
	var highest := -INF
	var f_out := await walk_to(Vector3(FAR_X, 0, 40.0), 1.0, 9000, true)
	out("REACHED_FAR", f_out >= 0)
	var far: Vector3 = player.global_position
	out("FAR_X", snappedf(far.x, 0.1))
	out("FAR_ON_FLOOR", player.is_on_floor())
	out("FAR_GROUND_ERR", snappedf(absf(far.y - terrain.ground_at(far.x, far.z)), 0.01))
	out("RECENTERS_OUT", terrain.recenters - rec0)
	out("COLLIDER_UNDER_FAR", terrain.collider_covers(far.x, far.z, 64.0))
	# The dunes are real: sample the height along the way out.
	for i in 50:
		var x := 120.0 + (FAR_X - 120.0) * i / 49.0
		var h := terrain.ground_at(x, 40.0 * i / 49.0)
		lowest = minf(lowest, h)
		highest = maxf(highest, h)
	out("DUNE_RANGE", snappedf(highest - lowest, 0.1))
	var f_back := await walk_to(exit + Vector3(2, 0, 0), 1.0, 9000, true)
	out("REACHED_BACK", f_back >= 0)
	out("BACK_ON_FLOOR", player.is_on_floor())
	out("BACK_Y", snappedf(player.global_position.y, 0.01))
	out("RECENTERS_TOTAL", terrain.recenters - rec0)
	out("AIR_FRAMES", _airborne)
	out("WALK_FRAMES", f_out + f_back)
	out("GROUND_ERR", snappedf(_ground_err, 0.01))
	out("GROUND_ERR_AT", "%.1f,%.2f,%.1f" % [_err_at.x, _err_at.y, _err_at.z])
	var gate_in: Vector3 = demo.town.marker_pos("gate") + Vector3(-6, 0, 0)
	out("BACK_INSIDE", await walk_to(gate_in) >= 0)
	out("RESCUES_WALKING", demo.gear.recoveries)
	# Frame cost of walking (the teleports below may rebuild the collider at once,
	# which is a load, not a frame).
	out("WORST_MS", snappedf(worst_ms, 0.01))
	out("WORST_REBUILD_STEP_MS", snappedf(terrain.worst_step_ms, 0.01))
	out("WORST_SWAP_MS", snappedf(terrain.worst_swap_ms, 0.01))
	out("SNAPS_WALKING", terrain.snaps)

	# ---- outside the north wall there is sand at the town's floor level now
	place(Vector3(-20, 0.5, 90))
	await frames(40)
	out("NORTH_OUTSIDE_ON_FLOOR", player.is_on_floor())
	out("NORTH_OUTSIDE_Y", snappedf(player.global_position.y, 0.01))

	# ---- falling through the world in the desert is still caught
	var g := terrain.ground_at(300, 60)
	place(Vector3(300, g + 0.3, 60))
	await frames(60)
	out("STOOD_IN_DESERT", player.is_on_floor())
	out("STAND_ERR", snappedf(absf(player.global_position.y - g), 0.01))
	var r0: int = demo.gear.recoveries
	player.global_position = Vector3(300, g - 40.0, 60)
	player.controller.body_pos = player.global_position
	await frames(5)
	out("FELL_RESCUED", demo.gear.recoveries - r0)
	out("RESCUED_ON_SAND", absf(player.global_position.y - g) < 1.5)

	out("STAND_COVERED", terrain.collider_covers(300, 60, 8.0))
	_write()


func _write() -> void:
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_results"))
		f = FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("DESERTTRACE wrote ", OUT, " (", lines.size(), " lines)")
	quit()
