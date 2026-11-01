class_name SaveSlots
extends RefCounted
## Two saves side by side: a story game and a free roam game, each in its own
## file, with its own outfit. Switching plays the other one from where it was left;
## a new game starts over only in its own slot. Nothing is shared between the two
## but the settings (sound, HUD, AI brain, keys).
##
## A save from before the slots (user://save.json) is copied into the slot its mode
## says, once, and the old outfit file into both slots. The old files stay where
## they were, untouched, for builds from before the slots.
##
## Static, like WorldState: the slot being played survives the town reloading. The
## last one played is remembered (settings/save_slot.cfg) and opens next launch.

const SaveSystem := preload("res://src/systems/save/save_system.gd")

const LEGACY := "save.json"
const LEGACY_OUTFIT := "player_outfit.json"
const FILES := { WorldState.STORY: "save_story.json", WorldState.FREEPLAY: "save_freeplay.json" }
const OUTFITS := { WorldState.STORY: "player_outfit_story.json", WorldState.FREEPLAY: "player_outfit_freeplay.json" }
const PICK := "settings/save_slot.cfg"

static var root := "user://"     ## tests point this elsewhere
static var active := ""          ## the mode whose save is being played ("" = not booted yet)


static func _mode(m: String) -> String:
	return WorldState.STORY if m == WorldState.STORY else WorldState.FREEPLAY


static func path(mode: String) -> String:
	return root + FILES[_mode(mode)]


## The outfit file of the save being played (WorldState's mode until booted).
static func outfit_path() -> String:
	return root + OUTFITS[_mode(active if active != "" else WorldState.mode)]


static func exists(mode: String) -> bool:
	return FileAccess.file_exists(path(mode))


## The mode of the save being played, booting once if need be.
static func current() -> String:
	boot()
	return active


static func current_path() -> String:
	return path(current())


## The mode being played, without booting (nothing read from disk): WorldState's
## until a save was picked.
static func playing() -> String:
	return active if active != "" else _mode(WorldState.mode)


## Once per run: move a save from before the slots into its slot, then pick the
## one to play: the last played, else the newer of the two, else free roam.
static func boot() -> void:
	if active != "":
		return
	migrate()
	var last := ""
	var cfg := ConfigFile.new()
	if cfg.load(root + PICK) == OK:
		last = str(cfg.get_value("save", "mode", ""))
	if last != "" and exists(last):
		active = _mode(last)
	elif exists(WorldState.STORY) and exists(WorldState.FREEPLAY):
		var newer_story := FileAccess.get_modified_time(path(WorldState.STORY)) > FileAccess.get_modified_time(path(WorldState.FREEPLAY))
		active = WorldState.STORY if newer_story else WorldState.FREEPLAY
	elif exists(WorldState.STORY):
		active = WorldState.STORY
	elif exists(WorldState.FREEPLAY):
		active = WorldState.FREEPLAY
	else:
		active = _mode(last)


## The old single save is copied into the slot its mode says, and the old outfit
## into each slot without one; a slot that has a file already is never written.
## Done once: the pick file says the copy was made.
static func migrate() -> void:
	if FileAccess.file_exists(root + PICK):
		return
	var old := root + LEGACY
	var mode := ""
	if FileAccess.file_exists(old):
		mode = mode_in(old)
		if not exists(mode):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(old), ProjectSettings.globalize_path(path(mode)))
	var outfit := root + LEGACY_OUTFIT
	if FileAccess.file_exists(outfit):
		for m in OUTFITS:
			if not FileAccess.file_exists(root + OUTFITS[m]):
				DirAccess.copy_absolute(ProjectSettings.globalize_path(outfit), ProjectSettings.globalize_path(root + OUTFITS[m]))
	if mode != "":
		remember(mode)


## The mode written in a save file (older saves are freeplay, as WorldState reads them).
static func mode_in(file: String) -> String:
	var d = JSON.parse_string(FileAccess.get_file_as_string(file)) if FileAccess.file_exists(file) else null
	var world = (d as Dictionary).get("world", {}) if d is Dictionary else {}
	return _mode(str((world as Dictionary).get("mode", WorldState.FREEPLAY)) if world is Dictionary else WorldState.FREEPLAY)


## What a slot's file says, for the F11 list: { exists, chapter, credits, planet }.
static func summary(mode: String) -> Dictionary:
	if not exists(mode):
		return { "exists": false }
	var d = JSON.parse_string(FileAccess.get_file_as_string(path(mode)))
	var world: Dictionary = (d as Dictionary).get("world", {}) if d is Dictionary else {}
	var where: Dictionary = (d as Dictionary).get("where", {}) if d is Dictionary else {}
	return { "exists": true, "chapter": str(world.get("story", {}).get("chapter", "")),
		"credits": int(world.get("credits", 0)), "planet": str(where.get("planet", "")) }


## The name book in `mode`'s save, or a new one (its seed gives the same names).
static func names_in(mode: String) -> NameBook:
	var book := NameBook.new()
	if exists(mode):
		var d = JSON.parse_string(FileAccess.get_file_as_string(path(mode)))
		if d is Dictionary:
			book.from_save((d as Dictionary).get("world", {}).get("names", {}))
	return book


## Play `mode`'s save from now on (and next launch).
static func remember(mode: String) -> void:
	active = _mode(mode)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path((root + PICK).get_base_dir()))
	var cfg := ConfigFile.new()
	cfg.set_value("save", "mode", active)
	cfg.save(root + PICK)


## As if the game had just been launched: the world empty, and everything a run
## keeps across town reloads (the planet you are on, the ship flown, resuming, the
## free roam tweaks, T-89's hello) back to how a launch finds it.
static func fresh_launch() -> void:
	WorldState.reset()
	GameFlow.reset()
	GameFlow.resumed = false
	GameFlow.resume_pos = Vector3.INF
	PlanetGen.layout_override = {}
	NpcBody.show_debug = false
	ShipSalesman.greeted = false
	NoiseEvents.reset()


## Leave the game being played (save it first) for `mode`'s: its world, from its
## file, or a new game in that slot when it has none. Returns true when it loaded
## one. `write` false: nothing on disk is touched (tests).
static func enter(mode: String, write := true) -> bool:
	if write:
		remember(mode)
	else:
		active = _mode(mode)
	fresh_launch()
	var s := SaveSystem.new()
	if exists(mode) and s.load_from(path(mode)) and not s.get_world().is_empty():
		WorldState.from_save(s.get_world())
		ConversationHost._loaded_once = true     # WorldState is the save's already
		return true
	start(mode, NameBook.new(), write)
	return false


## A new game in `mode`'s slot, with name book `names`; written there unless
## `write` is false. The other slot is not touched.
static func start(mode: String, names: NameBook, write := true) -> void:
	fresh_launch()
	WorldState.new_game(mode)
	WorldState.names = names
	ConversationHost._loaded_once = true
	if not write:
		return
	remember(mode)
	var s := SaveSystem.new()
	s.new_game()
	s.set_world(WorldState.to_save())
	s.data["credits"] = WorldState.credits
	s.save_to(path(mode))
