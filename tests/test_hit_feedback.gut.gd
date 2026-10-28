extends GutTest
## Issue #65, package C: hit markers + thud on any damage dealt, and enemy health
## bars instead of floating names. The marker and the bar are tested on their own
## (no player needed); one test checks PlayerWeapons wires them together.

const TownDemo := preload("res://scenes/town_demo.gd")
const PlayerBody := preload("res://src/systems/player/character_body.gd")
const CoreScript := preload("res://src/systems/dataload/core_content.gd")

var hud: CanvasLayer
var fb: HitFeedback


func before_each() -> void:
	WorldState.reset()
	hud = CanvasLayer.new()
	add_child_autofree(hud)
	fb = HitFeedback.new()
	add_child_autofree(fb)
	fb.setup(hud)


func after_each() -> void:
	WorldState.reset()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _npc(at: Vector3 = Vector3.ZERO) -> NpcBody:
	var cc = CoreScript.new()
	cc.load_from()
	var n := NpcBody.new()
	n.setup(cc.get_soldier("gate_guard"), at, 0.0, null)
	var tgt := Node3D.new()
	add_child_autofree(tgt)
	tgt.global_position = at + Vector3(10, 0, 0)
	n.target = tgt
	add_child_autofree(n)
	return n


# ---- the marker -------------------------------------------------------------------

func test_marker_is_hidden_until_a_hit() -> void:
	assert_false(fb.marker.is_showing())
	assert_false(fb.marker.visible)


func test_marker_shows_white_on_a_hit_and_fades() -> void:
	fb.marker.show_hit(false)
	assert_true(fb.marker.is_showing())
	assert_false(fb.marker.is_kill())
	assert_eq(fb.marker.current_color().r, 1.0)
	assert_eq(fb.marker.current_color().g, 1.0)
	assert_almost_eq(fb.marker.alpha(), 1.0, 0.001)
	fb.marker.advance(0.11)
	assert_between(fb.marker.alpha(), 0.1, 0.9, "fading")
	fb.marker.advance(0.2)
	assert_false(fb.marker.is_showing())
	assert_false(fb.marker.visible)


func test_kill_marker_is_red_and_bigger() -> void:
	fb.marker.show_hit(false)
	var plain := fb.marker.current_scale()
	fb.marker.show_hit(true)
	assert_true(fb.marker.is_kill())
	assert_gt(fb.marker.current_scale(), plain)
	assert_gt(fb.marker.current_color().r, 0.9)
	assert_lt(fb.marker.current_color().g, 0.4)


func test_a_plain_hit_does_not_downgrade_a_live_kill_marker() -> void:
	fb.marker.show_hit(true)
	fb.marker.show_hit(false)
	assert_true(fb.marker.is_kill())
	fb.marker.advance(1.0)
	fb.marker.show_hit(false)
	assert_false(fb.marker.is_kill(), "a new hit after it faded is plain")


func test_marker_is_its_own_child_of_the_hud_not_the_crosshair() -> void:
	assert_eq(fb.marker.get_parent(), hud)


# ---- what counts as damage --------------------------------------------------------

func test_a_wall_is_not_a_hit() -> void:
	var wall := StaticBody3D.new()
	add_child_autofree(wall)
	fb.on_hit(wall, 10.0)
	fb.on_hit(null, 10.0)
	assert_false(fb.marker.is_showing())
	assert_eq(fb.hit_markers_shown, 0)


func test_damaging_an_npc_shows_a_hit() -> void:
	var n := _npc()
	n.apply_damage_from(5.0, null)
	fb.on_hit(n, 5.0)
	assert_eq(fb.hit_markers_shown, 1)
	assert_true(fb.marker.is_showing())
	assert_false(fb.marker.is_kill())


func test_killing_an_npc_shows_the_kill_marker() -> void:
	var n := _npc()
	n.apply_damage_from(9999.0, null)
	assert_true(n.dead)
	fb.on_hit(n, 9999.0)
	assert_eq(fb.kill_markers_shown, 1)
	assert_true(fb.marker.is_kill())


func test_friendly_fire_that_did_nothing_shows_nothing() -> void:
	var n := _npc()
	var friend := _npc(Vector3(5, 0, 0))     # same faction: its bolts are ignored
	n.apply_damage_from(5.0, friend)
	OS.delay_msec(40)                        # the hit was not just now
	fb.on_hit(n, 5.0)
	assert_false(fb.marker.is_showing())
	assert_eq(n.health.hp, n.health.max_hp)


