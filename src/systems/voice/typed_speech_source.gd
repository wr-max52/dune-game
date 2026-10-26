extends RefCounted
## Typed speech source (M7): the DEFAULT and the only source with no dependency.
##
## The input is already text, so transcribing is identity. It is always available,
## which is why the slice can ship voice input without shipping an STT model: the
## controller prefers it, and a voice turn that cannot be served degrades to it.

func kind() -> String:
	return "typed"

func is_available() -> bool:
	return true

func dependency() -> String:
	return "none"

func transcribe(sample: Variant) -> String:
	return str(sample)
