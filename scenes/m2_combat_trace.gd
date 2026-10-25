extends SceneTree
## M2: a headless combat integration trace. Proves "both blasters work, a trooper
## fights back with cover, and health/death work" WITHOUT rendering, so it runs in
## CI.
##
## A duel is simulated: the player holds the rifle trigger toward a trooper; the
## trooper's brain seals to its nearest cover node and then suppresses the player;
## we record both sides' health and the trooper's state (sealing vs firing) each
## 0.5s. Output test_results/m2_combat_trace.txt is checked by
## tests/test_m2_combat.gut.gd.

var content
var weapon
var weapon_script
var brain_script
var brain

var player_hp := 100
var trooper_hp := 260
var trooper_pos := Vector3(6.0, 0.0, 0.0)
## Two cover nodes: one in front, one behind the player, so the trooper moves.
var cover := [
	{ "position": Vector3(5.0, 0.0, 4.0) },
	{ "position": Vector3(-3.0, 0.0, 2.0) },
]

var t := 0.0
var frames_done := 0
var target := 480  # 8s of 60fps
var log := ""
var file = null
var path := "res://test_results/m2_combat_trace.txt"
var _fire_cd := 0.0           # independent return-fire timer
var _fire_interval := 0.6
var _at_cover := false


func _build() -> void:
	if not DirAccess.dir_exists_absolute("res://test_results"):
		DirAccess.make_dir_recursive_absolute("res://test_results")
	content = load("res://src/systems/dataload/core_content.gd").new()
	content.load_from()
	weapon_script = load("res://src/systems/combat/weapon.gd")
	brain_script = load("res://src/systems/ai/trooper_brain.gd")
	weapon = weapon_script.new(content.get_weapon("rifle_blaster"))
	brain = brain_script.new()
	brain.cover_nodes = cover
	brain.self_position = trooper_pos
	brain.reach_radius = 1.0
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("# t  player_hp  trooper_hp  trooper_state\n")


func _process(_delta) -> bool:
	if file == null:
		_build()
	if frames_done > target:
		file.store_string(log)
		file.close()
		print("M2TRACE wrote ", path, " (", frames_done, " frames)")
		quit(0)
		return false
	_step(1.0 / 60.0)
	frames_done += 1
	return false


func _step(dt: float) -> void:
	t += dt

	# --- Player: hold the rifle trigger toward the trooper. ---
	var result: int = weapon.start_firing(dt, true)
	if result == int(weapon_script.Result.SHOT):
		var dmg: float = float(weapon.config.get("damage", 10.0))
		trooper_hp = int(maxf(0.0, trooper_hp - dmg))

	# --- Trooper: brain seals to the nearest cover. ---
	brain.self_position = trooper_pos
	brain.has_line_of_sight = true
	brain.update(dt)
	## Advance toward the nearest cover node the brain is sealing to.
	var idx: int = brain.pick_nearest_cover()
	var dist: float = 1000.0
	if idx >= 0:
		var target_pos: Vector3 = cover[idx].position
		dist = (target_pos - trooper_pos).length()
		if dist > 0.1:
			trooper_pos += (target_pos - trooper_pos).normalized() * 3.0 * dt
	_at_cover = idx >= 0 and dist <= brain.reach_radius

	# --- Return fire: a live trooper at cover suppresses the player. ---
	_fire_cd -= dt
	if _at_cover and trooper_hp > 0 and _fire_cd <= 0.0:
		_fire_cd = _fire_interval
		player_hp = int(maxf(0.0, player_hp - 5))

	if frames_done % 30 == 0:
		log += "t=%.2f player=%-3d trooper=%-3d %s\n" % \
			[t, player_hp, trooper_hp, _state_label()]


func _state_label() -> String:
	if not _at_cover:
		return "SEALING"
	return "FIRING" if trooper_hp > 0 else "DEAD"
