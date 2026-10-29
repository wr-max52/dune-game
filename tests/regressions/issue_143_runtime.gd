extends SceneTree
## Standalone runner for scripts/test_issue_143.sh, not a GUT test.
## The full sidecar script is loaded unchanged. The two droid methods and service
## startup method are extracted unchanged into small fixtures; their unrelated
## dependencies are stubbed. This is not a full game or model integration test.

const Sidecar := preload("res://sidecar.gd")
var failures := 0
var checks := 0

class ObservedSidecar extends Sidecar:
	var launches := 0

	func _launch() -> bool:
		launches += 1
		state = State.STARTING
		return true


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)


func profile(port: int, binary := "fake_sleep") -> Dictionary:
	return {"sidecar": {
		"port": port,
		"bin": ProjectSettings.globalize_path("res://" + binary),
		"model_path": ProjectSettings.globalize_path("res://run.gd"),
		"startup_timeout_s": 1.0,
	}}


func marker(text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://llm"))
	var f := FileAccess.open(Sidecar.PID_PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func settle_probe(s) -> void:
	var deadline := Time.get_ticks_msec() + 3000
	while s._port_probe != null and Time.get_ticks_msec() < deadline:
		s.poll()
		await process_frame
	check(s._port_probe == null, "port probe completes without blocking")


func test_sidecar() -> void:
	var listener := TCPServer.new()
	check(listener.listen(0, "127.0.0.1") == OK, "open isolated listener")
	var port := listener.get_local_port()
	marker("999999999")
	var s := ObservedSidecar.new(profile(port))
	s.search = false
	check(s.start(), "occupied-port startup begins")
	var probe = s._port_probe
	check(s.start() and s._port_probe == probe, "repeat start keeps the pending probe")
	await settle_probe(s)
	check(s.reused and s.pid == -1 and s.launches == 0, "occupied port never spawns or claims a foreign PID")
	check(s.state == Sidecar.State.STARTING, "listener is not assumed healthy")
	s.mark_ready()
	check(s.state == Sidecar.State.REUSED, "only health success marks an existing server ready")
	s.stop()
	check(FileAccess.get_file_as_string(Sidecar.PID_PATH) == "999999999", "reuse/stop leaves foreign PID marker alone")

	var waiting := ObservedSidecar.new(profile(port))
	waiting.search = false
	check(waiting.start(), "start loading-server wait")
	await settle_probe(waiting)
	waiting.started_ms = Time.get_ticks_msec() - 2000
	waiting.poll()
	check(waiting.state == Sidecar.State.FAILED and waiting.launches == 0, "unhealthy occupied port times out without a duplicate")
	check(waiting.reason().contains("health"), "occupied-port failure explains the health timeout")
	waiting.stop()

	var racing := ObservedSidecar.new(profile(port))
	racing.search = false
	check(racing.start(), "start health/probe race")
	racing.mark_ready()
	racing.poll()
	check(racing.state == Sidecar.State.REUSED and racing.launches == 0, "early health success cancels pending spawn")
	racing.stop()
	listener.stop()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Sidecar.PID_PATH))

	var idle := ObservedSidecar.new(profile(port))
	idle.search = false
	check(idle.start(), "free-port startup begins")
	await settle_probe(idle)
	check(idle.launches == 1 and not idle.reused, "free port launches exactly once")
	idle.start()
	idle.poll()
	check(idle.launches == 1, "repeat loading start does not launch twice")
	idle.stop()

	# Real, harmless child processes exercise OS ownership and exit-before-stop.
	for binary in ["fake_sleep", "fake_exit"]:
		var child := Sidecar.new(profile(port, binary))
		child.search = false
		check(child.start(), "start owned test child")
		await settle_probe(child)
		var owned_pid: int = child.pid
		check(owned_pid > 0, "real child launched")
		await create_timer(0.1).timeout
		child.stop()
		check(not OS.is_process_running(owned_pid), "stop reaps only its own live child, or skips an exited one")
		check(not FileAccess.file_exists(Sidecar.PID_PATH), "owned PID marker removed")
		child.stop()

	var replaced := Sidecar.new(profile(port))
	replaced.search = false
	check(replaced.start(), "start marker-replacement test")
	await settle_probe(replaced)
	marker("999999999")
	replaced.stop()
	check(FileAccess.get_file_as_string(Sidecar.PID_PATH) == "999999999", "stop does not delete another instance's replacement marker")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Sidecar.PID_PATH))

	var invalid := ObservedSidecar.new(profile(0))
	invalid.search = false
	check(not invalid.start() and invalid.state == Sidecar.State.FAILED, "invalid port fails before a process is started")
	print("PASS group: full sidecar lifecycle with real TCP listener and harmless child processes")


