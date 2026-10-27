extends GutTest
## M8: the polish pass. This proves the vertical slice hangs TOGETHER: a single
## headless playthrough threads every system -- walk + camera toggle, a trooper
## sealing to cover, a timed-deflection duel with the duelist, the mission loop to
## COMPLETE, a typed voice turn to the LLM cantina owner, and a save round-trip -- and a
## performance report proves no frame exceeded the 50ms budget.
##
## Two generated logs are read here (ci.sh generates both first):
##   test_results/m8_playthrough.txt  -- the cross-system trace.
##   test_results/m8_perf_report.txt  -- worst/avg/over-budget frame cost.
##
## The 3-minute recorded clip is the manual path (scripts/record.sh), not this
## deterministic proof -- same posture as M6/M7.

const PLAY := "res://test_results/m8_playthrough.txt"
const PERF := "res://test_results/m8_perf_report.txt"

var _play := PackedStringArray()
var _perf := PackedStringArray()


func before_each() -> void:
	_play = _read(PLAY)
	_perf = _read(PERF)


func _read(path: String) -> PackedStringArray:
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		var raw: String = f.get_as_text()
		f.close()
		return raw.replace("\r", "").split("\n")
	return PackedStringArray()


# ---- the playthrough was generated ---------------------------------------

func test_trace_exists_and_has_rows() -> void:
	assert_gt(_play.size(), 1, "the playthrough trace was generated with rows")
	assert_true(_play[0].contains("frame"), "the trace starts with its header row")


# ---- every major system runs in one playthrough -------------------------

func test_walk_and_camera_toggle() -> void:
	var text: String = "\n".join(_play)
	assert_true(text.contains("TPV"), "the third-person view appears")
	assert_true(text.contains("FPV"), "the first-person view appears (toggle worked)")


func test_trooper_seals_and_squad_spreads() -> void:
	var text: String = "\n".join(_play)
	# Squad coordinator: 4 troopers, 4 cover nodes -> none left in the open.
	assert_true(text.contains("SQUAD_OPEN=0"), "the squad is not all in the open")


func test_deflection_duel_works() -> void:
	var text: String = "\n".join(_play)
	assert_true(text.contains("DUELIST_DEFLECT=true"), "a timed block reflected the bolt in a duel")


func test_mission_completes() -> void:
	var text: String = "\n".join(_play)
	assert_true(text.contains("ENEMIES_DOWN=5"), "all 5 outpost enemies were defeated")
	assert_true(text.contains("SAVED=true"), "the end-of-mission save wrote")
	assert_true(text.contains("RELOAD_CREDITS=150"), "credits survived the save round-trip")


func test_voice_turn_through_typed_default() -> void:
	var text: String = "\n".join(_play)
	assert_true(text.contains("VOICE_SRC=typed"), "the typed default source served the turn")
	# "LAT=" on the voice line is the recorded capture latency for the turn.
	assert_true(text.contains("VOICE_SRC=typed") and text.contains("LAT="),
		"a latency was recorded for the voice turn")


# ---- performance: no frame over the 50ms budget --------------------------

func test_perf_report_has_no_frame_over_budget() -> void:
	assert_gt(_perf.size(), 1, "the perf report was generated")
	var text: String = "\n".join(_perf)
	# The generator counts every per-frame row and writes the summary. A 0 over
	# budget means no single frame's work exceeded the 50ms budget -- the "no
	# hitch over 50ms" property, measured across the whole playthrough.
	assert_true(text.contains("over_budget=0"), "no frame exceeded the 50ms budget")
	# The worst frame, reported in the summary, must itself be under 50ms.
	var ms: float = _parse_float(text, "worst_ms=")
	assert_gt(ms, 0.0, "a worst-frame figure was recorded")
	assert_lte(ms, 50.0, "the worst frame stayed under the 50ms budget")
	# Sanity: the playthrough ran a full session worth of frames.
	var frames: int = int(text.substr(text.find("frames=") + 7, 10).split(" ", true)[0])
	assert_gt(frames, 0, "the report reflects a real number of frames")


func _parse_float(text: String, key: String) -> float:
	var idx := text.find(key)
	if idx < 0:
		return -1.0
	var rest: String = text.substr(idx + key.length())
	return float(rest.split(" ", true)[0])
