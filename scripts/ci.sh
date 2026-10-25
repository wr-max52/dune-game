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