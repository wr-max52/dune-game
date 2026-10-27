#!/usr/bin/env bash
# Render character part review sheets (tools/look/sheets/*.json) to test_results/parts/.
#
#   ./tools/look/shoot_sheet.sh                                 # every sheet
#   ./tools/look/shoot_sheet.sh tools/look/sheets/02_guard_parts.json
#
# macOS: real GPU (Metal), a window opens briefly per sheet.
set -euo pipefail
cd "$(dirname "$0")/../.."
GODOT_BIN="${GODOT_BIN:-godot}"
sheets=("$@")
[[ ${#sheets[@]} -eq 0 ]] && sheets=(tools/look/sheets/*.json)
for s in "${sheets[@]}"; do
  "$GODOT_BIN" --path . -s res://tools/look/shoot_sheet.gd -- "sheet=$s" 2>&1 | grep -E "sheet:|ERROR" || true
done
