class_name GateCheckpoint
extends Node
## The gate checkpoint in the town (M15): the director that runs the gate guards,
## like the dogfight director runs the fighter brains. Each frame it reads the
## bodies and the world into the pure Checkpoint (what the gate does: wave,
## papers, search, bribe, warn, fight) and one GuardBrain per guard (how each
## guard does it: patrol, attend, cover and bursts, search, return), then writes
## the results back onto the bodies, the choice card, the guards' lines and
## WorldState. It also owns what happens when the player is downed: knocked out,
## dragged to the pit, robbed a little.
##
## Nothing here is a number: everything comes from the soldier profile
## (content/core/soldiers/gate_guard.json) and the barks from
## content/core/dialogue/gate_guard_lines.json.

const LINES_PATH := "res://content/core/dialogue/gate_guard_lines.json"
const BAND_TITLES := {
	"papers": "CHECKPOINT  -  papers",
	"search": "CHECKPOINT  -  papers and a search",
	"night_hostile": "CHECKPOINT  -  they know your face",
}

var demo
var town
var player: CharacterBody3D
var guards: Array = []            ## NpcBody
var brains: Dictionary = {}       ## NpcBody -> GuardBrain
var checkpoint: Checkpoint
var hud: CheckpointHud
var profile: Dictionary = {}
var lines: Dictionary = {}
var gate_pos := Vector3.ZERO
var spots: Array = []             ## cover spots near the gate (CoverPicker)
var claimed: Dictionary = {}      ## NpcBody -> Vector3 its cover spot

## Hooks a trace can replace (the greybox has no hand weapons).
var player_armed: Callable
var knockout_s := 1.6             ## black screen before you wake in the pit

## Numbers the traces read.
var barks_said: Array = []        ## [key, ...] in order
var cards_shown := 0
var knockouts := 0
var kills := 0

var _rng := RandomNumberGenerator.new()
var _unseen_s := 0.0
var _attacked := false
var _lock_left := 0.0
var _ko_left := 0.0
var _ko_done := false
var _spots_checked := false
var _last_key := ""
var _last_key_t := -100.0
var _clock := 0.0


func setup(town_demo, gate_guards: Array) -> void:
	demo = town_demo
	town = demo.town
	player = demo._player
	guards = gate_guards
	_rng.seed = 7
	profile = guards[0].profile if guards.size() > 0 else {}
	checkpoint = Checkpoint.new(profile.get("checkpoint", {}))
	lines = CharacterKit._read_json(LINES_PATH).get("lines", {})
	gate_pos = town.marker_pos("gate")
	var i := 0
	for g in guards:
		var b := GuardBrain.new(g.profile, 101 + i * 37)
		var m: Dictionary = town.get_marker(g.post_id)
		var pts: Array = town.route_points_3d(str(m.get("patrol", ""))) if m.has("patrol") else []
		b.patrol_points = pts if pts.size() >= 2 else [g.post_pos]
		b.post_facing = g.post_facing
		brains[g] = b
		g.died.connect(_on_guard_died.bind(g))
		g.hit_by.connect(_on_guard_hit.bind(g))
		i += 1
	var radius := float(profile.get("combat", {}).get("cover_search_radius", 28.0))
	spots = CoverPicker.candidates(town.boxes(), gate_pos, radius)
	hud = CheckpointHud.new()
	add_child(hud)
	hud.chosen.connect(_on_chosen)
	if player != null and player.has_signal("downed"):
		player.downed.connect(_on_player_downed)
		player.hurt.connect(func(_a): _hp_hud(true))


func _physics_process(dt: float) -> void:
	if checkpoint == null or player == null:
		return
	_clock += dt
	_tick_locks(dt)
	var alive := _alive()
	var ppos := _player_pos()
	var noticed := false
	var seen := false
	var recent_shot := false
	var shot_window := float(profile.get("checkpoint", {}).get("recent_shot_s", 30.0))
	for g in alive:
		var p: Perception = g.perception
		noticed = noticed or p.noticed
		seen = seen or p.visible
		if p.heard_kind == "shot" and p.since_heard < shot_window:
			recent_shot = true
	_unseen_s = 0.0 if seen else _unseen_s + dt
	var night := (profile.get("checkpoint", {}).get("night_times", ["dusk"]) as Array).has(WorldState.time_of_day)
	checkpoint.update(dt, {
		"standing": int(WorldState.standing.get("imperial_remnant", 0)), "night": night,
		"credits": WorldState.credits, "player_pos": ppos, "gate_pos": gate_pos, "gate_x": gate_pos.x,
		"noticed": noticed and _ko_left <= 0.0, "unseen_s": _unseen_s,
		"armed": player_armed.call() if player_armed.is_valid() else false,
		"recent_shot": recent_shot, "attacked": _attacked, "guards_alive": alive.size(),
	})
	_attacked = false
	_handle(checkpoint.drain())
	_order_brains()
	for g in alive:
		_run_brain(g, dt, ppos)
	_hp_hud(false)


