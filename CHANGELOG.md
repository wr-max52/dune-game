# Changelog

Plain English, newest on top. One entry per milestone.

## M4 — World streaming: port to desert, no hitch, outpost (2026-10-25)

What works now:
- A chunk streamer keeps a window of world chunks loaded around the player and
  AMORTIZES their load work across frames, so no single frame exceeds the frame-time
  budget. A naive "load the whole region now" loader would cost ~132ms at once and hitch;
  the streamer spreads that work so every frame stays under the 50ms ceiling from the spec.
- A headless frame-time log records the entire walk from the docking bay (x=0) through the
  port into the desert out to the outpost (x=1000). A GUT test reads that log and proves
  two properties from the actual numbers: (a) no frame's work exceeded 50ms, and (b) the
  walk travels the full distance, i.e. the port/desert boundary is crossed with no empty
  "loading" frame.
- The outpost is data in content/core (3 buildings, 1 crate objective, 4 troopers, 1
  duelist), loaded through the same IP-neutral data layer, and placed as a chunk at the far
  end of the desert.
- The data layer learned a new category, `locations`, so the outpost is swappable like
  everything else -- no code change to add a new location.

How to see it:
- `./scripts/ci.sh` writes test_results/m4_frame_time.txt and the GUT test reads it.
- The log's first line shows a ~36ms load spike at the bay (amortized under budget);
  the rest stay well under 18ms.

What is faked or stubbed:
- The world is a 1-D chunk strip in a simulation, not yet a 3D greybox you walk through
  on screen. The visible, streamed 3D desert with the outpost models rendered is part of
  the M8 polish pass. The streaming *behavior and its frame-cost* are the real thing,
  proven here in CI.
- The "no hitch over 50ms" is a load-work budget, not yet a measured GPU frame time of a
  real render. M8 will record real frame times with the model loaded.

What broke / fixed:
- A log parser that split on a single space produced empty fields (the log is space-
  padded); the parser now collapses whitespace runs.

What was needed from the user:
- None.

## M3 — Melee: energy blade, stamina, timed deflection, duelist enemy (2026-10-25)

What works now:
- The energy blade: light/heavy attacks and a block all draw from a stamina budget.
- Timed deflection is the core skill: a block pressed inside a tight window reflects
  an incoming bolt and refunds stamina; a block held too long only absorbs it, paying
  stamina. This is the "deflect when blocking with correct timing" from the spec.
- A duelist enemy presses the player, blocks, and parries using that same blade
  logic, so the duelist and the player fight on equal footing.
- A headless melee-duel trace shows a parry, a blow exchange, and the duelist brought
  DOWN; a GUT test asserts parries happened, blows landed, and a knockout occurred.

How to see it:
- `./scripts/ci.sh` generates the trace and runs the assertions.
- Read test_results/m3_melee_trace.txt for the duel log.

What is faked or stubbed:
- The trace is a simulated duel, not a rendered fight with animation. A visible
  blade-swing animation and on-screen parry feedback are part of the M8 polish pass.
- The duelist swing cadence in the trace is fixed.

What broke / fixed:
- A process-ordering bug in the blade: the recovery timer now runs before the frame's
  block drain, so reaching zero stamina correctly lands in BLOCKED_OUT (was: the same
  frame advanced the recovery to the point of missing the transition).
- Recovery action: M2 had been committed on its branch and not yet merged when M3 was
  branched, so M2 tests went missing on the active line. Fixed by merging M2 into main
  before building M3; the history now reads M0 -> M1 -> M2 -> M3 completely.

What was needed from the user:
- None.

## M2 — Ranged combat: two blasters + a covering trooper (2026-10-25)

What works now:
- Two ranged weapons from the data layer: a pistol blaster and a rifle blaster, with
  ammo drawdown, fire cooldown, recoil, and reload. The bolt travels as a visible
  projectile (in the GUI) that deals damage on contact.
- A trooper brain that seals to its nearest cover node and then suppresses the player,
  returning fire. A headless combat-integration trace records the whole arc: SEALING ->
  FIRING -> the trooper dying at 0 HP, while the player takes return fire and the
  return fire stops when the trooper dies.
- Health and death work for both sides.

How to see it:
- `./scripts/ci.sh` generates test_results/m2_combat_trace.txt and runs the assertions.

What is faked or stubbed:
- The combat trace is a simulation, not a rendered fight. On-screen hit feedback and
  bullet tracers are part of M8.
- The four-trooper squad coordinator (so they do not all stand in the open) is deferred
  to M5 with the mission loop; M2 brings a single covering trooper, as the spec asks.

What broke:
- Two blaster state-machine edge cases (idle recovery refunding an attack's cost; the
  deflect refund being capped at full stamina) were found and fixed so the numbers read
  correctly.

What was needed from the user:
- None.

## M1 — Movement + FPV/TPV camera toggle (2026-10-25)

What works now:
- Walk, sprint, crouch, and jump for the player, as pure, testable math.
- A camera rig that toggles between first-person and third-person on one key. The key
  requirement -- "toggle mid-combat without breaking aim" -- is that the toggle changes
  the camera position but not the look direction, which is proven by a test.
- A headless bot-driven trace proves the player moves and that the view toggles between
  FPV and TPV, without a rendered window.

How to see it:
- `./scripts/ci.sh` runs the trace and test_results/m1_trace.txt shows positions and
  view toggles.
- `scripts/record.sh` captures the live GUI (a rendered clip) for a human to watch;
  headless mode cannot render, so the trace is the machine proof.

What is faked or stubbed:
- No rendered clip was produced in CI because headless mode has no window. The human
  recording is available via record.sh; the machine trace stands in for it in CI.
- Take-cover-against-marked-surfaces (movement) is deferred to M4 with the world
  streaming; free walking with a pose change is what M1 proved.

What broke / fixed:
- A bare `godot --headless` run launches the project's main scene, which never quits, so
  the first CI run hung. Fixed by driving GUT through its CLI runner, which exits on its
  own.

What was needed from the user:
- None.

## M0 — Project setup (2026-10-25)

What works now:
- The repo exists on git from commit one, one feature per branch.
- Godot 4.7.2, Rust, and ffmpeg are installed locally; their versions are pinned
  and checked at the top of CI.
- A folder structure and a runtime-loaded data layer (`content/core`) are in place.
- The data-layer loader and the IP-neutrality guard are tested and passing.
- A headless CI script (`scripts/ci.sh`) runs the test suite and exits non-zero on
  failure, which is the merge gate.
- The README, this file, DECISIONS, and KNOWN_ISSUES live in the repo.

How to see it:
- Run `./scripts/ci.sh` -> it prints the GUT summary and exits 0.
- Open the editor and press F5 -> the console prints that the data layer loaded
  (npcs=2, weapons=3, factions=2).

What is faked or stubbed:
- Nothing gameplay-faked yet. There are no gameplay systems yet.

What broke:
- The first CI run hung because a bare `godot --headless` invocation runs the
  project's main scene, which never quits. Fixed by running GUT through its CLI
  runner, which quits on its own.

What was needed from the user:
- Approval to use NobodyWho's bundled TTS + STT instead of separate whisper.cpp.
- Approval to install the toolchain and download a small GGUF at M6.
- A neutral git identity.
- Confirmation the local CI script satisfies the headless-CI requirement.
