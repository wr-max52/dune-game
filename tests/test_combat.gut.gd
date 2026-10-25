extends GutTest
## M2: the combat layer. A bolt deals damage, health drops and dies, and a trooper
## under fire can be killed. This is the "two blasters work / a trooper fights
## back" proof, headless. The visible bolt itself is rendered in the GUI; here we
## prove its behavior.

var HealthScript
var BoltScript


func before_each() -> void:
	HealthScript = load("res://src/systems/combat/health.gd")
	BoltScript = load("res://scenes/entities/bolt.gd")


func test_damage_reduces_health() -> void:
	var h = HealthScript.new(100)
	h.apply_damage(30)
	assert_eq(h.hp, 70, "30 damage drops health to 70")


func test_lethal_damage_kills() -> void:
	var h = HealthScript.new(50)
	h.apply_damage(60)
	assert_eq(h.hp, 0, "health clamps to zero on lethal damage")
	assert_false(h.is_alive(), "the target is dead at zero health")


func test_death_does_not_apply_after_lethality() -> void:
	var h = HealthScript.new(50)
	h.apply_damage(50)
	assert_false(h.is_alive(), "dead at exactly zero")
	h.apply_damage(10)  # further damage is ignored
	assert_eq(h.hp, 0, "dead target does not drop below zero")


func test_damage_cannot_over_heal_below_zero() -> void:
	var h = HealthScript.new(10)
	h.apply_damage(100)
	assert_eq(h.hp, 0, "health clamps at zero")
	assert_false(h.is_alive(), "dead at zero")


func test_bolt_deals_its_damage_on_hit() -> void:
	## Build a bolt and hit its own owner (we put a health on it and point the
	## bolt's hit handler at it via the parent lookup bolt uses).
	var bolt = BoltScript.new()
	bolt.damage = 18
	var h = HealthScript.new(100)
	# _find_health returns the first ancestor that can take damage.
	bolt.hit_target = h
	bolt._on_body_entered.call(bolt)
	assert_eq(h.hp, 82, "an 18-damage bolt drops the target to 82")
	assert_true(bolt._alive == false, "the bolt dies after dealing damage")
	bolt.free()  # free the detached test bolt



func test_bolt_travels_along_its_direction() -> void:
	var bolt = BoltScript.new()
	bolt.direction = Vector3(0.0, 0.0, -1.0)
	bolt.speed = 30.0
	bolt.range_m = 60.0
	bolt.position = Vector3.ZERO
	# A 30u/s bolt moving for 0.1s is a 3-unit step; it no longer touches the tree.
	var step: Vector3 = bolt.integrate(0.1)
	assert_gt(step.length(), 0.0, "a bolt moves each frame")
	assert_almost_eq(step.z, -3.0, 0.001, "a 30u/s bolt takes a 3-unit step in 0.1s")
	bolt.free()
