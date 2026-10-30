extends SceneTree
## Orbit trace (rendered): take off from the port, climb straight to space, then
## fly at the moon station until its scene takes over. Every frame is logged with
## the ship's altitude, so a stutter in the climb or in orbit shows where it is.
## Writes test_results/orbit_trace.csv (one row a frame) and orbit_trace.txt (per
## altitude band: frames, p50/p95/max frame ms, frames over 25 ms and 50 ms).
## It found the orbit stutter: once the Remnant's interceptor was up, its ground
## checks (five a physics step) scanned every town box from high up, and 60 Hz
## physics fell behind (about 150 ms frames in orbit until the moon took over).
##
## Run (rendered, the full look): godot --path . -s res://scenes/orbit_trace.gd
## DUNE_PERF_VISUALS=0 builds the greybox instead.

const FighterBrain := preload("res://src/systems/ai/fighter_brain.gd")
const BANDS := [0.0, 200.0, 600.0, 1200.0, 2000.0, 3000.0, 4000.0, 4500.0, 5000.0, 6000.0, 1e9]

var demo
var pilot: ShipPilot
var player
var rows := PackedStringArray(["t,alt,frame_ms,process_ms,physics_ms,render_cpu_ms,tier,phase,objects,draw_calls,prims"])
var samples: Array = []          ## [alt, ms]
var _last := 0
var _t := 0.0
var _measure := false
var _phase := "setup"


func _initialize() -> void:
	WorldState.reset()
	WorldState.set_flag("ships_unlocked")
	GameFlow.reset()
	GameFlow.dogfight_override = false        # travel, not the fight
	GameFlow.change_scene = func(_path: String) -> void: pass
	_run()


func _process(d: float) -> bool:
	var now := Time.get_ticks_usec()
	if _measure and _last > 0 and pilot != null and is_instance_valid(pilot):
		var ms := (now - _last) / 1000.0
		_t += d
		var alt: float = pilot.atmo.altitude()
		samples.append([alt, ms])
		var vp := get_root().get_viewport_rid()
		rows.append("%.3f,%.0f,%.2f,%.2f,%.2f,%.2f,%d,%s,%d,%d,%d" % [_t, alt, ms,
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu(),
			demo.detail.tier if demo.detail != null else -9, _phase,
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	_last = now
	return false


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func fly_to(point: Vector3, throttle: float, max_s: float, done: Callable, boost: bool = false) -> float:
	var b = FighterBrain.new({ "steer_gain": 3.0 }, pilot.atmo.flight, 1)
	for i in int(max_s * 60.0):
		b._steer_to(point, throttle, boost)
		pilot.set_external_command(b.command)
		await physics_frame
		if pilot.atmo.state == AtmoFlight.State.CRASHED:
			return -2.0
		if done.call():
			return i / 60.0
	return -1.0


func _run() -> void:
	RenderingServer.viewport_set_measure_render_time(get_root().get_viewport_rid(), true)
	print("WINDOW ", DisplayServer.window_get_size(), " scale ", DisplayServer.screen_get_scale())
	demo = load("res://scenes/town_demo.gd").new()
	demo.npc_brains = true
	demo.use_look = OS.get_environment("DUNE_PERF_VISUALS") != "0"
	get_root().add_child(demo)
	await frames(240)                  # the port settles (staged pieces, shaders)
	pilot = demo.pilot
	player = demo._player
	var sp: Vector3 = pilot.atmo.position()
	player.global_position = sp + Vector3(5, 0.05, 0)
	await frames(3)
	pilot.board()
	pilot.set_external_command({ "throttle": 0.0 })
	pilot.takeoff()
	for i in 600:
		await physics_frame
		if pilot.atmo.state == AtmoFlight.State.FLYING:
			break
	_measure = true
	_phase = "climb"
	# Straight up at full throttle and boost, to well past the edge of space.
	var want := sin(deg_to_rad(70.0))
	for i in 60 * 120:
		var fy: float = pilot.atmo.flight.forward().y
		pilot.set_external_command({ "pitch": clampf((want - fy) * 4.0, -1.0, 1.0), "throttle": 1.0, "boost": true })
		await physics_frame
		if pilot.atmo.altitude() > 5000.0 or pilot.atmo.state == AtmoFlight.State.CRASHED:
			break
	# Cruise in orbit for a while, then at the station.
	_phase = "orbit"
	var station: Dictionary = pilot.travel.bodies.filter(func(b): return b.id == "grit_station")[0]
	pilot.travel.change = false
	await fly_to(station.at, 1.0, 120.0, func(): return pilot.travel.traveling != "", true)
	_measure = false
	_report()
	quit()


func _report() -> void:
	var out := PackedStringArray()
	for i in BANDS.size() - 1:
		var lo: float = BANDS[i]
		var hi: float = BANDS[i + 1]
		var ms: Array = samples.filter(func(s): return s[0] >= lo and s[0] < hi).map(func(s): return s[1])
		if ms.is_empty():
			continue
		ms.sort()
		var over25 := ms.filter(func(m): return m > 25.0).size()
		var over50 := ms.filter(func(m): return m > 50.0).size()
		out.append("BAND %5d-%-5d frames=%4d p50=%5.1f p95=%5.1f max=%6.1f over25=%d over50=%d" % [
			lo, mini(int(hi), 99999), ms.size(), ms[ms.size() / 2], ms[int(ms.size() * 0.95)], ms.back(), over25, over50])
	out.append("HANDOFF=%s" % pilot.travel.traveling)
	print("\n".join(out))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_results"))
	var f := FileAccess.open("res://test_results/orbit_trace.txt", FileAccess.WRITE)
	f.store_string("\n".join(out) + "\n")
	f.close()
	f = FileAccess.open("res://test_results/orbit_trace.csv", FileAccess.WRITE)
	f.store_string("\n".join(rows) + "\n")
	f.close()
