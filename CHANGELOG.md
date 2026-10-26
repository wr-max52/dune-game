# Changelog

Plain English, newest on top. One entry per milestone.

## M15 part 2 — Combat NPCs at the gate (2026-10-26)

What works now:
- **The gate guards walk.** Each has a loop by its post (in the town data). They
  pause, glance around, turn toward footsteps or a shot, and come back.
- **The checkpoint reads your standing with the Remnant.** 40 and up: "Move
  along." 0 to 39: papers, or a 10 cr bribe. Below 0: papers and a search (you are
  held still for 3 s), or a 25 cr bribe. -40 and below: "Halt!", then they open
  fire. After dark, bribes work one band lower: a wanted face can buy its way
  through for 40 cr, and the search bribe drops to 10. A drawn weapon close by, or
  gunfire in the street, makes it one band worse.
- **A choice card** (keys 1-4 or the mouse): show papers, submit to a search,
  bribe (greyed out if you cannot pay), mouth off (papers becomes a search; twice is
  a fight), or walk away (fine, but walking through the gate anyway gets one
  warning, then shots). What the guard says shows over its head and as a subtitle.
- **They fight like soldiers.** When the warning runs out, they fire an opening
  burst, then each sprints to its own cover (the two new barricades inside the
  gate, the walls, the tower, the stalls), crouches, stands, fires 3 to 5 bolts,
  and ducks again. They only shoot what they can see, miss more at range and at a
  moving target, hide longer when hurt, and never hit each other. Shoot one, even
  after being waved through, and both are on you.
- **You can be hurt now.** 100 health, back on its own after 4 s without a hit, a
  bar bottom left while hurt. At zero you are knocked out and wake up in the pit,
  20% lighter in credits, and the guards stand down.
- **Three ways out of a fight.** Win (both down: standing drops 40, the checkpoint
  is gone, Oda talks about it). Run (out of sight and 70 m off: they search near the
  gate, give up, and remember your face for 5 minutes). Or lose (the pit).
- **The world remembers.** Bribes, fights, dead guards and flights all land in
  WorldState, with three new rumors for the bartender.

How to see it:
- Run the town and walk to the gate (default standing is -10: you get searched).
  F4 still shows each guard's senses. Pull a gun near them, or fire one off first.
- `./scripts/ci.sh` writes `test_results/combat_trace.txt` (15 scenarios, each in a
  fresh town) and runs `test_combat_trace`, `test_checkpoint` and `test_guard_brain`.
  Review stills: `docs/npc/look/`.
## N1 — Sci-fi naming system, issue #15 (2026-10-26)

What works now:
- **Everything that spawns gets a name.** The gate guards ("Corporal L. Raske"),
  the space fight's pilots with callsigns ('"Wasp" Lieutenant Selma Sakete'), your
  ship ("Woeful Refrain"), the jetpack's make and model ("Embry XR-76 Skylark"), the
  town ("Quartzspring") and its planet ("Namlunyn").
- **One engine, no LLM.** A library of about 2,300 original terms, four "tongues"
  that build new words syllable by syllable, and a small template grammar per kind
  of name (people by culture, callsigns, ships, equipment, makers, towns, planets,
  moons, stars). Same world seed, same names, every time.
- **Unique across the game.** Every new name is checked against all the names
  already given out, and the authored ones, before it is saved. The bartender's own
  name is reserved. The book is saved with the game.
- **You see them.** A guard's name floats over them when you walk up. A place card
  shows the town and planet when you arrive. The flight HUD and board prompt name
  your ship, and "Leaving Namlunyn..." shows at the edge of space. The space
  banner names the planet below, a kill calls out who you shot down, and the trade
  prompts show the jetpack's model.
- **The bartender knows them.** Her briefing names the town, the planet and the
  people in town, so she uses the same names.

How to see it:
- Run the town: the place card is the first thing on screen. Walk up to a gate
  guard, or press E at the ship.
- `./scripts/ci.sh` writes `test_results/names_trace.txt`. It covers:
  - names in the real scenes;
  - a save and reload keeping them;
  - a new game with the same seed giving the same names, and another seed
    different ones;
  - two sorties of named pilots;
  - 5,000 people named with no repeats.
- `docs/names/NAMING.md`: how it works and how to add words, cultures and kinds.
- 498 GUT tests (496 pass, 2 need a local model and skip, as before).

What is faked or outstanding:
- Only the gate guards, the pilots, your ship, the jetpack, the town and the
  planet are hooked in. The fixer has a naming block, but its scene has no place
  to show it yet. Weapons are not named.
- English-only library, three human cultures. No aliens yet.

## M15 part 1 — Guards on foot: body, pathing, senses (2026-10-26)

What works now:
- **The two gate guards are real bodies, not statues.** They stand on the same
  movement code as the player (the same controller, capsule and collision), so a
  guard can never walk faster, climb higher or clip through anything you cannot.
  They block you, bolts hit them, they flinch, and after 60 hp they drop (a fallen
  guard no longer blocks shots or sight). Every number is in
  `content/core/soldiers/gate_guard.json`.
- **They can walk anywhere in town.** The navmesh is baked when the town loads,
  from the same box data as the collision (move a wall in the data and the guards
  path around it), on a worker thread so it never costs a frame. Buildings and
  crates are cleared (no walkable floor inside a closed box), and the step height
  matches what the capsule can really climb. In the trace a guard runs a patrol,
  165 m to the cantina and back, and down into the pit and back up, with no stuck
  events.
- **They see and hear.** A 120 degree, 32 m view cone, a line-of-sight ray about
  five times a second (only while you are in the cone), and an awareness meter that
  fills faster up close and if you hold a weapon, slower if you crouch (crouched,
  you vanish past about 19 m). Right behind them inside 2.5 m they feel you. The
  watchtower and walls block their view. They hear a blaster shot within about
  45 m and know where it came from, but not who fired. They forget you 8 s after
  losing sight. Their heads turn to follow what they see.
