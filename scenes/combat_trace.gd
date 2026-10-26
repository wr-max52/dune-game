extends SceneTree
## Combat NPCs at the gate (M15 part 2), headless with real physics: the gate
## guards patrol, the checkpoint treats you by your standing with the Remnant
## (wave / papers / search / hostile), bribes work one band lower after dark,
## weapons and gunfire make it worse, mouthing off and pushing through start a
## fight, and in a fight the guards take separate cover, fire in bursts and hit
## you. You can win (both guards down, standing drops), run (they search, give up,
## and remember), or get knocked out (you wake in the pit, lighter). Every
## scenario starts from a fresh town.
##
## Writes test_results/combat_trace.txt (KEY=value) for tests/test_combat_trace.gut.gd.
## Run: godot --headless --fixed-fps 60 --path . -s res://scenes/combat_trace.gd

const OUT := "res://test_results/combat_trace.txt"
const BoltScene := preload("res://scenes/entities/bolt.tscn")
const DT := 1.0 / 60.0
const GATE_INSIDE := Vector3(93.5, 0, 0)   ## in the zone, inside the gate
const DESERT := Vector3(108, 0, 0)

var demo
var cp: GateCheckpoint
var player: CharacterBody3D
var lines := PackedStringArray()
var failed := false
var frame := 0
var worst_ms := 0.0
var _last_usec := 0
var _done := false
var _armed := false
var _scenario := ""
var _worst_where := ""


func _initialize() -> void:
	lines.append("# combat_trace v1")
	_run()


func _physics_process(_delta: float) -> bool:
	frame += 1
	var now := Time.get_ticks_usec()
	if _last_usec > 0 and demo != null and demo.nav != null and demo.nav.is_ready:
		var ms := (now - _last_usec) / 1000.0
		if ms > worst_ms:
			worst_ms = ms
			_worst_where = "%s@%d" % [_scenario, frame]
	_last_usec = now
	if frame > 60 * 60 * 15 and not _done:
		fail("watchdog")
		_finish()
	return false


func kv(key: String, value) -> void:
	lines.append("%s_%s=%s" % [_scenario, key, str(value)] if _scenario != "" else "%s=%s" % [key, str(value)])


func fail(why: String) -> void:
	failed = true
	lines.append("FAIL %s: %s" % [_scenario, why])


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _until(cond: Callable, timeout_s: float) -> float:
	for f in int(timeout_s * 60.0):
		await physics_frame
		if cond.call():
			return (f + 1) * DT
	return -1.0


## A fresh town at this standing and time of day, player parked out of sight.
func _fresh(name: String, standing: int, time: String = "golden", credits: int = 60) -> void:
	_scenario = name
	if demo != null:
		# Tearing the old town down is the trace's own cost, not gameplay: stop
		# timing frames (demo = null) until the new town's navmesh is in.
		var old = demo
		demo = null
		old.queue_free()
		await _frames(2)
	WorldState.reset()
	NoiseEvents.reset()
	demo = load("res://scenes/town_demo.gd").new()
	demo.use_look = false
	demo.with_ship = false
	demo.preset = time
	get_root().add_child(demo)
	await _frames(2)
	WorldState.standing["imperial_remnant"] = standing
	WorldState.credits = credits
	WorldState.time_of_day = time
	player = demo._player
	cp = demo.checkpoint
	cp.player_armed = func(): return _armed
	cp.knockout_s = 1.0
	_armed = false
	for n in demo.npcs:
		n.target_armed = func(): return _armed
	_park(Vector3(40, 0, 40))
	await _until(func(): return demo.nav.is_ready, 10.0)
	await _frames(5)


func _park(at: Vector3) -> void:
	player.global_position = at + Vector3(0, 0.05, 0)
	player.velocity = Vector3.ZERO
	player.controller.velocity = Vector3.ZERO
	player.set_command(Vector2.ZERO, false, false, false)


