# Known Issues / Stubs / Fakes

Honest list of what is broken or faked. Updated every milestone.

## After M3 (2026-10-25)

**What is real and proven by tests:** movement + FPV/TPV toggle (M1), two blasters + a
covering trooper with health/death (M2), and the energy blade with stamina, timed
deflection, and a duelist enemy (M3). Each milestone ships a headless trace plus GUT
assertions.

**Known non-failing artifact:** GUT reports "1 orphan" at process exit (a detached test
bolt). It is a warning, not a test failure -- `ci.sh` exits 0 and "All tests passed"
shows. It is a headless test-harness detail (a bolt created without a scene tree is freed
at exit), not a gameplay bug. Will be cleaned up in M8.

**What is still stubbed / deferred:**
- **Combat/movement are logic + traces, not rendered fights.** No visible bolts, no
  blade-swing animation, no on-screen parry feedback yet. M8 is the polish pass that
  adds the GUI rendering and the 3-minute recording.
- **Take-cover-against-marked-surfaces (movement)** and the **four-trooper squad
  coordinator** (so troops do not all stand in the open) are deferred to M4/M5 with the
  world streaming and mission loop.
- **Bot playthrough (M5)** talks to a deterministic stub for the bartender; real LLM
  inference remains a manual + recorded check.
- **Cloud LLM fallback** is an interface + stub only; no API key ever enters the
  client. A backend proxy design is documented, not wired.
- **Voice-in (M7)** may start as a measured latency stub before being made good.

**Model risk (watch):** Qwen3 4B Q4 is the planned bartender model. If tool-calling
quality or speed on the dev machine is poor, the fallback is a 1-2B instruct model that
supports tool calls. Documented, not yet measured.

**Disk:** ~12 GB free on the volume at M0 start. A single 4B Q4 model is ~2.5 GB, so
M0 is fine; the full windows export + model cache later will be watched.

**Headless proof limitation:** I can run the engine and capture logs/frames, but I
cannot open the GUI editor and "watch it on screen." The primary proof for each
milestone is the headless CI run + JUnit XML + a machine trace; a screen recording
(scripts/record.sh) is the secondary proof where the spec asks for one.

## After M0 (2026-10-25) -- superseded by M1-M3 notes above.
