class_name Garrison
extends Node
## The town's Remnant garrison (M15): the director that runs every trooper in
## town, like the dogfight director runs the fighter brains. Each frame it reads
## the bodies and the world into three pure pieces and writes the results back:
##
##   Checkpoint (gate guards)   what the gate does: wave, papers, search (pockets
##                              included), bribe, warn, go hostile
##   TownAlarm  (everyone)      whether the whole garrison is fighting, and the
##                              shared last sighting; calm again when you flee,
##                              are knocked out, or nobody is left
##   GuardBrain (one each)      how each trooper does its part: patrol, attend,
##                              cover and bursts, hold a tower, search, go home
##
## Who is in it: every NpcBody with a soldier profile. Their profile's "role" says
## what they do: "gate" (on the checkpoint), "sentry" (the tower: never leaves it),
## "yard" (barracks troopers: patrol, then run to the fight on the alarm).
##
## Issue #55: a speeder ridden into town, or a ship lifting off in it, is hostile:
## the first trooper to notice it sounds the alarm and the garrison shoots its hull.
##
## It also owns: the choice card, subtitles and health bar (CheckpointHud), the
## alarm klaxon, confiscating what a search turns up, and what happens when the
## player is downed (knocked out, dragged to the pit, robbed a little).
##
## Nothing here is a number: the soldier profiles (content/core/soldiers/), the
## town's "garrison" block, the barks (content/core/dialogue/gate_guard_lines.json)
## and the sounds (content/look/npc_sounds.json).

const LINES_PATH := "res://content/core/dialogue/gate_guard_lines.json"
const CoreContent := preload("res://src/systems/dataload/core_content.gd")
const BAND_TITLES := {
	"papers": "CHECKPOINT  -  papers",
	"search": "CHECKPOINT  -  papers and a search",
	"night_hostile": "CHECKPOINT  -  they know your face",
	"found": "SEARCH  -  they found something",
}

var demo
var town
var player: CharacterBody3D
var members: Array = []           ## every NpcBody in the garrison
var guards: Array = []            ## the ones on the gate checkpoint (role "gate")
var brains: Dictionary = {}       ## NpcBody -> GuardBrain
var checkpoint: Checkpoint
var alarm: TownAlarm
var hud: CheckpointHud
var profile: Dictionary = {}      ## the gate guards' profile (checkpoint rules)
var lines: Dictionary = {}
var gate_pos := Vector3.ZERO
var spots: Array = []             ## cover spots in town (CoverPicker)
var claimed: Dictionary = {}      ## NpcBody -> Vector3 its cover spot
var content: CoreContent
var klaxon: AudioStreamPlayer3D
var klaxon_left := 0.0

## Hooks a trace can replace (the greybox has no hand weapons).
var player_armed: Callable
var knockout_s := 1.6             ## black screen before you wake in the pit

## Numbers the traces read.
var barks_said: Array = []        ## [key, ...] in order
var bark_times: Array = []        ## game seconds, one per barks_said entry
var alarm_t := -1.0               ## game seconds when the alarm last went up
var cards_shown := 0
var knockouts := 0
var kills := 0
var klaxon_plays := 0
var confiscated: Array = []       ## item ids taken by searches

var _rng := RandomNumberGenerator.new()
var _attacked := false
var _lock_left := 0.0
var _ko_left := 0.0
var _ko_done := false
var _spots_checked := false
var _spot_i := 0
var _spots_ok: Array = []
const SPOTS_PER_FRAME := 150
var _last_key := ""
var _last_key_t := -100.0
var _clock := 0.0
var _warn_left: Dictionary = {}   ## NpcBody -> seconds until a sentry/yard "halt" becomes the alarm


