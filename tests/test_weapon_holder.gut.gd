extends GutTest
## M11: the weapon swap state machine (pure).

func _h() -> WeaponHolder:
	return WeaponHolder.new(["pistol_blaster", "energy_blade", "rifle_blaster"])


func _run(h: WeaponHolder, secs: float) -> Array:
	var ev: Array = []
	var t := 0.0
	while t < secs:
		ev.append_array(h.update(1.0 / 60.0))
		t += 1.0 / 60.0
	return ev


func test_draw_from_empty_hands() -> void:
	var h := _h()
	h.request_slot(1)
	assert_true(h.is_swapping())
	var ev := _run(h, 0.3)
	assert_eq(h.current, "pistol_blaster")
	assert_true(h.is_ready())
	assert_true(ev.has("drawn:pistol_blaster"))


func test_swap_holsters_then_draws() -> void:
	var h := _h()
	h.request_slot(1)
	_run(h, 0.3)
	h.request_slot(2)
	var ev := _run(h, 0.5)
	assert_eq(ev, ["holstered:pistol_blaster", "drawing:energy_blade", "drawn:energy_blade"])
	assert_eq(h.previous, "pistol_blaster")


func test_same_key_again_holsters() -> void:
	var h := _h()
	h.request_slot(2)
	_run(h, 0.3)
	h.request_slot(2)
	_run(h, 0.3)
	assert_eq(h.current, "")
	assert_false(h.is_swapping())


func test_retarget_during_holster() -> void:
	var h := _h()
	h.request_slot(1)
	_run(h, 0.3)
	h.request_slot(2)
	_run(h, 0.05)
	h.request_slot(3)
	_run(h, 0.6)
	assert_eq(h.current, "rifle_blaster")


func test_reverse_during_draw_never_jumps() -> void:
	var h := _h()
	h.request_slot(1)
	_run(h, 0.1)
	var before := h.drawn()
	h.request_slot(2)
	assert_almost_eq(h.drawn(), before, 0.05, "the weapon goes back down from where it was")
	_run(h, 0.6)
	assert_eq(h.current, "energy_blade")


func test_spam_ends_on_last_request() -> void:
	var h := _h()
	for s in [1, 2, 1, 3, 2, 3, 1, 2]:
		h.request_slot(s)
		h.update(1.0 / 60.0)
	_run(h, 1.0)
	assert_eq(h.current, "energy_blade")
	assert_true(h.is_ready())


func test_last_weapon_and_cycle() -> void:
	var h := _h()
	h.request_slot(1)
	_run(h, 0.3)
	h.request_slot(3)
	_run(h, 0.5)
	h.request_last()
	_run(h, 0.5)
	assert_eq(h.current, "pistol_blaster")
	h.cycle(1)
	_run(h, 0.5)
	assert_eq(h.current, "energy_blade")


func test_tab_cycle_ends_on_empty_hands() -> void:
	var h := _h()
	for want in ["pistol_blaster", "energy_blade", "rifle_blaster", "", "pistol_blaster"]:
		h.cycle_to_empty()
		_run(h, 0.5)
		assert_eq(h.current, want)


func test_tab_cycle_skips_weapons_it_may_not_draw() -> void:
	var h := _h()
	h.can_draw = func(id): return id == "pistol_blaster"
	h.cycle_to_empty()
	_run(h, 0.5)
	assert_eq(h.current, "pistol_blaster")
	h.cycle_to_empty()
	_run(h, 0.5)
	assert_eq(h.current, "", "the only weapon, then empty hands")


func test_tab_cycle_mid_swap_follows_where_it_is_going() -> void:
	var h := _h()
	h.cycle_to_empty()
	h.cycle_to_empty()     # pressed again while the pistol is still coming up
	_run(h, 0.6)
	assert_eq(h.current, "energy_blade")
