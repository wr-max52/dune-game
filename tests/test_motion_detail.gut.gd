extends GutTest
## Flight-only detail override: enter/exit holds avoid flicker; non-flight states
## restore decorative props immediately. Pure state coverage, no renderer needed.

const AltitudeDetail := preload("res://src/systems/world/altitude_detail.gd")

var detail: AltitudeDetail
var small_prop: Node3D


func before_each() -> void:
	detail = AltitudeDetail.new()
	add_child(detail)
	small_prop = Node3D.new()
	add_child(small_prop)
	detail.setup({
		"hysteresis": 40.0,
		"tiers": [
			{ "above": 60.0, "off": [], "hide": [] },
			{ "above": 500.0, "off": [], "hide": [] },
			{ "above": 1500.0, "off": [], "hide": [] }
		],
		"motion": {
			"above": 550.0, "altitude_hysteresis": 60.0,
			"enter_speed": 80.0, "exit_speed": 35.0,
			"enter_turn_deg_s": 90.0, "exit_turn_deg_s": 30.0,
			"enter_s": 0.1, "restore_s": 0.75
		}
	})
	detail.add_group("small_props", [small_prop])


func after_each() -> void:
	if is_instance_valid(detail):
		detail.queue_free()
	if is_instance_valid(small_prop):
		small_prop.queue_free()


func test_fast_flight_enters_and_restores_after_separate_holds() -> void:
	detail.update_motion(0.09, 600.0, 100.0, 0.0, true)
	assert_false(detail.motion_active, "fast flight must hold for 0.1 seconds before lowering detail")
	assert_true(small_prop.visible)
	detail.update_motion(0.02, 600.0, 100.0, 0.0, true)
	assert_true(detail.motion_active)
	assert_false(small_prop.visible)
	detail.update_motion(0.74, 600.0, 0.0, 0.0, true)
	assert_true(detail.motion_active, "restoration must hold for 0.75 seconds")
	detail.update_motion(0.02, 600.0, 0.0, 0.0, true)
	assert_false(detail.motion_active)
	assert_true(small_prop.visible)


func test_turning_and_altitude_hysteresis_keep_override_stable() -> void:
	detail.update_motion(0.11, 550.0, 0.0, 100.0, true)
	assert_true(detail.motion_active, "turn rate can trigger the flight override")
	detail.update_motion(0.2, 520.0, 50.0, 50.0, true)
	assert_true(detail.motion_active, "altitude hysteresis prevents a boundary pop")
	detail.update_motion(0.75, 489.0, 100.0, 0.0, true)
	assert_false(detail.motion_active, "below the altitude exit boundary the override restores")
	assert_true(small_prop.visible)


func test_non_flight_motion_never_hides_props_and_clears_override() -> void:
	detail.update_motion(0.11, 600.0, 120.0, 0.0, true)
	assert_true(detail.motion_active)
	detail.update_motion(0.0, 600.0, 200.0, 180.0, false)
	assert_false(detail.motion_active, "walking, landed, crashed, or unpiloted states restore immediately")
	assert_true(small_prop.visible, "on-foot views keep decorative props visible")
