#!/usr/bin/env bash
# M0: headless CI gate. Runs the GUT suite + IP-neutrality scan without opening
# the editor. A failing test (or the IP scan) exits non-zero and blocks the merge.
# Run: ./scripts/ci.sh
set -euo pipefail

cd "$(dirname "$0")/.."

GODOT_BIN="${GODOT_BIN:-godot}"
if ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
  if [ -x /opt/homebrew/bin/godot ]; then GODOT_BIN=/opt/homebrew/bin/godot; fi
  if [ -x /usr/local/bin/godot ]; then GODOT_BIN=/usr/local/bin/godot; fi
fi
echo "CI: using $("$GODOT_BIN" --version 2>/dev/null || echo 'unknown godot')"

# Pin check: the engine must be the version we locked.
PIN="$(cat scripts/pin.txt)"
GODOT_VER="$("$GODOT_BIN" --version 2>/dev/null || true)"
echo "CI: pinned=$PIN  actual=$GODOT_VER"

# Register class_names (and import assets) first. On a fresh checkout without
# .godot/, GUT and the class_name scripts are unknown until this runs, and the
# suite would not start at all.
echo "CI: importing project..."
"$GODOT_BIN" --headless --path . --import >/dev/null 2>&1 || true

# M1: generate a headless bot-driven trace of the demo (movement + FPV/TPV toggle)
# before the test run so tests/test_m1_trace.gut.gd has something to check.
echo "CI: generating m1 bot trace..."
"$GODOT_BIN" --headless --path . -s res://scenes/m1_trace.gd >/dev/null 2>&1
if [ ! -f test_results/m1_trace.txt ]; then
  echo "CI: ERROR -- m1 trace was not generated" >&2
  exit 1
fi
echo "CI: m1 trace present ($(wc -l < test_results/m1_trace.txt) lines)"

# M2: generate the headless combat-integration trace so tests/test_m2_combat.gut.gd
# can check "the trooper seals to cover, both blasters work, health/death work".
echo "CI: generating m2 combat trace..."
"$GODOT_BIN" --headless --path . -s res://scenes/m2_combat_trace.gd >/dev/null 2>&1
if [ ! -f test_results/m2_combat_trace.txt ]; then
  echo "CI: ERROR -- m2 combat trace was not generated" >&2
  exit 1
fi
echo "CI: m2 trace present ($(wc -l < test_results/m2_combat_trace.txt) lines)"

# M3: generate the headless melee-duel trace so tests/test_m3_melee.gut.gd can
# check "the blade's timed-deflection works and a duelist parries it, and blows
# can still land and defeat the duelist."
echo "CI: generating m3 melee trace..."
"$GODOT_BIN" --headless --path . -s res://scenes/m3_melee_trace.gd >/dev/null 2>&1
if [ ! -f test_results/m3_melee_trace.txt ]; then
  echo "CI: ERROR -- m3 melee trace was not generated" >&2
  exit 1
fi
echo "CI: m3 trace present ($(wc -l < test_results/m3_melee_trace.txt) lines)"

# M4: generate the headless port->desert frame-time trace so
# tests/test_m4_streaming.gut.gd can read it and prove "no hitch over 50ms" and
# "seamless walk to the desert" from the actual log, not by assertion.
echo "CI: generating m4 frame-time trace..."
"$GODOT_BIN" --headless --path . -s res://scenes/m4_frame_trace.gd >/dev/null 2>&1
if [ ! -f test_results/m4_frame_time.txt ]; then
  echo "CI: ERROR -- m4 frame-time trace was not generated" >&2
  exit 1
fi
echo "CI: m4 frame-time trace present ($(wc -l < test_results/m4_frame_time.txt) lines)"

