# Known Issues / Stubs / Fakes

Honest list of what is broken or faked. Updated every milestone.

## After M11 + M12 (2026-10-26)

**What is real and proven by tests:** the body's gait/jump/land/crouch states, view
toggle spam, camera wall collision, swap spam, blaster hits on range targets, the
3-hit sword chain landing hits, timed deflections sent back into the remote, street
shots changing WorldState (`test_results/m11_body_trace.txt`). The bartender's whole
pipe: player text reaches the model fenced, rumors/jobs/secrets only from the
briefing, trust clamps, menu prices, meta/IP filtering, fallback, circuit breaker,
first-token timeout with a beat, stalled streams, canned-but-true offline answers,
memory across visits and save v2; and the real HTTP streaming path against a mock
server (`test_results/m12_bar_trace.txt`).

**Not done, honestly:**
- **No real model has answered her yet.** This sandbox has no GPU and no access to
  model downloads. The pipe is proven against a mock server that speaks the
  OpenAI streaming format; quality, voice and latency on a real model are the
  product owner's first run: `tools/llm/fetch_runtime.sh`, then the gauntlet. The
  latency targets (first token p50 < 800 ms) are unmeasured.
- **Her confidant secret is a draft** marked "PRODUCT OWNER TO WRITE" in
  `content/core/npcs/bartender_card.json`. The whole card is a first draft.
- **The visit summary** (2 to 3 facts written by the model when you leave) only runs
  when a model is up; offline she remembers only what the game wrote.
- **Bundling llama-server in an export build** is not done; the sidecar uses the
  Homebrew binary path from config.
- **Animation is procedural,** tuned by eye from software-GL renders, not on the Mac.
  No foot IK on slopes or ramps (feet can float a few cm on the pit ramps), no
  turn-in-place step, no hit reactions on the player.
- **Player hits have no consequence** beyond a flash and shake (no player health or
  death yet). Remote stun bolts do no damage by design.
- **The trooper posts and locals are static characters now** (were capsules): no AI,
  no collision, so bolts pass through them.
- **The rifle in first person is big** and partly covers the lower right of the view.
- **No crosshair spread feedback or hit markers.**
- **The old M6 scaffold** (`bartender_ai.gd`, `ollama_client.gd`) is kept only for the
  M6/M7/M8 traces; the game uses `bartender_brain.gd`.
- **Reviewed in software GL only** (`docs/m11/`); re-shoot on the Mac with
  `tools/m11/shoot_m11.sh`.

## After M9 (2026-10-26)

**What is real and proven by tests:** the town is built from data and validated
(V1 to V8, with a negative test per rule); a headless bot walks all 4 routes with
real collision (`test_results/town_walk_trace.txt`); the decor layer adds no
collision; the pit pad launches the dogfight and the player comes back to the pit
after it (`tests/test_flow.gut.gd`).

**Stubbed / deferred, honestly:**
- **NPCs are static capsules.** No AI, no collision. The bartender and fixer are not
  yet wired to their M6/M5 systems inside the town.
- **No navmesh.** The bot walks authored routes.
- **Residential is a uniform grid.** The art pass will vary it.
- **The ramps have no railings,** so you can fall into the pit (no fall damage exists).
- **Town streamer chunks are data only;** they do not load or unload geometry yet.
- **The town is not on the beauty corner plinth or terrain.** The roads down the
  cliff are unplanned. The aprons have no sand shader (flat sand color; at golden
  hour they read as dark grey from low angles).
- **The market stalls are bare boxes.** (The parked ship is now the real flight model.)
- **The parked ship is small in the pit.** The fighter is 9.3 m long and 2.6 m tall in a 36 by 44 m pit, 6 m deep, so it is hidden from the street until you reach the rim.
- **The gate lintel keeps its greybox color** (overhead outside the cantina has no
  decor rule).
- **Flight payout is shown, not saved.** No early abort from a flight.
- **Look reviewed in software GL only.** `docs/town/look/` was rendered on a machine
  without a GPU, where Godot falls back to OpenGL: no volumetric fog, SDFGI or SSIL.
  Re-shoot on the Mac with `tools/town/shoot_town.sh` for the real look.

## After M10 (2026-10-26)

**What is real and proven by tests:** everything through M8, plus starfighter flight
and dogfights. The headless trace (`test_results/m10_dogfight_trace.txt`) flies the
orbital_skirmish encounter to COMPLETE with the player flown by the AI; GUT checks the
flight model, guns, seekers, shields, AI actions, wave logic, ship looks, the playable
scene, and that a new ship/gun/pilot/fight works from data alone.

