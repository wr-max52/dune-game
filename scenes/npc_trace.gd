extends SceneTree
## NPCs on foot, headless with real physics (steps 1 to 3 of the guard work):
## the navmesh bakes from the town data on a worker thread, the gate guards walk
## a patrol and a long path across town and back to their posts on the player's
## own movement code, their senses see, miss, get blocked, hear and forget the
## player, and a real bolt hurts one until it drops.
##
## Writes test_results/npc_trace.txt (KEY=value lines) for tests/test_npc_trace.gut.gd.
## Run: godot --headless --fixed-fps 60 --path . -s res://scenes/npc_trace.gd

const OUT := "res://test_results/npc_trace.txt"
const BoltScene := preload("res://scenes/entities/bolt.tscn")
const DT := 1.0 / 60.0

var demo
var player: CharacterBody3D
var lines := PackedStringArray()
var failed := false
var frame := 0
var worst_ms := 0.0
var _last_usec := 0
var _armed := false
var _crouched := false
var _done := false
var _min_y := INF
var _worst_at := 0
var _worst_phase := ""
var _phase := "start"


func _initialize() -> void:
	NoiseEvents.reset()
	demo = load("res://scenes/town_demo.gd").new()
	demo.npc_brains = false   # M15: guards hold their posts; this trace is about something else
	demo.use_look = false        # greybox: fast, and no bar or body to wait for
	demo.with_ship = false
	demo.nav_async = true        # the live path: bake on a worker thread
	get_root().add_child(demo)
	lines.append("# npc_trace v1")
	_run()


func _physics_process(_delta: float) -> bool:
	frame += 1
	var now := Time.get_ticks_usec()
	if _last_usec > 0 and frame > 5:
		var ms := (now - _last_usec) / 1000.0
		if ms > worst_ms:
			worst_ms = ms
			_worst_at = frame
			_worst_phase = _phase
	_last_usec = now
	if frame > 60 * 600 and not _done:
		fail("watchdog: the trace ran past 10 minutes of game time")
		_finish()
	return false


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func log_kv(key: String, value) -> void:
	_phase = key
	lines.append("%s=%s" % [key, str(value)])


func fail(why: String) -> void:
	failed = true
	lines.append("FAIL " + why)