# M5: generate the headless bot playthrough trace so tests/test_bot_playthrough
# can check "fixer -> contract -> fight -> crate -> payout -> save/load close the
# loop end to end," and the squad coordinator keeps 4 troopers off the open.
echo "CI: generating m5 mission trace..."
"$GODOT_BIN" --headless --path . -s res://scenes/m5_mission_trace.gd >/dev/null 2>&1
if [ ! -f test_results/m5_mission_trace.txt ]; then
  echo "CI: ERROR -- m5 trace was not generated" >&2
  exit 1
fi
echo "CI: m5 trace present ($(wc -l < test_results/m5_mission_trace.txt) lines)"

# M6: generate the headless bartender conversation trace so
# tests/test_m6_dialogue.gut.gd can check "the npc's typed text is read but never
# executed as a command, an allowed tool applies, a disallowed tool is ignored,
# exhaustion routes to a fallback, and Kokoro gives a voice signature."
echo "CI: generating m6 dialogue trace..."
"$GODOT_BIN" --headless --path . -s res://scenes/m6_dialogue_trace.gd >/dev/null 2>&1
if [ ! -f test_results/m6_dialogue_trace.txt ]; then
  echo "CI: ERROR -- m6 trace was not generated" >&2
  exit 1
fi
echo "CI: m6 trace present ($(wc -l < test_results/m6_dialogue_trace.txt) lines)"

# M7: generate the headless voice-input trace so tests/test_m7_voice.gut.gd can
# check "typed is the default and dependency-free, a voice request degrades to
# typed when whisper is down, an allowed tool still applies through the voice
# path, a disallowed tool is ignored, and a latency is measured per turn."
echo "CI: generating m7 voice trace..."
"$GODOT_BIN" --headless --path . -s res://scenes/m7_voice_trace.gd >/dev/null 2>&1
if [ ! -f test_results/m7_voice_trace.txt ]; then
  echo "CI: ERROR -- m7 trace was not generated" >&2
  exit 1
fi
echo "CI: m7 trace present ($(wc -l < test_results/m7_voice_trace.txt) lines)"

# M8: generate the headless polish trace so tests/test_m8_polish.gut.gd can check
# "the whole slice hangs together in one playthrough with no frame over the 50ms
# budget": a cross-system run (walk + camera toggle, a trooper sealing, a deflection
# duel, the mission loop to COMPLETE, a typed voice turn, and a save round-trip) plus
# a performance report.
echo "CI: generating m8 playthrough + perf trace..."
"$GODOT_BIN" --headless --path . -s res://scenes/m8_playthrough.gd >/dev/null 2>&1
if [ ! -f test_results/m8_playthrough.txt ] || [ ! -f test_results/m8_perf_report.txt ]; then
  echo "CI: ERROR -- m8 trace was not generated" >&2
  exit 1
fi
echo "CI: m8 trace present (playthrough: $(wc -l < test_results/m8_playthrough.txt) lines, perf: $(wc -l < test_results/m8_perf_report.txt) lines)"

# M10: generate the headless dogfight trace so tests/test_m10_dogfight.gut.gd can
# check "the starfighter flies and fights, the encounter's waves are beaten, the
# enemy pilots fight back, and the AI pursues, attacks, breaks and extends."
echo "CI: generating m10 dogfight trace..."
"$GODOT_BIN" --headless --path . -s res://scenes/m10_dogfight_trace.gd >/dev/null 2>&1
if [ ! -f test_results/m10_dogfight_trace.txt ]; then
  echo "CI: ERROR -- m10 trace was not generated" >&2
  exit 1
fi
echo "CI: m10 trace present ($(wc -l < test_results/m10_dogfight_trace.txt) lines)"

# GUT headless run. -gdir points at tests; -gexit quits the process after the run.
# GUT quits with a non-zero exit code when any test asserts false, which makes
# `set -e` above turn a failing suite into a non-zero CI exit.
"$GODOT_BIN" --headless --path . \
  -s res://addons/gut/gut_cmdln.gd \
  -gdir=res://tests \
  -ginclude_subdirs=true \
  -gexit=true \
  -gjunit_xml_file=res://test_results/junit.xml

echo "CI: tests ran"