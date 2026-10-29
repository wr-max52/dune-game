extends GutTest
## Issue #76: the Remnant's dark ships and the dogfight in the port's sky. The
## outposts' dark interceptor and freighters are flyable and stealing one sounds
## that outpost's alarm; the barracks pad's dark interceptor (AtmoFighter) takes
## off after you when you are wanted, hunts you with the space dogfight's pilot,
## guns and shields, keeps off the ground, and both of you start again in town
## when one of you goes down.
##
## The town is the real one (greybox: no models), its ship and fighter stepped by
## hand at 60 Hz so a minute of flying takes a moment.

const TownDemo := preload("res://scenes/town_demo.gd")
const CoreContent := preload("res://src/systems/dataload/core_content.gd")
const DT := 1.0 / 60.0

var content


func before_each() -> void:
	WorldState.reset()
	content = CoreContent.new()
	content.load_from()


func after_each() -> void:
	WorldState.reset()


func _town() -> Node:
	var t = TownDemo.new()
	t.use_look = false
	t.nav_async = false
	add_child_autofree(t)
	return t


## Step the player's ship and the interceptor by hand (their own frames paused).
func _fly(t, secs: float, cmd: Dictionary = {}) -> void:
	t.pilot.set_physics_process(false)
	t.interceptor.set_physics_process(false)
	if not cmd.is_empty():
		t.pilot.set_external_command(cmd)
	for i in int(secs / DT):
		t.pilot._physics_process(DT)
		t.interceptor.step(DT)


func _outpost_berth(t, outpost_id: String) -> int:
	for i in t.pilot.berths.size():
		if str(t.pilot.berths[i].get("outpost", "")) == outpost_id:
			return i
	return -1


## Walk up to the near outpost's interceptor and climb in.
func _steal(t) -> int:
	WorldState.set_flag("ships_unlocked")
	var i := _outpost_berth(t, "remnant_outpost_near")
	var v: Node3D = t.pilot.berths[i].visual
	t._player.global_position = v.global_position + Vector3(6, -float(t.pilot.berths[i].clearance), 0)
	assert_eq(t.pilot.nearest_berth(), i, "standing at the outpost's ship")
	assert_true(t.pilot.board())
	return i


# ---- data ------------------------------------------------------------------------

func test_dark_ships_are_the_remnant_s() -> void:
	for pair in [["remnant_interceptor", "interceptor"], ["remnant_freighter", "freighter"]]:
		var d: Dictionary = content.get_ship(pair[0])
		var base: Dictionary = content.get_ship(pair[1])
		assert_eq(str(d.faction), "imperial_remnant")
		assert_eq(d.atmosphere, base.atmosphere, "%s flies like the port's" % pair[0])
		var look: Dictionary = ShipKit.new().looks.get(str(d.look), {})
		assert_true(look.get("darken") is Dictionary, "%s is painted dark" % pair[0])
		assert_eq(str(look.get("scene", "")), str(ShipKit.new().looks[pair[1]].scene), "the same model")
	assert_false(content.get_pilot("remnant_hunter").is_empty())
	var near: Dictionary = content.get_location("remnant_outpost_near")
	assert_eq(str(near.ship), "remnant_interceptor")
	assert_eq(str(content.get_location("remnant_outpost_far").ship), "remnant_freighter")


## Textured models (the freighter) go through the dark shader; flat-colour ones
## (the interceptor) get darker copies of their own colours, accents in oxblood.
func test_dark_looks_darken_the_models() -> void:
	for look in ["interceptor_dark", "freighter_dark"]:
		var ship := ShipKit.new().build(look)
		add_child_autofree(ship)
		if str(ship.get_meta("source", "")) != "scene":
			pass_test("no model in this build")
			continue
		var meshes: Array = ship.find_children("*", "MeshInstance3D", true, false)
		var dark: Array = meshes.filter(func(m): return m.material_override is ShaderMaterial \
			or m.get_surface_override_material(0) != null)
		assert_eq(dark.size(), meshes.size(), "%s: every part painted dark" % look)
		for m in meshes:
			var o = m.get_surface_override_material(0)
			if o is BaseMaterial3D:
				var c: Color = (o as BaseMaterial3D).albedo_color
				assert_true(c.v < 0.45, "%s: %s is dark (%s)" % [look, m.name, c])


# ---- stealing ----------------------------------------------------------------------

func test_outpost_ships_are_flyable_and_stealing_sounds_the_alarm() -> void:
	var t = _town()
	await wait_physics_frames(2)
	for id in Story.OUTPOSTS:
		assert_gte(_outpost_berth(t, id), 0, "%s's ship is a berth" % id)
	var g: Garrison = t.outposts.garrisons["remnant_outpost_near"]
	assert_false(g.alarm.active())
	var i := _steal(t)
	assert_eq(t.pilot.berth, i)
	assert_true(t.pilot.flying_stolen())
	assert_eq(t.pilot.steals, 1)
	assert_true(g.alarm.active(), "the outpost's alarm goes up")
	assert_eq(str(t.pilot.ship_id), "remnant_interceptor", "and you fly its own stats")


