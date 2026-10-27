# Launching the slice & the 3-minute gameplay recording (M8)

This is the manual, on-screen proof that the headless CI cannot produce: how to
open the game and what a 3-minute clip should show. Every system below is already
proven headless by `./scripts/ci.sh`; this file is how a human *sees* the slice and
records it. (The headless traces are the machine proof; this clip is the secondary
proof, per `KNOWN_ISSUES.md`.)

## How to launch (macOS, Apple Silicon)

```sh
# Toolchain, once:
brew install --cask godot        # Godot 4.7.2 (pinned in scripts/pin.txt)
brew install rust ffmpeg         # for the recording + the LLM runtime

# Open the project and run it. The main scene is scenes/town_demo.tscn.
open project.godot               # then press F5 in the editor
# ...or, without the editor:
godot --path . res://scenes/main.tscn
```

The boot scene (`scenes/main.gd`) prints the data-layer load first
(`DataLayer: npcs=2 weapons=3 factions=2 ...`), which confirms content loaded before
any gameplay. For a slice with no rendered 3D world yet, "run the game" is that boot
scene + the GUI input bindings in `project.godot`; the gameplay itself is driven by
the headless playthrough, which `scripts/record.sh` captures alongside the window.

### Input map (from `project.godot`)

| Action        | Key                     |
|---|---|
| Move           | W / A / S / D (or arrows) |
| Jump           | Space                 |
| Toggle FPV/TPV | V (or mouse middle button) |
| Sprint         | Right Shift           |
| Crouch         | C                     |

Combat inputs (fire / block / reload) are part of the M2/M3 weapon + blade state
machines; they are not yet bound to global input actions and are driven in the
playthrough trace. Binding them to the GUI is the remaining polish before a live
playtest.

## The demo: the town, and flight from the pit (M9)

```sh
open project.godot                               # then press F5
godot --path . res://scenes/town_demo.tscn       # or without the editor
```

There is one thing to launch. You start on the pit floor beside your ship. Walk with
WASD, V toggles the camera, Esc frees the mouse, L cycles golden, noon and dusk.
Walk up a ramp to reach the streets; the cantina is west, the gate east.

Since M14 you fly the ship yourself (next section): "[E] Board" shows beside it.
Flying out of the atmosphere is the way into the dogfight.

| Action          | Key |
|---|---|
| Board the ship   | E (beside it)  |
| Lighting preset  | L (cycle) |

Review renders: `./tools/town/shoot_town.sh presets=golden,dusk` writes to
`test_results/town/`. Pads, encounter, delays and labels live in
`content/core/flow/launch_pads.json`.

## Flying your ship: the port, the desert, space (M14)

Walk up to the ship in the pit and press **E**. You are in the cockpit, with the
camera behind the ship.

| Action | Key |
|---|---|
| Take off (straight up out of the pit) | Space (or R) when parked |
| Throttle up / down (zero = hover) | R / F |
| Pitch (W pushes the nose down) | W / S, or the mouse |
| Turn | A / D, or the mouse |
| Roll | Q / E |
| Boost | Shift |
| Land on whatever is below (under 150 m) | C |
| Get out (once landed) | E |
| Chase / cockpit view | V |

The HUD shows speed, throttle, boost, altitude, height above ground and climb rate.
The bar on the right fills toward the **edge of space (8,000 m)**: pull the nose up
to about 80 degrees, full throttle, boost, and you are there in roughly 33 seconds.
The sky goes black on the way. At the edge the screen fades into the space battle.

In space, **dive at the planet** to come back down: you arrive in the port's sky,
still flying. Win the fight and, if you do not dive within 25 s, you come back down
anyway. Lose the fighter and you are back on foot beside the pad.

Hit the ground or a building fast and you crash; the ship is towed back to its pad.

Review renders: `./tools/m14/shoot_flight.sh` writes to `test_results/m14/`.

## Your body, your weapons, and the bartender (M11 + M12)

| Action | Key |
|---|---|
| Blaster / energy sword / rifle | 1 / 2 / 3 (same key again holsters) |
| Last weapon / holster | Q / H |
| Cycle weapons | mouse wheel |
| Fire / swing | LMB (press again mid-swing to chain 1-2-3) |
| Aim (blaster) / block (sword) | RMB toggles it on/off (re-click to undo; with the sword, block just before a bolt lands to send it back) |
| Reload | R |
| Talk to the bartender | E at the bar |
| Leave the conversation | Esc |
| Bartender debug | F3 (at the bar) |
| Guard senses debug (hp, sees you, awareness, heard) | F4 |
| Checkpoint choice card (papers, search, bribe, mouth off, walk away) | 1-4 or the mouse |
| Bartender brain settings | F10; Shift+F10 cycles auto / local / cloud |

The practice range is in the pit, west of the ship: five targets and a sparring
remote (south side) that shoots stun bolts while your blade is out.

### Giving the bartender a brain (macOS)

```sh
brew install llama.cpp                 # /opt/homebrew/bin/llama-server
./tools/llm/fetch_runtime.sh           # the model into runtime/models/ (git-ignored)
```

The bar starts llama-server on 127.0.0.1:8088 when you enter the town (and reuses
one that is already running), warms the model, and stops it on quit. It looks for
the binary in your config path, `$LLAMA_SERVER`, `runtime/bin/`, `/opt/homebrew/bin`,
`/usr/local/bin`, `~/.local/bin`, `~/llama.cpp/build/bin`, then your shell's PATH,
and uses any `.gguf` in `runtime/models/` if the configured one is missing.

