extends SceneTree
## Issue #48: screenshots of the character builder (F11, Character) for review.
## Opens the town, shows the builder with the default outfit and two mixes, then
## the player wearing the last one in the town. Needs a display.
##
##   godot --path . -s res://tools/review/builder_shot.gd -- out=/abs/dir
##
## Writes builder_<n>.png into out (default user://). Uses its own outfit file, so
## the player's saved outfit is left alone; never closes the panel through close()
## (that saves the bar's memory).

const MIXES := [
	{},
	{ "head": "player:rust", "torso": "guard:gunmetal", "legs": "player:rust" },
	{ "head": "goggles:violet", "torso": "player:dusk", "legs": "guard:oxblood" },
]

var demo
var out := "user://"
var f := 0
var shot := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.trim_prefix("out=").trim_suffix("/") + "/"
	PlayerOutfit.save_path = "user://builder_shot_outfit.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerOutfit.save_path))
	demo = (load("res://scenes/town_demo.tscn") as PackedScene).instantiate()
	get_root().add_child(demo)


func _process(_d: float) -> bool:
	f += 1
	var ds: DevSettingsPanel = demo.dev_settings
	if f == 120:
		ds.open()
		(ds._panel.find_children("*", "TabContainer", true, false)[0] as TabContainer).current_tab = 2   # Player: the outfit
	for i in MIXES.size():
		if f == 140 + i * 90:
			if i > 0:
				ds.builder._commit(MIXES[i])
		if f == 140 + i * 90 + 30 or f == 140 + i * 90 + 75:
			_shoot()
	var town_at := 140 + MIXES.size() * 90
	if f == town_at:
		ds.visible = false
		paused = false
		demo._rig.set_first_person(false)
	if f == town_at + 60:
		_shoot()
	if f > town_at + 70:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerOutfit.save_path))
		quit()
	return false


func _shoot() -> void:
	shot += 1
	var path := out + "builder_%d.png" % shot
	get_root().get_texture().get_image().save_png(path)
	print("SHOT ", path, " ", demo.dev_settings.builder.outfit)
