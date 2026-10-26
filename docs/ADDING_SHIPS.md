# Adding ships, guns, pilots and dogfights

Everything in the flight game is data. Code never names a ship; it asks the data
layer by id. Adding any of the things below is a JSON file plus one manifest line,
with no code change. `tests/test_dogfight.gut.gd` proves this by building a new ship,
gun, pilot and fight in a throwaway folder and flying it.

## Where each part lives

| Part | Gameplay (how it flies and fights) | Look (what it looks like) |
|---|---|---|
| Ship | `content/core/ships/<id>.json` | `content/look/ships.json` → `looks.<look id>` |
| Ship gun | `content/core/weapons/<id>.json` | `content/look/ships.json` → `bolts` |
| Pilot (AI personality) | `content/core/pilots/<id>.json` | none |
| Dogfight | `content/core/encounters/<id>.json` | `content/look/space.json` (backdrop) |

Every new id also goes in `content/core/manifest.json` under `ships`, `weapons`,
`pilots` or `encounters`.

## A new ship

1. Copy `content/core/ships/remnant_fighter.json` to `content/core/ships/<id>.json`.
2. Change `id`, `label`, `faction`, `pilot` (its default AI) and `look`.
3. Tune it:
   - `hull`, `shield` (`max`, `regen` per second, `delay` before regen), `hit_radius`
     in metres.
   - `flight`: `min_speed`, `max_speed`, `boost_speed` (m/s); `accel`; `pitch_rate`,
     `yaw_rate`, `roll_rate` (radians/s); `boost_time`, `boost_recharge`,
     `boost_turn_scale`.
   - `hardpoints`: each is a weapon id and a `mount` point in the ship's own space
     (metres; forward is -Z, up is +Y, right is +X).
   - `convergence`: how far ahead the fixed guns cross.
4. Add the id to `ships` in the manifest.

### Flying it in the atmosphere (M14)

A ship the player flies around the port also needs an `atmosphere` block (copy the
interceptor's): `max_speed` and `boost_speed` near the ground (m/s), `min_speed`
(0 = it hovers), `accel`, `boost_time` / `boost_recharge`; `edge_speed_mult` (how
much faster at the edge of space) and `speed_curve`; `climb_drag` (speed lost
straight up); `liftoff_height` / `liftoff_speed`; `land_max_agl`, `land_descent`,
`land_slow`, `land_brake`, `touchdown_speed`; `crash_speed`; `body_radius` (for
hitting things) and `clearance` (origin to belly; taken from the model when there
is one). Turn rates come from `flight`.

## A new world around a town (M14)

`content/core/worlds/<id>.json` (listed under `worlds` in the manifest) names the
`town` it surrounds and holds:

- `terrain`: not the desert's shape (that is the town's `DesertTerrain`, and its
  rocks are `content/look/desert_landforms.json`, which ships also collide with), but
  where it ends and the planet begins: `extent` (the desert's own wins when it is
  built), `skirt_height`, and the curve (`planet_radius`, `curve_from`).
- `landmarks`: `location` (places a location's buildings, such as the outpost, at a
  position and yaw) and simple `mesa` / `spire` columns (a position, `radius`,
  `height`). Solid to ships; the location's buildings are solid to the player too.
- `atmosphere`: where the sky starts to darken (`upper_start`), is black
  (`sky_black_at`), and where space begins (`space_altitude`).

Colours are in `content/look/world.json`. Where the ship re-enters after space is the
pad's `reentry_*` in `content/core/flow/launch_pads.json`.

## A new look (any design)

Add an entry under `looks` in `content/look/ships.json`, keyed by the ship's `look` id.

- **A real model:** set `"scene": "res://art/ships/my_ship.glb"` (or a `.tscn`). The
  model is used as-is. Model it facing **-Z**, at **1 unit = 1 metre**, centred on the
  ship's middle. If the file is missing, the stand-in below is used so the ship never
  turns invisible.
- **A stand-in:** leave `scene` empty and pick a `frame` (`dart`, `blade`, `hauler`),
  then set `length`, `span`, `height` and the colours (`hull`, `trim`, `dark`,
  `canopy`, `engine`). Shapes are in `src/systems/look/ship_kit.gd`; a new frame is a
  new function there.

Engine glows go in a child node called `Engines`. A model can bring its own (name
the node `Engines` in the scene) or leave it out.

Check the look with `./tools/lookdev/shoot_dogfight.sh`: `lineup.png` shows every
look side by side.

## A new gun

Copy `content/core/weapons/ship_cannon.json` (fixed gun) or `ship_missile.json`
(seeker). Ship guns use the same fields as the hand blasters (`damage`, `rate`,
`mag`, `reload_time`, `range`) plus:

- `fire_group`: `primary` (main trigger) or `secondary` (seeker trigger).
- `bolt_speed` in m/s.
- Seekers only: `homing: true`, `turn_rate` (radians/s), `lock_time`,
  `lock_cone_deg`, `lock_range`.

## A new pilot

Copy `content/core/pilots/veteran.json`. The fields are the AI's personality:
`aim_cone_deg` (how far off the lead it will still shoot), `aim_error`,
`engage_range`, `break_distance`, `break_time`, `break_on_hit` and `evade_missile`
(chances, 0 to 1), `extend_distance`, `attack_throttle`, `retarget_interval`,
`missile_use`, `steer_gain`.

## A new dogfight

Copy `content/core/encounters/orbital_skirmish.json`:

- `player`: which ship the player flies and where it starts.
- `allies`: wingmen (ship, pilot, spawn).
- `waves`: in order. Each has a `delay` after the previous wave is cleared, a
  `spawn_distance` from the player, and a list of `{ ship, count }`. A wave can set
  `pilot` to override every ship's default.
- `arena`: `center` and `radius`. AI pilots turn back when they leave it.
- `payout`: credits on a win.

Play it by setting `encounter_id` on `scenes/flight/dogfight_demo.tscn`. To prove it
headless, point a copy of `scenes/m10_dogfight_trace.gd` at the new id.
