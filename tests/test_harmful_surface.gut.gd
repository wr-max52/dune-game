extends GutTest
## Issue #298: no air on the asteroid's rock. Outside the shelter without armour
## you take steady damage with a message; under cover, in a ship or armoured you
## don't. Which planets: the type's harmful_surface block (the asteroid), passed
## through by PlanetGen.


class FakePlayer:
	extends CharacterBody3D
	var is_downed := false
	var piloting := false
	var took := 0.0
	func apply_damage(a: float) -> void:
		took += a


class FakeShelter:
	extends Node
	var inside := false
	func sheltered(_p: Vector3) -> bool:
		return inside


class FakeDemo:
	extends Node
	var _player
	var platform
	var town := {}
	var gear = null


var demo: FakeDemo
var hz: HarmfulSurface


func before_each() -> void:
	WorldState.reset()
	demo = FakeDemo.new()
	demo._player = FakePlayer.new()
	demo.platform = FakeShelter.new()
	add_child_autofree(demo)
	demo.add_child(demo._player)
	demo.add_child(demo.platform)
	hz = HarmfulSurface.new().setup(demo, { "damage_per_s": 5.0 })
	demo.add_child(hz)


func _run(seconds: float) -> void:
	for i in int(seconds * 60.0):
		hz._physics_process(1.0 / 60.0)


func test_which_planets() -> void:
	assert_false(HarmfulSurface.config(PlanetGen.build("grit_station")).is_empty(), "the asteroid: no air")
	assert_true(HarmfulSurface.config(PlanetGen.build("port_desert")).is_empty(), "the home planet: fine")


func test_outside_without_armour_hurts_in_a_straight_line() -> void:
	_run(4.0)
	assert_true(hz.exposed)
	assert_almost_eq(demo._player.took, 20.0, 1.0, "5 a second")


func test_sheltered_or_flying_is_fine() -> void:
	demo.platform.inside = true
	_run(3.0)
	assert_eq(demo._player.took, 0.0)
	demo.platform.inside = false
	demo._player.piloting = true
	_run(3.0)
	assert_eq(demo._player.took, 0.0)


func test_armour_keeps_you_breathing() -> void:
	WorldState.inventory.attached["armour"] = "quantonium_armour"
	_run(3.0)
	assert_false(hz.exposed)
	assert_eq(demo._player.took, 0.0)