func _run() -> void:
	await _frames(2)
	player = demo._player
	var north: NpcBody = demo.npc("trooper_gate_n")
	var south: NpcBody = demo.npc("trooper_gate_s")
	log_kv("NPCS", demo.npcs.size())
	if north == null or south == null:
		fail("gate guards missing")
		_finish()
		return
	# The trace drives the player's "armed" and "crouched" itself (no hand weapons in the greybox).
	for n in demo.npcs:
		n.target_armed = func(): return _armed
		n.target_crouched = func(): return _crouched
	_park_player(Vector3(0, 0, 40))   # out of everyone's sight (residential side)

	# ---- step 2: the bake
	var waited := 0
	while not demo.nav.is_ready and waited < 600:
		await physics_frame
		waited += 1
	log_kv("NAV_READY", demo.nav.is_ready)
	log_kv("NAV_READY_FRAMES", waited)
	log_kv("NAV_BAKE_MS", snappedf(demo.nav.bake_ms, 0.1))
	log_kv("NAV_POLYS", demo.nav.polygon_count())
	if not demo.nav.is_ready:
		fail("navmesh never became ready")
		_finish()
		return
	var p: PackedVector3Array = demo.nav.path(south.global_position, demo.town.marker_pos("cantina_door"))
	log_kv("NAV_PATH_GATE_TO_CANTINA_POINTS", p.size())
	var pit: PackedVector3Array = demo.nav.path(south.global_position, demo.town.spawn_pos())
	log_kv("NAV_PATH_TO_PIT_END_Y", snappedf(pit[pit.size() - 1].y, 0.1) if pit.size() > 0 else "none")
	# Inside a solid building there is no floor to stand on: the mesh must not offer one.
	var hall_c: Vector3 = demo.nav.closest(Vector3(72.5, 0, 56.5))
	log_kv("NAV_BARRACKS_CLOSEST", "%.1f,%.1f,%.1f" % [hall_c.x, hall_c.y, hall_c.z])
	log_kv("NAV_NOT_INSIDE_BARRACKS", hall_c.y > 5.0 or absf(hall_c.x - 72.5) + absf(hall_c.z - 56.5) > 1.0)

	# ---- step 1 + 2: a short patrol for the north guard
	var legs := [Vector3(88, 0, 2), Vector3(84, 0, -3), north.post_pos]
	var leg_i := 0
	for goal in legs:
		var t := await _walk(north, goal, false, 20.0)
		log_kv("PATROL_LEG_%d_S" % leg_i, snappedf(t, 0.01))
		if t < 0.0:
			fail("patrol leg %d never arrived (at %s)" % [leg_i, str(north.global_position)])
		leg_i += 1
	await _frames(40)
	var face_err := rad_to_deg(absf(wrapf(north.rotation.y - north.post_facing, -PI, PI)))
	log_kv("POST_FACING_ERR_DEG", snappedf(face_err, 0.1))
	log_kv("POST_DIST", snappedf(NpcLocomotion_flat(north.global_position - north.post_pos), 0.01))

	# ---- step 1 + 2: across town and back, running
	var door: Vector3 = demo.town.marker_pos("cantina_door")
	var path_len := _path_length(demo.nav.path(south.global_position, door))
	log_kv("LONG_PATH_LEN", snappedf(path_len, 0.1))
	var walked_before: float = south.walked_m
	var t_out := await _walk(south, door, true, 90.0, func(): _min_y = minf(_min_y, south.global_position.y); _sample(south))
	log_kv("LONG_OUT_S", snappedf(t_out, 0.01))
	log_kv("LONG_OUT_WALKED", snappedf(south.walked_m - walked_before, 0.1))
	if t_out < 0.0:
		fail("long walk to the cantina never arrived (at %s)" % str(south.global_position))
	var t_back := await _walk(south, south.post_pos, true, 90.0, func(): _min_y = minf(_min_y, south.global_position.y); _sample(south))
	log_kv("LONG_BACK_S", snappedf(t_back, 0.01))
	if t_back < 0.0:
		fail("long walk back to the post never arrived (at %s)" % str(south.global_position))
	log_kv("LONG_MIN_Y", snappedf(_min_y, 0.01))
	# Down the pit ramps to the ship and back up, running: slopes and the tight
	# turns at the ramp ends (where a running body used to circle a corner).
	_min_y = INF
	var t_pit := await _walk(south, demo.town.spawn_pos(), true, 60.0, func(): _min_y = minf(_min_y, south.global_position.y); _sample(south))
	log_kv("PIT_DOWN_S", snappedf(t_pit, 0.01))
	log_kv("PIT_MIN_Y", snappedf(_min_y, 0.01))
	if t_pit < 0.0:
		fail("walk down into the pit never arrived (at %s)" % str(south.global_position))
	var t_up := await _walk(south, south.post_pos, true, 60.0, func(): _sample(south))
	log_kv("PIT_UP_S", snappedf(t_up, 0.01))
	if t_up < 0.0:
		fail("walk up out of the pit never arrived (at %s)" % str(south.global_position))
	log_kv("STUCK_EVENTS", north.stuck_events + south.stuck_events)
	log_kv("PATH_FAILURES", north.path_failures + south.path_failures)
	log_kv("REPATHS", north.repaths + south.repaths)
	# An unreachable goal (inside the barracks hall) is reported, not walked into forever.
	south.go_to(Vector3(72.5, 0, 56.5))
	await _frames(30)
	log_kv("UNREACHABLE_FLAGGED", not south.last_path_ok)
	south.stop()
	await _walk(south, south.post_pos, false, 30.0)

	# ---- step 3: senses. The south guard looks west down the street.
	var g := south
	var gp := g.global_position
	g.face_point(gp + Vector3(-10, 0, 0))
	await _frames(40)
	await _reset_senses(g)

	# In front, 15 m, in the open: seen, then noticed.
	_park_player(gp + Vector3(-15, 0, 0))
	var rays0: int = g.rays_cast
	var notice_s := await _until(func(): return g.perception.noticed, 5.0)
	log_kv("FRONT_VISIBLE", g.perception.visible)
	await _frames(int(3.0 * 60) - int(notice_s * 60))
	log_kv("RAYS_PER_S_IN_VIEW", snappedf((g.rays_cast - rays0) / 3.0, 0.01))
	log_kv("FRONT_NOTICE_S", snappedf(notice_s, 0.01))
	if notice_s < 0.0:
		fail("a player in the open in front was never noticed")

	# Gone: awareness decays and "noticed" clears after forget_s.
	_park_player(Vector3(0, 0, 40))
	var lost_s := await _until(func(): return not g.perception.noticed, 20.0)
	log_kv("FORGET_S", snappedf(lost_s, 0.01))

	# To the side, 12 m, 90 degrees off: outside the 120 degree cone.
	await _reset_senses(g)
	_park_player(gp + Vector3(0, 0, 12))
	await _frames(180)
	log_kv("SIDE_IN_CONE", g.perception.in_cone)
	log_kv("SIDE_AWARENESS", snappedf(g.perception.awareness, 0.01))

	# Right behind, 2 m: felt at any angle.
	await _reset_senses(g)
	_park_player(gp + Vector3(2, 0, 0))
	await _frames(30)
	log_kv("CLOSE_BEHIND_VISIBLE", g.perception.visible)

	# Armed vs unarmed at the same spot (25 m): the weapon is noticed faster.
	await _reset_senses(g)
	_park_player(gp + Vector3(-25, 0, 0))
	var unarmed_s := await _until(func(): return g.perception.noticed, 8.0)
	await _reset_senses(g)
	_armed = true
	var armed_s := await _until(func(): return g.perception.noticed, 8.0)
	_armed = false
	log_kv("UNARMED_25M_NOTICE_S", snappedf(unarmed_s, 0.01))
	log_kv("ARMED_25M_NOTICE_S", snappedf(armed_s, 0.01))
	log_kv("SAW_WEAPON", g.perception.saw_weapon)

	# Crouched at 25 m: past the crouched sight range (0.6 x 32 = 19.2 m).
	await _reset_senses(g)
	_crouched = true
	await _frames(180)
	log_kv("CROUCH_25M_VISIBLE", g.perception.visible)
	_crouched = false

	# Behind the watchtower: the north guard looks right at the player, but the tower is in the way.
	var n := north
	await _reset_senses(n)
	_park_player(Vector3(91, 0, 23))
	n.face_point(Vector3(91, 0, 23))
	await _frames(180)
	log_kv("TOWER_IN_CONE", n.perception.in_cone)
	log_kv("TOWER_VISIBLE", n.perception.visible)
	log_kv("TOWER_AWARENESS", snappedf(n.perception.awareness, 0.01))
	n.clear_face()

	# Hearing: a shot 30 m away is heard (and gives a place to look), one 80 m away is not.
	_park_player(Vector3(0, 0, 40))
	await _reset_senses(g)
	NoiseEvents.emit(gp + Vector3(-30, 0, 0), 45.0, "shot")
	await _frames(2)
	log_kv("HEARD_30M", g.perception.since_heard < 0.5)
	log_kv("HEARD_POS_OK", g.perception.heard_pos.distance_to(gp + Vector3(-30, 0, 0)) < 0.01)
	log_kv("HEARD_AWARENESS", snappedf(g.perception.awareness, 0.01))
	await _reset_senses(g)
	NoiseEvents.emit(gp + Vector3(-80, 0, 0), 45.0, "shot")
	await _frames(2)
	log_kv("HEARD_80M", g.perception.since_heard < 0.5)

	g.clear_face()

	# ---- step 1: a real bolt, then down
	_park_player(gp + Vector3(-10, 0, 0))
	await _frames(5)
	var hp0: int = g.health.hp
	var b = BoltScene.instantiate()
	var from := player.global_position + Vector3(0, 1.3, 0)
	var to := g.global_position + Vector3(0, 1.1, 0)
	b.direction = (to - from).normalized()
	b.speed = 40.0
	b.damage = 15.0
	b.range_m = 60.0
	b.shooter = player
	b.sweep = true
	demo.add_child(b)
	b.global_position = from
	await _frames(40)
	log_kv("BOLT_DAMAGE", hp0 - g.health.hp)
	log_kv("FLINCH_HITS", g.hits_taken)
	while not g.dead and g.health.hp > 0:
		g.apply_damage(15.0)
	await _frames(40)
	log_kv("DEAD", g.dead)
	var q := PhysicsRayQueryParameters3D.create(g.global_position + Vector3(-2, 1.0, 0), g.global_position + Vector3(2, 1.0, 0))
	var hit: Dictionary = demo.get_world_3d().direct_space_state.intersect_ray(q)
	log_kv("DEAD_BLOCKS_RAYS", not hit.is_empty() and hit.collider == g)
	log_kv("DEAD_STAYS_PUT", NpcLocomotion_flat(g.global_position - gp) < 0.5)
	g.go_to(door)
	await _frames(60)
	log_kv("DEAD_IGNORES_ORDERS", NpcLocomotion_flat(g.global_position - gp) < 0.5)

	log_kv("WORST_FRAME_MS", snappedf(worst_ms, 0.01))
	log_kv("WORST_FRAME_AT", "%d:%s" % [_worst_at, _worst_phase])
	_finish()