# ---- the interceptor ------------------------------------------------------------

func test_the_barracks_interceptor_waits_on_its_pad() -> void:
	var t = _town()
	await wait_physics_frames(2)
	var f: AtmoFighter = t.interceptor
	assert_not_null(f, "the barracks pad has its interceptor")
	assert_eq(f.mode, AtmoFighter.Mode.PARKED)
	var pad: Dictionary = t.town.get_box("barracks_pad")
	assert_false(pad.is_empty())
	var c := (WorldGround._v3(pad.min) + WorldGround._v3(pad.max)) * 0.5
	assert_lt(Vector2(f.position().x - c.x, f.position().z - c.z).length(), 0.5, "on the pad")
	assert_eq(str(f.ship_id), "remnant_interceptor")
	assert_false(t.pilot.berths.any(func(b): return b.visual == f.visual), "not one you can board")


func test_not_wanted_it_stays_down() -> void:
	var t = _town()
	await wait_physics_frames(2)
	WorldState.set_flag("ships_unlocked")
	t._player.global_position = t.pilot.berths[0].visual.global_position + Vector3(5, -1, 0)
	assert_true(t.pilot.board())
	assert_true(t.pilot.takeoff())
	_fly(t, 4.0)
	t.pilot.atmo.place_flying(Vector3(900, 300, 0), Vector3(1, 0, 0), 120.0, 0.6)
	_fly(t, 3.0, { "throttle": 0.6 })
	assert_eq(t.interceptor.mode, AtmoFighter.Mode.PARKED, "a clean flight out of town is left alone")
	t.garrison._raise("test")
	_fly(t, 0.5, { "throttle": 0.6 })
	assert_ne(t.interceptor.mode, AtmoFighter.Mode.PARKED, "wanted and out past the town: it takes off")


func test_a_stolen_ship_scrambles_it_and_it_hunts() -> void:
	var t = _town()
	await wait_physics_frames(2)
	_steal(t)
	assert_true(t.pilot.takeoff())
	_fly(t, 1.0)
	var f: AtmoFighter = t.interceptor
	assert_eq(f.launches, 1, "a stolen ship: it scrambles at once")
	_fly(t, 6.0, { "throttle": 0.4 })
	assert_eq(f.mode, AtmoFighter.Mode.HUNTING, "up and hunting")
	var d0: float = f.position().distance_to(t.pilot.atmo.position())
	var closest := d0
	var attacked := false
	var lowest := INF
	for k in 60:
		_fly(t, 0.5, { "throttle": 0.4, "pitch": 0.15 if k % 8 < 4 else -0.1, "yaw": 0.3 })
		closest = minf(closest, f.position().distance_to(t.pilot.atmo.position()))
		attacked = attacked or f.brain.state_label() == "ATTACK"
		lowest = minf(lowest, f.atmo.agl())
		if f.shots > 0:
			break
	assert_lt(closest, d0, "it closes in")
	assert_true(attacked, "it attacks (the space pilot's ATTACK)")
	assert_gt(f.shots, 0, "and fires its guns")
	assert_gt(lowest, 5.0, "without flying into the ground")
	t.pilot._update_hud(t.pilot.atmo.agl())
	assert_false(t.pilot.hud.target.is_empty(), "boxed on your HUD")
	assert_true(t.pilot.hud.target.has("lead"), "with a lead to aim at")


func test_shot_down_it_comes_back_on_its_pad() -> void:
	var t = _town()
	await wait_physics_frames(2)
	_steal(t)
	t.pilot.takeoff()
	_fly(t, 8.0, { "throttle": 0.4 })
	var f: AtmoFighter = t.interceptor
	assert_true(f.flying())
	var standing0 := int(WorldState.standing.get("imperial_remnant", 0))
	f._on_hit(9999.0, t.pilot.hull)
	assert_eq(f.mode, AtmoFighter.Mode.DOWN)
	assert_eq(f.times_shot_down, 1)
	assert_false(f.visual.visible, "blown up")
	assert_lt(int(WorldState.standing.get("imperial_remnant", 0)), standing0, "the Remnant notice")
	f.respawn_left = 0.4
	_fly(t, 0.5, { "throttle": 0.4 })
	assert_true(f.visual.visible, "a new one on the pad")
	assert_true(f.defense.is_alive())
	assert_lt(Vector2(f.position().x - f.home.x, f.position().z - f.home.z).length(), 1.0)
	_fly(t, 1.0, { "throttle": 0.4 })
	assert_eq(f.launches, 2, "and it comes after you again while you fly the stolen ship")


