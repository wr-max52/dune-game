extends SceneTree
## Issue #229: the first person review shots. Every hand weapon at the hip and
## aimed, the sword through a swing and a block, sprinting (first and third person),
## reloading, drawing and holstering, plus a gun against a wall.
##
## Needs a real renderer: ./tools/fpv/shoot_fpv.sh [shots=a,b] [out=dir]
## The HUD is hidden and every weapon is allowed (a story save has the pistol only),
## so the frame shows only the hands and what they hold. Saves PNGs, and a 2x crop
## of the lower right (where the hands are) as <name>_zoom.png.

const OUT := "res://test_results/fpv"

var demo
var kit: PlayerKit
var rig_node
var player
var _out := OUT
var _shots: Array = []
var _i := -1
var _wait := 0
var _frame := 0
var _only: Array = []
var _follow := Vector3.ZERO     ## third person: camera offset from the player (zero = off)
var _detail: Array = []         ## [weapon id, eye, target] in the weapon's space: a close-up


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shots="):
			_only = a.substr(6).split(",")
		elif a.begins_with("out="):
			_out = a.substr(4)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	Disclaimers.launch_shown = true
	for id in ["pistol_blaster", "energy_blade", "rifle_blaster"]:
		WorldState.set_flag("weapon_" + id)
	demo = load("res://scenes/town_demo.gd").new()
	demo.preset = "golden"
	demo.with_salesman = false
	get_root().add_child(demo)
	_shots = [
		["fpv_unarmed", _fpv.bind("", 0.0)],
		["fpv_unarmed_down", _fpv.bind("", -0.9)],
		["fpv_unarmed_walk", _fpv_move.bind("", false, 30)],
		["fpv_pistol", _fpv.bind("pistol_blaster", 0.0)],
		["fpv_pistol_ads", _fpv_ads.bind("pistol_blaster")],
		["fpv_pistol_fire", _fpv_fire.bind("pistol_blaster")],
		["fpv_rifle", _fpv.bind("rifle_blaster", 0.0)],
		["fpv_rifle_down", _fpv.bind("rifle_blaster", -0.6)],
		["fpv_rifle_ads", _fpv_ads.bind("rifle_blaster")],
		["fpv_rifle_into_sun", _fpv.bind("rifle_blaster", 0.0, true)],
		["fpv_rifle_sprint", _fpv_move.bind("rifle_blaster", true, 40)],
		["fpv_rifle_wall", _fpv_wall.bind("rifle_blaster")],
		["fpv_rifle_reload", _fpv_reload.bind("rifle_blaster")],
		["fpv_pistol_reload", _fpv_reload.bind("pistol_blaster")],
		["fpv_rifle_draw", _fpv_swap.bind("", "rifle_blaster", 0.5)],
		["fpv_rifle_holster", _fpv_swap.bind("rifle_blaster", "", 0.5)],
		["fpv_sword", _fpv.bind("energy_blade", 0.0)],
		["fpv_sword_ignite", _fpv_swap.bind("", "energy_blade", 0.6)],
		["fpv_sword_swing_a", _fpv_swing.bind(5)],
		["fpv_sword_swing_b", _fpv_swing.bind(10)],
		["fpv_sword_swing_c", _fpv_swing.bind(18)],
		["fpv_sword_block", _fpv_block],
		["detail_scope", _close.bind("rifle_blaster", Vector3(-0.2, 0.26, 0.05), Vector3(0, 0.17, 0.02))],
		["detail_scope_rear", _close.bind("rifle_blaster", Vector3(-0.12, 0.24, -0.3), Vector3(0, 0.17, -0.02))],
		["detail_rifle_hands", _close.bind("rifle_blaster", Vector3(-0.35, 0.12, 0.25), Vector3(0, 0.0, 0.05))],
		["detail_pistol_hand", _close.bind("pistol_blaster", Vector3(-0.22, 0.1, 0.18), Vector3(0, 0.0, -0.04))],
		["detail_sword_hands", _close.bind("energy_blade", Vector3(-0.3, 0.05, 0.25), Vector3(0, 0.05, 0.0))],
		["tpv_rifle_rest_side", _tpv.bind("rifle_blaster", false, Vector3(-2.6, 0.3, 0.3))],
		["tpv_rifle_sprint_side", _tpv.bind("rifle_blaster", true, Vector3(-2.6, 0.3, 0.3))],
		["tpv_rifle_sprint_front", _tpv.bind("rifle_blaster", true, Vector3(-0.8, 0.3, 2.4))],
		["tpv_rifle_sprint_back", _tpv.bind("rifle_blaster", true, Vector3(-0.6, 0.6, -3.2))],
	]
	# A strip through one swipe (strip_<frames>), and a chained second and third
	# (the combo: double click), for judging the whole arc.
	for f in range(2, 27, 2):
		_shots.append(["strip_left_%02d" % f, _fpv_swing.bind(f)])
	for f in range(2, 27, 2):
		_shots.append(["strip_right_%02d" % f, _fpv_swing_right.bind(f)])
	for f in range(2, 37, 3):
		_shots.append(["strip_combo_%02d" % f, _fpv_combo.bind(f)])
	if not _only.is_empty():
		_shots = _shots.filter(func(s): return _only.has(s[0]) or _only.any(func(o): return o.ends_with("*") and str(s[0]).begins_with(o.trim_suffix("*"))))


