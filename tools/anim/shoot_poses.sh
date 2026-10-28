#!/usr/bin/env bash
# Issue #87: render a contact sheet of the body poses to test_results/anim/poses.png.
#   ./tools/anim/shoot_poses.sh                       # the Remnant trooper
#   ./tools/anim/shoot_poses.sh archetype=player_smuggler
set -euo pipefail
cd "$(dirname "$0")/../.."
GODOT_BIN="${GODOT_BIN:-godot}"
"$GODOT_BIN" --path . --fixed-fps 60 --resolution 960x720 -s res://tools/anim/shoot_poses.gd -- "$@"