- **F4** shows a line over each guard: hp, what it is doing, whether it sees you,
  its awareness and NOTICED / heard.

What they do not do yet: anything about it. No challenge, no hostility, no
shooting back. That is part 2 (the guard brain); see `docs/npc/GUARD_PLAN.md`.

How to see it:
- Run the town, walk to the gate, press F4. Stand in front of a guard, then step
  behind the watchtower, crouch, draw a gun, fire one off.
- `./scripts/ci.sh` writes `test_results/npc_trace.txt` (the whole run above with
  real physics) and runs `test_npc_trace`, `test_perception`, `test_npc_locomotion`
  and `test_town_nav`. Review stills: `docs/npc/look/`.

## M14 — Fly your ship from the port to space and back (2026-10-26)

What works now:
- **The ship in the pit is yours to fly.** Walk up to it and press **E** to climb
  in (the old "[E] Launch" straight to space is gone). **Space** lifts it straight up
  out of the pit; it hovers until you throttle up with **R**. Fly with the dogfight
  keys (W/S pitch, A/D turn, Q/E roll, R/F throttle, Shift boost, mouse to steer, V
  for the cockpit view).
- **The desert is the sky's floor.** The ship flies over the seamless desert (the
  same sand you walk on), and its mesas and hoodoos are solid: land on a mesa top or
  fly into one. The M5 outpost's buildings stand 3 km out as placeholders. Past the
  desert's 6 km edge the planet's surface carries on and curves away below you. Fly
  low over the dunes or high over the town, like a plane in an open-world game.
- **Land anywhere, get out anywhere.** Below 150 m, **C** lands on whatever is
  under you (street, roof, mesa top or dune) inside the desert. Once down, **E** gets
  you out beside the ship onto ground that was built under you while you came in. The parked ship is solid; walk up and **E** to get back in.
- **Crashes.** Hit the ground or a building fast and the ship crashes; it is towed
  back to its pad and you stand beside it.
- **Up through the atmosphere.** The air thins as you climb: the ship gets faster
  (up to 4x at the top), the sky darkens to black, the clouds and haze go, stars come
  out, and the planet curves away below. A bar on the right fills toward the
  **edge of space at 8,000 m**. Nose up at full throttle it takes **about 33 s with
  boost, 39 s without**, from lift-off.
- **Into the space battle.** Crossing the edge fades into the pad's encounter (the
  M10 orbital skirmish).
- **And back down.** In space, dive at the planet whenever you like and you come out
  in the port's sky at 5 km, still flying, pointed at the town. Win the fight and you
  get 25 s to dive yourself before re-entry happens anyway. Lose your fighter and
  you limp home to the pad on foot, as before.
- **A flight HUD:** speed (m/s and km/h), throttle, boost, altitude, height above
  ground, climb rate, state, and the space bar.

How to see it:
- Run the town, walk to the ship, E, Space, R, then pull back. Controls are in
  `LAUNCH.md`. Review stills are in `docs/m14/` (`./tools/m14/shoot_flight.sh`).
- `./scripts/ci.sh` writes `test_results/m14_flight_trace.txt`: the whole loop with
  real physics and the real scenes. Board, lift off (3.6 s), reach space in
  33.3 s, hand off to the space scene, dive back, arrive flying at 5.2 km, reach the
  port in 32 s, fly a 2.8 km circuit past the outpost and over the hoodoos, land in
  the dunes 840 m out, get out with no hitch (the walkable ground was ready), walk
  19 m on the sand, crash into a mesa, get towed home, land on the pad. Worst frame
  39 ms (one frame, the physics step as you step out; budget 50).
- 438 GUT tests (436 pass, 2 need a local model and skip, as before).

