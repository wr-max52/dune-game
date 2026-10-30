extends SceneTree
## Moon handoff trace (rendered): take off from the port, climb, fly at the moon
## station until its scene takes over with a real scene change (as in the game),
## and keep flying in its sky. Around the switch it records:
##   - every frame's time (HANDOFF_FRAMES: the 20 before and 120 after),
##   - the last frame drawn by the port and the first ones drawn by the station
##     (test_results/handoff/*.png) and how different they are (mean RGB diff),
##   - the music and the engine: still playing, same track, no restart.
##   - the sky and light settings on both sides (LOOK_BEFORE / LOOK_AFTER), and
##   - which build steps ran on the first frames (SHELL_STEPS_OVER_4MS, EARLY_STAGED).
## Writes test_results/handoff_trace.txt.
##
## Run (rendered, the full look): godot --path . -s res://scenes/handoff_trace.gd

const FighterBrain := preload("res://src/systems/ai/fighter_brain.gd")
const DIR := "res://test_results/handoff"

var lines := PackedStringArray()
var frame_ms: Array = []          ## [frames since the switch, ms]
var _last := 0
var _switch_frame := -1
var _switch_pf := 0               ## Engine.get_process_frames() at the switch
var _frame := 0
var _before: Image
var _music_before := {}
var _engine_before := {}
var _look_before := ""
var _grab := false                ## keep every frame drawn (around a switch)
var _grabbed: Array = []          ## [ "old"/"new" scene, frame, Image ]
var _grab_us := 0                 ## time spent grabbing, left out of the frame times
var _old_id := 0                  ## the scene flown out of


func _initialize() -> void:
	RenderingServer.frame_post_draw.connect(_on_drawn)
	WorldState.reset()
	WorldState.set_flag("ships_unlocked")
	GameFlow.reset()
	GameFlow.dogfight_override = false
	_run()


func _process(_d: float) -> bool:
	var now := Time.get_ticks_usec()
	if _last > 0:
		frame_ms.append([_frame - _switch_frame if _switch_frame >= 0 else -1, (now - _last - _grab_us) / 1000.0,
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])
	_last = now
	_grab_us = 0
	_frame += 1
	return false


func _on_drawn() -> void:
	if not _grab:
		return
	var t := Time.get_ticks_usec()
	_grabbed.append(["old" if current_scene != null and current_scene.get_instance_id() == _old_id else "new", _frame, get_root().get_texture().get_image()])
	while _grabbed.size() > 4 and _grabbed[0][0] == "old" and _grabbed[_grabbed.size() - 1][0] == "old":
		_grabbed.pop_front()
	_grab_us += Time.get_ticks_usec() - t


## Metres to the switch to body `b`: into a child ball's scene, or off this ball.
func _gap(p, b: Dictionary) -> float:
	var t = p.travel
	var pos: Vector3 = p.atmo.position()
	if b.child:
		return pos.distance_to(b.at) - float(b.radius) - float(b.handoff)
	return t.self_radius + t.self_handoff + SpaceTravel.HYSTERESIS - pos.distance_to(Vector3(0, -t.self_radius, 0))


## Mean brightness (0..1) on a coarse grid.
func _lum(a: Image) -> float:
	var sum := 0.0
	var n := 0
	for y in range(0, a.get_height(), 8):
		for x in range(0, a.get_width(), 8):
			sum += a.get_pixel(x, y).get_luminance()
			n += 1
	return sum / maxf(n, 1)


func out(k: String, v) -> void:
	lines.append("%s=%s" % [k, str(v)])
	print("  ", k, "=", v)


func demo():
	return current_scene


func pilot() -> ShipPilot:
	return demo().pilot if demo() != null and "pilot" in demo() else null


func shot() -> Image:
	await RenderingServer.frame_post_draw
	return get_root().get_texture().get_image()


func look_state() -> String:
	var d = demo()
	if d == null or d.get("look") == null:
		return "?"
	var lk: LookEnvironment = d.look
	var e: Environment = lk.env
	var m: ShaderMaterial = lk.sky_mat
	var sk = d.pilot.sky if d.pilot != null else null
	return "preset=%s hour=%.2f level=%.2f zenith=%s horizon=%s ground=%s sky_energy=%.2f ambient=%.2f(x%.2f) fog=%.7f fogcol=%s aerial=%.2f sun=%s/%.2f exp=%.2f glow=%.2f bg_energy=%.2f" % [
		lk.current, lk.hour, sk.level if sk != null else -1.0, m.get_shader_parameter("zenith_color"), m.get_shader_parameter("horizon_color"),
		m.get_shader_parameter("ground_color"), m.get_shader_parameter("sky_energy"), e.ambient_light_energy, lk.ambient_energy_scale,
		e.fog_density, e.fog_light_color, e.fog_aerial_perspective, lk.sun.light_color, lk.sun.light_energy, e.tonemap_exposure, e.glow_intensity, e.background_energy_multiplier]


