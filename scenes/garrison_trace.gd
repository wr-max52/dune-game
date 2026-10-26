extends "res://scenes/combat_trace.gd"
## The whole garrison, sound, crouching and smuggling (M15 follow-up), headless
## with real physics, each scenario in a fresh town. Reuses combat_trace.gd's
## helpers (fresh towns, the walking bot, shooting).
##
##   YARD      shoot a barracks trooper while in good standing: the town alarm goes
##             up, the klaxon sounds, the gate guards and the sentry join in, and
##             the other barracks trooper runs to the fight
##   SENTRY    wanted by daylight in the street: the tower sentry spots you from
##             up there, shouts, and raises the alarm; it never leaves the tower
##   SOUND     rifles, footsteps, radio chatter and hurt all play
##   CROUCH    the player's capsule shrinks and the eye drops; a crouched player
##             behind a barricade is not seen
##   FOUND / KEEP / RUN / BRIBEFIRST   a search turns up contraband: hand it
##             over, pay to keep it, or run (the alarm); bribing first skips it
##   SPOT      showing papers can still get your pockets turned out
##   SMUGGLE   the loop: pick up the cache outside the gate, get it past the
##             checkpoint, sell it to the fence
##
## Writes test_results/garrison_trace.txt for tests/test_garrison_trace.gut.gd.
## Run: godot --headless --fixed-fps 60 --path . -s res://scenes/garrison_trace.gd

const OUT2 := "res://test_results/garrison_trace.txt"


func _initialize() -> void:
	out_path = OUT2
	lines.append("# garrison_trace v1")
	_run()


func _run() -> void:
	seed(4242)
	await _yard()
	await _sentry()
	await _sound()
	await _crouch()
	await _found()
	await _keep()
	await _run_for_it()
	await _bribe_first()
	await _spot()
	await _smuggle()
	_scenario = ""
	kv("WORST_FRAME_MS", snappedf(worst_ms, 0.01))
	kv("WORST_FRAME_AT", _worst_where)
	_finish()


func _by_role(role: String) -> Array:
	return demo.npcs.filter(func(n): return str(n.profile.get("role", "")) == role)


func _yard() -> void:
	await _fresh("YARD", 55)
	var ya: NpcBody = demo.npc("trooper_yard_a")
	var yb: NpcBody = demo.npc("trooper_yard_b")
	var yb_post: Vector3 = yb.post_pos
	await _walk(Vector3(52, 0, 22), 30.0)
	kv("CALM_BEFORE", cp.alarm.state_name())
	await _until(func(): return _player_sees(ya), 30.0)
	for i in 3:
		if _player_sees(ya):
			_shoot_at(ya, 0.05)
		await _frames(12)
	await _frames(10)
	kv("HIT", ya.hits_taken > 0)
	kv("ALARM", cp.alarm.state_name())
	kv("ALARM_WHY", cp.alarm.why)
	kv("KLAXON", cp.klaxon_plays)
	kv("SAID_ALARM", cp.barks_said.has("alarm"))
	await _frames(30)
	var fighting := 0
	for n in demo.npcs:
		if not n.dead and cp.brains[n].state == GuardBrain.State.COMBAT:
			fighting += 1
	kv("FIGHTING", fighting)
	kv("ALIVE", _alive().size())
	kv("GATE_FIGHTING", _by_role("gate").all(func(n): return cp.brains[n].state == GuardBrain.State.COMBAT))
	kv("SENTRY_FIGHTING", cp.brains[_by_role("sentry")[0]].state == GuardBrain.State.COMBAT)
	kv("CHECKPOINT", cp.checkpoint.state_name())
	# The other barracks trooper leaves its loop toward the trouble.
	var d0 := yb.global_position.distance_to(player.global_position)
	await _hold(6.0)
	kv("B_CLOSED_IN", yb.global_position.distance_to(player.global_position) < d0 - 2.0 or yb.global_position.distance_to(yb_post) > 6.0)
	kv("FLAG_FIGHT", WorldState.has_flag("gate_fight"))
	kv("STANDING", int(WorldState.standing.imperial_remnant))


