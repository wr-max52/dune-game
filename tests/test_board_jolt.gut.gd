extends GutTest
## Issue #87: a vehicle sinks, lifts and shudders as you climb in, then settles.


func test_idle_is_identity() -> void:
	var j := BoardJolt.new()
	assert_eq(j.step(1.0 / 60.0), Transform3D.IDENTITY)
	assert_false(j.active())


func test_sinks_then_lifts_then_settles() -> void:
	var j := BoardJolt.new()
	j.start()
	var low := 0.0
	var high := 0.0
	var low_t := -1.0
	var high_t := -1.0
	var shook := false
	var last := Transform3D.IDENTITY
	for i in 120:
		last = j.step(1.0 / 60.0)
		var y := last.origin.y
		if y < low:
			low = y
			low_t = j.t
		if y > high:
			high = y
			high_t = j.t
		shook = shook or absf(last.basis.get_euler().z) > 0.005
	assert_lt(low, -0.03, "sinks under the rider")
	assert_gt(high, 0.08, "lifts")
	assert_lt(low_t, high_t, "sink first, lift after")
	assert_true(shook, "rocks while the engine catches")
	assert_eq(last, Transform3D.IDENTITY, "settled")
	assert_false(j.active())


func test_a_ship_moves_more() -> void:
	var s := BoardJolt.new(1.6, 1.4)
	var b := BoardJolt.new()
	s.start()
	b.start()
	var hs := 0.0
	var hb := 0.0
	for i in 90:
		hs = maxf(hs, s.step(1.0 / 60.0).origin.y)
		hb = maxf(hb, b.step(1.0 / 60.0).origin.y)
	assert_gt(hs, hb)
