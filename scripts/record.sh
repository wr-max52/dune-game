#!/usr/bin/env bash
# Record a gameplay clip of the running scene to test_results/clip.mp4 using
# ffmpeg (macOS screen capture). Not active until M1. Usage: record.sh <seconds>
set -euo pipefail
SECS="${1:-10}"
WINID="$(/usr/sbin/ffmpeg -f avfoundation -list_devices true -i "" 2>&1 | grep -m1 "AVFoundation video devices" -A20 | grep -m1 -oE '\([0-9]+\): .*' | head -1 | cut -d' ' -f1 | tr -d '():')"
echo "record.sh: capturing ${SECS}s to test_results/clip.mp4"
mkdir -p test_results
ffmpeg -f avfoundation -i "${WINID}:none" -t "${SECS}" -pix_fmt yuv420p test_results/clip.mp4
echo "record.sh: wrote test_results/clip.mp4"
