# Round port: frame time against the square port (issue #237, part 5)

Same machine, same route, run back to back. The only change is the home planet's
`town_layout` (port_square at size 50, then port_round at size 67).

- Route: `scenes/planets_trace.gd` (#125's repeatable capture), rendered:
  `DUNE_PERF_VISUALS=1 DUNE_PERF_OUT=res://test_results/<name>.json godot --path . -s res://scenes/planets_trace.gd`
- It covers the port's opening frames, the take-off from the pit, the flight to
  Grit Station and its staged handoff (#121 / #162), and the flight home.
- Machine: Apple M5 Max (Metal 4), macOS 26.6, Godot 4.7.2, 120 Hz display (8.33 ms
  is the vsync floor). Both runs took about 120 s of wall time.

| frame time (ms)                 | port_square | port_round |
|---------------------------------|------------:|-----------:|
| all frames p50                  |        8.33 |       8.33 |
| all frames p99                  |        9.52 |      10.87 |
| all frames max                  |      146.05 |     142.56 |
| port to station p95             |        9.26 |      10.61 |
| port to station p99             |       10.00 |      11.11 |
| station p99 / max               | 9.09 / 132.98 | 9.09 / 35.59 |
| station to home p99 / max       | 6.94 / 41.65 | 9.09 / 12.76 |
| physics process p50 / p99       | 2.00 / 34.23 | 1.40 / 24.89 |

The median is unchanged and pinned to vsync. The round port costs about 1.3 ms at
p95 and p99 in the port phase (374 boxes against 182, and more people in the
market), still well under one 60 Hz frame. Spikes do not get worse. The headless
run of the same trace (logic only) flies to the station in the same 24.7 s and
stages the handoff the same way (`HANDOFF_STATION_STAGED=true`, ready in 29.5 ms).

Not covered: a rendered on-foot walk through the town. `scenes/m14_flight_trace.gd`
did not compile as an `-s` script on either layout (the NpcVoice autoload is not
registered yet when a `-s` script compiles), so it gave no numbers.

## With the fill: a quiet re-run of all three (2026-10-31)

The three layouts back to back, twice each, interleaved (square, round, round
with the fill, then again), with no other Godot running. Same machine and trace.
port_round here is part 5's (374 boxes); with the fill it is 454 boxes and nine
more people. Grit Station is the control: nothing here touches it.

| frame time (ms), run 1 / run 2  | port_square   | port_round    | round + fill  |
|---------------------------------|--------------:|--------------:|--------------:|
| all frames p50                  | 8.33 / 8.33   | 8.33 / 8.33   | 8.33 / 8.33   |
| all frames p99                  | 9.72 / 9.72   | 10.61 / 10.61 | 11.11 / 11.67 |
| port to station p95             | 9.72 / 9.52   | 10.42 / 10.42 | 11.11 / 11.11 |
| port to station p99             | 10.06 / 10.00 | 11.04 / 11.11 | 11.67 / 11.67 |
| port to station max             | 137.9 / 138.5 | 135.2 / 145.6 | 133.3 / 133.3 |
| station p99 (control)           | 9.09 / 8.44   | 8.35 / 9.09   | 9.09 / 9.09   |
| physics process p99             | 25.5 / 25.6   | 25.0 / 25.3   | 26.3 / 24.4   |

The fill costs about 0.7 ms at p95 and p99 in the port, on top of the round
port's 0.8 to 1 ms over the square one: under 2 ms in all, against a 16.7 ms
60 Hz frame. The median stays on vsync, spikes are no worse, and the control
does not move, so these differences are the town's. (Two earlier runs of the
fill, taken while ten other Godot processes were running, gave 12.1 and 13.3 ms
port p95; that was the machine, not the town.)
