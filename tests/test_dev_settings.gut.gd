extends GutTest
## F11 demo settings: the time-of-day blend, and the panel writing to the world.

const TownDemo := preload("res://scenes/town_demo.gd")


func before_each() -> void:
	WorldState.reset()
	GameFlow.reset()


func after_each() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	NpcBody.show_debug = false


func after_all() -> void:
	WorldState.reset()


func _town() -> Node:
	var scene = TownDemo.new()
	scene.use_look = false
	scene.with_npcs = false
	add_child_autofree(scene)
	return scene


func test_blend_mixes_numbers_and_colors() -> void:
	var a := { "x": 0.0, "c": "#000000", "on": true, "sub": { "y": 10 } }
	var b := { "x": 4.0, "c": "#ffffff", "on": false, "sub": { "y": 20 } }
	var m: Dictionary = LookEnvironment.blend(a, b, 0.25)
	assert_almost_eq(float(m.x), 1.0, 0.001)
	assert_almost_eq(Color.html(m.c).r, 0.25, 0.01)
	assert_true(m.on, "bools hold the first value until halfway")
	assert_almost_eq(float(m.sub.y), 12.5, 0.001)
	assert_false(LookEnvironment.blend(a, b, 0.75).on)


func test_hours_key_real_presets_in_order() -> void:
	var data := LookEnvironment.load_presets()
	var last := -1.0
	for e in data.get("hours", []):
		assert_true(data.presets.has(str(e.preset)), "hour key names a preset: " + str(e.preset))
		assert_gt(float(e.hour), last, "hour keys ascend")
		last = float(e.hour)


func test_apply_hour_blends_and_picks_nearest_preset() -> void:
	var look := LookEnvironment.new()
	add_child_autofree(look)
	var k := look.keys_at_hour(10.0)
	assert_eq(k.a, "golden")
	assert_eq(k.b, "noon")
	look.apply_hour(12.0)
	assert_eq(look.current, "noon")
	look.apply_hour(8.2)
	assert_eq(look.current, "golden")
	var golden_e := float(look.presets.golden.sun.energy)
	var noon_e := float(look.presets.noon.sun.energy)
	look.apply_hour(10.25)
	assert_between(look.sun.light_energy, minf(golden_e, noon_e), maxf(golden_e, noon_e))
	look.apply_hour(2.0)
	assert_eq(look.current, "dusk", "before the first key holds the first preset")
	look.apply("noon")
	assert_eq(look.hour, -1.0, "a plain preset clears the hour")


func test_panel_opens_pauses_and_closes() -> void:
	var town = _town()
	var p: DevSettingsPanel = town.dev_settings
	assert_not_null(p, "the town builds the F11 panel")
	assert_false(p.visible)
	p.toggle()
	assert_true(p.visible)
	assert_true(get_tree().paused, "the game pauses under the panel")
	p.toggle()
	assert_false(p.visible)
	assert_false(get_tree().paused)


func test_teleport_moves_player_to_marker() -> void:
	var town = _town()
	assert_true(town.dev_settings.teleport("cantina_door"))
	assert_almost_eq(town._player.global_position.x, town.town.marker_pos("cantina_door").x, 0.01)
	assert_false(town.dev_settings.teleport("no_such_marker"))


func test_known_flags_cover_content_conditions() -> void:
	var town = _town()
	WorldState.set_flag("my_custom")
	var flags: Array = town.dev_settings.known_flags()
	assert_true(flags.has("my_custom"), "flags already set are listed")
	assert_true(flags.has("remnant_patrol_beaten"), "flags rumors ask about are listed")
