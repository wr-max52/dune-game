extends GutTest
## M10: ship weapons and damage. The lead solver aims where a moving target will be,
## the projectile field sweeps fast bolts so they cannot tunnel, seekers home on a
## lock, the shield takes damage before the hull and recharges after a
## delay, and the loadout builds its guns from data.

const LeadSolver := preload("res://src/systems/flight/lead_solver.gd")
const ProjectileField := preload("res://src/systems/flight/projectile_field.gd")
const ShipDefense := preload("res://src/systems/flight/ship_defense.gd")
const ShipLoadout := preload("res://src/systems/flight/ship_loadout.gd")
const MissileLock := preload("res://src/systems/flight/missile_lock.gd")
const CoreScript := preload("res://src/systems/dataload/core_content.gd")

var content


func before_each() -> void:
	content = CoreScript.new()
	content.load_from()


# ---- lead -------------------------------------------------------------------

func test_lead_meets_a_crossing_target() -> void:
	var shooter := Vector3.ZERO
	var target := Vector3(0, 0, -400)
	var tvel := Vector3(50, 0, 0)
	var s := 300.0
	var lead := LeadSolver.intercept(shooter, Vector3.ZERO, target, tvel, s)
	assert_true(lead.valid, "a slow crossing target has an intercept")
	var bolt_at: Vector3 = shooter + (lead.dir as Vector3) * s * float(lead.time)
	var target_at: Vector3 = target + tvel * float(lead.time)
	assert_lt(bolt_at.distance_to(target_at), 0.01, "the bolt and the target meet")
	assert_gt((lead.point as Vector3).x, target.x, "the lead point is ahead of the target")


func test_lead_accounts_for_shooter_velocity() -> void:
	# Bolts inherit the shooter's velocity, so a shooter flying with the target
	# aims straight at it.
	var v := Vector3(40, 0, 0)
	var lead := LeadSolver.intercept(Vector3.ZERO, v, Vector3(0, 0, -300), v, 300.0)
	assert_almost_eq((lead.dir as Vector3).x, 0.0, 0.0001, "no lead needed in a shared frame")


func test_no_intercept_falls_back_to_target() -> void:
	var lead := LeadSolver.intercept(Vector3.ZERO, Vector3.ZERO, Vector3(0, 0, -100),
		Vector3(0, 0, -500), 100.0)
	assert_false(lead.valid, "a target running away faster than the bolt has no intercept")
	assert_eq(lead.point, Vector3(0, 0, -100), "fallback point is the target's position")


# ---- projectiles --------------------------------------------------------------

func _target(id: int, team: String, pos: Vector3, r: float = 3.0) -> Dictionary:
	return { "id": id, "team": team, "position": pos, "radius": r, "alive": true }


func test_fast_bolt_cannot_tunnel_through_a_ship() -> void:
	var field = ProjectileField.new()
	# 300 m/s at 60 fps moves 5 m a frame; the ship is 3 m wide. A point check misses.
	field.add({ "origin": Vector3(0, 0, 0), "velocity": Vector3(0, 0, -300), "damage": 9, "range": 900 }, 1, "player")
	var hits: Array = []
	for i in 60:
		hits.append_array(field.step(1.0 / 60.0, [_target(2, "hostile", Vector3(0, 0, -102.5), 1.5)]))
	assert_eq(hits.size(), 1, "the swept test catches the bolt exactly once")
	assert_eq(field.count(), 0, "a bolt is spent on its hit")


func test_bolts_ignore_their_own_team() -> void:
	var field = ProjectileField.new()
	field.add({ "origin": Vector3.ZERO, "velocity": Vector3(0, 0, -300), "range": 900 }, 1, "player")
	var hits: Array = field.step(0.5, [_target(3, "player", Vector3(0, 0, -100))])
	assert_eq(hits.size(), 0, "no friendly fire")


func test_bolts_expire_at_range() -> void:
	var field = ProjectileField.new()
	field.add({ "origin": Vector3.ZERO, "velocity": Vector3(0, 0, -300), "range": 300 }, 1, "player")
	field.step(0.5, [])
	assert_eq(field.count(), 1, "still flying at 150 m")
	field.step(0.6, [])
	assert_eq(field.count(), 0, "gone past its 300 m range")


func test_seeker_turns_toward_its_target() -> void:
	var field = ProjectileField.new()
	field.add({ "origin": Vector3.ZERO, "velocity": Vector3(0, 0, -130), "range": 2000,
		"homing": true, "turn_rate": 2.5, "target_id": 7, "kind": "missile", "damage": 55 }, 1, "player")
	var tgt := _target(7, "hostile", Vector3(300, 0, -300))
	var hit := false
	for i in 600:
		if not field.step(1.0 / 60.0, [tgt]).is_empty():
			hit = true
			break
	assert_true(hit, "a seeker curves onto a target well off its nose")


# ---- defense ------------------------------------------------------------------

func test_shield_takes_damage_before_the_hull() -> void:
	var d = ShipDefense.new(content.get_ship("interceptor"))
	var r: Dictionary = d.apply_damage(50.0)
	assert_eq(r.shield, 50.0, "the shield absorbs the whole hit")
	assert_eq(d.hull_hp(), d.hull_max(), "the hull is untouched")
	r = d.apply_damage(50.0)
	assert_eq(r.shield, 30.0, "the shield takes what it has left")
	assert_eq(r.hull, 20.0, "the rest spills into the hull")
	assert_eq(d.hull_hp(), d.hull_max() - 20, "hull lost the spill")


