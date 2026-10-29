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

## Starcruiser wreck (#93, wreck-only)

This standalone probe does **not** invoke CI or GUT:

```sh
godot --headless --path . -s res://tools/review/wreck_probe.gd
# Optional isolated terrain + wreck screenshots (needs a display):
godot --path . -s res://tools/review/wreck_probe.gd -- shots=/tmp/wreck
```

It checks the buried bow, raised stern and front-gate street sightline, the open breach,
a player-sized capsule route from the boarding plate onto the aft deck, matching
flight/physics surfaces, an actual flight-model landing, pointed fracture plates
and four segmented engine rims. Optional photos include the powered-off engines.
Screenshots omit
the town buildings/NPCs and are not a full gameplay or performance review.
