# Desert Spaceport — Vertical Slice

The smallest playable build that proves the concept: a frontier desert spaceport
days after an empire collapses. Land, roam a port district, talk to locals, take a
contract into the desert, fight, return, get paid. One LLM-driven bartender.

This is a **vertical slice**, not the full game.

## Engine

- **Godot 4.7.2** (pinned in `scripts/pin.txt`; CI checks it).
- GDScript (no C#).
- Dev/target: macOS on Apple Silicon, 64 GB unified memory.
- Windows export kept possible but not tested.

## How to run (macOS, Apple Silicon)

```sh
# 1. Install the toolchain once (Homebrew)
brew install --cask godot
brew install rust ffmpeg

# 2. Open the editor and run, OR run headless tests
open project.godot            # in the Godot editor, F5

# 3. Run the headless test + CI gate (no editor needed)
./scripts/ci.sh
```

`./scripts/ci.sh` runs the full GUT suite and the IP-neutrality scan headless and
exits non-zero if anything fails. That non-zero exit is the merge gate.

## What exists now (M0)

- IP-neutral **data layer** (`content/core/`) loaded at runtime by `core_content.gd`.
- Every name/faction/weapon/dialogue lives in data files and is referenced by id.
- Tests for the data layer, the IP-neutrality guard, and the CI smoke path.
- Three living docs: `DECISIONS.md`, `CHANGELOG.md`, `KNOWN_ISSUES.md`.

No gameplay yet. M1 adds movement and the camera toggle.

## IP-neutrality rule

No franchise names in code, file names, class names, commit messages, or the data
layer. Generic terms only: "energy blade", "blaster", "imperial remnant", "trooper",
"smuggler". `tests/test_ip_neutral.gut.gd` fails the build if a banned term appears.

## Plan

`PLAN.md` holds the 8 milestones (M0-M8) in build order, with status and the
"done means" for each. M0-M4 are done; M5 is in progress.

## Layout

```
content/core/      the only place names/weapons/dialogue live (swappable)
src/systems/       gameplay + support systems (dataloader, player, combat, ai, ...)
scenes/            boot + level scenes
tests/             GUT tests + (M5) the headless bot playthrough
scripts/           ci.sh, record.sh, pin.txt
addons/            godot plugins (gut; nobodywho added at M6)
```

See `DECISIONS.md` for why each significant choice was made.
