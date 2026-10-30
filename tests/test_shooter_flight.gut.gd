extends GutTest
## Issue #181: space battles more like a shooter. Hit markers for the ship's guns
## (ships, people on the ground, the space fight's own hits and kills), a red flash
## round the screen's edge when you are hit (a second at full, then a slow fade),
## the chase view's flight-sim HUD in place of the text read-out, and the cockpit
## view's dash of working instruments with a lamp for the Shift ability.
##
## The HUD pieces are tested on their own; the town tests check ShipPilot wires
## them up (greybox town, stepped by hand).

const TownDemo := preload("res://scenes/town_demo.gd")
const BoltScene := preload("res://scenes/entities/bolt.tscn")

var hud: FlightHud


func before_each() -> void:
	WorldState.reset()
	WorldState.set_flag("ships_unlocked")
	hud = FlightHud.new()
	add_child_autofree(hud)
	hud.visible = true


func after_each() -> void:
	WorldState.reset()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _town() -> Node:
	var t = TownDemo.new()
	t.use_look = false
	t.npc_brains = false
	add_child_autofree(t)
	return t


func _values() -> Dictionary:
	return {
		"speed": 120.0, "throttle": 0.6, "max_speed": 300.0, "boost": 0.5, "agl": 400.0, "altitude": 1234.0,
		"climb": 12.0, "state": "FLYING", "hull": 80, "hull_max": 100, "shield": 30,
		"shield_max": 60.0, "pitch": 12.0, "roll": -25.0, "heading": 275.0, "ability": "drift", "ability_on": true,
	}


func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		a += poly[i].cross(poly[(i + 1) % poly.size()])
	return absf(a) * 0.5


# ---- the red flash -----------------------------------------------------------------

func test_flash_is_hidden_until_you_are_hit() -> void:
	assert_false(hud.damage_flash.is_showing())
	assert_false(hud.damage_flash.visible)


func test_flash_holds_a_second_then_fades_slowly() -> void:
	var f := hud.damage_flash
	f.flash()
	assert_true(f.visible)
	f.advance(0.5)
	assert_almost_eq(f.alpha(), 1.0, 0.001, "full for the first second")
	f.advance(0.45)
	assert_almost_eq(f.alpha(), 1.0, 0.001, "still full just before a second")
	f.advance(0.25)
	assert_between(f.alpha(), 0.9, 0.999, "the fade starts slowly")
	f.advance(0.6)
	assert_between(f.alpha(), 0.2, 0.8, "halfway through the fade")
	f.advance(1.0)
	assert_false(f.is_showing())
	assert_false(f.visible)


func test_a_new_hit_lights_it_again_from_full() -> void:
	var f := hud.damage_flash
	f.flash()
	f.advance(1.8)
	assert_lt(f.alpha(), 1.0)
	f.flash()
	assert_almost_eq(f.alpha(), 1.0, 0.001)
	assert_eq(f.flashes, 2)


func test_flash_covers_the_screen_and_sits_over_the_views() -> void:
	await wait_process_frames(2)
	assert_almost_eq(hud.damage_flash.size.x, hud.damage_flash.get_viewport_rect().size.x, 0.5)
	assert_gt(hud.damage_flash.get_index(), hud.sim.get_index())
	assert_gt(hud.damage_flash.get_index(), hud.cockpit.get_index())


# ---- hit markers -------------------------------------------------------------------

func test_the_flight_hud_has_its_own_marker() -> void:
	assert_not_null(hud.feedback)
	assert_eq(hud.feedback.marker.get_parent(), hud)
	assert_false(hud.feedback.marker.is_showing())


func test_a_confirmed_hit_and_kill_show_the_marker() -> void:
	hud.confirm_hit(false)
	assert_true(hud.feedback.marker.is_showing())
	assert_false(hud.feedback.marker.is_kill())
	hud.confirm_hit(true)
	assert_true(hud.feedback.marker.is_kill())
	assert_eq(hud.feedback.hit_markers_shown, 1)
	assert_eq(hud.feedback.kill_markers_shown, 1)


func test_a_gun_hit_on_a_wall_shows_nothing() -> void:
	var wall := StaticBody3D.new()
	add_child_autofree(wall)
	hud.on_gun_hit(wall)
	assert_false(hud.feedback.marker.is_showing())


func test_a_ship_hull_counts_only_when_its_owner_took_the_hit() -> void:
	var hull := ShipHull.new()
	add_child_autofree(hull)
	hud.on_gun_hit(hull)
	assert_false(hud.feedback.marker.is_showing(), "shrugged off (parked, or its own side)")
	hull.took_damage()
	hud.on_gun_hit(hull)
	assert_true(hud.feedback.marker.is_showing())
	assert_false(hud.feedback.marker.is_kill())
	hull.took_damage()
	hull.dead = true
	hud.on_gun_hit(hull)
	assert_true(hud.feedback.marker.is_kill(), "shot down")


