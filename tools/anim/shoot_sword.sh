#!/usr/bin/env bash
# Render the energy sword's moves (and droids batted by it) to test_results/sword/:
# a contact sheet and a GIF per clip.
#   ./tools/anim/shoot_sword.sh                    # every clip
#   ./tools/anim/shoot_sword.sh clips=left,combo
set -euo pipefail
cd "$(dirname "$0")/../.."
GODOT_BIN="${GODOT_BIN:-godot}"
SIZE="${SIZE:-960x540}"
"$GODOT_BIN" --path . --fixed-fps 60 --resolution "$SIZE" -s res://tools/anim/shoot_sword.gd -- "$@"
for d in test_results/sword/*/; do
  clip="$(basename "$d")"
  # Frames are 60 fps; a GIF plays 50 at most (2 cs a frame), so drop one in six.
  ffmpeg -loglevel error -y -framerate 60 -i "$d%03d.png" \
    -vf "fps=50,scale=640:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4" \
    "test_results/sword/$clip.gif"
done
ls -1 test_results/sword/*.png test_results/sword/*.gif
