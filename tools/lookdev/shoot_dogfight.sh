#!/usr/bin/env bash
# Render review stills of the M10 dogfight to test_results/lookdev/flight/.
#
#   ./tools/lookdev/shoot_dogfight.sh                  # lineup + fight at 6s, 14s, 24s
#   ./tools/lookdev/shoot_dogfight.sh times=5,30 frames=20
#
# macOS: real GPU (Metal); a window opens briefly.
# Linux without a display: xvfb + Mesa's software Vulkan (lavapipe). Slow but exact.
set -euo pipefail
cd "$(dirname "$0")/../.."

GODOT_BIN="${GODOT_BIN:-godot}"
SIZE="${SIZE:-1280x720}"
ARGS=(--path . --resolution "$SIZE" -s res://tools/lookdev/shoot_dogfight.gd -- "$@")

if [[ "$(uname)" == "Linux" ]]; then
  if [[ -z "${DISPLAY:-}" ]]; then
    xvfb-run -a -s "-screen 0 ${SIZE}x24" "$GODOT_BIN" --rendering-driver vulkan "${ARGS[@]}"
  else
    "$GODOT_BIN" --rendering-driver vulkan "${ARGS[@]}"
  fi
else
  "$GODOT_BIN" "${ARGS[@]}"
fi
ls -1 test_results/lookdev/flight/*.png