func _sentry() -> void:
	await _fresh("SENTRY", -60, "noon")
	var s: NpcBody = _by_role("sentry")[0]
	var at := s.global_position
	await _walk(Vector3(64, 0, -2), 30.0)
	var t := await _until(func(): return cp.alarm.active(), 30.0)
	kv("RAISED_AFTER_S", snappedf(t, 0.01))
	kv("ALARM_WHY", cp.alarm.why)
	kv("SAID_HALT", cp.barks_said.has("halt_hostile"))
	player.revive(30.0)
	await _hold(8.0)
	kv("SENTRY_SHOTS", s.shots_fired)
	kv("SENTRY_STAYED", s.global_position.distance_to(at) < 1.5 and s.global_position.y > 11.0)


func _sound() -> void:
	await _fresh("SOUND", -60, "noon")
	var steps_heard := false
	for f in 60 * 6:
		await physics_frame
		for n in demo.npcs:
			steps_heard = steps_heard or n.steps_playing
	kv("STEPS", steps_heard)
	await _arrive_from_desert()
	await _until(func(): return cp.alarm.active(), 8.0)
	player.revive(60.0)
	await _hold(6.0)
	var rifle := 0
	var voice := 0
	for n in demo.npcs:
		rifle += int(n.sounds_played.get("rifle", 0))
		voice += int(n.sounds_played.get("voice", 0))
	kv("RIFLE", rifle)
	kv("VOICE", voice)
	var g: NpcBody = _by_role("gate")[0]
	g.apply_damage_from(5.0, player)
	kv("HURT", int(g.sounds_played.get("hurt", 0)))
	kv("KLAXON", cp.klaxon_plays)
	kv("KLAXON_STREAM", cp.klaxon.stream != null)
	var streams := true
	for k in ["rifle", "steps", "hurt", "death"]:
		streams = streams and g._sfx.has(k) and g._sfx[k].stream != null
	kv("STREAMS_LOADED", streams)


func _crouch() -> void:
	await _fresh("CROUCH", -10)
	var h0: float = player.current_height()
	player.set_command(Vector2.ZERO, false, true, false)
	for f in 60:
		player.set_command(Vector2.ZERO, false, true, false)
		await physics_frame
	kv("STAND_H", snappedf(h0, 0.01))
	kv("CROUCH_H", snappedf(player.current_height(), 0.01))
	kv("EYE", snappedf(demo._rig.rig.fpv_offset.y, 0.01))
	# Under something low you stay down.
	var lid := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(2, 0.2, 2)
	col.shape = bx
	lid.add_child(col)
	demo.add_child(lid)
	lid.global_position = player.global_position + Vector3(0, 1.35, 0)
	for f in 5:     # still crouched while the lid lands in the physics world
		player.set_command(Vector2.ZERO, false, true, false)
		await physics_frame
	for f in 20:
		player.set_command(Vector2.ZERO, false, false, false)
		await physics_frame
	kv("STAYED_DOWN_UNDER_LID", player.crouched_shape)
	lid.queue_free()
	for f in 20:
		player.set_command(Vector2.ZERO, false, false, false)
		await physics_frame
	kv("STOOD_UP", not player.crouched_shape)
	# Crouched behind the south barricade, a guard on the other side does not see you.
	_park(Vector3(88.4, 0, -4.8))
	var g: NpcBody = demo.npc("trooper_gate_s")
	g.global_position = Vector3(97, 0.05, -4.8)
	g.perception = Perception.new(g.profile.get("perception", {}))
	cp.brains[g].state = GuardBrain.State.ATTEND
	for f in 60 * 2:
		player.set_command(Vector2.ZERO, false, true, false)
		g.face_point(player.global_position)
		await physics_frame
	kv("CROUCHED_HIDDEN", not g.perception.visible)
	for f in 60 * 2:
		player.set_command(Vector2.ZERO, false, false, false)
		g.face_point(player.global_position)
		await physics_frame
	kv("STANDING_SEEN", g.perception.visible)


func _carry(n: int) -> void:
	WorldState.inventory.add("unmarked_cells", n)


func _searched_with_cells() -> void:
	_carry(3)
	await _walk(GATE_INSIDE, 30.0, false, func(): return cp.checkpoint.card_open)
	kv("BAND", cp.checkpoint.band)
	cp.choose("search")
	await _until(func(): return cp.checkpoint.state == Checkpoint.State.FOUND or cp.checkpoint.state == Checkpoint.State.CLEARED, 6.0)


