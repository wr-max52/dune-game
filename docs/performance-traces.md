# Repeatable performance traces

Issue #125 adds a repeatable route capture; it does not turn headless timing into a rendering benchmark or invent a target-hardware threshold.

## Capture the same routes

Run from the repository root. The trace scripts use the same physics-frame routes and warm up the scene before collecting samples.

Headless logic control (not a GPU measurement):

~~~sh
DUNE_PERF_OUT=res://test_results/m14-headless.json godot --headless --fixed-fps 60 --path . -s res://scenes/m14_flight_trace.gd
DUNE_PERF_OUT=res://test_results/planets-headless.json godot --headless --fixed-fps 60 --path . -s res://scenes/planets_trace.gd
~~~

Rendered route capture with the full look enabled (do not add --headless or --fixed-fps):

~~~sh
DUNE_PERF_VISUALS=1 DUNE_PERF_OUT=res://test_results/m14-rendered.json godot --path . -s res://scenes/m14_flight_trace.gd
DUNE_PERF_VISUALS=1 DUNE_PERF_OUT=res://test_results/planets-rendered.json DUNE_PERF_SCREENSHOT=res://test_results/stationary-hero.png godot --path . -s res://scenes/planets_trace.gd
~~~

The JSON reports nearest-rank frame-time p50/p95/p99/max, Godot process and physics-process CPU time distributions, per-phase frame-time summaries, scene-ready wall time, and terrain metrics when the scene exposes them. Terrain metrics include far patches visible/culled, queued terrain jobs, far-build and worker-wait wall time, and main-thread mesh creation/submission time. Mesh submission timing is CPU-side work; it is not GPU completion time. GPU frame time is recorded as null because these in-engine samples do not provide it.

The planets trace captures the same stationary opening frame when DUNE_PERF_SCREENSHOT is set. Save that image with the baseline and compare it after visual changes; the trace does not claim an automated perceptual image-diff.

## Comparing results

- Keep the same route, machine, driver, Godot version, warm-up, display resolution, and run conditions before and after a change.
- Compare headless JSON only with headless JSON. Use rendered captures for CPU/render submission and visual review; GPU time still requires an external GPU profiler.
- Record the GPU model and driver alongside rendered JSON when sharing results; the trace records OS and Godot version but does not guess hardware identity.
- Collect baseline and post-change files on the target machine before setting thresholds. A single constrained-runner result is not an acceptance threshold.
- scripts/ci.sh remains unchanged. Its headless 50 ms assertion is not evidence of rendered CPU/GPU performance.

No baseline values are committed by this change because this environment did not run Godot or the target hardware.
