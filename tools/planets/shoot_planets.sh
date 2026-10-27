#!/usr/bin/env bash
# Render the planet generator review stills (issue #45) to test_results/planets/.
#
#   ./tools/planets/shoot_planets.sh                     # every shot, 1280x720
#   ./tools/planets/shoot_planets.sh scenes=grit_station,style_snowy
#
# macOS: real GPU (Metal); a window opens briefly.
# Linux without a display: xvfb + Mesa's software Vulkan (lavapipe). Slow but exact.
set -euo pipefail
cd "$(dirname "$0")/../.."
GODOT_BIN="${GODOT_BIN:-godot}"
SIZE="${SIZE:-1280x720}"
DRIVER="${DRIVER:-vulkan}"
ARGS=(--path . --fixed-fps 60 --resolution "$SIZE" -s res://tools/planets/shoot_planets.gd -- "$@")
if [[ "$(uname)" == "Linux" ]]; then
  if [[ -z "${DISPLAY:-}" ]]; then
    xvfb-run -a -s "-screen 0 ${SIZE}x24" "$GODOT_BIN" --rendering-driver "$DRIVER" "${ARGS[@]}"
  else
    "$GODOT_BIN" --rendering-driver "$DRIVER" "${ARGS[@]}"
  fi
else
  "$GODOT_BIN" "${ARGS[@]}"
fi
ls -1 test_results/planets/*.png