func sky_dump() -> String:
	var d = demo()
	var parts := PackedStringArray()
	var we: Array = get_root().find_children("*", "WorldEnvironment", true, false)
	parts.append("world_envs=%d active_is_look=%s" % [we.size(), get_root().world_3d.environment == d.look.env if d.get("look") else false])
	var m: ShaderMaterial = d.look.sky_mat
	for u in m.shader.get_shader_uniform_list():
		parts.append("%s=%s" % [u.name, m.get_shader_parameter(u.name)])
	var e: Environment = d.look.env
	for k in ["background_mode", "background_color", "ambient_light_source", "ambient_light_color", "ambient_light_sky_contribution", "tonemap_mode", "adjustment_enabled", "fog_mode", "fog_sun_scatter", "fog_light_energy", "sky_custom_fov"]:
		parts.append("%s=%s" % [k, e.get(k)])
	return " ".join(parts)


func music_state() -> Dictionary:
	var s := Sound.lib()
	var d: AudioStreamPlayer = s._deck
	return { "mode": s.mode, "playing": d != null and d.playing, "stream": d.stream.resource_path if d != null and d.stream != null else "",
		"pos": d.get_playback_position() if d != null and d.playing else -1.0, "db": d.volume_db if d != null else 0.0 }


func engine_state(p) -> Dictionary:
	var e: AudioStreamPlayer = p._engine if p != null and is_instance_valid(p) else null
	return { "playing": e != null and e.playing, "pos": e.get_playback_position() if e != null and e.playing else -1.0,
		"id": e.get_instance_id() if e != null else 0 }


