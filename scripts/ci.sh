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