func _found() -> void:
	await _fresh("FOUND", -10)
	await _searched_with_cells()
	kv("STATE", _state())
	kv("CHOICES", ",".join(cp.checkpoint.choices.map(func(c): return str(c.id))))
	kv("SAID_FOUND", cp.barks_said.has("found"))
	kv("CHOSE", cp.choose("hand_over"))
	await _hold(0.5)
	kv("CELLS_LEFT", WorldState.inventory.count("unmarked_cells"))
	kv("FLAG", WorldState.has_flag("contraband_confiscated"))
	kv("STATE_AFTER", _state())
	kv("ALARM", cp.alarm.state_name())


func _keep() -> void:
	await _fresh("KEEP", -10, "golden", 100)
	await _searched_with_cells()
	var price := cp.checkpoint.keep_price(cp.checkpoint.found)
	kv("PRICE", price)
	kv("CHOSE", cp.choose("bribe_keep"))
	await _hold(0.5)
	kv("CREDITS", WorldState.credits)
	kv("CELLS_LEFT", WorldState.inventory.count("unmarked_cells"))
	kv("STATE_AFTER", _state())


func _run_for_it() -> void:
	await _fresh("RUN", -10)
	await _searched_with_cells()
	cp.choose("run")
	await _frames(5)
	kv("ALARM", cp.alarm.state_name())
	kv("ALARM_WHY", cp.alarm.why)
	kv("CELLS_LEFT", WorldState.inventory.count("unmarked_cells"))


func _bribe_first() -> void:
	await _fresh("BRIBEFIRST", -10, "golden", 60)
	_carry(3)
	await _walk(GATE_INSIDE, 30.0, false, func(): return cp.checkpoint.card_open)
	cp.choose("bribe")
	await _hold(0.5)
	kv("STATE", _state())
	kv("CELLS_LEFT", WorldState.inventory.count("unmarked_cells"))


func _spot() -> void:
	await _fresh("SPOT", 10)
	cp.checkpoint.cfg["spot_check_chance"] = 1.0
	_carry(1)
	await _walk(GATE_INSIDE, 30.0, false, func(): return cp.checkpoint.card_open)
	cp.choose("papers")
	kv("SAID_SPOT", cp.barks_said.has("spot_check"))
	kv("STATE", _state())
	await _until(func(): return cp.checkpoint.state == Checkpoint.State.FOUND, 6.0)
	kv("FOUND", cp.checkpoint.state == Checkpoint.State.FOUND)


func _smuggle() -> void:
	await _fresh("SMUGGLE", 10, "golden", 60)
	var gear: GearController = demo.gear
	var cache: Node3D = gear.pickup_node("desert_cache")
	kv("CACHE_PLACED", cache != null)
	if cache == null:
		return
	var at := cache.global_position
	_park(Vector3(at.x - 1.0, 0, at.z))
	await _frames(10)
	kv("PICKED", gear.interact())
	kv("CELLS", WorldState.inventory.count("unmarked_cells"))
	# Through the checkpoint on papers (no spot check here), then to the fence.
	await _walk(Vector3(104, 0, 1), 30.0)
	await _walk(GATE_INSIDE, 30.0, false, func(): return cp.checkpoint.card_open)
	# Wait at the gate for the guards to come round and ask (a patrol may be away).
	kv("CHALLENGED", await _until(func(): return cp.checkpoint.card_open, 40.0) >= 0.0)
	cp.choose("papers")
	await _hold(0.5)
	kv("THROUGH", cp.checkpoint.state == Checkpoint.State.CLEARED)
	var fence: Vector3 = demo.town.marker_pos("vendor_3")
	var path: PackedVector3Array = demo.nav.path(player.global_position, fence)
	for p in path:
		await _walk(p, 20.0)
	await _frames(10)
	var credits0 := WorldState.credits
	var sold := 0
	for i in 3:
		if gear.interact() == "sold":
			sold += 1
		await _frames(5)
	kv("SOLD", sold)
	kv("EARNED", WorldState.credits - credits0)
	kv("CELLS_AFTER", WorldState.inventory.count("unmarked_cells"))
	gear.inventory_panel.open()
	kv("PANEL_OPEN", gear.inventory_panel.is_open())
	kv("PANEL_ROWS", gear.inventory_panel.rows.size())