## `all` = every soldier NpcBody in town. Gate guards are those whose role is "gate".
func setup(town_demo, all: Array) -> void:
	demo = town_demo
	town = demo.town
	player = demo._player
	members = all
	_rng.seed = 7
	content = CoreContent.new()
	content.load_from()
	guards = members.filter(func(g): return str(g.profile.get("role", "gate")) == "gate")
	profile = guards[0].profile if guards.size() > 0 else (members[0].profile if members.size() > 0 else {})
	checkpoint = Checkpoint.new(profile.get("checkpoint", {}))
	var gcfg: Dictionary = town.data.get("garrison", {}) if town.data is Dictionary else {}
	alarm = TownAlarm.new(gcfg.get("alarm", {}))
	lines = CharacterKit._read_json(LINES_PATH).get("lines", {})
	gate_pos = town.marker_pos("gate")
	var i := 0
	for g in members:
		var b := GuardBrain.new(g.profile, 101 + i * 37)
		var m: Dictionary = town.get_marker(g.post_id)
		var pts: Array = town.route_points_3d(str(m.get("patrol", ""))) if m.has("patrol") else []
		b.patrol_points = pts if pts.size() >= 2 else [g.post_pos]
		b.post_facing = g.post_facing
		brains[g] = b
		g.sees_vehicles = true
		g.died.connect(_on_guard_died.bind(g))
		g.hit_by.connect(_on_guard_hit.bind(g))
		i += 1
	# Cover anywhere in town: the yard troopers fight wherever the alarm takes them.
	var b0 := TownNav.town_bounds(town)
	spots = CoverPicker.candidates(town.boxes(), b0.get_center(), b0.size.length())
	hud = CheckpointHud.new()
	add_child(hud)
	hud.chosen.connect(_on_chosen)
	_build_klaxon(gcfg)
	if player != null and player.has_signal("downed"):
		player.downed.connect(_on_player_downed)
		player.hurt.connect(func(_a): _hp_hud(true))


func _build_klaxon(gcfg: Dictionary) -> void:
	var c: Dictionary = NpcBody.sound_cfg().get("alarm", {})
	klaxon = AudioStreamPlayer3D.new()
	klaxon.name = "Klaxon"
	var path := str(c.get("stream", ""))
	if path != "" and ResourceLoader.exists(path):
		klaxon.stream = load(path)
	klaxon.volume_db = float(c.get("volume_db", -2.0))
	klaxon.unit_size = float(c.get("unit_size", 40.0))
	klaxon.max_distance = float(c.get("max_distance", 400.0))
	klaxon.bus = Sound.SFX_BUS
	add_child(klaxon)
	var mk := str(gcfg.get("klaxon_marker", ""))
	klaxon.position = (town.marker_pos(mk) if not town.get_marker(mk).is_empty() else gate_pos) + Vector3(0, 2.0, 0)


func _physics_process(dt: float) -> void:
	if checkpoint == null or player == null:
		return
	_clock += dt
	_check_spots()
	_tick_locks(dt)
	_tick_klaxon(dt)
	var alive := _alive()
	var ppos := _player_pos()
	var gate_noticed := false
	var seen := false
	var nearest := INF
	var recent_shot := false
	var shot_window := float(profile.get("checkpoint", {}).get("recent_shot_s", 30.0))
	for g in alive:
		var p: Perception = g.perception
		seen = seen or p.visible
		if guards.has(g):
			gate_noticed = gate_noticed or p.noticed
		if p.heard_kind == "shot" and p.since_heard < shot_window:
			recent_shot = true
		if ppos != Vector3.INF:
			nearest = minf(nearest, g.global_position.distance_to(ppos))
	var night := (profile.get("checkpoint", {}).get("night_times", ["dusk"]) as Array).has(WorldState.time_of_day)
	var vehicle := _hostile_vehicle()

	# The gate.
	var gate_alive := alive.filter(func(g): return guards.has(g))
	checkpoint.update(dt, {
		"standing": int(WorldState.standing.get("imperial_remnant", 0)), "night": night,
		"credits": WorldState.credits, "player_pos": ppos, "gate_pos": gate_pos, "gate_x": gate_pos.x,
		# Nobody asks a speeder for its papers: that is the alarm's business.
		"noticed": gate_noticed and _ko_left <= 0.0 and vehicle == null,
		"armed": player_armed.call() if player_armed.is_valid() else false,
		# Hurting a trooper is the garrison's alarm (below), not a gate matter.
		"recent_shot": recent_shot, "attacked": false,
		"guards_alive": gate_alive.size(), "contraband": contraband(),
	})
	_handle(checkpoint.drain())

	# The rest of the garrison: a remembered face, or a wanted one by daylight.
	if not alarm.active() and ppos != Vector3.INF and _ko_left <= 0.0:
		_watch_for_trouble(dt, alive, night)
	if vehicle != null and not alarm.active():
		for g in alive:
			if g.perception.noticed:
				_say(g, "contact")
				_raise("vehicle")
				break
	if _attacked:
		_raise("attacked")
	_attacked = false

	alarm.update(dt, { "seen": seen and _ko_left <= 0.0, "player_pos": ppos,
		"nearest_dist": nearest, "alive": alive.size() })
	_handle(alarm.drain())
	if alarm.active():
		checkpoint.set_alarm(true)

	_order_brains()
	for g in alive:
		_run_brain(g, dt, ppos)
	_hp_hud(false)