func test_shield_recharges_only_after_the_delay() -> void:
	var cfg: Dictionary = content.get_ship("interceptor")
	var d = ShipDefense.new(cfg)
	d.apply_damage(40.0)
	var low: float = d.shield
	d.step(float(cfg.shield.delay) * 0.5)
	assert_eq(d.shield, low, "no recharge inside the delay")
	for i in 120:
		d.step(0.05)
	assert_gt(d.shield, low, "the shield recharges after the delay")
	assert_lte(d.shield, d.shield_max, "never above max")


func test_unshielded_fighter_takes_hull_damage_and_dies() -> void:
	var d = ShipDefense.new(content.get_ship("remnant_fighter"))
	assert_eq(d.shield_max, 0.0, "the remnant fighter has no shield")
	d.apply_damage(1000.0)
	assert_false(d.is_alive(), "enough damage destroys the ship")


# ---- loadout + lock -------------------------------------------------------------

func test_loadout_builds_hardpoints_from_data() -> void:
	var lo = ShipLoadout.new(content.get_ship("interceptor"), content)
	assert_eq(lo.hardpoints.size(), 3, "two cannons and a seeker rack")
	assert_true(lo.has_group("primary"), "cannons are the primary group")
	assert_true(lo.has_group("secondary"), "the seeker is the secondary group")
	var fighter = ShipLoadout.new(content.get_ship("remnant_fighter"), content)
	assert_false(fighter.has_group("secondary"), "the remnant fighter carries no seekers")


func test_cannons_fire_linked_bolts_that_inherit_velocity() -> void:
	var lo = ShipLoadout.new(content.get_ship("interceptor"), content)
	var vel := Vector3(0, 0, -40)
	var out: Array = lo.fire(1.0 / 60.0, Transform3D.IDENTITY, vel, true, false)
	assert_eq(out.size(), 2, "both cannons fire together")
	for b in out:
		assert_eq(b.kind, "bolt")
		var v: Vector3 = b.velocity
		assert_lt(v.z, -300.0, "bolt speed adds to the ship's own speed")
	var again: Array = lo.fire(1.0 / 60.0, Transform3D.IDENTITY, vel, true, false)
	assert_eq(again.size(), 0, "the fire rate limits the next shot")


func test_seeker_spawn_carries_its_splash_and_homes_only_on_a_target() -> void:
	var lo = ShipLoadout.new(content.get_ship("interceptor"), content)
	var w: Dictionary = content.get_weapon("ship_missile")
	var out: Array = lo.fire(1.0 / 60.0, Transform3D.IDENTITY, Vector3.ZERO, false, true)
	assert_eq(out.size(), 1, "the seeker trigger launches without a target")
	assert_eq(out[0].kind, "missile")
	assert_eq(int(out[0].target_id), -1, "no target: it flies straight")
	assert_gt(float(out[0].splash_radius), 0.0, "a seeker bursts with splash")
	assert_almost_eq(float(out[0].splash_radius), float(w.splash_radius), 0.001)
	assert_gt(float(out[0].blast_size), 0.0, "and goes up like a vehicle")


func test_seeker_rack_hands_across() -> void:
	var air = ShipLoadout.new(content.get_ship("interceptor"), content)
	var space = ShipLoadout.new(content.get_ship("interceptor"), content)
	air.fire(1.0 / 60.0, Transform3D.IDENTITY, Vector3.ZERO, false, true)
	assert_eq(air.group_ammo("secondary"), int(content.get_weapon("ship_missile").mag) - 1)
	space.set_rack("secondary", air.rack("secondary"))
	assert_eq(space.group_ammo("secondary"), air.group_ammo("secondary"), "one rack in the air and in space")


func test_cannons_converge_ahead_of_the_nose() -> void:
	var cfg: Dictionary = content.get_ship("interceptor")
	var lo = ShipLoadout.new(cfg, content)
	var out: Array = lo.fire(1.0 / 60.0, Transform3D.IDENTITY, Vector3.ZERO, true, false)
	var conv := float(cfg.convergence)
	for b in out:
		var o: Vector3 = b.origin
		var v: Vector3 = b.velocity
		var d := v.normalized()
		var at := o + d * ((-conv - o.z) / d.z)
		assert_almost_eq(at.x, 0.0, 0.01, "each gun's line crosses the centre at the convergence range")


func test_missile_lock_builds_in_the_cone_and_resets_on_switch() -> void:
	var lock = MissileLock.new()
	lock.configure(content.get_weapon("ship_missile"))
	var fwd := Vector3(0, 0, -1)
	for i in int(lock.lock_time * 60.0) + 2:
		lock.update(1.0 / 60.0, 5, fwd, Vector3(0, 0, -300))
	assert_true(lock.is_locked(), "holding the target in the cone locks it")
	lock.update(1.0 / 60.0, 6, fwd, Vector3(0, 0, -300))
	assert_false(lock.is_locked(), "switching targets starts the lock over")
	lock.reset()
	for i in 200:
		lock.update(1.0 / 60.0, 5, fwd, Vector3(300, 0, 0))
	assert_false(lock.is_locked(), "a target off to the side never locks")
