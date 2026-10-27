extends SceneTree
## Review renders for M11/M12: the player's body, weapons in both cameras, the
## range and the cantina owner. Saves PNGs to test_results/m11/.
##
## Needs a real renderer: ./tools/m11/shoot_m11.sh [shots=a,b] [size=1280x720]
## Each shot is a little script: set up the player, wait some frames, save.

const OUT := "res://test_results/m11"

var demo
var kit: PlayerKit
var rig_node
var player
var _shots: Array = []
var _i := -1
var _wait := 0
var _frame := 0
var _only: Array = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shots="):
			_only = a.substr(6).split(",")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	Disclaimers.launch_shown = true     # the launch notice would cover every shot
	demo = load("res://scenes/town_demo.gd").new()
	demo.preset = "golden"
	get_root().add_child(demo)
	_shots = [
		["tpv_idle_front", _front.bind("", 3.2, 0.0)],
		["tpv_walk_side", _walk_side],
		["tpv_pistol_front", _front.bind("pistol_blaster", 3.0, 25.0)],
		["tpv_pistol_back", _back.bind("pistol_blaster")],
		["fpv_pistol", _fpv.bind("pistol_blaster", 0.0)],
		["fpv_rifle", _fpv.bind("rifle_blaster", 0.0)],
		["tpv_rifle_front", _front.bind("rifle_blaster", 3.0, 25.0)],
		["tpv_sword_guard", _front.bind("energy_blade", 3.0, 30.0)],
		["tpv_sword_swing", _swing.bind(0.48)],
		["tpv_sword_block", _block],
		["fpv_sword", _fpv.bind("energy_blade", 0.0)],
		["fpv_sword_swing", _fpv_swing],
		["range", _range_view],
		["walk_1", _walk_follow.bind(true)], ["walk_2", _walk_follow.bind(false)], ["walk_3", _walk_follow.bind(false)],
		["walk_4", _walk_follow.bind(false)], ["walk_5", _walk_follow.bind(false)], ["walk_6", _walk_follow.bind(false)],
		["sprint_1", _sprint_follow.bind(true)], ["sprint_2", _sprint_follow.bind(false)], ["sprint_3", _sprint_follow.bind(false)],
		["bar_wide", _bar_wide],
		["bar_talk", _bar_talk],
		["bar_oda_close", _oda_close],
	]
	if not _only.is_empty():
		_shots = _shots.filter(func(s): return _only.has(s[0]))


func _process(_d: float) -> bool:
	_frame += 1
	if _frame < 20:
		return false
	if kit == null:
		kit = demo.player_kit
		rig_node = demo._rig
		player = demo._player
	if _follow:
		var at: Vector3 = player.global_position + Vector3(0, 1.0, 0)
		rig_node.set_override(Transform3D(Basis(), at + Vector3(0, 0.3, 3.6)).looking_at(at, Vector3.UP))
		rig_node._override_blend = 1.0
	if _wait > 0:
		_wait -= 1
		if _wait == 0:
			var name: String = _shots[_i][0]
			var path := ProjectSettings.globalize_path(OUT + "/" + name + ".png")
			get_root().get_texture().get_image().save_png(path)
			print("SHOT ", name, " -> ", path)
		return false
	_i += 1
	if _i >= _shots.size():
		print("SHOOT M11: done")
		return true
	if not str(_shots[_i][0]).begins_with("walk_") and not str(_shots[_i][0]).begins_with("sprint_") \
			or str(_shots[_i][0]).ends_with("_1"):
		_follow = false
		_reset()
	var wait = _shots[_i][1].call()
	_wait = int(wait) if wait != null else 40
	return false


func _reset() -> void:
	if demo.bar != null and demo.bar.is_talking():
		demo.bar.end_talk()
	player.locked = false
	player.clear_external_command()
	player.set_command(Vector2.ZERO, false, false, false)
	player.velocity = Vector3.ZERO
	rig_node.clear_override()
	rig_node._override_blend = 0.0
	kit.weapons.release_fire()
	kit.weapons.set_alt(false)


func _place(pos: Vector3, yaw: float) -> void:
	player.global_position = pos
	player.controller.body_pos = pos
	rig_node.rig.yaw = yaw
	rig_node.rig.pitch = 0.0
	kit.avatar.facing_yaw = yaw