func _process(_d: float) -> bool:
	_frame += 1
	if _frame < 20:
		return false
	if kit == null:
		kit = demo.player_kit
		rig_node = demo._rig
		player = demo._player
	_hide_ui(get_root())
	if not _detail.is_empty():
		var w: Node3D = kit.avatar.weapon_node(_detail[0])
		var eye: Vector3 = w.global_transform * (_detail[1] as Vector3)
		rig_node.set_override(Transform3D(Basis(), eye).looking_at(w.global_transform * (_detail[2] as Vector3), Vector3.UP))
		rig_node._override_blend = 1.0
	if _follow != Vector3.ZERO:
		var at: Vector3 = player.global_position + Vector3(0, 1.0, 0)
		var b := Basis(Vector3.UP, kit.avatar.facing_yaw)
		rig_node.set_override(Transform3D(Basis(), at + b * _follow).looking_at(at, Vector3.UP))
		rig_node._override_blend = 1.0
	if _wait > 0:
		_wait -= 1
		if _wait == 0:
			var name: String = _shots[_i][0]
			var path := ProjectSettings.globalize_path(_out + "/" + name + ".png")
			var img := get_root().get_texture().get_image()
			img.save_png(path)
			if name.begins_with("fpv_"):
				_zoom(img, path.trim_suffix(".png") + "_zoom.png")
			print("SHOT ", name, " -> ", path)
		return false
	_i += 1
	if _i >= _shots.size():
		print("SHOOT FPV: done")
		return true
	_reset()
	var wait = _shots[_i][1].call()
	_wait = int(wait) if wait != null else 40
	return false


func _hide_ui(n: Node) -> void:
	for c in n.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false
		else:
			_hide_ui(c)


## The lower right of the frame at 2x, so the gloves and grips can be judged.
func _zoom(img: Image, path: String) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var crop := img.get_region(Rect2i(int(w * 0.45), int(h * 0.4), int(w * 0.55), int(h * 0.6)))
	crop.resize(crop.get_width() * 2, crop.get_height() * 2, Image.INTERPOLATE_LANCZOS)
	crop.save_png(path)


func _reset() -> void:
	_follow = Vector3.ZERO
	_detail = []
	player.locked = false
	player.clear_external_command()
	player.set_command(Vector2.ZERO, false, false, false)
	player.velocity = Vector3.ZERO
	rig_node.clear_override()
	rig_node._override_blend = 0.0
	kit.weapons.release_fire()
	kit.weapons.set_alt(false)
	kit.weapons.combo.reset()       # else the next swipe alternates side from the last shot


## Facing away from the low sun (lit hands), or into it.
func _place(into_sun := false, pos := Vector3(6, -6, 12)) -> void:
	var yaw := -PI * 0.5 if into_sun else PI * 0.5
	player.global_position = pos
	player.controller.body_pos = pos
	rig_node.rig.yaw = yaw
	rig_node.rig.pitch = 0.0
	kit.avatar.facing_yaw = yaw


