extends "res://scenes/combat_trace.gd"
## The port's locals (Townsfolk), headless with real physics, each scenario in a
## fresh town. Reuses combat_trace.gd's helpers (fresh towns, the walking bot,
## shooting).
##
##   STROLL    the five walkers (three in the houses, two shoppers) walk their
##             loops; the merchants and the fence stay at their stalls, facing
##             the aisle; walking through the market starts nothing
##   MARKET    shoot a shopper in the aisle: the locals' alarm goes up (not the
##             garrison's), every local fights, the merchants shoot back from
##             behind their counters without leaving the stall, the gear trader
##             stops trading, locals standing drops
##   HOUSES    shoot a resident in the west houses: the east houses' resident
##             joins in too (one alarm for every local) and shoots
##
## Writes test_results/locals_trace.txt for tests/test_locals_trace.gut.gd.
## Run: godot --headless --fixed-fps 60 --path . -s res://scenes/locals_trace.gd

const OUT3 := "res://test_results/locals_trace.txt"

var tf: Townsfolk


func _initialize() -> void:
	out_path = OUT3
	lines.append("# locals_trace v1")
	_run()


func _run() -> void:
	seed(5151)
	await _stroll()
	await _market()
	await _houses()
	_scenario = ""
	kv("WORST_FRAME_MS", snappedf(worst_ms, 0.01))
	kv("WORST_FRAME_AT", _worst_where)
	_finish()


func _fresh_town(name: String) -> void:
	await _fresh(name, 0)
	tf = demo.townsfolk
	for n in demo.locals:
		n.target_armed = func(): return _armed


func _by_role(role: String) -> Array:
	return demo.locals.filter(func(n): return str(n.profile.get("role", "")) == role)


func _fighting() -> int:
	var k := 0
	for n in demo.locals:
		if not n.dead and tf.brains[n].state == GuardBrain.State.COMBAT:
			k += 1
	return k


## Hold still for `seconds`, topping the player's health up so the locals never
## down them (this trace is about who fights, not who wins).
func _hold_alive(seconds: float) -> void:
	for f in int(seconds * 60.0):
		player.set_command(Vector2.ZERO, false, false, false)
		if f % 30 == 0:
			player.revive(60.0)
		await physics_frame


## Shoot `g` until it is hit (it may be walking out of the line of fire).
func _shoot_until_hit(g: NpcBody, seconds: float) -> bool:
	for f in int(seconds * 60.0):
		if g.hits_taken > 0:
			return true
		if f % 12 == 0 and _player_sees(g):
			_shoot_at(g, 0.05)
		await physics_frame
	return g.hits_taken > 0


func _stroll() -> void:
	await _fresh_town("STROLL")
	kv("LOCALS", demo.locals.size())
	kv("WALKERS", _by_role("local").size())
	kv("MERCHANTS", _by_role("merchant").size())
	kv("GARRISON", demo.npcs.size())
	var faced := true
	for m in _by_role("merchant"):
		var f: Vector3 = m.forward()
		faced = faced and absf(f.z) > 0.9 and signf(-38.0 - m.global_position.z) == signf(f.z)
	kv("MERCHANTS_FACE_AISLE", faced)
	_park(Vector3(36, 0, -38))
	await _walk(Vector3(90, 0, -38), 30.0)
	await _hold_alive(12.0)
	var walked := 0
	for n in _by_role("local"):
		if n.walked_m > 4.0:
			walked += 1
	kv("WALKED", walked)
	var stayed := true
	for n in _by_role("merchant"):
		stayed = stayed and Vector2(n.global_position.x - n.post_pos.x, n.global_position.z - n.post_pos.z).length() < 0.5
	kv("MERCHANTS_STAYED", stayed)
	kv("ALARM", tf.alarm.state_name())
	var trader: Dictionary = demo.gear.content.get_vendor("gear_trader")
	kv("TRADER_OPEN", demo.gear.is_open(trader))


func _market() -> void:
	await _fresh_town("MARKET")
	var s0 := int(WorldState.standing.get("locals", 0))
	_park(Vector3(66, 0, -38))
	var shopper: NpcBody = demo.npc("shopper_1")
	await _until(func(): return _player_sees(shopper) and shopper.global_position.distance_to(player.global_position) < 25.0, 40.0)
	kv("HIT", await _shoot_until_hit(shopper, 8.0))
	await _frames(10)
	kv("ALARM", tf.alarm.state_name())
	kv("ALARM_WHY", tf.alarm.why)
	kv("SAID_ALARM", tf.barks_said.has("alarm"))
	kv("GARRISON_ALARM", demo.garrison.alarm.state_name())
	await _frames(30)
	kv("FIGHTING", _fighting())
	kv("ALIVE", demo.locals.filter(func(n): return not n.dead).size())
	var trader: Dictionary = demo.gear.content.get_vendor("gear_trader")
	kv("TRADER_OPEN", demo.gear.is_open(trader))
	await _hold_alive(10.0)
	var shots := 0
	var stayed := true
	for n in _by_role("merchant"):
		shots += n.shots_fired
		stayed = stayed and Vector2(n.global_position.x - n.post_pos.x, n.global_position.z - n.post_pos.z).length() < 0.5
	kv("MERCHANT_SHOTS", shots)
	kv("MERCHANTS_STAYED", stayed)
	kv("PLAYER_HURT", player.hits_taken > 0)
	kv("STANDING_DROP", s0 - int(WorldState.standing.get("locals", 0)))


func _houses() -> void:
	await _fresh_town("HOUSES")
	var rw: NpcBody = demo.npc("resident_w")
	var re: NpcBody = demo.npc("resident_e")
	_park(Vector3(-17.5, 0, -48))
	await _until(func(): return _player_sees(rw) and rw.global_position.distance_to(player.global_position) < 22.0, 40.0)
	kv("HIT", await _shoot_until_hit(rw, 8.0))
	await _frames(20)
	kv("ALARM", tf.alarm.state_name())
	kv("EAST_FIGHTING", tf.brains[re].state == GuardBrain.State.COMBAT)
	await _hold_alive(8.0)
	kv("RESIDENT_SHOTS", rw.shots_fired)
