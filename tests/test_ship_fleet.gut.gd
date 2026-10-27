extends GutTest
## Issue #43: the port's fleet. Every ship parked in the pit is a ship you can fly:
## it has gameplay data with atmosphere flight, a named make and model, a Shift
## ability the flight model knows, and a Hyper3D model that fits its bay. The
## abilities behave as described (boost speeds up, drift slides, brake slows and
## turns faster), and blaster_power scales every bolt.

const CoreScript := preload("res://src/systems/dataload/core_content.gd")
const FlightModel := preload("res://src/systems/flight/flight_model.gd")
const ShipLoadout := preload("res://src/systems/flight/ship_loadout.gd")
const TownDecor := preload("res://src/systems/world/town_decor.gd")
const FLEET := ["interceptor", "freighter", "courier", "gunship"]

var content


func before_all() -> void:
	content = CoreScript.new()
	content.load_from()


func test_every_fleet_ship_is_flyable_and_named() -> void:
	for id in FLEET:
		var cfg: Dictionary = content.get_ship(id)
		assert_false(cfg.is_empty(), "%s is in the manifest" % id)
		assert_true(cfg.has("atmosphere"), "%s flies in the atmosphere" % id)
		assert_true(str(cfg.flight.get("ability", {}).get("kind", "")) in ["boost", "drift", "brake"],
			"%s has a known Shift ability" % id)
		assert_ne(str(cfg.label), "", "%s has a make and model" % id)
		assert_gt(float(cfg.get("blaster_power", 0.0)), 0.0, "%s has blaster power" % id)


func test_the_bays_hold_every_other_fleet_ship() -> void:
	var loc: Dictionary = content.locations.get("port_town", {})
	var parked := []
	for b in loc.get("boxes", []):
		if str(b.get("kind", "")) == "ship" and b.has("ship"):
			parked.append(str(b.ship))
	parked.sort()
	assert_eq(parked, ["freighter", "gunship"], "issue #58: the courier's bay is the empty pad; T-89 sells it")


func test_every_fleet_model_is_a_real_model_that_fits_a_bay() -> void:
	var kit := ShipKit.new()
	for id in FLEET:
		var ship := kit.build(str(content.get_ship(id).look))
		assert_eq(str(ship.get_meta("source", "")), "scene", "%s uses its Hyper3D model" % id)
		var a: AABB = TownDecor.visual_aabb(ship)
		assert_lt(a.size.z, 9.4, "%s is no longer than a bay" % id)
		assert_lt(a.size.x, 8.2, "%s is no wider than a bay" % id)
		ship.free()


func _fly(ability: Dictionary, frames: int, yaw: float = 0.0) -> FlightModel:
	var f := FlightModel.new({ "min_speed": 10.0, "max_speed": 40.0, "boost_speed": 70.0, "accel": 30.0,
		"yaw_rate": 1.0, "boost_time": 10.0, "ability": ability })
	f.speed = 40.0
	f.set_command(0.0, 0.0, 0.0, 1.0, false)
	f.step(0.1)
	f.set_command(0.0, yaw, 0.0, 1.0, true)
	for i in frames:
		f.step(0.05)
	return f


func test_boost_speeds_up() -> void:
	assert_gt(_fly({ "kind": "boost" }, 20).speed, 50.0)


func test_drift_slides_while_the_nose_turns() -> void:
	var f := _fly({ "kind": "drift", "turn_scale": 2.0 }, 10, 1.0)
	assert_gt(f.velocity().normalized().angle_to(f.forward()), 0.2, "moving off the nose")
	assert_almost_eq(f.speed, 40.0, 1.0, "drift holds speed")


func test_brake_slows_and_turns_faster() -> void:
	var plain := _fly({ "kind": "boost", }, 10, 1.0)
	var brake := _fly({ "kind": "brake", "turn_scale": 2.4 }, 10, 1.0)
	assert_lt(brake.speed, 20.0, "bled speed")
	assert_gt(brake.forward().angle_to(Vector3.FORWARD), plain.forward().angle_to(Vector3.FORWARD), "turned further")


func test_blaster_power_scales_damage() -> void:
	var weak := ShipLoadout.new({ "hardpoints": [{ "weapon": "ship_cannon", "mount": [0, 0, 0] }] }, content)
	var strong := ShipLoadout.new({ "blaster_power": 2.0, "hardpoints": [{ "weapon": "ship_cannon", "mount": [0, 0, 0] }] }, content)
	var a: Array = weak.fire(0.1, Transform3D.IDENTITY, Vector3.ZERO, true, false)
	var b: Array = strong.fire(0.1, Transform3D.IDENTITY, Vector3.ZERO, true, false)
	assert_almost_eq(float(b[0].damage), float(a[0].damage) * 2.0, 0.001)