## Put `id` in hand at once (no draw), or holster everything.
func _hold(id: String) -> void:
	var h = kit.weapons.holder
	h.current = ""
	h.pending = ""
	h.phase = 0
	if id != "":
		h.request(id)
		h._t = 99.0


func _fpv(id: String, pitch: float, into_sun := false) -> int:
	_place(into_sun)
	rig_node.rig.pitch = pitch
	rig_node.set_first_person(true)
	_hold(id)
	return 40


func _fpv_ads(id: String) -> int:
	_fpv(id, 0.0)
	_after(20, func(): kit.weapons.set_alt(true))
	return 50


func _fpv_fire(id: String) -> int:
	_fpv(id, 0.0)
	_after(30, func(): kit.weapons.press_fire())
	return 32


## Walk or sprint forward along open ground.
func _fpv_move(id: String, sprint: bool, frames: int) -> int:
	_place(false, Vector3(-14, -6, 18))
	rig_node.set_first_person(true)
	_hold(id)
	player.set_command(Vector2(0, 1), sprint, false, false)
	return frames


## Nose up to a wall: back off till the ray finds one 0.45 m ahead.
func _fpv_wall(id: String) -> int:
	_place()
	rig_node.set_first_person(true)
	_hold(id)
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var eye: Vector3 = player.global_position + Vector3(0, 1.6, 0)
	for yaw in [PI * 0.5, -PI * 0.5, 0.0, PI]:
		var fwd := Vector3(sin(yaw), 0, cos(yaw))
		var q := PhysicsRayQueryParameters3D.create(eye, eye + fwd * 60.0)
		q.exclude = [player.get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			var p: Vector3 = hit.position - fwd * 0.45
			p.y = player.global_position.y
			player.global_position = p
			player.controller.body_pos = p
			rig_node.rig.yaw = yaw
			kit.avatar.facing_yaw = yaw
			break
	return 40


func _fpv_reload(id: String) -> int:
	_fpv(id, 0.0)
	_after(20, func(): (kit.weapons.guns[id]).start_reloading())
	return 20 + 30


## `from` in hand, then ask for `to`; shot `frac` of the way through the swap.
func _fpv_swap(from: String, to: String, frac: float) -> int:
	_fpv(from, 0.0)
	var h = kit.weapons.holder
	_after(20, func(): h.request(to if to != "" else from))
	var t: float = h.draw_time if from == "" else h.holster_time
	return 20 + int(t * frac * 60.0) + 1


func _fpv_swing(frames: int) -> int:
	_fpv("energy_blade", 0.0)
	_after(25, func():
		kit.weapons.press_fire()
		kit.weapons.release_fire())
	return 25 + frames


## A left swipe, then a click once it ends: the right swipe, shot `frames` in.
func _fpv_swing_right(frames: int) -> int:
	_fpv("energy_blade", 0.0)
	for at in [20, 48]:
		_after(at, func():
			kit.weapons.press_fire()
			kit.weapons.release_fire())
	return 48 + frames


## A double click (the combo: left, right, centre), shot `frames` after the
## right swipe starts.
func _fpv_combo(frames: int) -> int:
	_fpv("energy_blade", 0.0)
	_after(25, func():
		kit.weapons.press_fire()
		kit.weapons.release_fire())
	_after(27, func():
		kit.weapons.press_fire()
		kit.weapons.release_fire())
	return 25 + int(0.42 * 0.74 * 60.0) + frames


func _fpv_block() -> int:
	_fpv("energy_blade", 0.0)
	_after(20, func(): kit.weapons.set_alt(true))
	return 45


## First person, the camera moved to `eye` looking at `at` (both in the weapon's
## space): a close-up of the gun and the hands on it.
func _close(id: String, eye: Vector3, at: Vector3) -> int:
	_fpv(id, 0.0)
	_detail = [id, eye, at]
	return 40


## Third person, the camera at `off` in the player's facing frame (+Z ahead).
func _tpv(id: String, sprint: bool, off: Vector3) -> int:
	_place(false, Vector3(-14, -6, 18))
	rig_node.set_first_person(false)
	_hold(id)
	if sprint:
		player.set_command(Vector2(0, 1), true, false, false)
	_follow = off
	return 45


func _after(frames: int, f: Callable) -> void:
	create_timer(frames / 60.0).timeout.connect(f)
