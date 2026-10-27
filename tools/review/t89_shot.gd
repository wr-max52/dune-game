extends SceneTree
## Issue #58: screenshots of T-89 and the spare pad for review. Opens the town,
## waits for T-89's hello, then looks at him, the empty pad, and the pad once a
## ship is bought. Needs a display. Saves and restores the player's save file.
##
##   godot --path . -s res://tools/review/t89_shot.gd -- out=/abs/dir

const SAVE := "user://save.json"
const BACKUP := "user://save.t89_shot.bak"

var demo
var out := "user://"
var f := 0
var cam: Camera3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.trim_prefix("out=").trim_suffix("/") + "/"
	if FileAccess.file_exists(SAVE):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(SAVE), ProjectSettings.globalize_path(BACKUP))
	Disclaimers.launch_shown = true
	demo = (load("res://scenes/town_demo.tscn") as PackedScene).instantiate()
	get_root().add_child(demo)


func _look(from: Vector3, at: Vector3) -> void:
	if cam == null:
		cam = Camera3D.new()
		cam.far = 4000.0
		demo.add_child(cam)
	cam.current = true
	cam.global_position = from
	cam.look_at(at, Vector3.UP)


func _process(_d: float) -> bool:
	f += 1
	var s: ShipSalesman = demo.salesman
	if f == 1 and demo.bar != null:
		demo.bar.autosave = false      # never write the player's save from here
	if f == 160:
		_shoot("greeting")
	if f == 170:
		s.menu.choose("no")
		WorldState.hangar = ""
		_look(s.pos + Vector3(-2.5, 1.6, -4.0), s.pos + Vector3(0, 1.2, 0))
	if f == 200:
		_shoot("t89")
	var pad: Dictionary = demo.town.get_box("spare_pad")
	var pc := Vector3((float(pad.min[0]) + float(pad.max[0])) * 0.5, -6.0, (float(pad.min[2]) + float(pad.max[2])) * 0.5)
	if f == 210:
		_look(pc + Vector3(14, 9, 14), pc)
	if f == 240:
		_shoot("pad_empty")
	if f == 250:
		WorldState.credits = 9999
		s.buy("courier")
	if f == 280:
		_shoot("pad_bought")
	if f == 290:
		_look(Vector3(0, 14, 34), Vector3(0, -6, 0))
	if f == 320:
		_shoot("pit")
	if f == 330:
		s.sell()
		s.talk()
		cam.current = false
		demo._rig._camera.current = true
	if f == 360:
		_shoot("shop")
	if f > 370:
		if FileAccess.file_exists(BACKUP):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(BACKUP), ProjectSettings.globalize_path(SAVE))
			DirAccess.remove_absolute(ProjectSettings.globalize_path(BACKUP))
		quit()
	return false


func _shoot(tag: String) -> void:
	var path := out + "t89_%s.png" % tag
	get_root().get_texture().get_image().save_png(path)
	print("SHOT ", path)
