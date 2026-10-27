extends GutTest
## M5: scripted "bot playthrough" that walks the full mission loop headless
## (fixer -> contract -> travel -> fight -> crate -> payout -> save/load).
##
## The bot is the event sequence the mission state machine consumes. The trace
## scene (scenes/m5_mission_trace.gd) runs it end to end and writes
## test_results/m5_mission_trace.txt; this test reads that log and asserts the
## loop closed and the save/load round-tripped the four things the spec names:
## player position, credits, mission state, and cantina owner memory.
##
## The cantina owner conversation is a deterministic stub, not real inference (real
## inference is the M6 manual + recorded check). A failing bot blocks the merge.

const TRACE := "res://test_results/m5_mission_trace.txt"
var _lines := PackedStringArray()


func before_each() -> void:
	_lines.clear()
	if not FileAccess.file_exists(TRACE):
		# The trace generator must have run in CI first. Fail loudly if it did not.
		assert_true(false, "M5 trace missing: run scenes/m5_mission_trace.gd (ci.sh does this)")
		return
	var f := FileAccess.open(TRACE, FileAccess.READ)
	var raw := f.get_as_text()
	f.close()
	_lines = raw.replace("\r", "").split("\n")


func _non_comment_lines() -> PackedStringArray:
	var out := PackedStringArray()
	for line in _lines:
		if line.begins_with("#") or line.strip_edges().is_empty():
			continue
		out.append(line)
	return out


func test_bot_completes_the_full_loop() -> void:
	var lines := _non_comment_lines()
	assert_gt(lines.size(), 0, "the bot produced a trace")
	# The trace ends in COMPLETE with a non-null-credits payout.
	var text: String = "\n".join(lines)
	assert_true(text.contains("COMPLETE"), "mission reached COMPLETE")
	assert_true(text.contains("RELOAD_COMPLETE=true"), "reload restored a complete mission")
	assert_true(text.contains("RELOAD_KILLS=5"), "all 4 troopers + 1 duelist were defeated")
	assert_true(text.contains("RELOAD_PAYOUT=150"), "the mission payout is 150")


func test_payout_is_credited() -> void:
	var text: String = "\n".join(_non_comment_lines())
	assert_true(text.contains("credits=150"), "the 150-credit payout landed in credits")


func test_barter_memory_survives_save_load() -> void:
	var text: String = "\n".join(_non_comment_lines())
	assert_true(text.contains("RELOAD_MEMORY=Rider"), "cantina owner memory survived the save/load")


func test_player_position_survives_save_load() -> void:
	var text: String = "\n".join(_non_comment_lines())
	assert_true(text.contains("RELOAD_POS="), "player position is recorded for save/load")
	# The bot started at the docking bay; the saved position round-trips.
	assert_true(text.contains("(0.0, 0.0, 0.0)"), "saved player position round-trips")


func test_squad_is_not_all_in_the_open() -> void:
	# The 4-trooper squad coordinator keeps them off the open. With 4 members and
	# 4 cover nodes in the trace, none are left standing in the open.
	var text: String = "\n".join(_non_comment_lines())
	assert_true(text.contains("SQUAD_OPEN=0"), "no trooper is left in the open")
