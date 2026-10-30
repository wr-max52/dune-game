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
var _frame := 0
var _before: Image
var _music_before := {}
var _engine_before := {}
var _look_before := ""


func _initialize() -> void:
	WorldState.reset()
	WorldState.set_flag("ships_unlocked")
	GameFlow.reset()
	GameFlow.dogfight_override = false
	_run()


func _process(_d: float) -> bool:
	var now := Time.get_ticks_usec()
	if _last > 0:
		frame_ms.append([_frame - _switch_frame if _switch_frame >= 0 else -1, (now - _last) / 1000.0,
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])
	_last = now
	_frame += 1
	return false


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
	var station: Dictionary = p.travel.bodies.filter(func(b): return b.id == "grit_station")[0]
	var b = FighterBrain.new({ "steer_gain": 3.0 }, p.atmo.flight, 1)
	var up: Vector3 = p.atmo.position() + Vector3(0, 1500, 0)
	var climbed := false
	for i in 60 * 150:
		climbed = climbed or p.atmo.altitude() >= 1300.0
		b._steer_to(station.at if climbed else up, 1.0, true)
		p.set_external_command(b.command)
		await physics_frame
		if p.travel.traveling != "":
			break
		# Grab every frame near the station: the last one before the switch is kept.
		if p.atmo.position().distance_to(station.at) < float(station.radius) + float(station.handoff) + 400.0:
			var img := await shot()
			if not is_instance_valid(p) or p.travel.traveling != "":
				break
			_before = img
			_look_before = look_state() + " || " + sky_dump()
			_music_before = music_state()
			_engine_before = engine_state(p)
	out("TRAVELING", p.travel.traveling if is_instance_valid(p) else "(scene gone)")
	if is_instance_valid(p):
		out("SHIP", "%s alt=%d dist=%d" % [p.atmo.state_label(), p.atmo.altitude(), p.atmo.position().distance_to(station.at)])
	_switch_frame = _frame
	var old_scene = demo()
	# The real change_scene_to_file runs deferred; wait for the station scene.
	for i in 30:
		await process_frame
		if demo() != old_scene and demo() != null and is_instance_valid(demo()) and demo().is_inside_tree():
			break
	out("SCENE_CHANGED", demo() != old_scene)
	out("FRAMES_TO_NEW_SCENE", _frame - _switch_frame)
	var after: Array = []
	for i in 4:
		after.append(await shot())
	var music_after := music_state()
	var engine_after := engine_state(pilot())
	for i in 120:
		var q := pilot()
		if q != null and q.piloting:
			q.set_external_command({ "throttle": 1.0 })
		await process_frame
		if i == 30 or i == 119:
			after.append(await shot())
	var sb = demo().staged
	out("READY_MS", snappedf(demo().ready_ms, 0.1))
	out("SHELL_STEPS_OVER_4MS", ", ".join(sb.history.filter(func(h): return int(h.frame) < 0 and float(h.ms) > 4.0).map(func(h): return "%s=%.0f" % [h.name, float(h.ms)])))
	out("EARLY_STAGED", ", ".join(sb.history.filter(func(h): return int(h.frame) >= 0 and int(h.frame) <= 4).map(func(h): return "f%d:%s=%.0f" % [int(h.frame), h.name, float(h.ms)])))

	out("SKY_PIXEL_AFTER", (await shot()).get_pixel(1100, 150))
	out("LOOK_BEFORE", _look_before)
	out("LOOK_AFTER", look_state() + " || " + sky_dump())
	_write_images(after)
	out("MUSIC_BEFORE", _music_before)
	out("MUSIC_AFTER", music_after)
	out("MUSIC_SAME_TRACK", _music_before.get("stream", "") == music_after.stream)
	out("MUSIC_KEPT_PLAYING", music_after.playing and float(music_after.pos) >= float(_music_before.get("pos", 0.0)))
	out("ENGINE_BEFORE", _engine_before)
	out("ENGINE_AFTER", engine_after)
	out("ENGINE_SAME_PLAYER", int(_engine_before.get("id", 0)) == int(engine_after.id))
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
	out("WORST_FRAME_AFTER_MS", snappedf(worst, 0.1))
	out("WORST_FRAME_AT", worst_at)
	out("FRAMES_OVER_33MS", over)
	out("FRAMES_AFTER", ",".join(PackedStringArray(near.slice(0, 40))))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_results"))
	var f := FileAccess.open("res://test_results/handoff_trace.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit()


func _write_images(after: Array) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	if _before != null:
		_before.save_png(ProjectSettings.globalize_path(DIR + "/before.png"))
	for i in after.size():
		(after[i] as Image).save_png(ProjectSettings.globalize_path(DIR + "/after_%d.png" % i))
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