func _order_brains() -> void:
	for g in brains:
		if g.dead:
			continue
		var b: GuardBrain = brains[g]
		match checkpoint.state:
			Checkpoint.State.HOSTILE:
				b.engage()
			Checkpoint.State.CHALLENGE, Checkpoint.State.SEARCHING, Checkpoint.State.WARN:
				b.attend()
			_:
				if b.state == GuardBrain.State.ATTEND:
					b.patrol()


func _run_brain(g: NpcBody, dt: float, ppos: Vector3) -> void:
	var b: GuardBrain = brains[g]
	var p: Perception = g.perception
	b.pos = g.global_position
	b.facing = g.rotation.y
	b.hp_frac = float(g.health.hp) / maxf(1.0, float(g.max_health))
	b.arrived = g.arrived()
	b.visible = p.visible
	b.target_pos = ppos
	b.target_vel = player.velocity if ppos != Vector3.INF else Vector3.ZERO
	b.target_chest = g.target_chest_height()
	b.last_seen = p.last_seen_pos
	b.heard_pos = p.heard_pos
	b.reloading = g.reloading()
	# A calm guard turns toward footsteps or a shot it just heard.
	if p.heard and not p.visible:
		b.investigate(p.heard_pos)
	b.update(dt)
	if b.want_cover:
		b.want_cover = false
		b.cover = _pick_cover(g, b)
	# Apply: the fighter pattern, outputs onto the body.
	if b.go_to == Vector3.INF:
		if g.command.go_to != Vector3.INF:
			g.stop()
	else:
		g.go_to(b.go_to, b.sprint)
	g.command.sprint = b.sprint
	g.command.crouch = b.crouch
	if b.face != Vector3.INF:
		g.face_point(b.face)
	else:
		g.clear_face()
	g.aim_point = b.aim
	if b.fire and b.aim != Vector3.INF:
		if g.fire_at(b.aim, dt):
			b.on_shot()
	else:
		g.hold_fire(dt)
	if b.bark != "":
		_say(g, b.bark)


## A cover spot for this guard against the threat, not taken by another guard.
## Returning the spot it already holds (no better one) means "none": the brain
## then fights in the open and moves on the last known position.
func _pick_cover(g: NpcBody, b: GuardBrain) -> Vector3:
	_check_spots()
	var threat: Vector3 = b.target_pos if b.visible else b.last_seen
	if threat == Vector3.INF:
		threat = _player_pos()
	if threat == Vector3.INF:
		return Vector3.INF
	var taken: Array = []
	for other in claimed:
		if other != g and not other.dead:
			taken.append(claimed[other])
	var c: Dictionary = profile.get("combat", {})
	# Stay on your own side of the gate: never run past the threat for a wall.
	var side := signf(g.global_position.x - gate_pos.x)
	var mine: Array = []
	for sp in spots:
		if signf((sp.pos as Vector3).x - gate_pos.x) == side:
			mine.append(sp)
	var i := CoverPicker.pick(g.global_position, threat, mine, taken,
		float(c.get("cover_min_threat_dist", 6.0)), float(c.get("cover_max_threat_dist", 40.0)))
	if i < 0:
		claimed.erase(g)
		return Vector3.INF
	var p: Vector3 = mine[i].pos
	if claimed.has(g) and (claimed[g] as Vector3).distance_to(p) < 1.2 and g.global_position.distance_to(p) < 1.5:
		claimed.erase(g)
		return Vector3.INF
	claimed[g] = p
	return p


## Drop spots the navmesh cannot reach (once it is in).
func _check_spots() -> void:
	if _spots_checked or demo.nav == null or not demo.nav.is_ready:
		return
	_spots_checked = true
	var keep: Array = []
	for s in spots:
		var c: Vector3 = demo.nav.closest(s.pos)
		if c != Vector3.INF and Vector2(c.x - s.pos.x, c.z - s.pos.z).length() < 0.5:
			keep.append(s)
	spots = keep


# ------------------------------------------------------------------ checkpoint events

