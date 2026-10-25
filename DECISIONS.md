# Decisions Log

Every significant technical choice, the alternative, and why. Newest on top.

## 2026-10-25 — M0

- **Engine pinned to Godot 4.7.2.** Latest stable at M0 start. Alternative: 4.6.x.
  Chose 4.7.2 so NobodyWho (lists 4.5+) and GUT 9.7.1 (tracks 4.7.x line per GUT's
  version matrix) both match. Version is enforced in `scripts/ci.sh` against `pin.txt`.

- **GUT 9.7.1 for testing.** MIT, is the standard Godot test framework, tracks the
  4.7.x line. Alternative: a hand-rolled runner — rejected, GUT gives JUnit XML +
  asserts for free. NOTE: GUT 9.7.1 uses `before_each()/after_each()`, NOT the old
  `setUp()/tearDown()`. Our tests use the former.

- **GUT is run headless via its CLI (`-s res://addons/gut/gut_cmdln.gd`).** A bare
  `godot --headless` invocation runs the project's main scene, which never quits, so
  it hangs forever. The CLI runner quits on its own and returns a non-zero exit code
  on failure; `scripts/ci.sh` relies on that exit code as the merge gate.

- **CI is a local shell script (`scripts/ci.sh`), not GitHub Actions.** Decision from
  the product owner: local-only repo. The script runs GUT headless and exits
  non-zero on any failure. If a remote host is wanted later, the same GUT command is
  the body of a GitHub Action.

- **IP-neutral data layer at `content/core/`, loaded at runtime.** This is the load
  path a future private "skin" layer would override with zero code changes — the
  loader takes a root path argument. No name is hardcoded outside this directory;
  `tests/test_ip_neutral.gut.gd` greps the source tree for franchise terms and fails
  the build on a hit.

- **Voice pipeline: use NobodyWho's bundled Kokoro (TTS) + Whisper (STT) + VAD**,
  not a separately-built whisper.cpp / Kokoro. The product owner approved this at
  M0 planning as a deliberate deviation from the literal spec wording, because it
  removes a second C++ build and a second license surface for no gameplay gain.
  This was logged as a deviation in the planning record; revisited at M7 only if
  quality demands.

- **LLM model: Qwen3 4B Q4 for the bartender.** Fits comfortably in 64 GB, strong
  tool-calling (which is what the 4-tool bartender needs). A fallback plan exists in
  KNOWN_ISSUES.md: drop to a 1-2B instruct model that supports tools if 4B is too
  slow or too large.

- **Bot playthrough (M5) drives the non-LLM loop live but talks to a deterministic
  stub model**, not real inference. Real LLM inference is a recorded/manual check.
  This is what makes "a failing bot blocks the merge" actually reliable; it is
  documented as a stub, not presented as a finished LLM loop.

- **No C#.** NobodyWho (the LLM plugin) is a Rust/C++ binding, not C#. Per the spec,
  GDScript is the default and C# is avoided unless a system genuinely needs it.

- **No GPL anywhere.** Godot MIT, GUT MIT, NobodyWho EUPL-1.2, llama.cpp/ONNX
  permissive, greybox assets CC0. Studied OpenJK for melee/deflection mechanics only;
  nothing is copied.
