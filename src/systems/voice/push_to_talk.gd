extends RefCounted
## PushToTalk (M7): the ONE door a player's request reaches the bartender through.
##
## Per the M7 decision, TYPED is the default and the only path with no dependency;
## WHISPER is an optional, dependency-bearing upgrade behind the same button. When
## whisper is unavailable (no runtime/model -- the CI case, and any build without
## the model) a voice turn degrades to typed, so a request is never dropped.
##
## Both paths feed the SAME bartender brain as M6, so the guardrail "the player's
## text is read but never executed as a command" is unchanged: the captured text is
## only something to talk about; an effect happens only when the MODEL proposes an
## allowed tool.
##
## The capture is pure and injects its clock (start/end ms) so a headless trace
## can assert latency deterministically. The literal press()/release() push-to-talk
## is a thin wrapper over that core using an injected monotonic clock.

enum Mode { TYPE, VOICE }
enum State { IDLE, RECORDING, DONE }

var typed      # a typed_speech_source -- default, zero dependency
var whisper    # a whisper_speech_source -- optional, dependency-bearing
var mode: Mode = Mode.TYPE  # the preference: typed by default
var state: State = State.IDLE

var now_ms: int = 0  # injected monotonic clock (deterministic trace)
var _press_at: int = 0

var last_latency_ms: int = 0
var last_source: String = ""
var last_text: String = ""


func _init() -> void:
	var t = load("res://src/systems/voice/typed_speech_source.gd")
	if t != null:
		typed = t.new()
	var w = load("res://src/systems/voice/whisper_speech_source.gd")
	if w != null:
		whisper = w.new()


## Preference helpers (the typed default vs the optional voice path).
func prefer_typed() -> void:
	mode = Mode.TYPE


func prefer_voice() -> void:
	mode = Mode.VOICE


## Which source serves this turn: voice only when it is the preference AND the
## whisper runtime is actually loaded; otherwise the typed default (no dep).
func active_source() -> Variant:
	if mode == Mode.VOICE and whisper != null and whisper.is_available():
		return whisper
	return typed


## True when the preferred voice path could not serve and we degraded to typed.
func fell_back_to_typed() -> bool:
	return mode == Mode.VOICE and last_source == "typed"


## The literal push-to-talk: hold to record, release to capture + route.
func press() -> void:
	state = State.RECORDING
	_press_at = now_ms


func release(sample: Variant) -> String:
	return capture(sample, _press_at, now_ms)


## Pure core (injects start/end so a headless trace is deterministic):
##   - pick the active source for the current preference;
##   - transcribe the sample; if a voice turn yields nothing (whisper down or empty
##     audio) fall back to the typed source, so a request is never dropped;
##   - measure latency and record which source served it.
func capture(sample: Variant, start_ms: int, end_ms: int) -> String:
	state = State.RECORDING
	last_latency_ms = end_ms - start_ms
	var src = active_source()
	var text: String = str(src.transcribe(sample))
	if text.is_empty() and typed != null and typed.is_available():
		var ttext: String = str(typed.transcribe(sample))
		if not ttext.is_empty():
			text = ttext
			src = typed
	state = State.DONE
	last_source = src.kind() if not text.is_empty() else "none"
	last_text = text
	return text