What is faked or outstanding:
- Built on the seamless desert (PR #17): its `DesertTerrain` gained `prefetch()`, so
  the walkable collider can be built ahead of a landing ship. Its collider stops
  following you while you fly. Main's desert-walk trace now lets you settle for a
  moment at the gate before checking you are on the floor (a collider re-centre can
  hop you a few cm; see KNOWN_ISSUES).
- The ship is still the stand-in model; no landing gear, no engine sound, no
  contrails or heat on the climb.
- Landmarks are placeholder shapes (cylinders and boxes); the outpost has no
  enemies or mission hooked up yet; no other ships or traffic in the sky.
- No ship weapons in the atmosphere (they fire in space only).
- Ships rest level wherever they land, even on a slope.
- The ship's position is not saved: a new session starts with it on the pad.
- The world is one desert around one port. Going to space and back always uses the
  same encounter and the same re-entry point.
## Seamless desert: the town sits on the dunes (2026-10-26)

What works now:
- **Walk out of the gate into the desert.** The town no longer floats in the sky.
  It sits on the same dune terrain as the beauty corner, at its own floor level:
  the paving runs straight into packed sand at the gate and the back gap, there is
  flat sand outside every wall, and about 30 m out the sand starts to swell into
  open dunes (fully dunes by about 300 m out).
- **The desert goes on.** The ground's collider follows you and rebuilds a little
  each frame (at most about 2 ms), so you can keep walking. The trace walks 700 m out
  and back with real physics, the collider re-centring under you on the way, with
  the worst frame well under the 50 ms budget. The visible terrain reaches about 6 km, with fog at
  the edge.
- **The pit is still a pit.** The ground dips under the landing pit, so the ship
  bay, its ramps and the launch pad work exactly as before.
- **Something to walk to.** Mesas on the horizon, hoodoos 300 m to 1 km out (solid,
  so you can walk up to them) and a few hundred boulders, all from
  `content/look/desert_landforms.json` (the same recipes as the beauty corner).
  The camera now sees 12 km.
- **The jetpack lands you on sand.** Flying out over a wall now sets you down on the
  sand outside. The fall guard still catches a fall through the world, measured
  from the ground under you (the old rule, "20 m under the town's lowest floor",
  would have yanked you home from any dune trough).
- **Review shots:** `gate_to_desert`, `desert_look_back`, `north_wall_outside`,
  `desert_aerial` in `content/look/town_shots.json`; golden-hour renders in
  `docs/town/look/desert/`.

How to see it: F5, walk up the ramp, head east through the gate and keep going.
`with_desert = false` on the town scene gives the old town in the void.

Proof: `scenes/desert_walk_trace.gd` (in `scripts/ci.sh`) +
`tests/test_desert_walk.gut.gd`, and `tests/test_desert_terrain.gut.gd` (the site
footprint from town data, nothing poking through the paving, the dip under the pit
for both mesh and collider, the follow-and-rebuild budget, teleports, landforms
clear of the town, the fall guard). The beauty corner's terrain is unchanged
(checked bit for bit against main over 20,000 points).

## M13 — Jetpack (issue #5) (2026-10-26)

What works now:
- **A jetpack you can find.** It sits glowing at the top of the pit's north-east
  ramp, on your way out of the pit. Walk up, press E: it is yours, and it goes
  straight onto your back.
- **Hold jump to fly.** A tap of Space is still the normal jump. Hold it and, after a
  fraction of a second in the air, the pack lights: flames out of both nozzles and a
  climb of about 17 m on a full tank (a normal jump is 0.6 m), with air control the
  whole way. Let go and you fall.
- **Fuel that recharges.** A JET meter at the bottom of the screen shows the tank:
  1.8 seconds of thrust. It refills on the ground, starting 0.8 s after you stop
  burning (about 3 s from empty). It does not refill in the air, so you cannot
  hover forever.
- **Attach, detach.** G takes the pack off (it stays in your inventory; you jump
  normally) and puts it back on.
- **Sell it, buy it back.** The gear trader at the market (the stall at `vendor_2`)
  buys gear at half its value: E sells the jetpack for 60 credits. The trader keeps
  it and sells it back for 120; if you are short, the prompt says what you have.
  Sales and purchases go into the world's event log, so the bartender's world knows.
- **Saved.** What you own, what you wear, which pickups you took and what the trader
  holds are saved with the world (inside the existing save, no version change). Come
  back from a dogfight or reload and the pack is still on your back, and the one in
  the street is still gone.
- **Flying out of town is caught.** The pack clears the 6 m walls, and there is no
  ground outside them. Fall 20 m below the lowest floor and you are put back where
  you last stood.
- **Any item, any design, from data.** Items, vendors and pickups are new data
  categories; the look is `content/look/items.json` (a stand-in today, or any
  `.glb`/`.tscn` through `scene`). `docs/ADDING_ITEMS.md` explains every field.

How to see it:
- Run the town (`scenes/town_demo.tscn`), walk up the ramp, E, then hold Space.
  Controls are in `LAUNCH.md`. Review stills are in `docs/m13/`
  (`./tools/m13/shoot_jetpack.sh` re-renders them).
- `./scripts/ci.sh` writes `test_results/m13_jetpack_trace.txt`: the bot walks out
  of the pit to the pack, picks it up, flies 17.3 m, runs the tank dry, recharges,
  detaches and reattaches, flies out over the north wall and is caught, sells for
  60, buys back for 120, and reloads with the pickup still taken. Worst frame 6.7 ms.
- 381 GUT tests pass (was 335), including a test that adds a new pack, vendor and
  pickup from JSON alone and trades with them.

What is faked or outstanding:
- The pack is a primitive stand-in (two tanks on a plate); the `scene` hook is
  ready for a real model.
- No thruster sound, no dust or heat haze, no flight pose (the body uses its
  airborne pose).
- No fall damage (the player has no health yet), so a 17 m drop costs nothing.
- One pack, one trader, one pickup. No drop key: gear leaves you only by selling.
## M12.1 — Oda's brain actually connects (2026-10-26)

Found by running a real llama-server (built from source) through the game's own
sidecar code, with a tiny random-weight model:
- **Fixed: every model turn failed with HTTP 400 and fell back to canned lines.**
  Godot reads `3` in the reply schema as `3.0`; llama-server's grammar builder rejects
  `"maxItems": 3.0`. Whole-number floats are turned back into integers before sending.
- **Fixed: llama-server could silently never start.** If a routine health check was
  in flight, the "start the sidecar" callback was dropped. Callbacks now queue.
- **Fixed: subtitles could not stream from llama-server.** It orders grammar keys
  alphabetically, so "say" came last. The reply keys are now `say`, `then` (actions),
  `tone` (mood), which sort with `say` first. Old names are still read.
- **The reply must say something** (`minLength: 1`); an empty line used to drop to canned.
- **She tells you why she is dumb.** While talking, the top right names the brain
  answering or the exact reason none is (not installed, no model file, loading,
  Ollama not running, cloud off). Canned replies are marked. The same report prints
  in the Godot output; F3 shows details and llama-server's last log line.
- **The sidecar looks harder:** configured path, `$LLAMA_SERVER`, `runtime/bin`, both
  Homebrew locations, `~/.local/bin`, `~/llama.cpp/build/bin`, and the login shell's
  PATH; any `.gguf` in `runtime/models/`. It logs the server's output to
  `user://logs/llama-server.log` and notices when the server dies.
- **New trace:** `scenes/m12_sidecar_trace.gd` starts a real server and has one turn;
  `ci.sh` runs it when `LLAMA_SERVER` and `TEST_GGUF` are set.
## M11.1 — The guns actually show up (2026-10-26)

- **Fixed: guns did not render on a fresh checkout.** The blaster models were never
  committed: the `models/` rule in `.gitignore` (meant for downloaded LLM models)
  matched `assets/.../models/` too. The rule is now `/models/`, the files are in,
  and `test_weapon_assets` fails CI if a weapon model or sound is ever missing.
- **Readable guns.** The retint is lighter worn gunmetal with tan or oxblood accents
  and catches light on its edges; it was near black because the material was too
  metallic with nothing to reflect.
- **Hands on the handles.** Grip points re-measured on the models: the right hand
  holds the rear handle, the left cups it (pistol) or takes the front band (rifle).
- **Held lower.** Chest height in third person (it used to cover the face); lower
  right and turned slightly inward in first person, so you see the barrel.
- **Muzzle.** A glowing emitter ring replaces the orange dot, plus a brief flash,
  a brighter muzzle light, and a small kick back and up on every shot.

## M11 + M12 — A body, hand weapons, and a bartender who actually talks (2026-10-26)

What works now:
- **You have a body.** Third person shows an animated smuggler (long coat, hat,
  teal scarf) who walks, jogs, sprints, strafes, jumps, lands and crouches, and
  faces where it moves. The camera sits over the shoulder and never goes through a
  wall. V still toggles views; the switch glides in 0.2 s and never moves your aim.
- **Weapons.** 1 blaster pistol, 2 energy sword, 3 rifle (same key again holsters;
  Q last weapon; mouse wheel cycles; H holsters). The weapon comes out of the
  holster (hip, left hip for the sword, back for the rifle) and your hands are on it.
  LMB fires or swings, RMB aims (blaster) or blocks (sword), R reloads. Bolts are
  glowing streaks with recoil, shake and muzzle flash. The sword ignites with a
  sound, hums, chains three swings (forehand, backhand, overhead), and a block timed
  just before a bolt lands sends it back. First person shows your forearms, hands
  and the weapon.
- **A practice range in the pit:** five targets that fall and stand back up, and a
  sparring remote that fires stun bolts while your blade is out.
- **The bartender is real.** Oda Vell stands behind the counter (apron, mechanical
  arm, goggles up), wipes a glass, looks at you, gestures while she talks, pours.
  Walk to the bar, press E, type anything. Her reply streams onto the screen from a
  local model (bundled llama-server), Ollama, or any cloud key (OpenAI-compatible or
  Anthropic), with canned lines that still use true rumors and real jobs when every
  model is down. She never hangs: no first word in time and she moves to the next
  brain with a "Mm." beat.
- **She knows the town.** Rumors are only shown to her when they are true (the
  checkpoint, the patrol you shot down, the shots you fired in the street, the
  range record). Trust (0 to 100, four tiers) unlocks secrets that are not even in
  her prompt before then. Jobs she offers complete on real events and pay. Drinks
  cost the menu price, from your credits or onto your tab. She remembers you between
  visits and between sessions (save v2).
- **Tools to tune her.** F3 shows provider, model, time to first token, tokens,
  fallbacks, dropped actions and why, the raw reply, and copies the prompt. F10 picks
  local / Ollama / cloud, sets URLs, models and a key, and has a Test button.
  Shift+F10 cycles modes. Every turn is logged to `user://logs/bartender/`.
- **Proven headless.** `scenes/m11_body_trace.gd` (real physics) and
  `scenes/m12_bar_trace.gd` (scripted providers, then real HTTP against a mock
  server) feed `test_m11_body_weapons` and `test_m12_bar`; plus unit suites for the
  animator, swap, sword chain, SSE, providers, config, parser, filter, validator,
  prompt, relationship, world state and save v2.
- **The live gauntlet:** `tools/llm/eval_runner.gd` runs 32 cases (jailbreak, meta,
  franchise names, neutrality, grounding, secrets, barometer, memory) against a real
  model and writes a readable report to `docs/bartender/evals/`.

## M9 — Port town, and one demo (2026-10-26)

What works now:
- **Press Play and you are in the town.** `scenes/town_demo.tscn` is the main scene:
  a walled desert port built at runtime from `content/core/locations/port_town.json`
  (112 boxes, 18 markers, 4 routes): gate, market, barracks with a watchtower, the
  sunken landing pit with your ship, the cantina (bartender + fixer spots) and two
  residential districts. You start on the pit floor beside the ship.
- **Your ship launches the dogfight.** Beside the ship, "[E] Launch" shows; E fades
  out into the dogfight. When it is won or lost you land back beside the ship with
  the result on screen. The dogfight scene opened on its own (F6) is unchanged.
- **It looks like the beauty corner.** A visual-only decor layer gives the town the
  look-dev sky, sun, fog and materials (plaster with dye bands, paving, hull metal),
  lamps that come on at dusk, and two torn banners on the watchtower. Keys 1, 2, 3
  switch golden, noon and dusk.
- **Proven headless.** The validator checks 8 rules, with a negative test for each.
  A bot walks every route with real collision: spawn to cantina 1495 frames, cantina
  to gate 2051, gate to cantina 2052, back gap to cantina 1243; worst frame about
  3 ms. New suites: `test_town_layout`, `test_town_walk`, `test_town_decor`,
  `test_flow`.
- **Review cameras.** `content/look/town_shots.json` and `tools/town/shoot_town.sh`;
  golden and dusk shots are in `docs/town/look/`.
- `scenes/m1_demo.gd` now builds its boxes with the shared greybox helper.
- **The ship in the pit is the ship you fly.** Same model, same colors, built from the
  same data as the dogfight. Its collision box now matches the model.

Faked or not yet done: see KNOWN_ISSUES.md "After M9" (capsule NPCs, bare stalls,
box ship, no railings, payout not saved).

## M10 — Starfighter flight and dogfights (2026-10-26)

What works now:
- **Ships are data.** Three starfighters in `content/core/ships/`: the player's
  interceptor (shielded, two cannons, a seeker rack), the remnant fighter (fast,
  unshielded) and the remnant heavy (slow, armoured, one seeker rack). Hull, shield,
  speeds, turn rates, boost and gun mounts are all JSON. Two ship guns join
  `content/core/weapons/`: the ship cannon and the seeker missile.
- **AI pilots are data.** `content/core/pilots/` holds three personalities (rookie,
  veteran, ace): how wide they shoot, when they break, whether they use seekers.
- **Fights are data.** `content/core/encounters/orbital_skirmish.json`: the player and
  a wingman hold off two raid waves above the port.
- **A flight model.** `src/systems/flight/flight_model.gd`: arcade flight along the
  nose, throttle between min and max speed, pitch/yaw/roll rates, a boost meter that
  trades turn rate for speed. Pure, so the AI, a human and the headless bot all fly it.
- **Guns and damage.** Each hardpoint runs the M2 weapon state machine, so ship guns
  share the blasters' ammo/fire-rate/reload rules (an empty cannon "cools", a seeker
  rack reloads). Bolts inherit the ship's speed and are swept against ship hit
  spheres so they cannot pass through a fighter between frames. Seekers need a lock
  (keep the target in the cone), then home with a limited turn rate. A regenerating
  shield sits in front of the M2 hull.