**Stubbed / deferred, honestly:**
- **Ships are primitive stand-ins.** `ship_kit.gd` builds them from boxes, cylinders
  and prisms. Real models plug in through the look's `scene` path; none exist yet.
- **No ship-to-ship collisions.** Ships pass through each other and through the
  planet. Hit spheres exist for bolts only.
- **The encounter is not tied to the fixer's contracts or the save file.** (Launch
  and return from the town pit landed in M9.) (The flight model has `to_dict()`/`from_dict()`
  ready for the save system.)
- **Not tested on a Mac.** Logic is proven headless; the look was reviewed in Linux
  software rendering (lavapipe), and the scene has not been played with a real GPU,
  keyboard or mouse.
- **Glow is off** in `content/look/space.json`: under lavapipe it lifted the black of
  space to navy. Try it on the Mac.
- **No gamepad bindings** for flight yet; keyboard and mouse only.
- **Balance is first-pass.** Tuned so the trace's AI-flown player wins with damage
  taken. A human will find it easier or harder; the numbers are all in JSON.
- **The 3D world on foot is still greybox**, as after M8 (unchanged by M10).

## After M8 (2026-10-25) -- superseded by the notes above.

**What is real and proven by tests:** everything in M1-M7, plus the M8 polish pass.
The vertical slice now hangs together in one playthrough
(`scenes/m8_playthrough.gd` / `test_results/m8_playthrough.txt`): walk + FPV/TPV toggle,
a trooper sealing to cover, the 4-trooper squad spreading, a timed-deflection duel with
the duelist, the mission loop to COMPLETE, a typed-default voice turn to the LLM
bartender, and a save/load round-trip of the four named things. A performance report
(`test_results/m8_perf_report.txt`) shows the worst frame under the 50ms budget across
the whole session. The GUT "1 orphan" artifact has been **cleared** (it was a
`queue_free` on a detached test node; now `free`). The suite is 0 orphans.

**Stubbed / deferred, honestly (the remaining polish):**
- **The 3-minute gameplay recording is the manual/recorded path**
  (`scripts/record.sh`, macOS screen capture; needs a display). The headless
  cross-system trace is its machine equivalent; this is the same posture as M6/M7.
- **Combat inputs are not yet bound to global input actions.** Fire / block / reload run
  the M2/M3 weapon + blade state machines in the playthrough, but they are not wired to
  on-screen inputs yet. The GUI input layer (and GUI feedback: hit flashes, blade swing,
  on-screen parry) is the remaining polish.
- **The visible 3D world is greybox; full geometry + rendered bolts/blades are
  outstanding.** World streaming is a load-cost model, not a rendered 3D walk (M4), and
  combat/movement are logic + traces, not rendered fights (M2/M3/M5).
- **Take-cover-against-marked-surfaces (movement)** remains deferred.
- **The bartender runs a scripted client in CI; live Ollama inference is the manual +
  recorded path.** Kokoro voice and the whisper STT are optional runtimes -- typed input
  is the dependency-free default.
- **Cloud LLM fallback** is an interface + stub only; no API key ever enters the client.

**Model risk (watch):** Qwen3 4B Q4 is the planned bartender model. If tool-calling
quality or speed on the dev machine is poor, the fallback is a 1-2B instruct model
that supports tool calls. Documented, not yet measured.

**Disk:** ~12 GB free at M0 start. A single 4B Q4 model is ~2.5 GB; fine; the full
windows export + model cache later will be watched.

**Headless proof limitation:** I can run the engine and capture logs/frames, but I
cannot open the GUI editor and "watch it on screen." The primary proof for each
milestone is the headless CI run + JUnit XML + a machine trace; a screen recording
(scripts/record.sh) is the secondary proof where the spec asks for one. `LAUNCH.md` is
the human-facing guide to running and recording the finished slice.

## After M7 (2026-10-25) -- superseded by the notes above.

**What is real and proven by tests:** everything in M1-M6, plus voice input on top of
the M6 bartender (M7). A push-to-talk routes a captured request to the same
`bartender.respond()`; **typed is the default and dependency-free path**, whisper is an
optional upgrade that degrades to typed when its runtime/model is absent; a captured
request is read but never executed as a command (no `TOOL=cut_power` in the trace); an
allowed tool still applies; and each turn records a latency.

