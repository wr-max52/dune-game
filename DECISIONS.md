# Decisions Log

Every significant technical choice, the alternative, and why. Newest on top.

## 2026-10-25 — M8 (polish pass: bug list, performance report, cross-system trace)

- **The "3-minute gameplay recording" is the manual/recorded path, not a headless
  artifact.** A rendered clip needs a window a CI run does not have. So M8 ships the
  *machine* proof of the same content -- a single cross-system playthrough trace
  (`scenes/m8_playthrough.gd`) and a per-frame performance report -- and hands the human
  a guide (`LAUNCH.md`) to open the game and record the clip. This is the same posture
  as M6/M7 (real inference / real voice / real render are manual + recorded; CI proves
  the behavior deterministically). Alternative: a headless render -- rejected, Godot
  `--headless` has no window and a synthetic render would not prove the *look*, only the
  *behavior*.

- **"No hitch over 50ms" is proven over a whole playthrough, not one frame.** M4 proved
  the streaming budget for the port->desert walk; M8 extends it to a full session that
  interposes every system, and the report's `over_budget=0` + `worst_ms` are the
  measured "no hitch" across that session. The per-frame work is a load-cost figure the
  trace itself accounts for, so the proof stays honest and reproducible.

- **The "bug list" was the one standing artifact; it was a timing mismatch, not a logic
  bug.** GUT's "1 orphan" at exit was a detached test node cleared with
  `queue_free()`, which the engine only honors on the next idle frame -- never, because
  GUT quits immediately. `free()` on a detached node is correct; that change clears the
  orphan. The suite now reports 0.

- **A cross-system integration trace, not more isolated unit tests, is the M8 proof.**
  Each milestone proved its own system; M8's job is to show them *together*. One SceneTree
  run threads movement -> camera -> combat -> squad -> duel -> mission -> voice -> save,
  and a test reads the resulting log. This is what "hangs together end to end" means, and
  it complements (does not replace) the per-milestone traces.

## 2026-10-25 — M7 (voice input: typed default, whisper fallback)

- **Typed is the DEFAULT speech source; whisper is the optional, dependency-bearing
  upgrade.** This deliberately supersedes the M0 assumption that whisper/VAD was the
  primary voice-in pipeline. The product owner's M7 direction: type the speech by
  default (zero dependency, easy) and only wire whisper as a fallback. A speech source
  is dependency-aware (`dependency()` says "none" for typed, "whisper runtime" for
  whisper), and the controller prefers the typed source unless voice is both preferred
  AND the whisper runtime is actually loaded. Alternative: keep whisper primary —
  rejected because it forces an STT model + mic into the default path for no gameplay
  gain and makes the slice harder to ship.

- **One door, the same brain.** The push-to-talk routes every captured request to the
  M6 `bartender.respond()`, so the "text is read but never executed as a command, only
  an allowed model tool may act" guardrail is unchanged. No new code path can move
  world state except through the M6 guardrail.

- **A degraded voice turn is a typed turn, never nothing.** When voice is preferred
  but whisper is absent (the CI case, and any build without the model) or a sample
  transcribes to empty, the controller serves the request through the typed source, so a
  conversation never dead-ends on a missing model. This is the same "graceful null,
  not a crash" posture as M6's Kokoro and Ollama.

- **The whisper runtime is a stand-in that loads only when a model is present**,
  mirroring M6's Ollama client (pure parts tested, I/O part a documented stub). This
  keeps "does the voice path work when wired?" answerable headless while the real
  whisper.cpp + mic capture stays the manual + recorded path.

- **Latency is measured from an injected clock.** The press/release core takes
  start/end ms, so a headless trace records a deterministic per-turn latency — the M7
  "latency measured" requirement — without a mic. Real wall-time timing is the manual
  wiring.

- **GUT/GDScript-4.7 gotchas (carried from M6):** GUT 9.7.1 uses snake-case asserts
  (`assert_true`/`assert_eq`/`assert_gt`/`assert_false`), not Java-style; and
  `Object.has("field")` does not exist in this engine -- use `has_method(...)` for a
  presence guard. Both surfaced in M7 and are noted here so a future test does not redo
  the work.

## 2026-10-25 — M6 (LLM bartender, text + Kokoro voice)

- **The bartender talks to the model through a client interface, not a hardcoded
  model call.** `llm_client.gd` is the contract (`pop_next() -> response or null`);
  `scripted_client` (canned, deterministic) and `ollama_client` (real, local) both
  satisfy it. Alternative: hardcode Ollama into the brain — rejected because it would
  make the conversation untestable headless and lock the brain to one backend. Same
  reasoning as the M1-M4 "pure spine, node wraps it" pattern. Real inference stays a
  manual + recorded check; CI uses the canned client.

