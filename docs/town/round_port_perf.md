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