- **Fighter AI.** `src/systems/ai/fighter_brain.gd`: patrol, pursue, attack (fly the
  lead point, fire inside the aim cone), break (hard turn away when too close, when
  hit, or when a seeker is launched at it), extend, and return to the arena.
- **The dogfight director.** `src/systems/flight/dogfight.gd` runs an encounter:
  ships, targeting, projectiles, waves, hits, kills, and the COMPLETE/FAILED outcome.
- **Playable.** `scenes/flight/dogfight_demo.tscn` (F6): fly with the keyboard (or
  mouse), V toggles chase/cockpit view, T cycles targets, HUD with speed, shield,
  hull, ammo, lock meter, target box and lead marker. Set `autopilot` to watch the AI
  fly your ship.
- **Any design later.** Looks live in `content/look/ships.json`. Today they are
  stand-ins built by `src/systems/look/ship_kit.gd`; setting a look's `scene` to a
  `.glb`/`.tscn` swaps in a real model with no code change. `docs/ADDING_SHIPS.md`
  explains every field.
- **Review stills.** `tools/lookdev/shoot_dogfight.sh` renders a lineup of every look
  and chase-camera shots of the fight; current stills are in `docs/lookdev/flight/`.

How to see it:
- `./scripts/ci.sh` now writes `test_results/m10_dogfight_trace.txt`: the AI flies the
  player through orbital_skirmish to COMPLETE (both waves, 7 kills, seekers launched,
  some evaded, the player hit along the way) with every AI action used and no frame
  near the 50ms budget.
