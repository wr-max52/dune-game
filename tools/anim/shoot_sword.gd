extends SceneTree
## The energy sword's moves on the real player in the town: a left swipe, a right
## swipe, a flurry of single clicks, the double-click combo (left, right, centre),
## and Remnant droids batted away by a killing cut. Each clip saves every other
## frame (30 fps) to test_results/sword/<clip>/NNN.png and a contact sheet to
## test_results/sword/<clip>.png; shoot_sword.sh turns the frames into GIFs.
##
## Needs a real renderer: ./tools/anim/shoot_sword.sh [clips=left,combo]

const OUT := "res://test_results/sword"
const SHEET_COLS := 8
const THUMB := Vector2i(400, 225)

var demo
var kit: PlayerKit
var rig_node
var player
var _only: Array = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("clips="):
			_only = a.substr(6).split(",")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	Disclaimers.launch_shown = true     # the launch notice would cover every shot
	demo = load("res://scenes/town_demo.gd").new()
	demo.preset = "golden"
	get_root().add_child(demo)
	_run.call_deferred()


func _run() -> void:
	await _frames(240)                  # the town and its droids build in stages
	kit = demo.player_kit
	rig_node = demo._rig
	player = demo._player
	for c in get_root().find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false       # the HUD and its notices cover the moves
	for clip in ["left", "right", "flurry", "combo", "bat_assassin", "bat_floating"]:
		if not _only.is_empty() and not _only.has(clip):
			continue
		match clip:
			"left":
				await _ready_sword()
				await _record(clip, 34, { 1: _click })
			"right":
				await _ready_sword()
				_click()
				await _frames(32)            # the left swipe plays out; the next click goes right
				await _record(clip, 34, { 1: _click })
			"flurry":
				await _ready_sword()
				await _record(clip, 96, { 1: _click, 21: _click, 41: _click, 61: _click })
			"combo":
				await _ready_sword()
				await _record(clip, 90, { 1: _click, 9: _click })
			"bat_assassin", "bat_floating":
				await _ready_sword()
				var u = _droid(clip.trim_prefix("bat_"))
				_cut_behind()
				await _frames(20)
				await _record(clip, 90, { 1: _click, 9: _click })
				if is_instance_valid(u):
					demo.droids.remove_site_unit(u)
	print("SHOOT SWORD: done")
	quit()


func _click() -> void:
	kit.weapons.press_fire()
	kit.weapons.release_fire()


## The player on the range, sword out, the camera three-quarters in front.
func _ready_sword() -> void:
	kit.weapons.combo.reset()
	_place(Vector3(6, -6, 9), PI * 0.5)
	rig_node.set_first_person(false)
	kit.weapons.holder.current = ""
	kit.weapons.holder.phase = 0
	kit.weapons.holder.request("energy_blade")
	var yaw := PI * 0.5 + deg_to_rad(28.0)
	var at: Vector3 = player.global_position + Vector3(0, 1.15, 0)
	_cut(at + Vector3(sin(yaw), 0.16, cos(yaw)) * 2.5, at)
	await _frames(50)


## A Remnant droid of `kind` a step in front of the player, facing them, one cut from dead.
func _droid(kind: String):
	var fwd := Vector3(sin(PI * 0.5), 0, cos(PI * 0.5))
	var at: Vector3 = player.global_position + fwd * (1.35 if kind == "assassin" else 1.2)
	var ctl = demo.droids
	var u = ctl._spawn_remnant({ "kind": kind, "variant": "remnant", "hp": 60, "respawn": false,
		"patrol": [at], "gun": {} }, 0, at)
	ctl._face(u, -fwd)
	return u


## Over the player's shoulder, high enough to see where the droid lands.
func _cut_behind() -> void:
	var fwd := Vector3(sin(PI * 0.5), 0, cos(PI * 0.5))
	var right := fwd.cross(Vector3.UP)
	var p: Vector3 = player.global_position
	_cut(p - fwd * 3.0 + right * 1.2 + Vector3(0, 2.2, 0), p + fwd * 2.5 + Vector3(0, 0.7, 0))


func _record(clip: String, frames: int, act: Dictionary) -> void:
	var dir := ProjectSettings.globalize_path(OUT + "/" + clip)
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + f)
	var shots: Array[Image] = []
	for f in frames:
		if act.has(f):
			(act[f] as Callable).call()
		await RenderingServer.frame_post_draw
		if f % 2 == 0:
			var img := get_root().get_texture().get_image()
			img.save_png("%s/%03d.png" % [dir, f / 2])
			shots.append(img)
	_sheet(clip, shots)
	print("CLIP ", clip, " -> ", dir, " (", shots.size(), " frames)")


## Every few frames of a clip, left to right, top to bottom.
func _sheet(clip: String, shots: Array[Image]) -> void:
	var n := mini(16, shots.size())
	var rows := ceili(float(n) / SHEET_COLS)
	var sheet := Image.create(THUMB.x * SHEET_COLS, THUMB.y * rows, false, Image.FORMAT_RGBA8)
	for i in n:
		var img: Image = shots[int(float(i) * float(shots.size() - 1) / maxf(1.0, n - 1))].duplicate()
		img.convert(Image.FORMAT_RGBA8)
		img.resize(THUMB.x, THUMB.y, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, THUMB), Vector2i((i % SHEET_COLS) * THUMB.x, (i / SHEET_COLS) * THUMB.y))
	sheet.save_png(ProjectSettings.globalize_path(OUT + "/" + clip + ".png"))


func _place(pos: Vector3, yaw: float) -> void:
	player.global_position = pos
	player.controller.body_pos = pos
	player.velocity = Vector3.ZERO
	rig_node.rig.yaw = yaw
	rig_node.rig.pitch = 0.0
	kit.avatar.facing_yaw = yaw


func _cut(eye: Vector3, at: Vector3) -> void:
	rig_node.set_override(Transform3D(Basis(), eye).looking_at(at, Vector3.UP))
	rig_node._override_blend = 1.0


func _frames(n: int) -> void:
	for i in n:
		await process_frame