## Sentries and barracks troopers do not run the checkpoint, but they know a face
## the garrison remembers, and they know who is wanted on sight (by day).
func _watch_for_trouble(dt: float, alive: Array, night: bool) -> void:
	var standing := int(WorldState.standing.get("imperial_remnant", 0))
	var wanted := checkpoint.base_band(standing) == "hostile" and not night
	for g in alive:
		if guards.has(g) or not bool(g.profile.get("alarm", {}).get("raise_on_hostile_sight", false)):
			continue
		if not g.perception.noticed:
			_warn_left.erase(g)
			continue
		if alarm.remembers():
			_say(g, "contact")
			_raise("remembered")
			return
		if wanted:
			if not _warn_left.has(g):
				_warn_left[g] = float(profile.get("checkpoint", {}).get("warn_s", 3.0))
				_say(g, "halt_hostile")
			_warn_left[g] -= dt
			if _warn_left[g] <= 0.0:
				_raise("spotted")
				return


## Sound the town alarm. The checkpoint's own "hostile" already took the standing
## hit for a gate fight; anything else costs it here.
func _raise(why: String) -> void:
	if not alarm.raise(why, _player_pos()):
		return
	_handle(alarm.drain())
	if why != "gate":
		var gcfg: Dictionary = town.data.get("garrison", {}).get("alarm", {})
		WorldState.set_flag("gate_fight")
		if WorldState.cooldown_ok("gate_fight", float(profile.get("checkpoint", {}).get("standing_cooldown_s", 120.0))):
			WorldState.change_standing("imperial_remnant", int(gcfg.get("raise_standing", -10)), "The Remnant garrison sounded the alarm.")


func _order_brains() -> void:
	for g in brains:
		if g.dead:
			continue
		var b: GuardBrain = brains[g]
		if alarm.active():
			b.engage()
			b.alarm_pos = alarm.last_known
			continue
		b.alarm_pos = Vector3.INF
		if guards.has(g):
			match checkpoint.state:
				Checkpoint.State.CHALLENGE, Checkpoint.State.SEARCHING, Checkpoint.State.WARN, Checkpoint.State.FOUND:
					b.attend()
					continue
		if b.state == GuardBrain.State.ATTEND:
			b.patrol()


func _run_brain(g: NpcBody, dt: float, ppos: Vector3) -> void:
	var b: GuardBrain = brains[g]
	var vel := Vector3.ZERO
	if ppos != Vector3.INF:
		var v := _hostile_vehicle()
		vel = v.threat_velocity() if v != null else player.velocity
	g.brief(b, ppos, vel)
	b.update(dt)
	if b.want_cover:
		b.want_cover = false
		b.cover = _pick_cover(g, b)
	g.carry_out(b, dt)
	if b.bark != "":
		_say(g, b.bark)


## A cover spot for this trooper against the threat, not taken by another, within
## its profile's cover_search_radius, and on its own side of the town wall.
## Returning the spot it already holds (no better one) means "none": the brain
## then fights in the open and moves on the last known position.
func _pick_cover(g: NpcBody, b: GuardBrain) -> Vector3:
	_check_spots()
	var threat: Vector3 = b.target_pos if b.visible else b.last_seen
	if threat == Vector3.INF:
		threat = b.alarm_pos
	if threat == Vector3.INF:
		threat = _player_pos()
	if threat == Vector3.INF:
		return Vector3.INF
	var taken: Array = []
	for other in claimed:
		if other != g and not other.dead:
			taken.append(claimed[other])
	var c: Dictionary = g.profile.get("combat", {})
	var reach := float(c.get("cover_search_radius", 28.0))
	var side := signf(g.global_position.x - gate_pos.x)
	var mine: Array = []
	for sp in spots_near(g.global_position, reach):
		var sp_pos: Vector3 = sp.pos
		if signf(sp_pos.x - gate_pos.x) == side and Vector2(sp_pos.x - g.global_position.x, sp_pos.z - g.global_position.z).length() <= reach:
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


## Spots within `r` of `p`, from an 8 m grid (the town has ~2,900 spots; a full
## scan per cover request, five troopers asking every couple of seconds, made
## frame spikes).
const GRID := 8.0
var _grid: Dictionary = {}
var _grid_of: Array = []


