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

## 2026-10-25 — M3 (melee + duelist)

- **The energy blade and the duelist are pure, testable `RefCounted` state machines**
  (`src/systems/combat/energy_blade.gd`, `src/systems/ai/duelist_brain.gd`), with no
  Node3D. This mirrors M1/M2: the gameplay math is proven by GUT, and a node wraps it for
  the live game. A duelist that *uses the player's exact blade logic* is the design so
  "a melee duelist that blocks, parries, and pressures" and the "timed deflection" skill
  are the *same code* on both sides.

- **Timed deflection is modeled as a block-timing window, not as a separate input.**
  `intercept_bolt()` checks how long the current block has been held: a block opened
  within `deflect_window` reflects the bolt and refunds stamina; a block held longer only
  absorbs it. This is the "deflection of incoming bolts when blocking with correct
  timing" from the spec, and it reduces to one number (`deflect_window`) so the skill can
  be tuned from the data layer in a future skin.

- **Process-ordering rule for multi-stage timers.** When a single `update(dt)` both ends
  a state and starts the next, the *recovery* timer must be advanced before the *drain*/
  *end* logic of that frame, otherwise a state reached that frame is instantly advanced
  out of its own recovery. The `energy_blade.update` is structured in that order and the
  rule is noted here for the next timer-based system (reload, parry cooldowns).

- **M2 was committed before it was merged, so M3 was built on a base missing M2.**
  This is a process bug, not a code one: a feature branch can be complete and correct
  while not yet integrated. The fix was to merge the in-flight work into `main` before
  branching the next milestone, and to keep the rule **"branch each milestone off the
  latest main, and merge only when its tests pass."** If this pattern ever recurs, the
  recovery is `git merge --no-ff <branch>` because the branches are disjoint.

- **The trace, not the render, is the M2/M3 proof in CI.** Each combat milestone ships a
  headless *trace* (a text log of a simulated encounter) plus GUT assertions on that log.
  A rendered GUI fight with bullets and animation is M8 polish. This keeps the merge gate
  fast and deterministic while still proving the *behavior* the spec asks for.

- **One known non-failing artifact is disclosed, not hidden.** GUT flags "1 orphan" at
  process exit: a test bolt created without a scene tree is freed at exit. It does not
  fail the suite (exit 0, "All tests passed"); it is tracked in KNOWN_ISSUES.md for M8
  cleanup.
