#!/usr/bin/env bash
# Render the port town review shots (content/look/town_shots.json) to test_results/town/.
#
#   ./tools/town/shoot_town.sh                      # all presets, all shots, 1600x900
#   ./tools/town/shoot_town.sh presets=golden shots=hero_vista frames=30
#
# macOS: uses the real GPU with Godot's default driver (Metal); a window opens briefly.
# Linux without a display: xvfb + Mesa's software Vulkan (lavapipe). Slow but exact.
set -euo pipefail
cd "$(dirname "$0")/../.."

GODOT_BIN="${GODOT_BIN:-godot}"
SIZE="${SIZE:-1600x900}"
ARGS=(--path . --resolution "$SIZE" -s res://tools/town/shoot_town.gd -- "$@")

if [[ "$(uname)" == "Linux" ]]; then
  if [[ -z "${DISPLAY:-}" ]]; then
    xvfb-run -a -s "-screen 0 ${SIZE}x24" "$GODOT_BIN" --rendering-driver vulkan "${ARGS[@]}"
  else
    "$GODOT_BIN" --rendering-driver vulkan "${ARGS[@]}"
  fi
else
  "$GODOT_BIN" "${ARGS[@]}"
fi
ls -1 test_results/town/*.png
