#!/usr/bin/env python3
"""Issue #104: bring the club playlists' tracks into the game.

Run: python3 tools/audio/rip_club.py [source dir]   (default ~/Desktop/Music/club; needs ffmpeg)

Download the tracks content/look/sound.json lists under club.playlists (each
entry's "source" page) into the source dir, under any name: Pixabay's downloads
end in the track's id (e.g. play_house-hakuna-matata-322660.mp3), which is how a
file finds its entry. A track with no id in its page (Free Music Archive) is
matched by its title words instead. Each is re-encoded like tools/audio/rip_music.sh
(160 kb/s MP3, one loudness) to the entry's stream path. Lists what is missing.
"""
import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else pathlib.Path.home() / "Desktop/Music/club").expanduser()


def key_of(entry):
    """The Pixabay id from the source page, or the file's title words."""
    m = re.search(r"-(\d{5,})/?$", entry.get("source", ""))
    if m:
        return m.group(1)
    return re.sub(r"^\d+_", "", pathlib.Path(entry["stream"]).stem).replace("_", "")


def main():
    cfg = json.loads((ROOT / "content/look/sound.json").read_text())
    files = [p for p in SRC.rglob("*") if p.suffix.lower() in (".mp3", ".wav", ".flac", ".ogg", ".m4a")]
    missing = []
    for playlist, entries in cfg["club"]["playlists"].items():
        for e in entries:
            key = key_of(e)
            hit = next((f for f in files if key in re.sub(r"[^a-z0-9]", "", f.stem.lower()) or key in f.stem), None)
            if hit is None:
                missing.append(f"{playlist}: {e['stream']}  <- {e.get('source', '')}")
                continue
            out = ROOT / e["stream"].replace("res://", "")
            out.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(hit), "-map_metadata", "-1",
                            "-af", "loudnorm=I=-18:TP=-1.5:LRA=11", "-ar", "44100", "-c:a", "libmp3lame", "-b:a", "160k",
                            str(out)], check=True)
            print(f"wrote {out.relative_to(ROOT)}  ({hit.name})")
    if missing:
        print("\nmissing (download these into %s):" % SRC)
        print("\n".join("  " + m for m in missing))
        sys.exit(1)


if __name__ == "__main__":
    main()
