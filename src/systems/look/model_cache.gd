class_name ModelCache
extends RefCounted
## The game's imported models (.glb / .tscn), loaded once a run and kept.
##
## A planet handoff swaps the whole town scene. Without this, the old scene's
## models are freed with it and the new scene loads them again from disk on the
## main thread: a Hyper3D speeder is ~145 ms each, so flying home froze for a
## third of a second on the speeders alone, and the ship, items and droids added
## to both directions. Holding the PackedScene here keeps Godot's resource cache
## warm across change_scene, so a second build is just an instantiate().
##
## Static on purpose (no autoload), like GameFlow: the state survives scene
## changes and nothing runs until something asks for a model.

static var _scenes: Dictionary = {}       ## path -> Resource (what load() gave)


## load(path), once per path per run. Same result as load(): null when missing.
static func scene(path: String) -> Resource:
	if _scenes.has(path):
		return _scenes[path]
	var res := load(path)
	if res != null:
		_scenes[path] = res
	return res


## Forget everything (tests; the models load again on next use).
static func clear() -> void:
	_scenes.clear()
