class_name ModelCache
extends RefCounted
## The game's imported models (.glb / .tscn) and the characters' outfit textures,
## loaded once a run and kept.
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
static var _pending: Dictionary = {}      ## path -> true: prefetch() asked a worker thread for it


## load(path), once per path per run. Same result as load(): null when missing.
static func scene(path: String) -> Resource:
	if _scenes.has(path):
		return _scenes[path]
	var res: Resource
	if _pending.has(path):
		_pending.erase(path)
		res = ResourceLoader.load_threaded_get(path)   # waits only if the worker is not done yet
	else:
		res = load(path)
	if res != null:
		_scenes[path] = res
	return res


## Issue #162: start loading `paths` on worker threads, so a later scene() is only
## a lookup. A planet handoff builds its people a frame at a time; a 2048² outfit
## texture read from disk on the main thread was a 35-110 ms stall per new colour.
static func prefetch(paths: Array) -> void:
	for p in paths:
		var path := str(p)
		if _scenes.has(path) or _pending.has(path) or not ResourceLoader.exists(path):
			continue
		if ResourceLoader.load_threaded_request(path) == OK:
			_pending[path] = true


## Paths asked for by prefetch() and not yet picked up by scene().
static func pending() -> Array:
	return _pending.keys()


## Forget everything (tests; the models load again on next use).
static func clear() -> void:
	for path in _pending:
		ResourceLoader.load_threaded_get(path)   # let the worker's result go
	_pending.clear()
	_scenes.clear()