- 198 GUT tests pass (was 132), including a test that adds a brand-new ship, gun,
  pilot and fight from JSON alone and flies it.
- Play it: `godot --path . res://scenes/flight/dogfight_demo.tscn` (controls in
  `LAUNCH.md`).

Fixed along the way:
- **The IP-neutrality scan skipped every top-level file** in the folders it scans
  (`scenes/*.gd`, `content/core/manifest.json`, `scripts/*`, `tests/*`): it joined
  the folder and file names without a slash. Fixed; the guard file itself is the one
  exclusion. Added "x-wing", "tie fighter" and "millennium falcon" to the list.
- **CI on a fresh checkout ran no tests but still passed.** Without an import step GUT
  could not load, printed an error, and `ci.sh` exited 0. `ci.sh` now imports first.

What is faked or outstanding:
- Ships are primitive stand-ins until real models are made (the `scene` hook is ready).
- No ship-to-ship collisions; ships fly through each other.
- No flight on-ramp from the port yet: the dogfight is its own scene, not reached by
  walking to a ship.
- Untested on the Mac; review stills are from Linux software rendering.

## Look-dev: art direction, beauty corner, character kit (2026-10-26)

What works now:
- **Art bible.** `docs/ART_DIRECTION.md`: pillars, palette, lighting presets,
  materials, the cast, character research notes, and the screenshot review loop.
- **Beauty corner.** `scenes/lookdev/beauty_corner.tscn`: the port on a cliff above a
  basin, a crashed capital ship, a broken orbital ring, a ringed planet, a market lane,
  and staged characters. Walkable (F6), with presets on keys 1-3.
- **Lighting is data.** `content/look/time_of_day.json` (golden, noon, dusk) and
  `content/look/shots.json` (five fixed review cameras).
- **Screenshots, for real.** `tools/lookdev/shoot.sh` renders every shot per preset to
  `test_results/lookdev/` (Metal on the Mac; software Vulkan under xvfb on Linux).
  Review renders are in `docs/lookdev/`.
- **Character kit.** Five original archetypes on a jointed body with two-bone IK:
  Remnant trooper, Remnant commander, smuggler, duelist and local. The energy sword is
  yellow by default (`blade_color` in `content/core/weapons/energy_blade.json`).
- **Tests.** `tests/test_lookdev.gut.gd`: presets, wall normals, terrain, skeletons,
  IK hands on the rifle and the sword, the yellow default, and a headless scene build.

What is faked or outstanding:
- Characters are built from primitives (a design stand-in for rigged models).
- Everything in the stills is static: no wind, dust motes or cloth motion yet.
- Frame time on the Mac has not been measured for this scene.

## M8 — Polish pass: cleared bug list, performance report, cross-system playthrough (2026-10-25)

What works now:
- **The bug list was cleared.** The one standing artifact -- GUT's "1 orphan" at process
  exit -- was a detached node in a test that called `queue_free()` instead of `free()`.
  A detached node is freed by the engine only on the next idle frame, which never comes
  before GUT tears down, so it left one orphan. Changing it to `free()` clears it; the
  suite now reports zero orphans.