func test_a_body_already_dead_is_not_a_fresh_hit() -> void:
	var n := _npc()
	n.apply_damage_from(9999.0, null)
	OS.delay_msec(40)
	n.apply_damage_from(5.0, null)           # ignored: dead
	fb.on_hit(n, 5.0)
	assert_false(fb.marker.is_showing())


func test_training_target_hit_and_knockdown() -> void:
	var t := TrainingRange.RangeTarget.new()
	t.setup("t1", 20.0, 4.0, LookMaterials.new())
	add_child_autofree(t)
	t.apply_damage(5.0)
	fb.on_hit(t, 5.0)
	assert_eq(fb.hit_markers_shown, 1)
	t.apply_damage(50.0)
	fb.on_hit(t, 50.0)
	assert_eq(fb.kill_markers_shown, 1)


# ---- the thud ---------------------------------------------------------------------

func test_thud_is_rate_limited_in_a_burst() -> void:
	var n := _npc()
	for i in 6:
		n.apply_damage_from(1.0, null)
		fb.on_hit(n, 1.0)
	assert_eq(fb.hit_markers_shown, 6, "every hit shows a marker")
	assert_eq(fb.thuds_played, 1, "but a burst is one thud, not noise")


func test_thud_plays_again_after_the_gap() -> void:
	var n := _npc()
	n.apply_damage_from(1.0, null)
	fb.on_hit(n, 1.0)
	OS.delay_msec(70)
	n.apply_damage_from(1.0, null)
	fb.on_hit(n, 1.0)
	assert_eq(fb.thuds_played, 2)


func test_the_sounds_exist() -> void:
	assert_true(ResourceLoader.exists(HitFeedback.THUD))
	assert_true(ResourceLoader.exists(HitFeedback.KILL))


# ---- the enemy health bar ---------------------------------------------------------

func test_bar_is_hidden_for_a_calm_unhurt_npc() -> void:
	var n := _npc()
	await wait_physics_frames(2)
	assert_false(n.health_bar_shown())
	assert_false(n.nameplate_shown(), "no floating names any more")
	assert_almost_eq(n.health_bar_fill(), 1.0, 0.001)


func test_bar_shows_after_damage_with_the_right_fill() -> void:
	var n := _npc()
	n.apply_damage_from(float(n.health.max_hp) * 0.25, null)
	await wait_physics_frames(2)
	assert_true(n.health_bar_shown())
	assert_almost_eq(n.health_bar_fill(), 0.75, 0.02)
	var fill := n.get_node("HealthBarFill") as MeshInstance3D
	assert_almost_eq((fill.mesh as QuadMesh).size.x, NpcBody.BAR_W * n.health_bar_fill(), 0.02)


func test_bar_shows_when_hostile_even_at_full_health() -> void:
	var n := _npc()
	n.hostile = true
	await wait_physics_frames(2)
	assert_true(n.health_bar_shown())


func test_brain_in_combat_makes_them_hostile() -> void:
	var n := _npc()
	var b := GuardBrain.new(n.profile, 3)
	n.brief(b, Vector3.INF, Vector3.ZERO)
	assert_false(n.hostile)
	b.engage()
	n.brief(b, Vector3.INF, Vector3.ZERO)
	assert_true(n.hostile)


func test_bar_hidden_on_death_and_when_far() -> void:
	var n := _npc()
	n.apply_damage_from(1.0, null)
	await wait_physics_frames(2)
	assert_true(n.health_bar_shown())
	n.target.global_position = n.global_position + Vector3(60, 0, 0)
	await wait_physics_frames(2)
	assert_false(n.health_bar_shown(), "too far")
	n.target.global_position = n.global_position + Vector3(10, 0, 0)
	n.apply_damage_from(9999.0, null)
	await wait_physics_frames(2)
	assert_false(n.health_bar_shown(), "dead")


# ---- wiring -----------------------------------------------------------------------

func test_player_weapons_feed_the_marker() -> void:
	var p := PlayerBody.new()
	add_child_autofree(p)
	var bolts := Node3D.new()
	add_child_autofree(bolts)
	var rig := Node3D.new()
	add_child_autofree(rig)
	var kit := PlayerKit.attach(p, rig, bolts, LookMaterials.new())
	var w: PlayerWeapons = kit.weapons
	assert_not_null(w.feedback)
	assert_eq(w.feedback.marker.get_parent(), w._hud, "its own child of the HUD layer")
	assert_ne(w.feedback.marker.get_parent(), w._cross)
	var n := _npc()
	n.apply_damage_from(3.0, null)
	w.hit_something.emit(n, 3.0)
	assert_eq(w.feedback.hit_markers_shown, 1)
	w._cross.visible = false      # aimed down sights hides the crosshair
	assert_true(w.feedback.marker.is_showing())