func _cell(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / GRID), floori(z / GRID))


func spots_near(p: Vector3, r: float) -> Array:
	if not is_same(_grid_of, spots):   # identity, not a 2,900-entry compare
		_grid.clear()
		for sp in spots:
			var c := _cell((sp.pos as Vector3).x, (sp.pos as Vector3).z)
			if not _grid.has(c):
				_grid[c] = []
			_grid[c].append(sp)
		_grid_of = spots
	var out: Array = []
	var lo := _cell(p.x - r, p.z - r)
	var hi := _cell(p.x + r, p.z + r)
	for cx in range(lo.x, hi.x + 1):
		for cz in range(lo.y, hi.y + 1):
			var c := Vector2i(cx, cz)
			if _grid.has(c):
				out.append_array(_grid[c])
	return out


## Drop spots the navmesh cannot reach, a slice a frame once the mesh is in
## (thousands of nearest-point queries in one frame cost ~80 ms). Until it is
## done, picks use the spots not yet checked too.
func _check_spots() -> void:
	if _spots_checked or demo.nav == null or not demo.nav.is_ready:
		return
	var end := mini(_spot_i + SPOTS_PER_FRAME, spots.size())
	for k in range(_spot_i, end):
		var s: Dictionary = spots[k]
		var c: Vector3 = demo.nav.closest(s.pos)
		if c != Vector3.INF and Vector2(c.x - s.pos.x, c.z - s.pos.z).length() < 0.5:
			_spots_ok.append(s)
	_spot_i = end
	if _spot_i >= spots.size():
		spots = _spots_ok
		_spots_ok = []
		_spots_checked = true


# ------------------------------------------------------------------ contraband

## What the player carries that the Remnant would confiscate: [{ id, label, count, value }].
func contraband() -> Array:
	var out: Array = []
	var inv: Inventory = WorldState.inventory
	for id in inv.item_ids():
		var it: Dictionary = content.get_item(str(id))
		if bool(it.get("contraband", false)):
			out.append({ "id": str(id), "label": str(it.get("label", id)), "count": inv.count(str(id)), "value": int(it.get("value", 0)) })
	return out


# ------------------------------------------------------------------ events

func _handle(events: Array) -> void:
	for e in events:
		match str(e.type):
			"bark":
				_say(_lead(guards), str(e.key))
			"card":
				cards_shown += 1
				var title: String = BAND_TITLES.get(str(e.band), "CHECKPOINT")
				if str(e.band) == "found":
					title += ":  " + ", ".join((e.get("found", []) as Array).map(func(it): return "%s x%d" % [it.label, int(it.count)]))
				hud.show_card(title, e.choices)
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
			"confiscate":
				var names: Array = []
				for id in e.items:
					var n := WorldState.inventory.count(str(id))
					WorldState.inventory.remove(str(id), n)
					confiscated.append(str(id))
					names.append(str(content.get_item(str(id)).get("label", id)))
				WorldState.log_event("The front gate confiscated %s." % ", ".join(names).to_lower())
				hud.toast("Confiscated: " + ", ".join(names), 3.0)
			"hostile":
				_raise("gate")
			"alarm":
				alarm_t = _clock
				for g in _alive():
					g.perception.awareness = 1.0
					g.perception.noticed = true
				_say(_lead(_alive()), "alarm")
				klaxon_left = float(NpcBody.sound_cfg().get("alarm", {}).get("seconds", 8.0))
				klaxon_plays += 1
				if klaxon.stream != null and klaxon.is_inside_tree():
					klaxon.play()
				hud.toast("ALARM", 2.5)
			"calm":
				checkpoint.set_alarm(false)
				_warn_left.clear()
				for g in _alive():
					var b: GuardBrain = brains[g]
					if str(e.why) == "downed":
						b.stand_down()
					else:
						b.calm()
				claimed.clear()


func _tick_klaxon(dt: float) -> void:
	if klaxon_left <= 0.0:
		return
	klaxon_left -= dt
	if klaxon_left <= 0.0 or not alarm.active():
		klaxon_left = 0.0
		klaxon.stop()
	elif klaxon.stream != null and not klaxon.playing and klaxon.is_inside_tree():
		klaxon.play()   # loop the wail while it lasts


func _on_chosen(id: String) -> void:
	choose(id)


