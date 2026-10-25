#!/usr/bin/env bash
# Record the running game scene to an mp4 using macOS screen capture + ffmpeg.
# Usage: open the game in the GUI (F5 in the editor, or run the project binary),
# then in another terminal run:  ./scripts/record.sh [seconds]
#
# Headless mode cannot render a window, so this MUST run with a real display.
set -euo pipefail
SECS="${1:-15}"

DEVICE_NUM="$(/usr/sbin/avfoundation -list_devices 2>/dev/null \
  | sed -n '/AVFoundation video devices:/,/^$/p' | grep -oE '\([0-9]+\)' | head -1 | tr -d '()')"
DEVICE_NUM="${DEVICE_NUM:-0}"

OUT="test_results/clip_$(date +%s).mp4"
mkdir -p test_results

echo "record.sh: capturing ${SECS}s of window ${DEVICE_NUM} -> ${OUT}"
# :none = no audio capture.
ffmpeg -y -f avfoundation -i "${DEVICE_NUM}:none" \
  -t "${SECS}" -pix_fmt yuv420p -r 30 "${OUT}"
echo "record.sh: wrote ${OUT}"