func test_its_own_side_cannot_hurt_it() -> void:
	var t = _town()
	await wait_physics_frames(2)
	_steal(t)
	t.pilot.takeoff()
	_fly(t, 8.0, { "throttle": 0.4 })
	var f: AtmoFighter = t.interceptor
	var hp: int = f.defense.hull_hp()
	var trooper = t.npc("trooper_yard_a")
	f._on_hit(50.0, trooper)
	f._on_hit(50.0, f.hull)
	assert_eq(f.defense.hull_hp(), hp)


func test_it_shoots_you_down_and_you_both_start_again_in_town() -> void:
	var t = _town()
	await wait_physics_frames(2)
	var i := _steal(t)
	t.pilot.takeoff()
	_fly(t, 8.0, { "throttle": 0.4 })
	var f: AtmoFighter = t.interceptor
	assert_true(f.flying())
	t.pilot._on_hull_hit(9999.0, f.hull, i)
	assert_eq(t.pilot.atmo.state, AtmoFlight.State.CRASHED, "shot down")
	_fly(t, 4.0)
	assert_false(t.pilot.piloting, "towed: out of the ship")
	assert_true(bool(t.pilot.berths[i].destroyed), "the stolen ship is gone")
	assert_lt(t._player.global_position.distance_to(t.town.spawn_pos()), 3.0, "you wake in the pit")
	assert_eq(f.mode, AtmoFighter.Mode.PARKED, "it is back on its pad")
	assert_eq(f.kills_of_player, 1)
	assert_ne(t.pilot.berth, i, "your own ship is the one you fly again")
	assert_false(WorldState.ships_destroyed.has("outpost_ship_remnant_outpost_near"), "not for ever: not saved")


func test_it_gives_up_and_flies_home() -> void:
	var t = _town()
	await wait_physics_frames(2)
	_steal(t)
	t.pilot.takeoff()
	_fly(t, 8.0, { "throttle": 0.4 })
	var f: AtmoFighter = t.interceptor
	assert_eq(f.mode, AtmoFighter.Mode.HUNTING)
	t.pilot.atmo.state = AtmoFlight.State.PARKED      # you set down out in the desert
	t.pilot.berths[t.pilot.berth].stolen = false
	t.outposts.garrisons["remnant_outpost_near"].alarm.stand_down()
	t.garrison.alarm.stand_down()
	_fly(t, 12.0)
	assert_eq(f.mode, AtmoFighter.Mode.RETURNING, "nothing to chase: it heads home")
	for k in 120:
		_fly(t, 1.0)
		if f.mode == AtmoFighter.Mode.PARKED:
			break
	assert_eq(f.mode, AtmoFighter.Mode.PARKED, "and lands on its pad")
	assert_lt(Vector2(f.position().x - f.home.x, f.position().z - f.home.z).length(), 1.0)


## The space pilot does not know the ground; the fighter pulls up for it.
func test_it_pulls_up_near_the_ground() -> void:
	var t = _town()
	await wait_physics_frames(2)
	var f: AtmoFighter = t.interceptor
	var at := Vector3(800, 0, 300)
	at.y = t.pilot.ground.terrain.height_at(at.x, at.z) + 15.0
	f.atmo.place_flying(at, Vector3(1, -0.2, 0), 120.0, 0.8)
	var cmd := { "pitch": -1.0, "yaw": 0.0, "roll": 0.0, "throttle": 0.5, "boost": false }
	assert_true(f._keep_clear(cmd), "too low: it takes over")
	assert_gt(float(cmd.pitch), 0.3, "nose up")
	at.y += 400.0
	f.atmo.place_flying(at, Vector3(1, 0, 0), 120.0, 0.8)
	cmd = { "pitch": 0.0, "yaw": 0.0, "roll": 0.0, "throttle": 0.5, "boost": false }
	assert_false(f._keep_clear(cmd), "high enough: the pilot flies")


## After the fleet the garrison leaves, but the pad's interceptor stays: the Remnant
## shoot on sight now, so it comes after any flight out past the town.
func test_after_the_fleet_it_hunts_any_flight_out_of_town() -> void:
	Story.skip_to("free")
	var t = _town()
	await wait_physics_frames(2)
	assert_null(t.garrison, "the town's garrison is gone")
	var f: AtmoFighter = t.interceptor
	assert_not_null(f, "the interceptor is still on the pad")
	t._player.global_position = t.pilot.berths[0].visual.global_position + Vector3(5, -1, 0)
	assert_true(t.pilot.board())
	assert_true(t.pilot.takeoff())
	_fly(t, 4.0)
	assert_eq(f.mode, AtmoFighter.Mode.PARKED, "not while you are over the town")
	t.pilot.atmo.place_flying(Vector3(900, 300, 0), Vector3(1, 0, 0), 120.0, 0.6)
	_fly(t, 0.5, { "throttle": 0.6 })
	assert_eq(f.launches, 1, "out past the town: it takes off")
