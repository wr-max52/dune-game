extends RefCounted
## LLM client interface (M6). The cantina owner brain talks to the LLM through this,
## so it does not care whether the response came from a live model or a canned
## one. A client yields one response per pop; a response is a Dictionary:
##   { "text": <reply String>, "tool": <name String, optional>, "args": <Dict> }
## `tool`/`args` are the model proposing an action; the brain validates the
## tool against the npc's allowed set and never assumes the user's request is a
## command. `pop_next()` returns null when the client is exhausted (so the brain
## falls back).
##
## Subclass (or use ScriptedClient / OllamaClient). Nothing here does I/O or is a
## Node, so it is headless-testable.

func pop_next() -> Variant:
	# Subclasses override. Return a response Dictionary, or null when empty.
	return null
