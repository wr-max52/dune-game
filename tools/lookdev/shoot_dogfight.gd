extends SceneTree
## Renders review stills of the M10 dogfight to test_results/lookdev/flight/:
##   lineup.png       -- every ship look side by side, lit by the space backdrop
##   fight_<t>s.png   -- the autopilot dogfight from the chase camera at time t
##
## Needs a real renderer (not --headless). See tools/lookdev/shoot_dogfight.sh.
## User args (after "--"):  times=6,14,24   frames=12   out=res://test_results/lookdev/flight

const Demo := preload("res://scenes/flight/dogfight_demo.gd")

var _demo
var _out := "res://test_results/lookdev/flight"
var _frames := 12
var _jobs: Array = []
var _job := -1
var _wait := 0
var _started := false
var _lineup: Node3D
var _cam: Camera3D


func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	_frames = int(args.get("frames", "12"))
	_out = args.get("out", _out)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	get_root().msaa_3d = Viewport.MSAA_2X
	_jobs.append(["lineup", 0.0])
	for t in str(args.get("times", "6,14,24")).split(","):
		_jobs.append(["fight", float(t)])
	_demo = Demo.new()
	_demo.autopilot = true
	_demo.fixed_step = 1.0 / 60.0
	get_root().add_child(_demo)


func _process(_dt: float) -> bool:
	if not _started:
		_started = true
		_demo.set_process(false)
		_next()
		return false
	_wait -= 1
	if _wait > 0:
		return false
	var job: Array = _jobs[_job]
	var name := "lineup" if job[0] == "lineup" else "fight_%02ds" % int(job[1])
	var img := get_root().get_texture().get_image()
	var path := _out + "/" + name + ".png"
	img.save_png(ProjectSettings.globalize_path(path))
	print("SHOOT: ", path)
	_next()
	return false


func _next() -> void:
	_job += 1
	if _job >= _jobs.size():
		print("SHOOT: done")
		quit(0)
		return
	var job: Array = _jobs[_job]
	_demo._show_banner("", 0.0)
	_demo._update_hud(0.0)
	if job[0] == "lineup":
		_demo.hud.visible = false
		_build_lineup()
	else:
		if _lineup != null:
			_lineup.queue_free()
			_lineup = null
			_demo.camera.current = true
			_demo.hud.visible = true
		var already: float = _demo.df.t
		_demo.warm_up(maxf(0.0, float(job[1]) - already))
		_demo._update_hud(0.0)
	_wait = _frames


func _build_lineup() -> void:
	_lineup = Node3D.new()
	_lineup.name = "Lineup"
	get_root().add_child(_lineup)
	var origin := Vector3(0, 400, 600)
	var ids: Array = _demo.kit.look_ids()
	ids.sort()
	var x := -float(ids.size() - 1) * 9.0
	for id in ids:
		var ship: Node3D = _demo.kit.build(id)
		_lineup.add_child(ship)
		ship.global_position = origin + Vector3(x, 0, 0)
		ship.rotation = Vector3(0.12, 0.85, 0.0)
		x += 18.0
	_cam = Camera3D.new()
	_cam.fov = 45.0
	_lineup.add_child(_cam)
	_cam.look_at_from_position(origin + Vector3(0, 9, 44), origin, Vector3.UP)
	_cam.current = true
