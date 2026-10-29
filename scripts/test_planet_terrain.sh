#!/usr/bin/env bash
# Parse the real terrain dependency graph and exercise incremental collider jobs
# without importing the game's character models, textures, or audio.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT_BIN="${GODOT_BIN:-godot}"
command -v "$GODOT_BIN" >/dev/null
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
printf 'config_version=5\n[application]\nconfig/name="PlanetTerrain regression"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n' > "$tmp/project.godot"
files=(
  src/systems/look/planet_terrain.gd
  src/systems/look/desert_terrain.gd
  src/systems/look/look_environment.gd
  src/systems/planets/planet_sphere.gd
  src/systems/planets/asteroid_sphere.gd
  src/systems/look/shaders/sand.gdshader
  src/systems/look/shaders/moon_rock.gdshader
  src/systems/look/shaders/desert_sky.gdshader
  tests/regressions/planet_terrain_runtime.gd
)
for file in "${files[@]}"; do
  mkdir -p "$tmp/$(dirname "$file")"
  cp "$file" "$tmp/$file"
done
"$GODOT_BIN" --version
# Register the copied scripts' actual class names/bases without starting the
# editor or its asset importer. The runtime still parses each complete script.
mkdir -p "$tmp/.godot"
{
  printf 'list=[\n'
  separator=""
  for file in "${files[@]}"; do
    [[ "$file" == *.gd ]] || continue
    class="$(sed -n 's/^class_name //p' "$tmp/$file")"
    [[ -n "$class" ]] || continue
    base="$(sed -n 's/^extends //p' "$tmp/$file")"
    printf '%s{"base":"%s","class":"%s","icon":"","is_abstract":false,"is_tool":false,"language":"GDScript","path":"res://%s"}' "$separator" "$base" "$class" "$file"
    separator=$',\n'
  done
  printf '\n]\n'
} > "$tmp/.godot/global_script_class_cache.cfg"
"$GODOT_BIN" --headless --path "$tmp" --check-only --script res://src/systems/look/planet_terrain.gd 2>&1 | tee "$tmp/parse.log"
if grep -Eq 'SCRIPT ERROR:|^ERROR:' "$tmp/parse.log"; then
  echo "FAIL: production terrain script did not parse." >&2
  exit 1
fi
"$GODOT_BIN" --headless --path "$tmp" --script res://tests/regressions/planet_terrain_runtime.gd 2>&1 | tee "$tmp/results.log"
if grep -Eq 'SCRIPT ERROR:|^ERROR:' "$tmp/results.log"; then
  echo "FAIL: terrain runtime reported an error, even if Godot exited zero." >&2
  exit 1
fi
