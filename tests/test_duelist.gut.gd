extends GutTest
## M3: the duelist enemy. A duelist that presses the player, blocks, and parries
## (timed deflection) using the same EnergyBlade the player uses. Proven headless.

var BrainScript


func before_each() -> void:
	BrainScript = load("res://src/systems/ai/duelist_brain.gd")


func _brain() -> RefCounted:
	var cfg := {
		"max_stamina": 100.0,
		"block_cost_stamina": 8.0,
		"deflect_window": 0.18,
		"deflect_refund_stamina": 6.0,
		"light_damage": 16,
		"heavy_damage": 30,
	}
	return BrainScript.new(cfg)


func test_duelist_presses_when_close() -> void:
	var b = _brain()
	b.enemy_pos = Vector3(0.0, 0.0, 0.0)
	b.player_pos = Vector3(1.0, 0.0, 0.0)  # within ~1.9m reach
	var stance: int = b.update(0.01)
	assert_eq(stance, int(b.Stance.PRESS), "a duelist presses when the player is close")


func test_duelist_parries_a_timed_strike() -> void:
	var b = _brain()
	b.enemy_pos = Vector3(0.0, 0.0, 0.0)
	b.player_pos = Vector3(1.0, 0.0, 0.0)
	b.player_is_attacking = true
	# A fresh duel with parry off cooldown should open a parry window.
	var stance: int = b.update(0.01)
	assert_eq(stance, int(b.Stance.PARRY), "a duelist parries a timed in-range strike")
	assert_true(b.is_parrying(), "parry is active for a moment after it triggers")


func test_duelist_cannot_parry_every_frame() -> void:
	var b = _brain()
	b.enemy_pos = Vector3(0.0, 0.0, 0.0)
	b.player_pos = Vector3(1.0, 0.0, 0.0)
	b.player_is_attacking = true
	b._parry_cd = 1.0  # just parried, on cooldown
	var stance: int = b.update(0.01)
	assert_ne(stance, int(b.Stance.PARRY), "no parry while the parry cooldown is active")


func test_duelist_blocks_when_far_and_player_not_attacking() -> void:
	var b = _brain()
	b.enemy_pos = Vector3(0.0, 0.0, 0.0)
	b.player_pos = Vector3(8.0, 0.0, 0.0)  # far, out of reach
	var stance: int = b.update(0.01)
	# Far away and not being attacked -> defensive posture (not a blind press).
	assert_eq(stance, int(b.Stance.DEFEND), "out of reach, the duelist defends")