## Walk the player (bot) toward `to`; stops early if `stop` holds. Seconds, or -1.
func _walk(to: Vector3, timeout_s: float, sprint: bool = false, stop: Callable = Callable()) -> float:
	player.rotation.y = 0.0
	for f in int(timeout_s * 60.0):
		var d := Vector3(to.x - player.global_position.x, 0, to.z - player.global_position.z)
		if d.length() < 0.6:
			player.set_command(Vector2.ZERO, false, false, false)
			return f * DT
		if stop.is_valid() and stop.call():
			player.set_command(Vector2.ZERO, false, false, false)
			return f * DT
		player.set_command(Vector2(d.x, d.z).normalized(), sprint, false, false)
		await physics_frame
	player.set_command(Vector2.ZERO, false, false, false)
	return -1.0


func _hold(seconds: float) -> void:
	for f in int(seconds * 60.0):
		player.set_command(Vector2.ZERO, false, false, false)
		await physics_frame


## Come in from the desert to just outside the gate and wait there until the
## checkpoint reacts (guards on their loop may need a while to look this way).
func _arrive_from_desert(to: Vector3 = Vector3(104, 0, 1)) -> void:
	_park(Vector3(135, 0, 0))
	await _walk(to, 30.0, false, func(): return cp.checkpoint.state != Checkpoint.State.IDLE)
	await _until(func(): return cp.checkpoint.state != Checkpoint.State.IDLE, 40.0)


## Hunt: shoot whoever shows; if nobody does, walk toward the nearest guard.
func _hunt(seconds: float, heal: bool) -> float:
	var cool := 0.0
	var step_left := 0.0
	for f in int(seconds * 60.0):
		if heal:
			player.health.heal(100)
		cool -= DT
		var target: NpcBody = null
		for g in _alive():
			if _player_sees(g):
				target = g
				break
		if target != null:
			player.set_command(Vector2.ZERO, false, false, false)
			if cool <= 0.0:
				_shoot_at(target)
				_hunt_shots += 1
				cool = 0.18
		else:
			var near: NpcBody = null
			for g in _alive():
				if near == null or g.global_position.distance_to(player.global_position) < near.global_position.distance_to(player.global_position):
					near = g
			if near != null:
				var p: PackedVector3Array = demo.nav.path(player.global_position, near.global_position)
				var to: Vector3 = p[1] if p.size() > 1 else near.global_position
				player.rotation.y = 0.0
				var d := Vector3(to.x - player.global_position.x, 0, to.z - player.global_position.z)
				player.set_command(Vector2(d.x, d.z).normalized(), false, false, false)
		await physics_frame
		if _alive().is_empty():
			return f * DT
	return -1.0

var _hunt_shots := 0
var _searched := false
var _shot: NpcBody = null
var _saw_warn := false


func _state() -> String:
	return cp.checkpoint.state_name()


func _alive() -> Array:
	var out: Array = []
	for g in demo.npcs:
		if not g.dead:
			out.append(g)
	return out


## The player shoots: a real bolt from the chest at a guard's chest, like the rifle.
func _shoot_at(g: NpcBody, err_m: float = 0.15) -> void:
	var from := player.global_position + Vector3(0, 1.35, 0)
	var to: Vector3 = g.global_position + Vector3(0, 0.7 if g.command.crouch else 1.2, 0)
	to += Vector3(randf_range(-err_m, err_m), randf_range(-err_m, err_m), randf_range(-err_m, err_m))
	var b = BoltScene.instantiate()
	b.direction = (to - from).normalized()
	b.speed = 48.0
	b.damage = 18.0
	b.range_m = 110.0
	b.shooter = player
	b.sweep = true
	demo.add_child(b)
	b.global_position = from + b.direction * 0.6
	NoiseEvents.emit(player.global_position, 45.0, "shot")