## Game seconds since the first time `key` was said (or -1), for traces.
func first_said(key: String) -> float:
	var i := barks_said.find(key)
	return bark_times[i] if i >= 0 else -1.0


## Pick a card choice from code (traces, tests). Same path as the card.
func choose(id: String) -> bool:
	var ok := checkpoint.answer(id)
	_handle(checkpoint.drain())
	return ok


# ------------------------------------------------------------------ troopers

func _on_guard_hit(shooter: Node, _amount: float, g: NpcBody) -> void:
	if _is_player(shooter):
		_attacked = true
		brains[g].notify_hit()
	elif shooter != null:
		brains[g].notify_hit()


func _on_guard_died(g: NpcBody) -> void:
	kills += 1
	claimed.erase(g)
	var left := _alive()
	var delta := int(g.profile.get("checkpoint", profile.get("checkpoint", {})).get("standing", {}).get("guard_killed", -15))
	WorldState.on_guard_killed(delta, left.filter(func(x): return guards.has(x)).is_empty())
	if not left.is_empty():
		_say(_nearest(left, g.global_position), "man_down")
		_attacked = true      # a trooper dropping is a fight, whoever started it


# ------------------------------------------------------------------ the player

func _on_player_downed() -> void:
	if _ko_left > 0.0:
		return
	knockouts += 1
	var lead := _lead(_alive())
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
	alarm.stand_down()
	checkpoint.on_player_downed()
	_handle(checkpoint.drain())
	_handle(alarm.drain())
	for g in _alive():
		g.perception = Perception.new(g.profile.get("perception", {}))
	hud.toast("You wake up in the pit. They took %d cr." % taken, 4.0)


## Where the garrison's target is: the player on foot, or the speeder / ship they
## are in while it is a threat in town (it carries the player's position). INF
## for nobody to fight.
func _player_pos() -> Vector3:
	if player == null or not is_instance_valid(player) or _ko_left > 0.0:
		return Vector3.INF
	if player.get("piloting") == true and _hostile_vehicle() == null:
		return Vector3.INF
	return player.global_position


## Issue #55: the speeder or ship the player is in, while it is hostile in town.
func _hostile_vehicle() -> Node:
	if player == null or not is_instance_valid(player) or player.get("piloting") != true:
		return null
	var v = player.get("vehicle")
	if v == null or not is_instance_valid(v) or not v.hostile_in_town():
		return null
	return v


## The player, or a bolt from the speeder or ship they are in.
func _is_player(shooter: Node) -> bool:
	if shooter == null:
		return false
	if shooter == player:
		return true
	var v = player.get("vehicle") if player != null and is_instance_valid(player) else null
	return v != null and is_instance_valid(v) and shooter == v.hull_body()


func _hp_hud(hurt: bool) -> void:
	if player == null or player.get("health") == null:
		return
	hud.set_hp(float(player.health.hp) / maxf(1.0, float(player.max_health)), hurt)


# ------------------------------------------------------------------ helpers

func _alive() -> Array:
	var out: Array = []
	for g in members:
		if is_instance_valid(g) and not g.dead:
			out.append(g)
	return out


## Who speaks: the living one in `among` nearest the player.
func _lead(among: Array) -> NpcBody:
	var live := among.filter(func(g): return is_instance_valid(g) and not g.dead)
	if live.is_empty() or player == null:
		return null
	return _nearest(live, player.global_position)


func _nearest(among: Array, at: Vector3) -> NpcBody:
	var best: NpcBody = null
	var bd := INF
	for g in among:
		var d: float = g.global_position.distance_to(at)
		if d < bd:
			bd = d
			best = g
	return best


func _say(g: NpcBody, key: String) -> void:
	var list: Array = lines.get(key, [])
	if g == null or list.is_empty():
		return
	# Two troopers shouting the same thing in the same breath is a choir, not a garrison.
	if key == _last_key and _clock - _last_key_t < 1.5:
		return
	_last_key = key
	_last_key_t = _clock
	var text := str(list[_rng.randi() % list.size()])
	barks_said.append(key)
	bark_times.append(_clock)
	var shout_keys: Array = NpcBody.sound_cfg().get("shout_keys", [])
	g.say(text, 2.6, shout_keys.has(key))
	if player != null and g.global_position.distance_to(player.global_position) < 35.0:
		var who: String = g.display_name if g.display_name != "" else str(g.profile.get("label", "Trooper"))
		hud.say(who, text)
