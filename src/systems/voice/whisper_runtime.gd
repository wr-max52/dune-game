extends RefCounted
## Whisper runtime (M7): a stub for the OPTIONAL STT dependency.
##
## The real path loads whisper.cpp plus a model -- a dependency the typed default
## has no need for. It is absent in headless CI, so is_loaded() is false and the
## controller falls back to typed. forceload() stands in for a successful load in
## tests and in a real build with the model present; it only "loads" when a model
## was set, mirroring the real thing needing a model to run. A load can never
## crash the slice: a failed load keeps the runtime unloaded and the typed default
## handles the request.

var model_name := ""
var _loaded := false


func set_model(name: String) -> void:
	model_name = name


func is_loaded() -> bool:
	return _loaded


func forceload() -> bool:
	# Real: dlopen whisper + load model_name. Stand-in for a present model.
	_loaded = model_name != ""
	return _loaded
