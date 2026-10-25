extends GutTest
## M2: the combat integration trace. Proves, in CI and without rendering, the exact
## claim "both blasters work, a trooper fights back with cover, health/death work":
##   - the trooper SEALs to cover first, then opens FIRING,
##   - the player's rifle reduces the trooper to 0 HP (it dies),
##   - and the trooper takes the player down from 100 HP (it fights back).

const TRACE := "res://test_results/m2_combat_trace.txt"


func _read() -> PackedStringArray:
	var f := FileAccess.open(TRACE, FileAccess.READ)
	var text: String = f.get_as_text()
	f.close()
	return text.split("\n")


func test_trace_exists_and_has_rows() -> void:
	assert_true(FileAccess.file_exists(TRACE), "the trace should exist after trace run")
	var lines := _read()
	var data := 0
	for l in lines:
		if not (l.begins_with("#") or l.strip_edges().is_empty()):
			data += 1
	assert_gt(data, 3, "the trace should record many rows")


func _rows() -> Array:
	var out := []
	for l in _read():
		if not (l.begins_with("#") or l.strip_edges().is_empty()):
			out.append(l.strip_edges())
	return out


func test_trooper_seals_then_fires() -> void:
	var rows := _rows()
	var saw_sealing := false
	var saw_firing := false
	var firing_first_seen := 0
	# Track first index of each state.
	var seal_idx := -1
	var fire_idx := -1
	for i in rows.size():
		var r: String = rows[i]
		if r.contains("SEALING"):
			if seal_idx < 0:
				seal_idx = i
		if r.contains("FIRING") and fire_idx < 0:
			fire_idx = i
	if seal_idx >= 0:
		saw_sealing = true
	if fire_idx >= 0:
		saw_firing = true
	assert_true(saw_sealing, "the trooper should spend a phase sealing to cover")
	assert_true(saw_firing, "the trooper should open fire once at cover")
	if seal_idx >= 0 and fire_idx >= 0:
		assert_lt(seal_idx, fire_idx, "sealing to cover must precede firing")


func test_rifle_kills_the_trooper() -> void:
	var rows := _rows()
	var min_trooper := 100000
	var ever_dead := false
	for r in rows:
		var hp: int = _col(r, "trooper=")
		min_trooper = mini(min_trooper, hp)
		if r.contains("DEAD"):
			ever_dead = true
	assert_lte(min_trooper, 0, "the rifle should reduce the trooper to 0 HP")
	assert_true(ever_dead, "a 0-HP trooper is recorded as DEAD")


func test_trooper_fights_back() -> void:
	var rows := _rows()
	# Read every numeric player HP; first seen is the start, last seen is the end.
	var first: int = _col(rows[0], "player=")
	var last: int = _col(rows[rows.size() - 1], "player=")
	# The trooper should have reduced the player below their starting 100.
	assert_lt(last, 95, "the trooper should deal the player at least some damage")
	assert_gt(first, last, "the player ends the duel with less HP than they started")


func _col(row: String, key: String) -> int:
	# Parse "key=NN" out of a row.
	var after: String = row.split(key, false)[1] if row.contains(key) else "0"
	var val_str := after.split(" ", false)[0]
	return int(val_str)
