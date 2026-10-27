extends SceneTree
## Issue #42 trace (headless): out the back gate to Skrugs, buy a speeder, ride it
## off the ramp, take a bolt, get off. Real physics, the real town (greybox), the
## real conversation pipeline with a scripted model (the same parser, validator
## and filter a live model goes through). Writes test_results/speeder_trace.txt
## (KEY=value lines) for tests/test_speeder_trace.gut.gd.
##
##   1. Walk from inside the back gate, through it, to Skrugs's stall.
##   2. Talk: ask the price. The model proposes offer_speeder; the price card
##      comes up; the player clicks Buy. 100 credits, a speeder behind the house.
##   3. Climb on, ride to the ramp's run-up, then straight up the ramp and off it.
##   4. A bolt hits the hull. Get off beside it.
##
## Run: godot --headless --fixed-fps 60 --path . -s res://scenes/speeder_trace.gd

const OUT := "res://test_results/speeder_trace.txt"
const BoltScene := preload("res://scenes/entities/bolt.tscn")

var demo
var post: SpeederPost
var player
var lines := PackedStringArray()
var worst_ms := 0.0
var _last := 0
var _measure := false
var model_provider: ScriptedProvider


func _initialize() -> void:
	WorldState.reset()
	_run()


func _process(_d: float) -> bool:
	var now := Time.get_ticks_usec()
	if _measure and _last > 0:
		worst_ms = maxf(worst_ms, (now - _last) / 1000.0)
	_last = now
	return false


func out(k: String, v) -> void:
	lines.append("%s=%s" % [k, str(v)])


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func place_player(p: Vector3) -> void:
	player.global_position = p + Vector3(0, 0.05, 0)
	player.velocity = Vector3.ZERO
	player.controller.velocity = Vector3.ZERO
	player.controller.body_pos = player.global_position


## Walk toward `to` (xz) for up to `max_s` seconds. Returns true when within 1.2 m.
func walk_to(to: Vector3, max_s: float) -> bool:
	demo._rig.rig.yaw = 0.0          # yaw 0: command x -> world x, y -> world z
	for i in int(max_s * 60.0):
		var d := Vector2(to.x - player.global_position.x, to.z - player.global_position.z)
		if d.length() < 1.2:
			player.set_command(Vector2.ZERO, false, false, false)
			return true
		player.set_command(d.normalized(), false, false, false)
		await physics_frame
	player.set_command(Vector2.ZERO, false, false, false)
	return false


## Steer the speeder at `to` until `done` or `max_s` seconds.
func ride_to(s: SpeederNode, to: Vector3, throttle: float, max_s: float, done: Callable) -> bool:
	for i in int(max_s * 60.0):
		var f := s.model.forward()
		var want := Vector3(to.x - s.model.position.x, 0, to.z - s.model.position.z).normalized()
		var cross := f.cross(want).y
		var steer := clampf(-cross * 3.0, -1.0, 1.0)
		if f.dot(want) < 0.0:
			steer = 1.0 if cross < 0.0 else -1.0
		# Ease off while the target is off the nose, so the turn is tighter than
		# the distance (a human does the same).
		var ease := clampf((f.dot(want) + 0.2) / 1.2, 0.15, 1.0)
		s.set_external_command({ "throttle": throttle * ease, "steer": steer })
		await physics_frame
		if done.call():
			return true
	return false


