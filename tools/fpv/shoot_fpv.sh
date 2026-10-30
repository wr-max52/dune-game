#!/usr/bin/env bash
# Render the M11/M12 review shots (player body, weapons, range, bar) to
# test_results/fpv_arms/. Same driver setup as tools/town/shoot_town.sh.
#   ./tools/m11/shoot_m11.sh                 # every shot
#   ./tools/m11/shoot_m11.sh shots=fpv_pistol,tpv_sword_swing
set -euo pipefail
cd "$(dirname "$0")/../.."
GODOT_BIN="${GODOT_BIN:-godot}"
SIZE="${SIZE:-1280x720}"
DRIVER="${DRIVER:-vulkan}"
ARGS=(--path . --fixed-fps 60 --resolution "$SIZE" -s res://tools/fpv/shoot_fpv.gd -- "$@")
if [[ "$(uname)" == "Linux" ]]; then
  if [[ -z "${DISPLAY:-}" ]]; then
    xvfb-run -a -s "-screen 0 ${SIZE}x24" "$GODOT_BIN" --rendering-driver "$DRIVER" "${ARGS[@]}"
  else
    "$GODOT_BIN" --rendering-driver "$DRIVER" "${ARGS[@]}"
  fi
else
  "$GODOT_BIN" "${ARGS[@]}"
fi
ls -1 test_results/fpv/*.png 2>/dev/null || true
