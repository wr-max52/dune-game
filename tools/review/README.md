# Review probes

Scripts used for the senior dev review in `docs/review/REVIEW.html`. These aren't
part of CI; they reproduce the numbers marked [measured] in the review.

```sh
# Probe each system outside the happy path (prints PROBE lines)
godot --headless --path . -s res://tools/review/review_probe.gd

# Screenshot the M1 demo in FPV and TPV (needs a display; xvfb works on Linux)
xvfb-run -a godot --path . --rendering-driver opengl3 -s res://tools/review/review_shot.gd
```

The probe was written against the pre-fix code, so on this branch several of its
lines (camera determinant, spin, wall, bolt) now report the fixed behavior.