# ---- the two views -----------------------------------------------------------------

func test_chase_view_is_the_sim_hud_and_cockpit_view_the_dash() -> void:
	assert_true(hud.sim.visible)
	assert_false(hud.cockpit.visible)
	hud.set_cockpit(true)
	assert_true(hud.cockpit_view)
	assert_true(hud.cockpit.visible)
	assert_false(hud.sim.visible)
	hud.set_cockpit(false)
	assert_true(hud.sim.visible)
	assert_false(hud.cockpit.visible)


func test_both_views_get_the_values_and_draw() -> void:
	hud.vessel_name = "Dust Hare"
	hud.show_values(_values())
	assert_eq(hud.sim.values.heading, 275.0)
	assert_eq(hud.cockpit.values.ability, "drift")
	assert_eq(hud.cockpit.vessel_name, "Dust Hare")
	await wait_process_frames(2)
	hud.set_cockpit(true)
	await wait_process_frames(2)
	assert_true(hud.cockpit.visible, "drew a frame of each without falling over")


func test_compass_labels() -> void:
	assert_eq(FlightSimHud.compass_label(0), "N")
	assert_eq(FlightSimHud.compass_label(90), "E")
	assert_eq(FlightSimHud.compass_label(180), "S")
	assert_eq(FlightSimHud.compass_label(270), "W")
	assert_eq(FlightSimHud.compass_label(30), "03")
	assert_eq(FlightSimHud.compass_label(330), "33")
	assert_eq(FlightSimHud.compass_label(-90), "W")


# ---- the attitude the instruments show ---------------------------------------------

func test_level_flight_north_is_all_zero() -> void:
	var a := FlightHud.attitude(Basis.IDENTITY)
	assert_almost_eq(float(a.pitch), 0.0, 0.01)
	assert_almost_eq(float(a.roll), 0.0, 0.01)
	assert_almost_eq(float(a.heading), 0.0, 0.01)


func test_heading_turns_clockwise_from_north() -> void:
	assert_almost_eq(float(FlightHud.attitude(Basis(Vector3.UP, -PI * 0.5)).heading), 90.0, 0.01, "east is +X")
	assert_almost_eq(float(FlightHud.attitude(Basis(Vector3.UP, PI)).heading), 180.0, 0.01)
	assert_almost_eq(float(FlightHud.attitude(Basis(Vector3.UP, PI * 0.5)).heading), 270.0, 0.01)


func test_pitch_and_roll_signs() -> void:
	var up := FlightHud.attitude(Basis(Vector3.RIGHT, deg_to_rad(20.0)))
	assert_almost_eq(float(up.pitch), 20.0, 0.01, "nose up is +")
	assert_almost_eq(float(up.roll), 0.0, 0.01)
	var right := FlightHud.attitude(Basis(Vector3.BACK, deg_to_rad(-30.0)))
	assert_almost_eq(float(right.roll), 30.0, 0.01, "right wing down is +")
	assert_almost_eq(float(right.pitch), 0.0, 0.01)
	var inverted := FlightHud.attitude(Basis(Vector3.BACK, PI))
	assert_almost_eq(absf(float(inverted.roll)), 180.0, 0.01)


func test_straight_up_still_has_a_heading() -> void:
	# Pitched up 90 from heading east: the belly faces west.
	var b := Basis(Vector3.UP, -PI * 0.5) * Basis(Vector3.RIGHT, PI * 0.5)
	var a := FlightHud.attitude(b)
	assert_almost_eq(float(a.pitch), 90.0, 0.01)
	assert_almost_eq(float(a.heading), 90.0, 0.5)


# ---- the attitude ball's horizon ---------------------------------------------------

func test_clip_keeps_the_half_past_the_line() -> void:
	var sq := PackedVector2Array([Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)])
	var bottom := CockpitView.clip_half_plane(sq, Vector2(0, 1), 0.0)
	assert_almost_eq(_area(bottom), 2.0, 0.001, "half the square")
	for p in bottom:
		assert_true(p.y >= -0.0001)
	assert_almost_eq(_area(CockpitView.clip_half_plane(sq, Vector2(0, 1), 0.5)), 1.0, 0.001)
	assert_eq(CockpitView.clip_half_plane(sq, Vector2(0, 1), 2.0).size(), 0, "all sky")
	assert_almost_eq(_area(CockpitView.clip_half_plane(sq, Vector2(0, 1), -2.0)), 4.0, 0.001, "all ground")


