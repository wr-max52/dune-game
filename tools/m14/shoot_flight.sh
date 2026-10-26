#!/usr/bin/env bash
# Render the M14 flight review stills to test_results/m14/.
#
#   ./tools/m14/shoot_flight.sh                     # every shot, 1280x720
#   ./tools/m14/shoot_flight.sh shots=over_town,edge_7km
#
# macOS: real GPU (Metal); a window opens briefly.
# Linux without a display: xvfb + Mesa's software Vulkan (lavapipe). Slow but exact.
set -euo pipefail
cd "$(dirname "$0")/../.."
GODOT_BIN="${GODOT_BIN:-godot}"
SIZE="${SIZE:-1280x720}"
DRIVER="${DRIVER:-vulkan}"
ARGS=(--path . --fixed-fps 60 --resolution "$SIZE" -s res://tools/m14/shoot_flight.gd -- "$@")
if [[ "$(uname)" == "Linux" ]]; then
  if [[ -z "${DISPLAY:-}" ]]; then
    xvfb-run -a -s "-screen 0 ${SIZE}x24" "$GODOT_BIN" --rendering-driver "$DRIVER" "${ARGS[@]}"
  else
    "$GODOT_BIN" --rendering-driver "$DRIVER" "${ARGS[@]}"
  fi
else
  "$GODOT_BIN" "${ARGS[@]}"
fi
ls -1 test_results/m14/*.png
