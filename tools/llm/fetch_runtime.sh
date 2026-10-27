#!/usr/bin/env bash
# Get the cantina owner's local brain (M12): checks for llama-server and downloads the
# model into runtime/models/cantina_owner.gguf (git-ignored).
#
#   ./tools/llm/fetch_runtime.sh            # the default (30B-class MoE, ~18 GB)
#   MODEL=small ./tools/llm/fetch_runtime.sh   # a 4B model (~2.5 GB) for quick tests
#   MODEL_URL=https://.../any.gguf ./tools/llm/fetch_runtime.sh
#
# Model choice is config, not code: the bake-off (docs/cantina_owner/CANTINA_OWNER_PLAN.md,
# section 8) decides. These URLs were current when written; check for newer
# releases before the bake-off, since this moves monthly.
set -euo pipefail
cd "$(dirname "$0")/../.."

case "${MODEL:-default}" in
  small) URL_DEFAULT="https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/main/Qwen3-4B-Instruct-2507-Q4_K_M.gguf" ;;
  *)     URL_DEFAULT="https://huggingface.co/unsloth/Qwen3-30B-A3B-Instruct-2507-GGUF/resolve/main/Qwen3-30B-A3B-Instruct-2507-Q4_K_M.gguf" ;;
esac
URL="${MODEL_URL:-$URL_DEFAULT}"
OUT="runtime/models/cantina_owner.gguf"

if command -v llama-server >/dev/null 2>&1; then
  echo "fetch_runtime: llama-server found at $(command -v llama-server)"
elif [ -x /opt/homebrew/bin/llama-server ]; then
  echo "fetch_runtime: llama-server found at /opt/homebrew/bin/llama-server"
else
  echo "fetch_runtime: llama-server not found. On macOS: brew install llama.cpp" >&2
  echo "  (then set profiles.local.sidecar.bin in user://llm_config.json if it is not /opt/homebrew/bin/llama-server)" >&2
fi

mkdir -p runtime/models
if [ -f "$OUT" ] && [ -z "${FORCE:-}" ]; then
  echo "fetch_runtime: $OUT already exists (FORCE=1 to replace)"
else
  echo "fetch_runtime: downloading $URL"
  curl -L --fail --progress-bar -o "$OUT.part" "$URL"
  mv "$OUT.part" "$OUT"
fi
SHA="$(shasum -a 256 "$OUT" 2>/dev/null || sha256sum "$OUT")"
echo "$URL ${SHA%% *}" > runtime/model_pin.txt
echo "fetch_runtime: ready. sha256 ${SHA%% *} (recorded in runtime/model_pin.txt)"
echo "Run the game (the bar starts llama-server on 127.0.0.1:8088), or test it:"
echo "  godot --headless --path . -s res://tools/llm/eval_runner.gd -- mode=local suite=all"