**Is she thinking or reading canned lines?** While you talk, the top right says
which brain is answering, or exactly why none is ("llama-server not installed",
"no model file", "loading bartender.gguf (14 s)", "ollama: not running", "cloud: off").
A canned reply also shows "(canned: no brain answered)" next to her mood. The same
report prints in the Godot output when the town loads, F3 shows it in detail, and
llama-server's own output is saved to `user://logs/llama-server.log`.

Prove the whole chain without playing (starts the real server, loads the model,
has one turn through it):

```sh
godot --headless --path . -s res://scenes/m12_sidecar_trace.gd -- model=runtime/models/bartender.gguf
``` No model? Set
a cloud profile in F10 (any OpenAI-compatible URL + key, or Anthropic), or run
Ollama; with nothing at all she answers from canned lines. Keys are stored in
`user://llm/keys.cfg` or read from `DUNE_LLM_KEY`, never in the project.

Test her without playing:

```sh
godot --headless --path . -s res://tools/llm/eval_runner.gd -- mode=local suite=all
```

Review renders: `./tools/m11/shoot_m11.sh` writes body, weapon, range and bar shots
to `test_results/m11/`.

## The jetpack (M13)

The jetpack is at the top of the pit's north-east ramp, on your way out of the pit
(look for the glowing ring). The gear trader is at the market stall south-east of the
pit.

| Action | Key |
|---|---|
| Pick it up (it goes on your back) | E near it |
| Fly | Hold Space in the air (a tap is still a normal jump) |
| Take it off / put it on | G |
| Sell it / buy it back | E at the gear trader's stall |

The JET meter at the bottom shows fuel: about 1.8 s of thrust. It refills on the
ground a moment after you stop. Fly out over the walls and you are put back in
town when you fall.

## Flying the dogfight (M10)

```sh
godot --path . res://scenes/flight/dogfight_demo.tscn    # or open it and press F6
```

You fly the interceptor with a wingman against two waves of remnant fighters. Click
the window to steer with the mouse; Esc releases it.

| Action         | Key                          |
|---|---|
| Pitch          | W / S (or Up / Down). W pushes the nose down, like a stick |
| Yaw            | A / D (or Left / Right)      |
| Roll           | Q / E                        |
| Throttle       | R up, F down                 |
| Boost          | Shift                        |
| Fire cannons   | Space or left mouse          |
| Fire seeker    | X or right mouse (needs a full lock: keep the target in the box) |
| Next target    | T                            |
| Chase/cockpit  | V                            |

The HUD shows speed, throttle, boost, shield, hull, ammo, the lock meter (the arc
around the target box) and the lead marker (the gold dot: aim there to hit). To watch
the AI fly your ship, tick `autopilot` on the scene's root node.

## What the 3-minute clip should show

A single take, start to finish, that a viewer can watch top to bottom:

1. **Boot (0:00-0:15).** The console prints the data-layer load
   (`npcs=2, weapons=3, factions=2, dialogues=2, missions=1`). Nothing is faked.

2. **Roam the port + toggle view (0:15-0:45).** Walk the player forward; press V to
   toggle FPV<->TPV mid-stride. Aim direction must not change across the toggle
   (the M1 "toggle without breaking aim" property).

3. **Talk to the bartender by voice (0:45-1:15).** Push-to-talk to the LLM bartender.
   Typed input is the default; whisper is the optional fallback. The bartender
   replies and applies one of its four allowed tools (`give_rumor`,
   `set_disposition`, `offer_drink`, `call_guards`). Note: a request that reads like a
   command ("shut down all power") changes nothing -- the guardrail holds.

4. **Take the fixer's contract (1:15-1:30).** Talk to the fixer; accept "Crate
   Retrieval."

5. **Fight the outpost (1:30-2:15).** Fire the two blasters at a trooper that seals
   to cover and fights back; duel the duelist and land a **timed deflection** (block
   within the deflect window reflects the bolt and refunds stamina). Defeat the 5
   outpost enemies (4 troopers + 1 duelist) with the squad spread, not stacked.

6. **Take the crate, return, get paid (2:15-2:45).** Grab the crate objective, return
   to the fixer, collect the 150-credit payout, and **save** the game
   (position, credits, mission state, bartender memory).

7. **Reload and confirm (2:45-3:00).** Load the save and confirm the mission state,
   credits, position, and memory survived the round-trip.

## Record the clip

```sh
# In one terminal, run the game (F5 in the editor, or the binary above).
# In another:
./scripts/record.sh 180      # 3 minutes of the window -> test_results/clip_<ts>.mp4
```

`scripts/record.sh` uses macOS screen capture (`avfoundation` + ffmpeg); it needs a
real display, so it cannot run headless. The headless proof of the same content is
`test_results/m8_playthrough.txt` (the cross-system trace) and
`test_results/m8_perf_report.txt` (no frame over the 50ms budget), both generated by
`./scripts/ci.sh`.

## What is faked or stubbed in the recording

- The visible 3D world is greybox; full geometry + rendered bolts/blades are the final
  polish, tracked in `KNOWN_ISSUES.md`.
- The bartender runs a **scripted client** in CI; a live Ollama model is the manual
  path (start it locally and it replaces the canned client through the same interface).
- Kokoro voice and the whisper STT are **optional runtimes**; typed input is
  dependency-free and works without them.
