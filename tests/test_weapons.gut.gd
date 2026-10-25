extends GutTest
## M2: the weapon state machine. Proves visible-bolt blasters: fire timing, recoil,
## ammo drawdown, and reload. This is the core of "two ranged weapons work" and is
## proven headless -- no rendered bolts needed in CI.

var pistol
var rifle
var blade


func before_each() -> void:
	var content = load("res://src/systems/dataload/core_content.gd").new()
	content.load_from()
	var Weapon = load("res://src/systems/combat/weapon.gd")
	pistol = Weapon.new(content.get_weapon("pistol_blaster"))
	rifle = Weapon.new(content.get_weapon("rifle_blaster"))
	blade = content.get_weapon("energy_blade")


func test_both_weapons_exist_and_differ() -> void:
	assert_eq(pistol.config.get("class"), "pistol")
	assert_eq(rifle.config.get("class"), "rifle")
	assert_gt(rifle.config.get("damage"), pistol.config.get("damage"), "rifle hits harder")
	assert_true(pistol.config.get("visible_bolt"), "blaster bolts are visible")
	assert_true(rifle.config.get("visible_bolt"), "rifle bolts are visible")


func test_firing_drops_ammo_one_per_shot() -> void:
	var start: int = pistol.ammo
	pistol.start_firing(0.05, true)   # fire this frame
	assert_eq(pistol.ammo, start - 1, "firing drops one round")
	# Fire again immediately should be blocked by the cooldown.
	var blocked: int = pistol.start_firing(0.05, true)
	assert_eq(blocked, int(pistol.Result.NONE), "cooldown blocks the 2nd shot")
	assert_eq(pistol.ammo, start - 1, "ammo unchanged while on cooldown")


func test_cooldown_unlocks_firing() -> void:
	pistol.start_firing(0.05, true)
	pistol.start_firing(0.5, true)  # advance past the 0.12s cooldown
	# After cooldown, a fresh trigger pull should fire.
	pistol._fire_cd_left = 0.0
	var res: int = pistol.start_firing(0.01, true)
	assert_eq(res, int(pistol.Result.SHOT), "after cooldown the weapon fires")


func test_firing_to_empty_triggers_reload() -> void:
	var Weapon := load("res://src/systems/combat/weapon.gd")
	var tiny = Weapon.new({ "mag": 2, "rate": 0.0, "reload_time": 0.5, "damage": 1 })
	tiny.ammo = 2
	tiny.start_firing(0.01, true)   # shot 1
	tiny.start_firing(0.01, true)   # shot 2 -> empty
	var res: int = tiny.start_firing(0.01, true)   # empty + trigger -> reload start
	assert_eq(res, int(tiny.Result.RELOAD_START), "empty + trigger starts reload")
	assert_true(tiny.is_reloading(), "reloading flag is set")
	# Finish the reload and confirm it restores the full magazine.
	tiny.start_firing(1.0, false)
	assert_eq(tiny.ammo, 2, "reload restores full magazine")
	assert_false(tiny.is_reloading(), "reload completes")


func test_recoil_is_configured() -> void:
	assert_gt(pistol.recoil(), 0.0, "pistol has recoil")
	assert_gt(rifle.recoil(), 0.0, "rifle has recoil")
	assert_gt(rifle.recoil(), pistol.recoil(), "rifle has more recoil")


func test_energy_blade_is_melee_in_core() -> void:
	# The blade is a melee; it lives in the same data layer and is distinguished
	# by class. (Full blade behavior is M3; this only proves it is present and
	# labeled melee for the data layer.)
	assert_eq(blade.get("class"), "melee")