func _run() -> void:
	var town = load("res://scenes/town_demo.gd").new()
	town.use_look = true
	get_root().add_child(town)
	current_scene = town
	for i in 240:
		await process_frame
	for o in get_root().find_children("*", "DisclaimerOverlay", true, false):
		o.accept()
	paused = false
	var p := pilot()
	var player = demo()._player
	player.global_position = p.atmo.position() + Vector3(5, 0.05, 0)
	for i in 3:
		await physics_frame
	out("BOARD", p.board())
	for i in 2:
		await physics_frame
	p.set_external_command({ "throttle": 0.0 })
	out("TAKEOFF", p.takeoff())
	for i in 600:
		await physics_frame
		if p.atmo.state == AtmoFlight.State.FLYING:
			break
	var up: Vector3 = p.atmo.position() + Vector3(0, 1500, 0)
	await _leg("grit_station", "", up)
	# And back: from the station's sky to the port's.
	await _leg("port_desert", "HOME_", Vector3.INF)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_results"))
	var f := FileAccess.open("res://test_results/handoff_trace.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()


## Fly from the current scene's sky at body `id` until its scene takes over, and
## record the switch. Keys are prefixed with `tag`. `up`: climb there first
## (Vector3.INF: already high, head straight for it).
func _leg(id: String, tag: String, up: Vector3) -> void:
	var p := pilot()
	var station: Dictionary = p.travel.bodies.filter(func(b): return b.id == id)[0]
	_before = null
	_switch_frame = -1
	frame_ms.clear()
	_grabbed.clear()
	_old_id = demo().get_instance_id()
	var b = FighterBrain.new({ "steer_gain": 3.0 }, p.atmo.flight, 1)
	var climbed := up == Vector3.INF
	for i in 60 * 150:
		climbed = climbed or p.atmo.altitude() >= 1300.0
		b._steer_to(station.at if climbed else up, 1.0, true)
		p.set_external_command(b.command)
		await physics_frame
		if not is_instance_valid(p) or p.travel.traveling != "":
			break
		# Close to the switch: every frame drawn from here on is kept (_on_drawn).
		if _gap(p, station) < 300.0:
			_grab = true
			_look_before = look_state() + " || " + sky_dump()
			_music_before = music_state()
			_engine_before = engine_state(p)
	out(tag + "TRAVELING", p.travel.traveling if is_instance_valid(p) else "(scene gone)")
	if is_instance_valid(p):
		out(tag + "SHIP", "%s alt=%d gap=%d" % [p.atmo.state_label(), p.atmo.altitude(), _gap(p, station)])
	_switch_frame = _frame
	_switch_pf = Engine.get_process_frames()
	# The swap runs deferred; wait for the new scene, then for 8 frames it drew.
	for i in 60:
		await process_frame
		if _grabbed.filter(func(g): return g[0] == "new").size() >= 8:
			break
	_grab = false
	out(tag + "SCENE_CHANGED", demo().get_instance_id() != _old_id)
	var olds: Array = _grabbed.filter(func(g): return g[0] == "old")
	var news: Array = _grabbed.filter(func(g): return g[0] == "new")
	_before = olds.back()[2] if not olds.is_empty() else null
	var after: Array = news.slice(0, 4).map(func(g): return g[2])
	var music_after := music_state()
	var engine_after := engine_state(pilot())
	for i in 120:
		var q := pilot()
		if q != null and q.piloting:
			q.set_external_command({ "throttle": 1.0 })
		await process_frame
		if i == 30 or i == 119:
			after.append(await shot())
	# (After the timed frames: the pictures are slow to save.)
	# Every frame drawn around the switch: which scene drew it, how bright it is
	# (a black frame shows) and how far it is from the old scene's last frame.
	var row := PackedStringArray()
	for g in olds.slice(-3) + news:
		row.append("%s@%d:lum=%.3f/diff=%.3f" % [g[0], int(g[1]) - _switch_frame, _lum(g[2]), _diff(_before, g[2]) if _before != null else -1.0])
	out(tag + "SWITCH_FRAMES", ", ".join(row))
	var dir := DIR + ("/" + tag.to_lower().trim_suffix("_") if tag != "" else "")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	for k in news.size():
		(news[k][2] as Image).save_png(ProjectSettings.globalize_path(dir + "/switch_new_%d.png" % k))
	var sb = demo().staged
	out(tag + "READY_MS", snappedf(demo().ready_ms, 0.1))
	out(tag + "SHELL_STEPS_OVER_4MS", ", ".join(sb.history.filter(func(h): return int(h.frame) < 0 and float(h.ms) > 4.0).map(func(h): return "%s=%.0f" % [h.name, float(h.ms)])))
	out(tag + "LATE_STAGED_OVER_12MS", ", ".join(sb.history.filter(func(h): return int(h.frame) > 4 and float(h.ms) > 12.0).map(func(h): return "f%d:%s=%.0f" % [int(h.frame), h.name, float(h.ms)])))
	var reaper = get_root().get_node_or_null("SceneReaper")
	out(tag + "REAPER_SLOWEST", "%s at +%d" % [str(reaper.slowest), int(reaper.slowest.get("frame", 0)) - _switch_pf] if reaper != null else "none")
	if reaper != null:
		reaper.slowest = {}
	out(tag + "EARLY_STAGED", ", ".join(sb.history.filter(func(h): return int(h.frame) >= 0 and int(h.frame) <= 4).map(func(h): return "f%d:%s=%.0f" % [int(h.frame), h.name, float(h.ms)])))

	out(tag + "SKY_PIXEL_AFTER", (await shot()).get_pixel(1100, 150))
	out(tag + "LOOK_BEFORE", _look_before)
	out(tag + "LOOK_AFTER", look_state() + " || " + sky_dump())
	_write_images(after, tag)
	out(tag + "MUSIC_BEFORE", _music_before)
	out(tag + "MUSIC_AFTER", music_after)
	out(tag + "MUSIC_SAME_TRACK", _music_before.get("stream", "") == music_after.stream)
	out(tag + "MUSIC_KEPT_PLAYING", music_after.playing and float(music_after.pos) >= float(_music_before.get("pos", 0.0)))
	out(tag + "ENGINE_BEFORE", _engine_before)
	out(tag + "ENGINE_AFTER", engine_after)
	out(tag + "ENGINE_SAME_PLAYER", int(_engine_before.get("id", 0)) == int(engine_after.id))
	var worst := 0.0
	var worst_at := 0
	var over := 0
	var near: Array = []
	for f in frame_ms:
		if f[0] >= -1 and f[0] <= 120:
			if f[0] >= 0:
				near.append("%d:%.0f(p%.0f/f%.0f)" % [f[0], f[1], f[2], f[3]] if f[0] < 6 else "%d:%.0f" % [f[0], f[1]])
			if f[1] > worst and f[0] >= 0:
				worst = f[1]
				worst_at = f[0]
			if f[1] > 33.0 and f[0] >= 0:
				over += 1
	out(tag + "WORST_FRAME_AFTER_MS", snappedf(worst, 0.1))
	out(tag + "WORST_FRAME_AT", worst_at)
	out(tag + "FRAMES_OVER_33MS", over)
	out(tag + "FRAMES_AFTER", ",".join(PackedStringArray(near.slice(0, 40))))


func _write_images(after: Array, tag: String) -> void:
	var dir := DIR + ("/" + tag.to_lower().trim_suffix("_") if tag != "" else "")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	if _before != null:
		_before.save_png(ProjectSettings.globalize_path(dir + "/before.png"))
	for i in after.size():
		(after[i] as Image).save_png(ProjectSettings.globalize_path(dir + "/after_%d.png" % i))
		if _before != null:
			out("DIFF_AFTER_%d" % i, snappedf(_diff(_before, after[i]), 0.001))


## Mean absolute RGB difference (0..1) on a coarse grid.
func _diff(a: Image, b: Image) -> float:
	if a.get_size() != b.get_size():
		return -1.0
	var sum := 0.0
	var n := 0
	for y in range(0, a.get_height(), 8):
		for x in range(0, a.get_width(), 8):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			sum += (absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) / 3.0
			n += 1
	return sum / maxf(n, 1)