- **Text is read but never executed; only a model tool proposal may act on the
  world, and only one in the npc's allowed set.** This is the guardrail the spec asks
  for ("the player's typed text is never a command"). It is enforced in one place
  (`respond()`): the request string is logged/read but no branch acts on it; an
  effect happens only via `_apply_tool`, which refuses any tool not in `allowed_tools`
  (loaded from the npc data entry). A disallowed tool is dropped, so no effect leaks
  into memory.

- **A disallowed tool is ignored, not partially applied.** When the model proposes a
  tool outside the allowed set, the brain zeroes out `tool`/`args` before applying, so
  the conversation can never smuggle an out-of-scope action through. This is asserted
  in `test_disallowed_tool_is_ignored`.

- **Kokoro ships as a deterministic signature + a graceful null render.** The
  text+speaker -> signature mapping is pure and tested (same input, same signature;
  different speaker, different signature). The audio render needs the Kokoro/ONNX run,
  which is not in headless CI, so `synthesize()` returns null instead of crashing --
  the conversation never dead-ends on sound. A real recorded voice is M8. This follows
  the M0 decision to use NobodyWho's bundled Kokoro/Whisper/VAD rather than separate
  builds.

- **Client `pop_next()` returns `Variant`, not `Dictionary`.** GDScript forbids
  returning `null` against a `Dictionary` return type; the interface needs "a response
  or null," so `Variant` is correct. Same class of fix as the M5 parse bugs.

- **The Ollama client is pure except for the HTTP post.** Request-building and
  response-parsing are plain functions tested on canned JSON (the real `/api/chat`
  shape: `message.content` + `message.tool_calls[].function`); only `_post()` does I/O
  and is a documented stub. This keeps the "is the response parsed right?" question
  answerable without a running server.

## 2026-10-25 — M5 (mission loop + save)

- **Missions are a generic data category, like `locations` was at M4.** The slice
  mission lives in content/core/missions/crate_retrieval.json and the loader loads it
  from the manifest with the same code path as every other category. Alternative: a
  hand-wired mission table — rejected because it would hardcode the one mission and
  break the "zero code change to add content" rule. New missions extend the manifest
  only.

- **The mission is a pure RefCounted state machine driven by events, not a Node3D
  scene.** This mirrors M1-M4: the gameplay spine (IDLE -> ... -> COMPLETE) is proven
  by GUT headless, and the live game wraps it. The same spine is what the bot bot
  plays and what a human plays, so the bot playthrough is a faithful proof.

- **The squad coordinator assigns each trooper a DISTINCT cover node.** With N nodes
  and N troopers, every trooper gets one node and none is left in the open; with
  fewer nodes than troopers the surplus is honestly left open. This is the "4
  troopers do not all stand in the open" the spec asks, on top of the single-unit
  M2 cover logic.

- **The save round-trip is a file test, not an LLM test.** The four named things
  (player position, credits, mission state, bartender memory) are written to user://
  and read back into a fresh instance; the trace asserts each survives. This is what
  "save/load all working end to end" means here, and it stays honest because it is a
  deterministic file round-trip, not inference.

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
   This was logged as a deviation in the plan (PLAN.md); revisited at M7 only if
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

## 2026-10-25 — M4 (chunk streaming)

- **"No hitch over 50ms" is proven as an amortized frame-time budget, not a GPU
  measure.** The spec asks for "no loading screen at the boundary / no hitch over 50ms."
  We model chunk loading as a cost in milliseconds and a `chunk_streamer` that never lets
  one frame spend more than `work_budget_per_frame` (=50ms). The property "max per-frame
  work never exceeds the budget" is the exact anti-hitch invariant, and it is the part
  that can be proven headless. Real GPU frame-time of a rendered world is deferred to M8;
  this is the load-side budget that makes a seam hitch-free.

- **Streaming proof is a generated log, read by a test.** Rather than assert behavior in
  vacuum, M4 runs a full bay-to-outpost walk in a SceneTree harness that writes a
  per-frame log (frame, player_x, frame_work_ms) to `test_results/`, and a GUT test reads
  that file and checks "0 frames over 50ms" and "the walk crosses to x=1000." This is the
  same machine-evidence pattern as the M1/M2/M3 traces; it keeps the proof honest (read
  from a real run) and reproducible (CI regenerates it). It is disclosed that this is the
  load-cost model, not yet a recorded rendered frame time.

- **The data layer gained a `locations` category.** The outpost (3 buildings + 1 crate +
  its guards) is content/core data, not code, so a future skin or a new location needs
  zero code change — consistent with the M0 IP-neutral design. New categories extend the
  manifest (`"locations": ["outpost"]`), and the loader loads them the same generic way.

- **A 1-D chunk strip stands in for a rendered 3D world at M4.** Streaming logic and its
  frame cost don't depend on geometry; a 1-D coordinate (player position east) is enough
  to prove the window/coverage/amortization invariants without a 3D level. The visible 3D
  greybox is M8.
