# Known Issues / Stubs / Fakes

Honest list of what is broken or faked. Updated every milestone.

## After M0 (2026-10-25)

**Nothing gameplay-faked yet.** The project currently has:
- a runtime data-layer loader,
- a test framework running headless,
- a CI gate that blocks on any failing test,
- the IP-neutrality guard.

No movement, no combat, no camera, no world streaming, no LLM, no voice, yet.
Each arrives at M1-M7.

**Planned stubs that will exist before they are real (declared now, not hidden):**
- **Bot playthrough (M5)** talks to a deterministic stub model for the bartender
  conversation; real LLM inference is a manual + recorded check. Stated in DECS.
- **Cloud LLM fallback** is an interface + stub only; no API key ever enters the
  client. A backend proxy design is documented, not wired.
- **Voice-in (M7)** whisper/VAD may start as a measured latency stub before being
  made "good."

**Model risk (watch):** Qwen3 4B Q4 is the planned bartender model. If tool-calling
quality or speed on the dev machine is poor, the fallback is a 1-2B instruct model
that supports tool calls. Documented, not yet measured.

**Disk:** ~12 GB free on the volume at M0 start. A single 4B Q4 model is ~2.5 GB,
so M0 is fine; the full windows export + model cache later will be watched.

**Headless proof limitation:** I can run the engine and capture logs/screenshots, but
I cannot open the GUI editor and "watch it on screen." The primary proof is the
headless CI run + JUnit XML; a screen recording is the secondary proof where the
spec asks for one.
