extends SceneTree
## Renders the port town from the fixed review cameras in content/look/town_shots.json
## for each lighting preset, and saves PNGs to test_results/town/.
##
## Needs a real renderer (not --headless). See tools/town/shoot_town.sh.
## User args (after "--"):
##   presets=golden,noon,dusk   shots=hero_vista,street   frames=24   out=res://test_results/town

const TownDemo := preload("res://scenes/town_demo.gd")

var _scene: Node3D
var _jobs: Array = []
var _frames_per_shot := 24
var _out := "res://test_results/town"
var _wait := 0
var _job := -1
var _t0 := 0
var _args := {}
var _planned := false
var _t_start := 0


func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	_frames_per_shot = int(args.get("frames", "24"))
	_out = args.get("out", _out)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))

	get_root().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	get_root().msaa_3d = Viewport.MSAA_2X
	RenderingServer.directional_shadow_atlas_set_size(4096, true)

	_t_start = Time.get_ticks_msec()
	_scene = TownDemo.new()
	_scene.lookdev_mode = true
	get_root().add_child(_scene)
	_args = args


## The scene's _ready runs after _initialize, so jobs are planned on the first frame.
func _plan(args: Dictionary) -> void:
	var presets: PackedStringArray = args.get("presets", "golden,noon,dusk").split(",")
	var shots: PackedStringArray = args.get("shots", ",".join(PackedStringArray(_scene.shot_ids()))).split(",")
	for p in presets:
		for s in shots:
			_jobs.append([p, s])
	print("SHOOT: %d jobs, %d frames each -> %s" % [_jobs.size(), _frames_per_shot, _out])
	_next()


func _next() -> void:
	_job += 1
	if _job >= _jobs.size():
		print("SHOOT: done")
		quit(0)
		return
	var p: String = _jobs[_job][0]
	var s: String = _jobs[_job][1]
	if _scene.preset != p or _job == 0:
		_scene.set_preset(p)
	if not _scene.show_shot(s):
		push_error("SHOOT: unknown shot %s" % s)
	_wait = _frames_per_shot
	_t0 = Time.get_ticks_msec()


func _process(_delta: float) -> bool:
	if not _planned:
		_planned = true
		print("SHOOT: scene built in %.1fs" % ((Time.get_ticks_msec() - _t_start) / 1000.0))
		_plan(_args)
		return false
	if _job < 0 or _job >= _jobs.size():
		return false
	_wait -= 1
	if _wait > 0:
		return false
	var p: String = _jobs[_job][0]
	var s: String = _jobs[_job][1]
	var img := get_root().get_texture().get_image()
	var path := ProjectSettings.globalize_path("%s/%s_%s.png" % [_out, p, s])
	img.save_png(path)
	print("SHOT %s/%s saved in %.1fs -> %s" % [p, s, (Time.get_ticks_msec() - _t0) / 1000.0, path])
	_next()
	return false
