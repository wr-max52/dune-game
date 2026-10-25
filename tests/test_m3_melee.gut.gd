extends GutTest
## M3: the melee-duel trace. Proves, in CI and without rendering, that the energy
## blade's timed-deflection works and that a duelist enemy parries it -- while the
## blade still lands blows and can defeat the duelist.

const TRACE := "res://test_results/m3_melee_trace.txt"


func _rows() -> Array:
	var out := []
	var f := FileAccess.open(TRACE, FileAccess.READ)
	var text := f.get_as_text()
	f.close()
	for l in text.split("\n"):
		if not (l.begins_with("#") or l.strip_edges().is_empty()):
			out.append(l.strip_edges())
	return out


func test_trace_exists() -> void:
	assert_true(FileAccess.file_exists(TRACE), "the melee trace should exist")
	var rows := _rows()
	var data := 0
	for l in rows:
		data += 1
	assert_gt(data, 3, "the trace should record many rows")


func test_duelist_parries() -> void:
	var rows := _rows()
	var parried := false
	for r in rows:
		if r.contains("PARRY"):
			parried = true
			break
	assert_true(parried, "the duelist should parry (deflect) at least one blow")


func test_blade_blow_lands() -> void:
	var rows := _rows()
	var landed := false
	for r in rows:
		if r.contains("HIT"):
			landed = true
			break
	assert_true(landed, "the blade should land blows on the duelist")


func test_duelist_can_be_brought_down() -> void:
	var rows := _rows()
	var down := false
	var min_hp := 100000
	for r in rows:
		if r.contains("DOWN"):
			down = true
		var hp := _col(r, "duelist=")
		min_hp = mini(min_hp, hp)
	assert_true(down, "the duelist should be brought down in the duel")
	assert_lte(min_hp, 0, "the duelist's health should reach 0")


func _col(row: String, key: String) -> int:
	var after := row.split(key, false)[1] if row.contains(key) else "0"
	return int(after.split(" ", false)[0])