func _run() -> void:
	demo = load("res://scenes/town_demo.gd").new()
	demo.npc_brains = false
	demo.use_look = false
	get_root().add_child(demo)
	await frames(5)
	model_provider = ScriptedProvider.new("scripted_skrugs")
	demo._build_bar([model_provider], "")
	post = demo.speeder_post
	post.attach_host(demo.bar)
	player = demo._player
	await frames(3)
	out("POST_BUILT", post != null and post.spot != null)
	out("SPOTS", ",".join(PackedStringArray(demo.bar.spots.map(func(s): return s.id()))))

	# ---------------------------------------------------------------- 1. out the back gate
	_measure = true
	var gap: Vector3 = demo.town.marker_pos("back_gap")
	place_player(gap + Vector3(8, 0, 0))
	await frames(10)
	var through := await walk_to(gap + Vector3(-8, 0, 0), 10.0)
	out("THROUGH_THE_BACK_GATE", through and player.global_position.x < gap.x - 2.0)
	var stall := post.world_point("customer")
	var reached := await walk_to(stall, 20.0)
	await frames(10)
	out("REACHED_THE_STALL", reached)
	out("CAN_TALK_TO_SKRUGS", demo.bar.spot_in_range() == post.spot)

	# ---------------------------------------------------------------- 2. buy one
	WorldState.credits = 160
	demo.bar.start_talk(post.spot)
	await frames(2)
	out("TALKING_TO", demo.bar.active.display_name() if demo.bar.active != null else "")
	out("AI_NOTICE_PINNED", demo.bar.panel.notice().contains("AI"))
	model_provider.push({ "text": JSON.stringify({ "say": "One hundred credits, friend, and she's yours.",
		"then": [{ "type": "offer_speeder", "price": 5 }], "tone": "warm" }), "chunk": 9, "ms_first": 30, "ms_per_chunk": 10 })
	demo.bar.player_says("How much for a speeder?")
	for i in 240:
		await physics_frame
		if not post.spot.brain.busy:
			break
	var turn: Dictionary = post.spot.brain.last_turn
	out("SKRUGS_SAID", str(turn.get("say", "")))
	out("SKRUGS_KEPT", ",".join(PackedStringArray((turn.get("kept", []) as Array).map(func(a): return str(a.type)))))
	out("SALE_CARD_UP", demo.bar.panel.job_open())
	out("OFFER_PRICE", int(post._offered.get("price", -1)))
	demo.bar.panel.answer_card(true)
	await frames(2)
	out("CREDITS_AFTER", WorldState.credits)
	out("OWNED", WorldState.count("speeders_owned"))
	out("SKRUGS_MOOD", post.spot.brain.rel.mood)
	var s: SpeederNode = post.speeders[0] if not post.speeders.is_empty() else null
	out("SPEEDER_PARKED", s != null)
	if s == null:
		_write()
		return
	var house_x := post.origin.x - 0.5
	out("PARKED_BEHIND_HOUSE", s.model.position.x < house_x - 4.0)
	demo.bar.end_talk()
	await frames(5)

	# ---------------------------------------------------------------- 3. ride and jump
	place_player(s.model.position + Vector3(0, -1.0, 2.0))
	await frames(5)
	out("MOUNT", s.mount())
	out("RIDING", s.riding and player.piloting)
	var run_up := post.world_point("ramp_run_up")
	out("TO_THE_RAMP", await ride_to(s, run_up, 0.35, 30.0,
		func(): return Vector2(s.model.position.x - run_up.x, s.model.position.z - run_up.z).length() < 2.5))
	# Stop, turn on the spot to face up the ramp (it rises toward -z), then full
	# throttle straight up it, aiming far down the line so the steering stays small.
	for i in 120:                    # brake (reverse throttle) to a stop right there
		s.set_external_command({ "throttle": -1.0 if s.model.speed > 0.3 else 0.0 })
		await physics_frame
		if absf(s.model.speed) < 0.3:
			break
	s.model.speed = 0.0
	for i in 240:
		var f := s.model.forward()
		if f.dot(Vector3(0, 0, -1)) > 0.995:
			break
		s.set_external_command({ "throttle": 0.0, "steer": 1.0 if f.cross(Vector3(0, 0, -1)).y < 0.0 else -1.0 })
		await physics_frame
	out("LINED_UP_X_OFF", snappedf(absf(s.model.position.x - run_up.x), 0.1))
	var ramp_end := Vector3(run_up.x, 0, run_up.z - 120.0)
	var ev_from := s.log_events.size()
	await ride_to(s, ramp_end, 1.0, 6.0, func(): return s.model.airborne and s.model.position.z < run_up.z - 18.0)
	for i in 180:
		s.set_external_command({ "throttle": 0.6 })
		await physics_frame
		if not s.model.airborne and s.log_events.slice(ev_from).any(func(e): return str(e.type) == "landed"):
			break
	var jump := s.log_events.slice(ev_from)
	var launch := jump.filter(func(e): return str(e.type) == "launch")
	var landed := jump.filter(func(e): return str(e.type) == "landed")
	out("LAUNCHED_OFF_RAMP", not launch.is_empty())
	out("LANDED", not landed.is_empty())
	out("AIR_TIME", snappedf(float(landed[0].air_time), 0.01) if not landed.is_empty() else 0.0)
	out("JUMP_HEIGHT", snappedf(float(landed[0].top), 0.01) if not landed.is_empty() else 0.0)
	out("HULL_AFTER_JUMP", s.model.hp)
	out("HULL_MAX", s.model.max_hp)

	# ---------------------------------------------------------------- 4. a bolt, then off
	for i in 240:                    # brake to a stop
		s.set_external_command({ "throttle": -1.0 if s.model.speed > 0.3 else 0.0 })
		await physics_frame
		if absf(s.model.speed) < 0.3 and not s.model.airborne:
			break
	s.set_external_command({ "throttle": 0.0 })
	await frames(10)
	var bolt = BoltScene.instantiate()
	var from := s.model.position + Vector3(12, 0.2, 0)
	bolt.direction = (s.model.position - from).normalized()
	bolt.speed = 60.0
	bolt.damage = 25.0
	bolt.range_m = 40.0
	demo.add_child(bolt)
	bolt.global_position = from
	await frames(40)
	out("HULL_AFTER_BOLT", s.model.hp if is_instance_valid(s) else -1)
	out("DISMOUNT", s.dismount() if is_instance_valid(s) else false)
	await frames(30)
	out("ON_FOOT", not player.piloting and player.visible)
	out("PLAYER_ON_GROUND", player.is_on_floor())
	_write()


func _write() -> void:
	out("WORST_MS", snappedf(worst_ms, 0.01))
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_results"))
		f = FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("SPEEDERTRACE wrote ", OUT, " (", lines.size(), " lines)")
	quit()