func method_source(text: String, name: String, indent := "") -> String:
	var lines := text.split("\n")
	var result := ""
	var copying := false
	for line in lines:
		if line.begins_with(indent + "func " + name + "("):
			copying = true
		elif copying and line.strip_edges() != "" and not line.begins_with(indent + "\t"):
			break
		if copying:
			result += line + "\n"
	check(result != "", "found production method " + name)
	return result


func fixture(source: String):
	var script := GDScript.new()
	script.source_code = source
	var err := script.reload()
	check(err == OK, "compile exact production methods")
	return script.new() if err == OK else null


func test_chirps() -> void:
	var text := FileAccess.get_file_as_string("res://controller.txt")
	var source := """extends Node3D
class DroidRoster:
	static func kind_cfg(kind: String) -> Dictionary:
		return {"chirp_s": {"floating": [9.0, 20.0], "cargo": [7.0, 16.0], "assassin": [11.0, 22.0]}[kind]}
class DroidUnit extends StaticBody3D:
	var uid := 1
	var dead := false
	var kind := "assassin"
	var chirp_cd := 0.0
"""
	source += method_source(text, "quirk", "\t")
	source += """
var rng := RandomNumberGenerator.new()
var companions := {}
var remnant := []
var player: Node3D
var beeps := 0
func _beep(_unit) -> void:
	beeps += 1
func add_unit(kind: String, uid: int, owned: bool):
	var u := DroidUnit.new()
	u.kind = kind
	u.uid = uid
	add_child(u)
	if owned:
		companions[uid] = u
	else:
		remnant.append(u)
	return u
"""
	source += method_source(text, "_chirps")
	var ctl = fixture(source)
	if ctl == null:
		return
	root.add_child(ctl)
	ctl.player = Node3D.new()
	ctl.add_child(ctl.player)
	ctl.rng.seed = 143
	var units := []
	for owned in [true, false]:
		for kind in ["floating", "cargo", "assassin"]:
			units.append(ctl.add_unit(kind, units.size() + 1, owned))
	for round_i in 20:
		for u in units:
			u.chirp_cd = 0.0
			u.position.x = 100.0 if round_i % 2 == 0 else 0.0
		ctl._chirps(0.016)
		for u in units:
			var bounds: Array = {"floating": [9.0, 20.0], "cargo": [7.0, 16.0], "assassin": [11.0, 22.0]}[u.kind]
			check(u.chirp_cd >= float(bounds[0]) * 0.8 and u.chirp_cd <= float(bounds[1]) * 1.2,
				"chirp timer resets within bounds for " + u.kind)
	var first = units[0]
	first.dead = true
	first.chirp_cd = 0.0
	var before: float = units[1].chirp_cd
	ctl._chirps(0.016)
	check(first.chirp_cd == 0.0, "dead droids do not chirp")
	check(is_equal_approx(units[1].chirp_cd, before - 0.016), "unexpired timers count down without resetting")
	check(ctl.beeps == 60, "only nearby droids beep")
	ctl.free()
	print("PASS group: exact chirp/quirk methods, 120 resets, all kinds and factions, distance/death/countdown")


func test_service_start() -> void:
	var text := FileAccess.get_file_as_string("res://service.txt")
	var source := """extends RefCounted
const LLMSidecar = preload("res://sidecar.gd")
class Config:
	func profile(_id) -> Dictionary:
		return {"sidecar": {"enabled": true}}
var config = Config.new()
var sidecar
var _sidecar_start_pending := false
var callbacks := []
var health := {}
signal status_changed
func _check_health(_id, cb):
	callbacks.append(cb)
"""
	source += method_source(text, "start_sidecar")
	var svc = fixture(source)
	if svc == null:
		return
	svc.start_sidecar()
	var first = svc.sidecar
	svc.start_sidecar()
	check(svc.callbacks.size() == 1 and svc.sidecar == first, "only one health callback and sidecar while start is pending")
	svc.callbacks[0].call(true)
	check(first.reused and first.state == Sidecar.State.REUSED, "healthy server is reused")
	for state in [Sidecar.State.REUSED, Sidecar.State.READY, Sidecar.State.STARTING]:
		first.state = state
		svc.start_sidecar()
		check(svc.sidecar == first and svc.callbacks.size() == 1, "repeat start preserves ownership in active state")
	# Break the fixture's callback/self reference cycle before leaving.
	svc.callbacks.clear()
	first.stop()
	print("PASS group: exact service startup method, pending callback and active-state idempotence")


func _run() -> void:
	create_timer(15.0).timeout.connect(func():
		printerr("FAIL: isolated regression runner timed out")
		quit(1))
	print("Issue 143 isolated regressions on Godot ", Engine.get_version_info().string)
	await test_sidecar()
	test_chirps()
	test_service_start()
	print("RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