**Stubbed / deferred, honestly:**
- **whisper.cpp + the STT model are not wired in CI.** The `whisper_runtime` is a
  stand-in that "loads" only when a model is set (mirroring M6's Ollama HTTP post);
  transcription in CI is a canned map. The real whisper run + mic capture is the manual
  + recorded path (scripts/record.sh), not a headless CI step, per DECISIONS.
- **Voice latency is measured from an injected clock**, not the real mic->transcribe
  wall time; real timing is the manual path.
- **Kokoro voice is a signature + graceful null in CI** (M6); a real recorded voice is
  M8.
- **World streaming is still a load-cost model, not a rendered 3D walk** (M8).
- **Combat/movement are logic + traces, not rendered fights** (M8).
- **Take-cover-against-marked-surfaces (movement)** remains deferred.
- **Cloud LLM fallback** is an interface + stub only; no API key ever enters the client.

**Known non-failing artifact:** GUT reports "1 orphan" at process exit (a detached
test bolt). It is a warning, not a test failure -- `ci.sh` exits 0 and "All tests
passed" shows. Tracked for M8 cleanup.

**Model risk (watch):** Qwen3 4B Q4 is the planned bartender model. If tool-calling
quality or speed on the dev machine is poor, the fallback is a 1-2B instruct model
that supports tool calls. Documented, not yet measured.

**Disk:** ~12 GB free at M0 start. A single 4B Q4 model is ~2.5 GB; M0 is fine; the
full windows export + model cache later will be watched.

**Headless proof limitation:** I can run the engine and capture logs/frames, but I
cannot open the GUI editor and "watch it on screen." The primary proof for each
milestone is the headless CI run + JUnit XML + a machine trace; a screen recording
(scripts/record.sh) is the secondary proof where the spec asks for one.

## After M6 (2026-10-25) -- superseded by the notes above.

**What is real and proven by tests:** movement + FPV/TPV toggle (M1), two blasters +
a covering trooper with health/death (M2), the energy blade with stamina, timed
deflection, and a duelist enemy (M3), chunk streaming with no >50ms frame-cost over
the port->desert walk plus a data-driven outpost (M4), the full mission loop
(fixer -> contract -> fight -> crate -> payout) with a save/load round-trip of the
four named things plus the 4-trooper squad coordinator (M5), and the bartender LLM
conversation (M6). Each milestone ships a headless trace or log plus GUT assertions.

**Stubbed / deferred, honestly:**
- **The bartender talks to a scripted client in CI, not a live model.** The
  conversation logic (read-but-never-execute text, 4-tool guardrails, fallback,
  memory) is the real thing and is proven headless; the model on the other end of the
  client is a canned stand-in. Live Ollama inference is a manual + recorded path
  (scripts/record.sh), not a headless CI step, per DECISIONS.
- **Kokoro voice is a signature + graceful null in CI.** The deterministic part
  (text+speaker -> signature) is proven; the audio render returns null when the TTS
  model is absent (headless). A real recorded voice is M8.
- **The Ollama HTTP post is a documented stub.** Request-building and
  response-parsing are live code tested on canned JSON; the actual `/api/chat` call is
  a TODO wiring step, not run in CI.
- **Voice-in (M7)** is not started; the bartender takes typed text only. M7 adds
  push-to-talk with measured latency.
- **World streaming is still a load-cost model, not a rendered 3D walk** (M8).
- **Combat/movement are logic + traces, not rendered fights** (M8).
- **Take-cover-against-marked-surfaces (movement)** remains deferred.
- **Cloud LLM fallback** is an interface + stub only; no API key ever enters the
  client. A backend proxy design is documented, not wired.

**Known non-failing artifact:** GUT reports "1 orphan" at process exit (a detached
test bolt). It is a warning, not a test failure -- `ci.sh` exits 0 and "All tests
passed" shows. Tracked for M8 cleanup.

**Model risk (watch):** Qwen3 4B Q4 is the planned bartender model. If tool-calling
quality or speed on the dev machine is poor, the fallback is a 1-2B instruct model
that supports tool calls. Documented, not yet measured.

**Disk:** ~12 GB free at M0 start. A single 4B Q4 model is ~2.5 GB; M0 is fine; the
full windows export + model cache later will be watched.

**Headless proof limitation:** I can run the engine and capture logs/frames, but I
cannot open the GUI editor and "watch it on screen." The primary proof for each
milestone is the headless CI run + JUnit XML + a machine trace; a screen recording
(scripts/record.sh) is the secondary proof where the spec asks for one.

## After M5 (2026-10-25) -- superseded by the notes above.

**What is real and proven by tests:** movement + FPV/TPV toggle (M1), two blasters +
a covering trooper with health/death (M2), the energy blade with stamina, timed
deflection, and a duelist enemy (M3), chunk streaming with no >50ms frame-cost over
the port->desert walk plus a data-driven outpost (M4), and the full mission loop
(fixer -> contract -> fight -> crate -> payout) with a save/load round-trip of the
four named things plus the 4-trooper squad coordinator (M5). Each milestone ships a
headless trace or log plus GUT assertions.

**Stubbed / deferred, honestly:**
- **The mission loop is a headless simulation, not a rendered fight or a live AI
  agent.** The bot feeds the state machine a fixed event sequence; the bartender
  conversation is a deterministic stub, not real inference. Real LLM inference (the
  bartender, M6) is a manual + recorded check.
- **World streaming is still a load-cost model, not a rendered 3D walk.** M4 proved
  the per-frame work stays under the 50ms budget and a walk crosses the boundary; the
  3D greybox and a recorded real frame time are M8.
- **Combat/movement are logic + traces, not rendered fights.** No visible bolts, no
  blade-swing animation, no on-screen parry feedback yet. M8 is the polish pass that
  adds the GUI rendering and the 3-minute recording.
- **Take-cover-against-marked-surfaces (movement)** remains deferred; free walking
  with a pose change and the squad coordinator are what exist so far.
- **Cloud LLM fallback** is an interface + stub only; no API key ever enters the
  client. A backend proxy design is documented, not wired.
- **Voice-in (M7)** may start as a measured latency stub before being made good.

**Known non-failing artifact:** GUT reports "1 orphan" at process exit (a detached
test bolt). It is a warning, not a test failure -- `ci.sh` exits 0 and "All tests
passed" shows. Tracked for M8 cleanup.

**Model risk (watch):** Qwen3 4B Q4 is the planned bartender model. If tool-calling
quality or speed on the dev machine is poor, the fallback is a 1-2B instruct model
that supports tool calls. Documented, not yet measured.

**Disk:** ~12 GB free on the volume at M0 start. A single 4B Q4 model is ~2.5 GB, so
M0 is fine; the full windows export + model cache later will be watched.

**Headless proof limitation:** I can run the engine and capture logs/frames, but I
cannot open the GUI editor and "watch it on screen." The primary proof for each
milestone is the headless CI run + JUnit XML + a machine trace; a screen recording
(scripts/record.sh) is the secondary proof where the spec asks for one.

## After M4 (2026-10-25) -- superseded by the notes above.

**What is real and proven by tests:** movement + FPV/TPV toggle (M1), two blasters + a
covering trooper with health/death (M2), the energy blade with stamina, timed deflection,
and a duelist enemy (M3), and chunk streaming with no >50ms frame-cost over the
port->desert walk plus a data-driven outpost (M4). Each milestone ships a headless trace
or log plus GUT assertions.

**Stubbed / deferred, honestly:**
- **World streaming is a load-cost model + frame-time log, not yet a rendered 3D walk.**
  M4 proves the chunk streamer's per-frame work never exceeds the 50ms budget and that a
  walk crosses the port/desert boundary to the outpost -- via a generated per-frame log
  read by a test, not a recorded rendered frame time. The 3D greybox and a recorded
  real frame time are M8.
- **Combat/movement are logic + traces, not rendered fights.** No visible bolts, no
  blade-swing animation, no on-screen parry feedback yet. M8 is the polish pass that
  adds the GUI rendering and the 3-minute recording.
- **Take-cover-against-marked-surfaces (movement)** was deferred; the squad "not all in
  the open" coordinator is still outstanding (note: M4 delivered streaming + the outpost,
  and M5 will carry the 4-trooper squad with the mission loop).
- **Bot playthrough (M5)** talks to a deterministic stub for the bartender; real LLM
  inference remains a manual + recorded check.
- **Cloud LLM fallback** is an interface + stub only; no API key ever enters the
  client. A backend proxy design is documented, not wired.
- **Voice-in (M7)** may start as a measured latency stub before being made good.

**Known non-failing artifact:** GUT reports "1 orphan" at process exit (a detached test
bolt). It is a warning, not a test failure -- `ci.sh` exits 0 and "All tests passed"
shows. Tracked for M8 cleanup.

**Model risk (watch):** Qwen3 4B Q4 is the planned bartender model. If tool-calling
quality or speed on the dev machine is poor, the fallback is a 1-2B instruct model that
supports tool calls. Documented, not yet measured.

**Disk:** ~12 GB free on the volume at M0 start. A single 4B Q4 model is ~2.5 GB, so
M0 is fine; the full windows export + model cache later will be watched.

**Headless proof limitation:** I can run the engine and capture logs/frames, but I
cannot open the GUI editor and "watch it on screen." The primary proof for each
milestone is the headless CI run + JUnit XML + a machine trace; a screen recording
(scripts/record.sh) is the secondary proof where the spec asks for one.

## After M0 (2026-10-25) -- superseded by the notes above.