func _player_sees(g: NpcBody) -> bool:
	var from := player.global_position + Vector3(0, 1.5, 0)
	var to: Vector3 = g.global_position + Vector3(0, 0.7 if g.command.crouch else 1.3, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [player.get_rid()]
	var hit: Dictionary = demo.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or hit.collider == g


func _run() -> void:
	seed(12345)
	await _patrol()
	await _wave()
	await _papers()
	await _search()
	await _bribe_day()
	await _night_bribe()
	await _no_credits()
	await _armed_escalates()
	await _shot_escalates()
	await _mouth_off()
	await _push_through()
	await _fight_and_win()
	await _flee()
	await _downed()
	await _attack_friendly()
	_scenario = ""
	kv("WORST_FRAME_MS", snappedf(worst_ms, 0.01))
	kv("WORST_FRAME_AT", _worst_where)
	_finish()


# ------------------------------------------------------------------ scenarios

func _patrol() -> void:
	await _fresh("PATROL", -10)
	var start := {}
	var far := {}
	for g in demo.npcs:
		start[g] = g.walked_m
		far[g] = 0.0
	var back := {}
	for f in 60 * 30:
		await physics_frame
		for g in demo.npcs:
			far[g] = maxf(far[g], g.global_position.distance_to(g.post_pos))
			if far[g] > 4.0 and g.global_position.distance_to(g.post_pos) < 1.0:
				back[g] = true
	var i := 0
	for g in demo.npcs:
		kv("WALKED_%d" % i, snappedf(g.walked_m - start[g], 0.1))
		kv("FARTHEST_%d" % i, snappedf(far[g], 0.1))
		kv("BACK_AT_POST_%d" % i, back.has(g))
		kv("STUCK_%d" % i, g.stuck_events)
		i += 1
	kv("STATE", _state())


func _wave() -> void:
	await _fresh("WAVE", 55)
	await _walk(GATE_INSIDE, 30.0)
	await _hold(2.0)
	await _walk(DESERT, 15.0)
	await _hold(1.0)
	kv("STATE", _state())
	kv("CARDS", cp.cards_shown)
	kv("SAID_WAVE", cp.barks_said.has("wave"))
	kv("OUTSIDE", player.global_position.x > 101.0)
	kv("HOSTILE", cp.checkpoint.fights > 0)


func _papers() -> void:
	await _fresh("PAPERS", 10)
	var t := await _walk(GATE_INSIDE, 30.0, false, func(): return cp.checkpoint.card_open)
	kv("CARD_OPEN", cp.checkpoint.card_open)
	kv("BAND", cp.checkpoint.band)
	kv("CHOICES", ",".join(cp.checkpoint.choices.map(func(c): return str(c.id))))
	var before := int(WorldState.standing.imperial_remnant)
	kv("CHOSE", cp.choose("papers"))
	await _hold(0.5)
	kv("STATE", _state())
	kv("STANDING_DELTA", int(WorldState.standing.imperial_remnant) - before)
	await _walk(DESERT, 20.0)
	await _hold(1.0)
	kv("OUTSIDE", player.global_position.x > 101.0)
	kv("HOSTILE", cp.checkpoint.fights > 0)


func _search() -> void:
	await _fresh("SEARCH", -10)
	await _walk(GATE_INSIDE, 30.0, false, func(): return cp.checkpoint.card_open)
	kv("BAND", cp.checkpoint.band)
	var at := player.global_position
	kv("CHOSE", cp.choose("search"))
	# The bot keeps pushing toward the desert: the search holds it still.
	player.rotation.y = 0.0
	for f in 60:
		player.set_command(Vector2(1, 0), false, false, false)
		await physics_frame
	kv("HELD_STILL", player.global_position.distance_to(at) < 0.3)
	kv("STATE_DURING", _state())
	await _hold(3.0)
	kv("STATE", _state())
	kv("SAID", ",".join(cp.barks_said))
	await _walk(DESERT, 20.0)
	await _hold(1.0)
	kv("OUTSIDE", player.global_position.x > 101.0)
	kv("HOSTILE", cp.checkpoint.fights > 0)


func _bribe_day() -> void:
	await _fresh("BRIBE", -10, "golden", 60)
	await _walk(GATE_INSIDE, 30.0, false, func(): return cp.checkpoint.card_open)
	kv("PRICE", cp.checkpoint.bribe_price(cp.checkpoint.band, false))
	kv("CHOSE", cp.choose("bribe"))
	await _hold(0.5)
	kv("CREDITS", WorldState.credits)
	kv("FLAG", WorldState.has_flag("bribed_gate"))
	kv("STATE", _state())


func _night_bribe() -> void:
	await _fresh("NIGHT", -60, "dusk", 60)
	await _walk(GATE_INSIDE, 30.0, false, func(): return cp.checkpoint.card_open or cp.checkpoint.state != Checkpoint.State.IDLE)
	kv("BAND", cp.checkpoint.band)
	kv("CARD_OPEN", cp.checkpoint.card_open)
	kv("CHOSE", cp.choose("bribe"))
	await _hold(0.5)
	kv("CREDITS", WorldState.credits)
	kv("STATE", _state())
	kv("HOSTILE", cp.checkpoint.fights > 0)
	# The same standing in daylight is a fight (checked in FIGHT).


func _no_credits() -> void:
	await _fresh("BROKE", -60, "dusk", 10)
	await _walk(GATE_INSIDE, 30.0, false, func(): return cp.checkpoint.card_open)
	var bribe: Dictionary = {}
	for c in cp.checkpoint.choices:
		if c.id == "bribe":
			bribe = c
	kv("BRIBE_ENABLED", bribe.get("enabled", true))
	kv("CHOSE", cp.choose("bribe"))
	kv("SAID_NO_CREDITS", cp.barks_said.has("no_credits"))
	kv("CREDITS", WorldState.credits)


func _armed_escalates() -> void:
	await _fresh("ARMED", 10)
	_armed = true
	await _walk(GATE_INSIDE, 30.0, false, func(): return cp.checkpoint.card_open)
	kv("BAND", cp.checkpoint.band)


func _shot_escalates() -> void:
	await _fresh("SHOT", 10)
	await _walk(Vector3(80, 0, 0), 20.0)
	NoiseEvents.emit(player.global_position, 45.0, "shot")
	await _frames(3)
	await _walk(GATE_INSIDE, 30.0, false, func(): return cp.checkpoint.card_open)
	kv("BAND", cp.checkpoint.band)


func _mouth_off() -> void:
	await _fresh("MOUTH", 10)
	await _walk(GATE_INSIDE, 30.0, false, func(): return cp.checkpoint.card_open)
	var before := int(WorldState.standing.imperial_remnant)
	cp.choose("mouth_off")
	kv("BAND_AFTER", cp.checkpoint.band)
	kv("CARD_OPEN", cp.checkpoint.card_open)
	kv("STANDING_DELTA", int(WorldState.standing.imperial_remnant) - before)
	cp.choose("mouth_off")
	kv("STATE_AFTER_SECOND", _state())
	await _hold(4.0)
	kv("STATE", _state())


func _push_through() -> void:
	await _fresh("PUSH", 10)
	await _walk(GATE_INSIDE, 30.0, false, func(): return cp.checkpoint.card_open)
	cp.choose("walk_away")
	_saw_warn = false
	await _walk(DESERT, 15.0, false, func():
		if cp.checkpoint.state == Checkpoint.State.WARN:
			_saw_warn = true
		return false)
	await _hold(4.0)
	kv("WARNED", _saw_warn and cp.barks_said.has("warn"))
	kv("STATE", _state())


func _fight_and_win() -> void:
	await _fresh("FIGHT", -60, "noon", 60)
	var s0 := int(WorldState.standing.imperial_remnant)
	await _arrive_from_desert()
	kv("WARN_FIRST", _state() == "WARN")
	kv("SAID_HALT", cp.barks_said.has("halt_hostile"))
	var t_hostile := await _until(func(): return cp.checkpoint.state == Checkpoint.State.HOSTILE, 6.0)
	kv("HOSTILE_AFTER_S", snappedf(t_hostile, 0.01))
	# Hold still in the open and let them work: opening burst, cover, crouch, bursts.
	var crouched := {}
	var hp0: int = player.health.hp
	var fired_before := 0
	for g in demo.npcs:
		fired_before += g.shots_fired
	player.revive(0.0)
	for f in 60 * 6:
		player.set_command(Vector2.ZERO, false, false, false)
		await physics_frame
		for g in demo.npcs:
			if g.command.crouch:
				crouched[g] = true
	var spots: Array = []
	for g in demo.npcs:
		if cp.claimed.has(g):
			spots.append(cp.claimed[g])
	kv("COVER_SPOTS", spots.size())
	kv("COVER_DISTINCT", spots.size() < 2 or (spots[0] as Vector3).distance_to(spots[1]) > 1.2)
	var spot_covers := spots.size() > 0
	var same_side := true
	for at in spots:
		var ok := false
		for sp in cp.spots:
			if (sp.pos as Vector3).distance_to(at) < 0.01:
				ok = CoverPicker.covers(sp, player.global_position)
		spot_covers = spot_covers and ok
		same_side = same_side and (at as Vector3).x < cp.gate_pos.x
	kv("COVER_HIDES_FROM_PLAYER", spot_covers)
	kv("COVER_STAYS_INSIDE", same_side)
	kv("CROUCHED_BEHIND_COVER", crouched.size())
	var fired := 0
	for g in demo.npcs:
		fired += g.shots_fired
	kv("GUARD_SHOTS", fired - fired_before)
	kv("PLAYER_HP_LOST", hp0 - player.health.hp + (100 if player.is_downed else 0))
	kv("PLAYER_HITS", player.hits_taken)
	player.revive(0.0)
	# Fight back like a player who shoots well (and, being a bot, cannot be dropped).
	_hunt_shots = 0
	var won_t := await _hunt(60.0, true)
	kv("WON", _alive().is_empty())
	kv("WON_AFTER_S", snappedf(won_t, 0.01))
	kv("PLAYER_SHOTS", _hunt_shots)
	await _hold(1.0)
	kv("STATE_AFTER", _state())
	kv("STANDING_DELTA", int(WorldState.standing.imperial_remnant) - s0)
	kv("FLAG_FIGHT", WorldState.has_flag("gate_fight"))
	kv("FLAG_DOWN", WorldState.has_flag("gate_guards_down"))
	kv("KILLED", WorldState.count("guards_killed"))
	kv("CHECKPOINT_FLAG_CLEARED", not WorldState.has_flag("gate_checkpoint_up"))
	var rumors: Array = WorldState.rumors("confidant", [], 99).map(func(r): return str(r.id))
	kv("RUMOR_FIGHT", rumors.has("r_gate_fight"))
	kv("RUMOR_DEAD", rumors.has("r_gate_dead"))
	# And out through the gate nobody holds.
	await _walk(DESERT + Vector3(10, 0, 0), 20.0)
	kv("OUTSIDE", player.global_position.x > 101.0)


func _flee() -> void:
	await _fresh("FLEE", -60, "noon", 60)
	await _arrive_from_desert()
	await _until(func(): return cp.checkpoint.state == Checkpoint.State.HOSTILE, 6.0)
	kv("WAS_HOSTILE", cp.checkpoint.state == Checkpoint.State.HOSTILE)
	var s0 := int(WorldState.standing.imperial_remnant)
	player.revive(60.0)                     # do not get dropped while running
	var t := await _walk(Vector3(178, 0, 2), 40.0, true)
	kv("RAN", t >= 0.0)
	var calm_t := await _until(func(): return cp.checkpoint.state == Checkpoint.State.IDLE, 30.0)
	kv("GAVE_UP_AFTER_S", snappedf(calm_t, 0.01))
	kv("FLAG_FLED", WorldState.has_flag("fled_gate_fight"))
	kv("STANDING_DELTA", int(WorldState.standing.imperial_remnant) - s0)
	_searched = false
	var back := await _until(func():
		for g in demo.npcs:
			if cp.brains[g].state == GuardBrain.State.SEARCH:
				_searched = true
		var all_home := true
		for g in demo.npcs:
			all_home = all_home and cp.brains[g].state == GuardBrain.State.PATROL
		return all_home, 40.0)
	kv("SEARCHED", _searched)
	var leash := 0.0
	for g in demo.npcs:
		leash = maxf(leash, g.global_position.distance_to(cp.gate_pos))
	kv("FARTHEST_FROM_GATE_AFTER", snappedf(leash, 0.1))
	kv("BACK_ON_PATROL_S", snappedf(back, 0.01))
	# They remember: walk back to the gate.
	await _walk(Vector3(104, 0, 1), 40.0, false, func(): return cp.checkpoint.state == Checkpoint.State.HOSTILE)
	await _until(func(): return cp.checkpoint.state == Checkpoint.State.HOSTILE, 40.0)
	kv("REMEMBERED", cp.checkpoint.state == Checkpoint.State.HOSTILE)
	kv("SAID_CONTACT_ON_RETURN", cp.barks_said.count("contact") >= 2)


func _downed() -> void:
	await _fresh("DOWNED", -60, "noon", 50)
	await _arrive_from_desert()
	await _until(func(): return cp.checkpoint.state == Checkpoint.State.HOSTILE, 6.0)
	# Stand in the open and take it.
	var t := await _until(func(): return player.is_downed or cp.knockouts > 0, 60.0)
	kv("DOWNED_AFTER_S", snappedf(t, 0.01))
	await _until(func(): return not player.is_downed and not player.locked, 5.0)
	await _frames(5)
	kv("WOKE_IN_PIT", player.global_position.y < -5.0)
	kv("HP_AFTER", player.health.hp)
	kv("CREDITS", WorldState.credits)
	kv("STATE", _state())
	var home := await _until(func():
		for g in demo.npcs:
			if cp.brains[g].state == GuardBrain.State.COMBAT:
				return false
		return true, 10.0)
	kv("GUARDS_STOOD_DOWN", home >= 0.0)


func _attack_friendly() -> void:
	await _fresh("SNEAK", 55)
	await _walk(GATE_INSIDE, 30.0)
	await _hold(1.0)
	kv("WAVED", cp.checkpoint.state == Checkpoint.State.CLEARED)
	# Shoot the first guard in sight (wait for one to come round on its loop).
	_shot = null
	await _until(func():
		for g in demo.npcs:
			if _player_sees(g) and g.global_position.distance_to(player.global_position) < 25.0:
				_shot = g
				return true
		return false, 30.0)
	var shot := _shot
	for i in 4:
		if shot != null and _player_sees(shot):
			_shoot_at(shot, 0.05)
		await _frames(12)
	await _frames(20)
	kv("HIT", shot != null and shot.hits_taken > 0)
	kv("STATE", _state())
	var other: NpcBody = null
	for g in demo.npcs:
		if g != shot:
			other = g
	kv("OTHER_FIGHTING", other != null and (other.dead or cp.brains[other].state == GuardBrain.State.COMBAT))


func _finish() -> void:
	if _done:
		return
	_done = true
	_scenario = ""
	kv("FAILED", failed)
	if not DirAccess.dir_exists_absolute("res://test_results"):
		DirAccess.make_dir_recursive_absolute("res://test_results")
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("COMBATTRACE wrote ", OUT, " failed=", failed)
	quit(1 if failed else 0)
