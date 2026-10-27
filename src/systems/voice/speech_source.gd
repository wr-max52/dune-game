extends RefCounted
## Speech source (M7): turns raw input into the text the cantina owner hears.
##
## A source is pure and dependency-aware: is_available()/dependency() say whether
## it can be used and what it needs, so the controller prefers the dependency-free
## typed source and treats whisper as an optional upgrade it falls back to.
##
## Subclass (or use a typed_speech_source / whisper_speech_source). Nothing here
## is a Node, so it is headless-testable.

func kind() -> String:
	return "unknown"

func is_available() -> bool:
	return false

func dependency() -> String:
	return "none"

func transcribe(_sample: Variant) -> String:
	return ""