func _handle(events: Array) -> void:
	for e in events:
		match str(e.type):
			"bark":
				_say(_lead(), str(e.key))
			"card":
				cards_shown += 1
				hud.show_card(BAND_TITLES.get(str(e.band), "CHECKPOINT"), e.choices)
			"card_close":
				hud.hide_card()
			"lock_player":
				player.locked = true
				_lock_left = float(e.seconds)
			"standing":
				var key := str(e.get("cooldown", ""))
				var cd := float(profile.get("checkpoint", {}).get("standing_cooldown_s", 120.0))
				if key == "" or WorldState.cooldown_ok(key, cd):
					WorldState.change_standing("imperial_remnant", int(e.delta), str(e.get("why", "")))
			"bribe":
				WorldState.on_gate_bribe(int(e.price))
				hud.toast("-%d cr" % int(e.price), 2.0)
			"flag":
				WorldState.set_flag(str(e.name))
			"hostile":
				for g in _alive():
					g.perception.awareness = 1.0
					g.perception.noticed = true
			"calm":
				for g in _alive():
					var b: GuardBrain = brains[g]
					if str(e.why) == "downed":
						b.stand_down()
					else:
						b.calm()
				claimed.clear()


func _on_chosen(id: String) -> void:
	choose(id)


## Pick a card choice from code (traces, tests). Same path as the card.
func choose(id: String) -> bool:
	var ok := checkpoint.answer(id)
	_handle(checkpoint.drain())
	return ok


# ------------------------------------------------------------------ guards

func _on_guard_hit(shooter: Node, _amount: float, g: NpcBody) -> void:
	if shooter == player:
		_attacked = true
		brains[g].notify_hit()
	elif shooter != null:
		brains[g].notify_hit()


func _on_guard_died(g: NpcBody) -> void:
	kills += 1
	claimed.erase(g)
	var left := _alive()
	var delta := int(profile.get("checkpoint", {}).get("standing", {}).get("guard_killed", -15))
	WorldState.on_guard_killed(delta, left.is_empty())
	if not left.is_empty():
		_say(left[0], "man_down")
		_attacked = true      # a guard dropping is a fight, whoever started it


# ------------------------------------------------------------------ the player

func _on_player_downed() -> void:
	if _ko_left > 0.0:
		return
	knockouts += 1
	var lead := _lead()
	if lead != null:
		_say(lead, "downed")
	player.locked = true
	_ko_left = knockout_s
	_ko_done = false
	hud.hide_card()


func _tick_locks(dt: float) -> void:
	if _lock_left > 0.0:
		_lock_left -= dt
		if _lock_left <= 0.0 and _ko_left <= 0.0:
			player.locked = false
	if _ko_left > 0.0:
		_ko_left -= dt
		hud.fade.color.a = clampf(1.0 - _ko_left / knockout_s * 0.5, 0.0, 1.0)
		if _ko_left <= 0.0 and not _ko_done:
			_ko_done = true
			_wake_in_pit()
	elif hud.fade.color.a > 0.0:
		hud.fade.color.a = maxf(0.0, hud.fade.color.a - dt * 1.5)


func _wake_in_pit() -> void:
	var taken := WorldState.on_player_downed()
	player.global_position = town.spawn_pos() + Vector3(0, 0.05, 0)
	player.velocity = Vector3.ZERO
	player.controller.velocity = Vector3.ZERO
	player.revive()
	player.locked = false
	checkpoint.on_player_downed()
	_handle(checkpoint.drain())
	for g in _alive():
		g.perception = Perception.new(g.profile.get("perception", {}))
	hud.toast("You wake up in the pit. They took %d cr." % taken, 4.0)


func _player_pos() -> Vector3:
	if player == null or not is_instance_valid(player) or player.get("piloting") == true or _ko_left > 0.0:
		return Vector3.INF
	return player.global_position


func _hp_hud(hurt: bool) -> void:
	if player == null or player.get("health") == null:
		return
	hud.set_hp(float(player.health.hp) / maxf(1.0, float(player.max_health)), hurt)


# ------------------------------------------------------------------ helpers

func _alive() -> Array:
	var out: Array = []
	for g in guards:
		if is_instance_valid(g) and not g.dead:
			out.append(g)
	return out


## The guard who speaks for the gate: the one nearest the player.
func _lead() -> NpcBody:
	var best: NpcBody = null
	var bd := INF
	var pp := player.global_position
	for g in _alive():
		var d: float = g.global_position.distance_to(pp)
		if d < bd:
			bd = d
			best = g
	return best


func _say(g: NpcBody, key: String) -> void:
	var list: Array = lines.get(key, [])
	if g == null or list.is_empty():
		return
	# Two guards shouting the same thing in the same breath is a choir, not a gate.
	if key == _last_key and _clock - _last_key_t < 1.5:
		return
	_last_key = key
	_last_key_t = _clock
	var text := str(list[_rng.randi() % list.size()])
	barks_said.append(key)
	g.say(text)
	if player != null and g.global_position.distance_to(player.global_position) < 35.0:
		hud.say("Gate guard", text)