func _draw(id: String) -> void:
	kit.weapons.holder.current = ""
	kit.weapons.holder.phase = 0
	if id != "":
		kit.weapons.holder.request(id)


## A camera that looks at the player from the front-left, `dist` away.
func _front(id: String, dist: float, side_deg: float) -> int:
	_place(Vector3(6, -6, 9), PI * 0.5)
	rig_node.set_first_person(false)
	_draw(id)
	var yaw := PI * 0.5 + deg_to_rad(side_deg)
	var at: Vector3 = player.global_position + Vector3(0, 1.15, 0)
	var eye := at + Vector3(sin(yaw), 0.1, cos(yaw)) * dist
	_cut(eye, at)
	return 45


func _back(id: String) -> int:
	_place(Vector3(6, -6, 9), -PI * 0.5)
	rig_node.set_first_person(false)
	_draw(id)
	return 45


func _walk_side() -> int:
	_place(Vector3(0, -6, 12), PI * 0.5)
	rig_node.set_first_person(false)
	_draw("")
	player.set_command(Vector2(0, 1), false, false, false)
	var at: Vector3 = Vector3(3.5, -4.85, 12)
	_cut(at + Vector3(0, 0.2, 4.0), at)
	return 26


func _fpv(id: String, pitch: float) -> int:
	_place(Vector3(6, -6, 12), -PI * 0.5)
	rig_node.rig.pitch = pitch
	rig_node.set_first_person(true)
	_draw(id)
	return 40


func _swing(at_frac: float) -> int:
	_front("energy_blade", 3.0, 30.0)
	_after(25, func():
		kit.weapons.press_fire()
		kit.weapons.release_fire())
	return 25 + int(0.5 * at_frac * 60.0) + 1


func _block() -> int:
	_front("energy_blade", 3.0, 30.0)
	_after(25, func(): kit.weapons.set_alt(true))
	return 40


func _fpv_swing() -> int:
	_fpv("energy_blade", 0.0)
	_after(25, func():
		kit.weapons.press_fire()
		kit.weapons.release_fire())
	return 25 + 13


func _range_view() -> int:
	_place(Vector3(4, -6, 14), -PI * 0.6)
	rig_node.set_first_person(false)
	_draw("energy_blade")
	_cut(Vector3(8, -3.2, 6), Vector3(-10, -5, 15))
	return 60


func _bar_wide() -> int:
	_place(Vector3(-70, 0, 3), -PI * 0.5)
	rig_node.set_first_person(false)
	_draw("")
	_cut(Vector3(-66, 2.2, 6), Vector3(-81, 1.0, 0))
	return 50


func _bar_talk() -> int:
	_place(Vector3(-76.5, 0, 0), -PI * 0.5)
	rig_node.set_first_person(false)
	_draw("")
	if demo.bar != null and demo.bar.has_method("start_talk"):
		demo.bar.start_talk()
	return 70


func _oda_close() -> int:
	_place(Vector3(-76.5, 0, 0), -PI * 0.5)
	rig_node.set_first_person(false)
	_draw("")
	var her: Vector3 = demo.cantina_owner.global_position
	_cut(her + Vector3(1.9, 1.55, 0.9), her + Vector3(0, 1.15, 0))
	return 50


func _cut(eye: Vector3, at: Vector3) -> void:
	var xf := Transform3D(Basis(), eye).looking_at(at, Vector3.UP)
	rig_node.set_override(xf)
	rig_node._override_blend = 1.0


var _follow := false
func _walk_follow(first: bool) -> int:
	if first:
		_place(Vector3(-14, -6, 18), PI * 0.5)
		rig_node.set_first_person(false)
		_draw("")
		player.set_command(Vector2(0, 1), false, false, false)
		_follow = true
		return 50
	return 6


func _sprint_follow(first: bool) -> int:
	if first:
		_place(Vector3(-14, -6, 18), PI * 0.5)
		rig_node.set_first_person(false)
		_draw("")
		player.set_command(Vector2(0, 1), true, false, false)
		_follow = true
		return 40
	return 5


var _timers: Array = []
func _after(frames: int, f: Callable) -> void:
	var t := create_timer(frames / 60.0)
	t.timeout.connect(f)