## Walk `npc` to `goal`; seconds taken, or -1 on timeout. `each` runs every frame.
func _walk(npc: NpcBody, goal: Vector3, sprint: bool, timeout_s: float, each: Callable = Callable()) -> float:
	npc.go_to(goal, sprint)
	var f := 0
	while f < int(timeout_s * 60.0):
		await physics_frame
		f += 1
		if each.is_valid():
			each.call()
		if f > 3 and npc.arrived():
			npc.stop()
			return f * DT
	npc.stop()
	return -1.0


## Seconds until `cond` holds, or -1.
## A position row every half second while a guard walks: frame x y z.
func _sample(npc: NpcBody) -> void:
	if frame % 30 == 0:
		var p := npc.global_position
		lines.append("POS %s %d %.2f %.2f %.2f" % [npc.post_id, frame, p.x, p.y, p.z])


func _until(cond: Callable, timeout_s: float) -> float:
	var f := 0
	while f < int(timeout_s * 60.0):
		await physics_frame
		f += 1
		if cond.call():
			return f * DT
	return -1.0


func _reset_senses(npc: NpcBody) -> void:
	var cfg: Dictionary = npc.profile.get("perception", {})
	npc.perception = Perception.new(cfg)
	await _frames(1)


func _park_player(at: Vector3) -> void:
	player.global_position = at + Vector3(0, 0.05, 0)
	player.velocity = Vector3.ZERO
	player.controller.velocity = Vector3.ZERO
	player.set_command(Vector2.ZERO, false, false, false)


func _path_length(p: PackedVector3Array) -> float:
	var d := 0.0
	for i in range(1, p.size()):
		d += NpcLocomotion_flat(p[i] - p[i - 1])
	return d


func NpcLocomotion_flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


func _finish() -> void:
	if _done:
		return
	_done = true
	log_kv("FAILED", failed)
	if not DirAccess.dir_exists_absolute("res://test_results"):
		DirAccess.make_dir_recursive_absolute("res://test_results")
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("NPCTRACE wrote ", OUT, " failed=", failed)
	quit(1 if failed else 0)
