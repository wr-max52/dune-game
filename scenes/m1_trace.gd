extends SceneTree
## M1 trace harness (bot-driven, headless). Runs the real demo scene for N frames,
## letting its auto-pilot move the player and toggle FPV<->TPV, and writes every
## toggle with the player position and view to a text file. This is machine
## evidence (in test_results/m1_trace.txt) that movement + the camera toggle ran
## end to end, produced without a human or a rendered window.
##
## A human watching the GUI use scripts/record.sh; this is the reproducible,
## no-display equivalent that CI can check for.

var _demo
var _built := false
var _frame_no := 0
var _warmup := 5
var _total := 600          # 10s at 60fps of simulated play
var _trace := ""


func _process(_delta) -> bool:
	if not _built:
		if _frame_no < _warmup:
			_frame_no += 1
			return false
		_demo = load("res://scenes/m1_demo.gd").new()
		_demo._auto = true
		get_root().add_child(_demo)
		_built = true
		_trace += "# frame  view  pos_x  pos_z\n"

	_frame_no += 1
	if _frame_no % 5 == 0:
		var pos: Vector3 = _demo._player.controller.body_pos
		var view := "TPV" if not _demo._rig.rig.is_first_person() else "FPV"
		_trace += str(_frame_no).pad_zeros(4) + "  " + view + "  "
		_trace += "%.2f" % pos.x + "  " + "%.2f" % pos.z + "\n"

	if _frame_no >= _total:
		_dir_ensure()
		var f := FileAccess.open("res://test_results/m1_trace.txt", FileAccess.WRITE)
		f.store_string(_trace)
		f.close()
		print("M1TRACE wrote test_results/m1_trace.txt (", _frame_no, " frames)")
		quit(0)
	return false


func _dir_ensure() -> void:
	if not DirAccess.dir_exists_absolute("res://test_results"):
		DirAccess.make_dir_recursive_absolute("res://test_results")