- **One playthrough, every system together.** A single headless run
  (`scenes/m8_playthrough.gd`) threads the whole slice: walk the port + toggle FPV/TPV,
  a trooper seals to cover, the squad spreads (4 troopers, none in the open), a
  timed-deflection duel with the duelist reflects a bolt, the mission loop runs to
  COMPLETE, a typed-default voice turn reaches the LLM bartender, and the game saves and
  reloads the four named things. This is the "the slice hangs together end to end" proof,
  beyond the per-milestone traces.
- **A performance report.** The same run writes `test_results/m8_perf_report.txt`:
  worst/average frame cost and how many frames exceeded the 50ms budget. Across the whole
  playthrough the worst frame is under the 50ms ceiling -- the "no hitch over 50ms"
  property, measured over a full session, not asserted in a vacuum.
- **How to run and record.** `LAUNCH.md` is the human-facing guide: how to open the
  game, the input map, what the 3-minute clip should show, and how to record it with
  `scripts/record.sh` (macOS screen capture; the manual path, not headless CI).

How to see it:
- `./scripts/ci.sh` generates both `test_results/m8_playthrough.txt` and
  `test_results/m8_perf_report.txt`; a GUT test reads them and proves every system ran
  and no frame exceeded the 50ms budget.
- 116 GUT tests pass (was 109); the merge gate is green with zero orphans.
- `LAUNCH.md` is how to watch the slice on screen and record the 3-minute clip.

What is faked or stubbed:
- The 3-minute clip is the manual/recorded path (`scripts/record.sh` needs a display);
  the headless cross-system trace is its machine equivalent. Same posture as M6/M7.
- The visible 3D world is greybox; full geometry + rendered bolts/blades and GUI-bound
  combat inputs are the remaining polish (tracked in KNOWN_ISSUES), and the bartender
  runs a scripted client in CI.

What broke / fixed:
- The GUT "1 orphan" was a real, if non-failing, artifact: a detached test node
  `queue_free`-d instead of `free`-d. Fixed by freeing it immediately. (Also: this build
  of GUT has no `assert_le`; the helper is `assert_lte`.)

What was needed from the user:
- Confirmation that the 3-minute clip may stay the manual/recorded path (headless CI
  cannot render) -- taken, so M8 ships the headless proof + the LAUNCH.md recording guide.
- The scope call: M8 = clear the bug list + performance report + a cross-system trace,
  with the rendered 3-min clip documented as the manual step.

## M7 — Voice input: push-to-talk, typed default, whisper fallback (2026-10-25)

What works now:
- The bartender now also takes voice input through a push-to-talk, and the design
  is the reverse of the M0 assumption: **typed is the default and the only path with
  no dependency; whisper is an optional, dependency-bearing upgrade.** A voice turn
  that cannot be served degrades to typed, so a request is never dropped and the slice
  ships voice input without shipping an STT model.
- A single door, the `push_to_talk`, routes every captured request to the **same
  `bartender.respond()` from M6**, so the guardrail "the player's text is read but
  never executed as a command" is unchanged: only a model tool proposal, validated
  against the npc's allowed set, may move the world.
- The voice path is wired end to end but optional: a `whisper_runtime` stands in for
  whisper.cpp + a model; it loads only when a model is present, exactly like M6's
  Ollama HTTP post. With the runtime loaded, a sample is transcribed and answers the
  bartender; without it, the controller falls back to typed.
- Every turn records a **latency** (ms from press to release), the M7 "latency
  measured" requirement, measured from an injected clock so it is deterministic.
- The headless voice trace (scenes/m7_voice_trace.gd) writes
  test_results/m7_voice_trace.txt with, in order: a typed default capture applying an
  allowed tool, a voice request that degrades to typed, a wired whisper capture that
  transcribes, a command-looking request that moves nothing, and a fallback; a GUT test
  reads it. ci.sh generates the trace before the suite.

How to see it:
- `./scripts/ci.sh` writes test_results/m7_voice_trace.txt and the GUT test reads it.
  The trace shows MODE=TYPE/SOURCE=typed, a FALLBACK=yes row (voice -> typed), a
  SOURCE=whisper row (the wired path), no TOOL=cut_power (a disallowed tool ignored),
  and a LAT on every row.
- 109 GUT tests pass (was 97); the merge gate is green.

What is faked or stubbed:
- whisper.cpp + the STT model are **not wired in CI**: the `whisper_runtime` is a
  stand-in that "loads" only when a model is set. Transcription in CI is a canned map.
  The real whisper run is the manual + recorded path (scripts/record.sh), not a
  headless CI step, per DECISIONS.
- Latency is measured from an injected clock, not the real mic->transcribe wall time;
  the wiring for real timing is the manual path.
- The push-to-talk `press()/release()` is the literal PTT over the same core; the mic
  capture that feeds it is a manual wiring step.

What broke / fixed:
- None at build level. Two GUT/GDScript-4.7 gotchas surfaced and were fixed: the test
  used Java-style asserts (`assertTrue`) and the trace's `Object.has("field")` does not
  exist in this engine -- switched to snake-case asserts and a presence guard via
  `has_method`.

What was needed from the user:
- None in this pass. Wiring the live whisper runtime + mic capture is the manual step
  (see M8 and KNOWN_ISSUES).

## M6 — LLM bartender (text + Kokoro voice) (2026-10-25)

What works now:
- The single LLM-driven NPC, the bartender, now takes the player's typed text and
  replies. It talks to the model through an interface (`llm_client`), so a live
  client (`ollama_client`) and a canned client (`scripted_client`) are the same shape.
  The canned client is what CI uses, so a conversation is deterministic and repeatable.
- Four tools, exactly the npc's allowed set taken from its data entry
  (`give_rumor`, `set_disposition`, `offer_drink`, `call_guards`). When the model
  proposes one, the brain validates it against the allowed set and applies only the
  effect it is allowed to.