func test_horizon_drops_as_the_nose_comes_up_and_turns_against_the_roll() -> void:
	var r := 100.0
	var circle := CockpitView.circle_points(r, 64)
	var full := _area(circle)
	var level := CockpitView.horizon(r, 0.0, 0.0)
	assert_almost_eq(_area(CockpitView.clip_half_plane(circle, level.normal, level.offset)), full * 0.5, full * 0.01,
		"level: half ground")
	var climb := CockpitView.horizon(r, 20.0, 0.0)
	assert_gt(float(climb.offset), 0.0, "nose up: the horizon is lower on the ball")
	assert_lt(_area(CockpitView.clip_half_plane(circle, climb.normal, climb.offset)), full * 0.5, "less ground")
	var bank := CockpitView.horizon(r, 0.0, 30.0)
	var n: Vector2 = bank.normal
	assert_gt(n.x, 0.0, "rolled right: the world turns the other way, the ground swings to the right")


func test_dash_rises_toward_the_middle() -> void:
	var vp := Vector2(1920, 1080)
	assert_lt(CockpitView.dash_top(vp, 960.0), CockpitView.dash_top(vp, 0.0))
	assert_almost_eq(CockpitView.dash_top(vp, 0.0), CockpitView.dash_top(vp, 1920.0), 0.01)


# ---- ShipPilot wires it up ---------------------------------------------------------

func _seated(t) -> ShipPilot:
	var pilot: ShipPilot = t.pilot
	t._player.global_position = t.town.spawn_pos()
	assert_true(pilot.board(), "boards from the spawn")
	pilot.set_physics_process(false)
	return pilot


func test_being_shot_in_the_ship_flashes_red() -> void:
	var t = _town()
	await wait_physics_frames(2)
	var pilot := _seated(t)
	assert_false(pilot.hud.damage_flash.is_showing())
	pilot._on_hull_hit(5.0, null, pilot.berth)
	assert_true(pilot.hud.damage_flash.is_showing())


func test_space_fight_hits_flash_you_and_mark_them() -> void:
	var t = _town()
	await wait_physics_frames(2)
	var pilot := _seated(t)
	pilot.fight = SpaceFight.new()
	t.add_child(pilot.fight)
	pilot.fight.df = load("res://src/systems/flight/dogfight.gd").new()
	pilot.fight.df.player_id = 1
	pilot._fight_hit({ "type": "hit", "id": 7, "by": 1 })
	assert_true(pilot.hud.feedback.marker.is_showing(), "you hit them")
	assert_false(pilot.hud.damage_flash.is_showing())
	pilot._fight_hit({ "type": "hit", "id": 1, "by": 7 })
	assert_true(pilot.hud.damage_flash.is_showing(), "they hit you")
	pilot.fight.queue_free()
	pilot.fight = null


func test_the_guns_bolts_report_to_the_marker() -> void:
	var t = _town()
	await wait_physics_frames(2)
	var pilot := _seated(t)
	var before := get_tree().get_nodes_in_group("bolts").size()
	for i in 10:
		pilot._fire_guns(0.1, true)
	var bolts := get_tree().get_nodes_in_group("bolts")
	assert_gt(bolts.size(), before, "the guns fired")
	var b: Node = bolts[bolts.size() - 1]
	assert_true(b.is_connected("on_hit", pilot.hud.on_gun_hit))
	assert_true(b.is_connected("on_splash", pilot.hud.on_gun_hit))


func test_v_switches_the_hud_to_the_cockpit_and_it_gets_the_attitude() -> void:
	var t = _town()
	await wait_physics_frames(2)
	var pilot := _seated(t)
	pilot._physics_process(1.0 / 60.0)
	assert_false(pilot.hud.cockpit_view)
	assert_true(pilot.hud.values.has("pitch"))
	assert_true(pilot.hud.values.has("ability"))
	assert_eq(str(pilot.hud.values.ability), pilot.atmo.flight.ability())
	pilot.chase.toggle_mode()
	pilot._physics_process(1.0 / 60.0)
	assert_true(pilot.hud.cockpit_view)
	assert_true(pilot.hud.cockpit.visible)
	assert_false(pilot.hud.sim.visible)


func test_a_burst_reports_what_it_splashed() -> void:
	var t = _town()
	await wait_physics_frames(2)
	var g = t.npc("trooper_yard_a")
	assert_not_null(g)
	var hull := ShipHull.new()
	t.add_child(hull)
	var hit: Array = []
	var b = BoltScene.instantiate()
	b.shooter = hull
	b.damage = 9.0
	b.splash_radius = 3.5
	b.splash_damage = 5.0
	b.on_splash.connect(func(c): hit.append(c))
	t.add_child(b)
	b.global_position = g.global_position + Vector3(1.5, 0.2, 0)
	b.apply_to(null)
	await wait_physics_frames(1)
	assert_has(hit, g, "the trooper was caught in it")
