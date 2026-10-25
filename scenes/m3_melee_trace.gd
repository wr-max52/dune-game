extends SceneTree
## M3: a headless melee-duel trace. Proves, without rendering, that the energy
## blade's timed-deflection works and that a duelist enemy parries it -- while
## still being killable.
##
## One persistent duelist brain is driven like a real fight: the player swings at
## a fixed cadence; the brain parries a swing when it is off its parry cooldown,
## otherwise the blow lands. A parry cadence longer than the swing cadence means
## most swings are parried and the occasional one lands, so the duelist takes
## damage and eventually goes DOWN. This is a real back-and-forth, not a fixed
## script.
##
## Output test_results/m3_melee_trace.txt is checked by tests/test_m3_melee.gut.gd.

var BrainScript

var duelist_hp := 100
var t := 0.0
var frames_done := 0
var target := 360  # 6s at 60fps
var log := ""
var file = null
var path := "res://test_results/m3_melee_trace.txt"

var swings := 0
var parries := 0
var blows := 0
var _swing_cd := 0.2
var brain


func _build() -> void:
	if not DirAccess.dir_exists_absolute("res://test_results"):
		DirAccess.make_dir_recursive_absolute("res://test_results")
	BrainScript = load("res://src/systems/ai/duelist_brain.gd")
	var cfg := {
		"max_stamina": 100.0,
		"block_cost_stamina": 8.0,
		"deflect_window": 0.18,
		"deflect_refund_stamina": 6.0,
		"light_damage": 16,
		"heavy_damage": 30,
	}
	brain = BrainScript.new(cfg)
	brain.enemy_pos = Vector3(0.0, 0.0, 0.0)
	brain.player_pos = Vector3(1.0, 0.0, 0.0)
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("# t  duelist_hp  event\n")


func _process(_delta) -> bool:
	if file == null:
		_build()
	if frames_done > target:
		file.store_string(log)
		file.close()
		print("M3TRACE wrote ", path, " (", frames_done, " frames) ",
			"swings=", swings, " parries=", parries, " blows=", blows)
		quit(0)
		return false
	_step(1.0 / 60.0)
	frames_done += 1
	return false


func _step(dt: float) -> void:
	t += dt
	if duelist_hp <= 0:
		return

	# Idle between swings; the brain keeps its timers ticking.
	brain.player_is_attacking = false
	var base: int = brain.update(dt)

	# Swing at a fixed cadence.
	_swing_cd -= dt
	if _swing_cd <= 0.0:
		_swing_cd = 0.5
		# The player commits a fresh swing this frame.
		brain.player_is_attacking = true
		var stance: int = brain.update(dt)
		swings += 1
		if stance == int(BrainScript.Stance.PARRY):
			parries += 1
			_log(t, "PARRY")
		else:
			blows += 1
			duelist_hp = maxi(0, duelist_hp - 16)
			if duelist_hp <= 0:
				_log(t, "DOWN")
			else:
				_log(t, "HIT")

	if frames_done % 30 == 0 and duelist_hp > 0:
		_log(t, "fighting")


func _log(time: float, event: String) -> void:
	log += "t=%.2f duelist=%-3d %s\n" % [time, duelist_hp, event]
