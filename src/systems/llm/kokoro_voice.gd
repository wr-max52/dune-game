extends RefCounted
## Kokoro voice (M6). Pure signature + graceful offline render.
##
## The deterministic part is `signature()`: given text + speaker it returns the
## same "which-utterance" signature every time, so a line can be routed to a
## consistent voice without running the model. The actual audio render
## (`synthesize()`) needs the Kokoro/ONNX run, which is not wired in headless CI;
## it fails GRACEFULLY with a null rather than crashing, so a conversation never
## dead-ends on sound.

## Cheap, deterministic mapping of (text, speaker) to an utterance signature.
func signature(text: String, speaker: String) -> String:
	return str(hash(text + "::" + speaker))


## Render audio for the line with the speaker's voice. Offline (no model) this is a
## graceful null, not a crash.
func synthesize(_text: String, _speaker: String) -> Variant:
	# Real Kokoro TTS needs the plugin/ONNX run; not wired in CI.
	return null