- Two guardrails the spec asks for, both proven by tests:
  - **Text is read, never executed.** A request that reads like a command ("shut down
    all power") changes nothing in the world; only a model tool proposal may, and only
    an allowed one.
  - **A disallowed tool is ignored.** If the model proposes a tool the npc is not allowed
    to use, it is dropped, not acted on, and no effect leaks into memory.
- **Fallback.** When the model comes up dry (the client is exhausted), the bartender
  falls back to a canned line, so a conversation never dead-ends.
- **Memory survives.** The npc writes remembered facts to `memory`, which is the same
  thing the M5 save system already round-trips (`bartender_memory`).
- **Kokoro voice.** Each reply gets a deterministic voice signature from text+speaker,
  and the audio render fails gracefully (a null, not a crash) when the TTS model is not
  running -- as it is in headless CI.
- The headless conversation trace (scenes/m6_dialogue_trace.gd) drives three turns and
  writes test_results/m6_dialogue_trace.txt; a GUT test reads it and proves a reply, an
  applied tool, and a fallback all happened. ci.sh generates the trace before the suite.

How to see it:
- `./scripts/ci.sh` writes test_results/m6_dialogue_trace.txt and the GUT test reads it.
  The trace shows a model reply applying a rumor, a disallowed tool ignored, and an
  exhausted client routing to a fallback line, each with a voice signature.
- 97 GUT tests pass (was 86); the merge gate is green.

What is faked or stubbed:
- The bartender talks to a **scripted client in CI**, not a live model. Real Ollama
  inference is the manual + recorded path (scripts/record.sh); it is not run headless.
- Kokoro's audio render returns a **null offline** (no TTS model in CI); the voice
  *signature* is the deterministic, proven part. A real recorded voice is M8.
- The Ollama HTTP post is a documented stub; only the request-building and
  response-parsing are live code (and are tested on canned JSON).

What broke / fixed:
- None at build level. The first CI run surfaced the usual GDScript strictness: two
  client methods returned `null` against a `Dictionary` type (changed to `Variant`),
  and the Ollama parser had to always carry the `tool`/`args` keys so callers never hit
  a missing key.

What was needed from the user:
- None in this pass. Wiring the live Ollama server + Kokoro model is the manual step
  (see M7/M8 and KNOWN_ISSUES).

## M5 — Mission loop and save (2026-10-25)

What works now:
- The single slice mission "Crate Retrieval" runs end to end: talk to the fixer,
  accept the contract, travel to the desert outpost, defeat 4 troopers + 1 duelist,
  take the crate, return, and get paid. It is a pure state machine (IDLE -> ACCEPT
  -> TRAVEL -> FIGHT -> TAKE_CRATE -> RETURN -> COMPLETE) driven by world events, so
  the loop is the same spine a bot plays and a human plays.
- The mission is data in content/core/missions (crate_retrieval.json) and is now
  loaded through the same IP-neutral data layer as everything else. The data layer
  learned a new category, `missions`; the manifest lists it; the loader loads it the
  same generic way it loads locations. A new mission needs zero code change.
- A save system writes and reads the four things the spec names: player position,
  credits, mission state, and bartender memory. The trace proves all four survive a
  save/load round-trip.
- The 4-trooper squad coordinator (deferred from M4) now spreads the squad: each
  member is assigned a DISTINCT cover node, so 4 troopers do not all stand in the
  open. With 4 members and 4 nodes, none is left in the open.
- The headless bot playthrough (scenes/m5_mission_trace.gd) walks the whole loop and
  writes test_results/m5_mission_trace.txt; a GUT test reads it and proves the loop
  closed (COMPLETE, 5 kills, payout 150) and that save/load preserved the four named
  things. ci.sh generates the trace, then runs the suite.

How to see it:
- `./scripts/ci.sh` writes test_results/m5_mission_trace.txt and the GUT test reads
  it. The log ends in phase=COMPLETE, kills=5, credits=150, with RELOAD_* lines
  showing the save/load round-trip.
- 86 GUT tests pass (was 74); the merge gate is green.

What is faked or stubbed:
- The bot drives the loop by feeding the state machine a fixed event sequence; it is
  not an AI agent choosing actions. The bartender conversation is a deterministic
  stub, not real LLM inference (that is M6). Real inference stays a manual +
  recorded check.
- The fight is the same headless-simulation proof as M2/M3: a 1-D/numeric loop, not a
  rendered combat. The visible fight and the 3-minute recording are M8.
- The save writes to user://; a fresh save path or extra fields is a data-only change.

What broke / fixed:
- Two parse bugs in the pre-built mission state machine were found and fixed: a
  function returned null against a String type, and the enum was called as a
  function during save restore. Both were blocking the build; the loop now compiles
  and closes.

What was needed from the user:
- None.

## M4 — World streaming: port to desert, no hitch, outpost (2026-10-25)

What works now:
- A chunk streamer keeps a window of world chunks loaded around the player and
  AMORTIZES their load work across frames, so no single frame exceeds the frame-time
  budget. A naive "load the whole region now" loader would cost ~132ms at once and hitch;
  the streamer spreads that work so every frame stays under the 50ms ceiling from the spec.
- A headless frame-time log records the entire walk from the docking bay (x=0) through the
  port into the desert out to the outpost (x=1000). A GUT test reads that log and proves
  two properties from the actual numbers: (a) no frame's work exceeded 50ms, and (b) the
  walk travels the full distance, i.e. the port/desert boundary is crossed with no empty
  "loading" frame.
- The outpost is data in content/core (3 buildings, 1 crate objective, 4 troopers, 1
  duelist), loaded through the same IP-neutral data layer, and placed as a chunk at the far
  end of the desert.
- The data layer learned a new category, `locations`, so the outpost is swappable like
  everything else -- no code change to add a new location.

How to see it:
- `./scripts/ci.sh` writes test_results/m4_frame_time.txt and the GUT test reads it.
- The log's first line shows a ~36ms load spike at the bay (amortized under budget);
  the rest stay well under 18ms.

What is faked or stubbed:
- The world is a 1-D chunk strip in a simulation, not yet a 3D greybox you walk through
  on screen. The visible, streamed 3D desert with the outpost models rendered is part of
  the M8 polish pass. The streaming *behavior and its frame-cost* are the real thing,
  proven here in CI.
- The "no hitch over 50ms" is a load-work budget, not yet a measured GPU frame time of a
  real render. M8 will record real frame times with the model loaded.

What broke / fixed:
- A log parser that split on a single space produced empty fields (the log is space-
  padded); the parser now collapses whitespace runs.

What was needed from the user:
- None.

## M3 — Melee: energy blade, stamina, timed deflection, duelist enemy (2026-10-25)

What works now:
- The energy blade: light/heavy attacks and a block all draw from a stamina budget.
- Timed deflection is the core skill: a block pressed inside a tight window reflects
  an incoming bolt and refunds stamina; a block held too long only absorbs it, paying
  stamina. This is the "deflect when blocking with correct timing" from the spec.
- A duelist enemy presses the player, blocks, and parries using that same blade
  logic, so the duelist and the player fight on equal footing.
- A headless melee-duel trace shows a parry, a blow exchange, and the duelist brought
  DOWN; a GUT test asserts parries happened, blows landed, and a knockout occurred.

How to see it:
- `./scripts/ci.sh` generates the trace and runs the assertions.
- Read test_results/m3_melee_trace.txt for the duel log.

What is faked or stubbed:
- The trace is a simulated duel, not a rendered fight with animation. A visible
  blade-swing animation and on-screen parry feedback are part of the M8 polish pass.
- The duelist swing cadence in the trace is fixed.

What broke / fixed:
- A process-ordering bug in the blade: the recovery timer now runs before the frame's
  block drain, so reaching zero stamina correctly lands in BLOCKED_OUT (was: the same
  frame advanced the recovery to the point of missing the transition).
- Recovery action: M2 had been committed on its branch and not yet merged when M3 was
  branched, so M2 tests went missing on the active line. Fixed by merging M2 into main
  before building M3; the history now reads M0 -> M1 -> M2 -> M3 completely.

What was needed from the user:
- None.

## M2 — Ranged combat: two blasters + a covering trooper (2026-10-25)

What works now:
- Two ranged weapons from the data layer: a pistol blaster and a rifle blaster, with
  ammo drawdown, fire cooldown, recoil, and reload. The bolt travels as a visible
  projectile (in the GUI) that deals damage on contact.
- A trooper brain that seals to its nearest cover node and then suppresses the player,
  returning fire. A headless combat-integration trace records the whole arc: SEALING ->
  FIRING -> the trooper dying at 0 HP, while the player takes return fire and the
  return fire stops when the trooper dies.
- Health and death work for both sides.

How to see it:
- `./scripts/ci.sh` generates test_results/m2_combat_trace.txt and runs the assertions.

What is faked or stubbed:
- The combat trace is a simulation, not a rendered fight. On-screen hit feedback and
  bullet tracers are part of M8.
- The four-trooper squad coordinator (so they do not all stand in the open) is deferred
  to M5 with the mission loop; M2 brings a single covering trooper, as the spec asks.

What broke:
- Two blaster state-machine edge cases (idle recovery refunding an attack's cost; the
  deflect refund being capped at full stamina) were found and fixed so the numbers read
  correctly.

What was needed from the user:
- None.

## M1 — Movement + FPV/TPV camera toggle (2026-10-25)

What works now:
- Walk, sprint, crouch, and jump for the player, as pure, testable math.
- A camera rig that toggles between first-person and third-person on one key. The key
  requirement -- "toggle mid-combat without breaking aim" -- is that the toggle changes
  the camera position but not the look direction, which is proven by a test.
- A headless bot-driven trace proves the player moves and that the view toggles between
  FPV and TPV, without a rendered window.

How to see it:
- `./scripts/ci.sh` runs the trace and test_results/m1_trace.txt shows positions and
  view toggles.
- `scripts/record.sh` captures the live GUI (a rendered clip) for a human to watch;
  headless mode cannot render, so the trace is the machine proof.

What is faked or stubbed:
- No rendered clip was produced in CI because headless mode has no window. The human
  recording is available via record.sh; the machine trace stands in for it in CI.
- Take-cover-against-marked-surfaces (movement) is deferred to M4 with the world
  streaming; free walking with a pose change is what M1 proved.

What broke / fixed:
- A bare `godot --headless` run launches the project's main scene, which never quits, so
  the first CI run hung. Fixed by driving GUT through its CLI runner, which exits on its
  own.

What was needed from the user:
- None.

## M0 — Project setup (2026-10-25)

What works now:
- The repo exists on git from commit one, one feature per branch.
- Godot 4.7.2, Rust, and ffmpeg are installed locally; their versions are pinned
  and checked at the top of CI.
- A folder structure and a runtime-loaded data layer (`content/core`) are in place.
- The data-layer loader and the IP-neutrality guard are tested and passing.
- A headless CI script (`scripts/ci.sh`) runs the test suite and exits non-zero on
  failure, which is the merge gate.
- The README, this file, DECISIONS, and KNOWN_ISSUES live in the repo.

How to see it:
- Run `./scripts/ci.sh` -> it prints the GUT summary and exits 0.
- Open the editor and press F5 -> the console prints that the data layer loaded
  (npcs=2, weapons=3, factions=2).

What is faked or stubbed:
- Nothing gameplay-faked yet. There are no gameplay systems yet.

What broke:
- The first CI run hung because a bare `godot --headless` invocation runs the
  project's main scene, which never quits. Fixed by running GUT through its CLI
  runner, which quits on its own.

What was needed from the user:
- Approval to use NobodyWho's bundled TTS + STT instead of separate whisper.cpp.
- Approval to install the toolchain and download a small GGUF at M6.
- A neutral git identity.
- Confirmation the local CI script satisfies the headless-CI requirement.
