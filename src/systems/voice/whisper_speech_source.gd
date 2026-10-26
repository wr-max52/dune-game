extends RefCounted
## Whisper speech source (M7): the optional STT upgrade behind the same button.
##
## It is NOT available until a runtime + model are present (a dependency the typed
## default does not have), which is exactly why typed is the default. With a
## runtime loaded, transcribe turns an audio sample into text via a canned map
## (there is no live model in CI); an unknown sample yields "" so the controller
## falls back to typed rather than dropping the request.

var runtime            # a whisper_runtime; may be null
var canned: Dictionary = {}  # sample/token -> transcript


func kind() -> String:
	return "whisper"


func dependency() -> String:
	return "whisper runtime"


func is_available() -> bool:
	return runtime != null and runtime.is_loaded()


func set_runtime(rt) -> void:
	runtime = rt


## Test/real hook: load the runtime so the voice path activates. Only succeeds
## when a model was set, mirroring a real STT needing a model.
func enable() -> bool:
	if runtime != null:
		return runtime.forceload()
	return false


func transcribe(sample: Variant) -> String:
	if not is_available():
		return ""
	return str(canned.get(str(sample), ""))
