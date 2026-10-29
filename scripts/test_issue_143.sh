#!/usr/bin/env bash
# Asset-free runtime checks for the process lifecycle and exact chirp methods.
# Does not import the game, load a model, or connect to a configured LLM endpoint.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT_BIN="${GODOT_BIN:-godot}"
command -v "$GODOT_BIN" >/dev/null
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
printf 'config_version=5\n[application]\nconfig/name="Sidecar regression %s"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n' "$(basename "$tmp")" > "$tmp/project.godot"
cp src/systems/llm/sidecar.gd "$tmp/sidecar.gd"
cp src/systems/llm/llm_service.gd "$tmp/service.txt"
cp src/systems/droids/droid_controller.gd "$tmp/controller.txt"
cp tests/regressions/issue_143_runtime.gd "$tmp/run.gd"
printf '#!/bin/sh\nexec sleep 30\n' > "$tmp/fake_sleep"
printf '#!/bin/sh\nexit 0\n' > "$tmp/fake_exit"
chmod +x "$tmp/fake_sleep" "$tmp/fake_exit"
"$GODOT_BIN" --headless --path "$tmp" --script res://run.gd 2>&1 | tee "$tmp/results.log"
if grep -Eq 'SCRIPT ERROR:|^ERROR:' "$tmp/results.log"; then
  echo "FAIL: Godot reported a runtime error, even if its process exited zero." >&2
  exit 1
fi
