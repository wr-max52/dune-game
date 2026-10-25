extends GutTest
## M3: the energy blade. Light/heavy attacks, a stamina budget, blocking, and the
## skill -- timed deflection of an incoming bolt. All proven headless.

var BladeScript


func before_each() -> void:
	BladeScript = load("res://src/systems/combat/energy_blade.gd")


func _blade() -> RefCounted:
	var b = BladeScript.new({
		"max_stamina": 100.0,
		"block_cost_stamina": 8.0,
		"deflect_window": 0.18,
		"deflect_refund_stamina": 6.0,
		"light_damage": 16,
		"heavy_damage": 30,
	})
	return b


func test_light_attack_costs_stamina_and_ends() -> void:
	var b = _blade()
	assert_true(b.light_attack(), "a light attack starts when stamina and stance allow")
	var s: int = b.update(1.0)  # run past the 0.25s duration
	assert_eq(s, int(b.State.IDLE), "the attack returns to IDLE after its duration")
	var cost: float = 100.0 - b.stamina
	assert_gt(cost, 0.0, "the light attack spent stamina")


func test_heavy_attack_costs_more_than_light() -> void:
	var b1 = _blade()
	b1.light_attack()
	var after_light: float = 100.0 - b1.stamina
	var b2 = _blade()
	b2.heavy_attack()
	var after_heavy: float = 100.0 - b2.stamina
	assert_gt(after_heavy, after_light, "a heavy attack costs more stamina than a light one")


func test_attack_blocked_when_no_stamina() -> void:
	var b = _blade()
	b.stamina = 1.0
	var ok: bool = b.heavy_attack()
	assert_false(ok, "a heavy attack cannot start with too little stamina")
	assert_eq(b.state, int(b.State.IDLE), "staying IDLE when under-stunned on stamina")


func test_block_drains_stamina_over_time() -> void:
	var b = _blade()
	b.start_block()
	assert_true(b.is_blocking(), "the blade is blocking")
	var before: float = b.stamina
	b.update(1.0)  # block for a second
	var after: float = b.stamina
	assert_lt(after, before, "blocking drains stamina over time")


func test_block_to_zero_ends_in_blocked_out() -> void:
	var b = _blade()
	b.stamina = 8.0  # ~1s of block at 8/s
	b.start_block()
	b.update(1.0)  # drains to 0 within this second
	assert_eq(b.state, int(b.State.BLOCKED_OUT), "an empty block becomes BLOCKED_OUT")


func test_timed_deflection_reflects_a_bolt() -> void:
	## The core skill: press block, then while the block is fresh (within the
	## deflect window) a bolt arrives -> DEFLECTED, and stamina is refunded. Start
	## with low stamina so the refund is visible (it is otherwise capped).
	var b = _blade()
	b.stamina = 40.0
	b.start_block()
	var s_before: float = b.stamina
	var res: int = b.intercept_bolt()
	assert_eq(res, int(b.BoltResult.DEFLECTED), "a fresh block deflects the bolt")
	assert_gt(b.stamina, s_before, "a deflect refunds stamina")


func test_late_block_absorbs_instead_of_deflecting() -> void:
	## Hold the block PAST the deflect window, then a bolt arrives -> BLOCKED, not
	## the cheaper DEFLECTED. This is the timing failure: "too late to deflect."
	var b = _blade()
	b.start_block()
	b.update(0.5)  # 0.5s > 0.18s deflect window
	var res: int = b.intercept_bolt()
	assert_eq(res, int(b.BoltResult.BLOCKED), "a late block absorbs, it does not deflect")


func test_pierced_when_not_blocking() -> void:
	## Not blocking at all -> a bolt pierces through as damage.
	var b = _blade()
	var res: int = b.intercept_bolt()
	assert_eq(res, int(b.BoltResult.PIERCED), "with no block, the bolt pierces")


func test_stamina_recovered_when_idle() -> void:
	var b = _blade()
	b.stamina = 10.0
	b.update(2.0)  # idle regen
	assert_gte(b.stamina, 10.0, "stamina recovers while idle")
	assert_lt(b.stamina, 100.0 + 0.001, "recovery is capped at max")