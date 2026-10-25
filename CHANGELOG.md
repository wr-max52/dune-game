# Changelog

Plain English, newest on top. One entry per milestone.

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
