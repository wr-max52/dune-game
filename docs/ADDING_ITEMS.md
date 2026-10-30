# Adding items, vendors and pickups

Gear is data, like ships. Code never names an item; it asks the data layer by id.
Adding any of the things below is a JSON file plus one manifest line, with no code
change. `tests/test_inventory.gut.gd` proves this by adding a new pack, a new
vendor and a new pickup in a throwaway folder and trading with them.

## Where each part lives

| Part | Gameplay | Look |
|---|---|---|
| Item | `content/core/items/<id>.json` | `content/look/items.json` → `looks.<look id>` |
| Vendor | `content/core/vendors/<id>.json` | the town character at its marker |
| Pickups in a place | `content/core/pickups/<location>.json` | the item's look, spinning over a glow |
| Prompt wording | `content/core/flow/gear.json` | |

Every new id also goes in `content/core/manifest.json` under `items`, `vendors` or
`pickups` (pickups are listed by location id).

## A new item

Copy `content/core/items/jetpack.json`:

- `kind`: what vendors look at when deciding to buy it (`gear` today).
- `slot`: where it is worn (`back`). One item per slot; G puts the back-slot item on
  or takes it off. An item without a slot can be owned and sold but not worn.
- `value`: the base price. Vendors pay `value x buy_rate` and ask `value x sell_rate`.
- `look`: the id of its look in `content/look/items.json`.
- `jetpack` (optional): makes it fly. `fuel` is seconds of thrust; `thrust` (m/s²,
  gravity is 20) and `max_rise` (m/s) set the climb; `kick_in` is how long jump must
  be held before it lights (so taps stay jumps); `min_fuel_to_start`;
  `recharge_delay`, `recharge_ground`, `recharge_air` (fuel per second).

### Its make and model (issue #15)

`"naming": { "kind": "equipment", "class": "jetpack" }` gives the item a generated
make and model, shown in its prompts ("Jetpack (Embry XR-76 Skylark)"). `class`
picks the product words: jetpack, blaster, blade, ship, armor or tool. See
`docs/names/NAMING.md`.

## A new look (any design)

Add an entry under `looks` in `content/look/items.json`:

- **A real model:** set `"scene": "res://art/gear/my_pack.glb"` (or a `.tscn`). Model
  it with the wearer's back toward **-Z**, at **1 unit = 1 metre**. Put the flames
  under a node named `Flames` (shown while thrusting). A missing file falls back to
  the stand-in, so the pack never turns invisible.
- **A stand-in:** leave `scene` empty, keep `frame: "twin_tank"`, and change sizes
  and colours. A new frame is a new function in `src/systems/items/item_kit.gd`.
- `on_back`: where it sits on the chest joint (`pos` in metres, `rot` in degrees).
- `model_scale`: `[x, y, z]` squeezes a real model along its own axes, worn and as a
  pickup (the jetpack is `[1, 1, 0.5]`: half as deep, flat on the back). Move
  `flames_at` to match.

Check it with `./tools/m13/shoot_jetpack.sh shots=worn_back,worn_side,flames_close`.

## A new vendor

Copy `content/core/vendors/gear_trader.json`: `location` and `marker` say where it
stands (a marker id in that location's town data), `reach` how close you must be,
`buys` which kinds it buys, `buy_rate` / `sell_rate`, and `stock` what it sells
before you have traded with it. What you sell it, it keeps and sells back.

## Put an item in the world

Add an entry to `content/core/pickups/<location>.json`: a unique `id`, the `item`,
a town `marker` plus an `offset` (metres), and a `reach`. A taken pickup stays taken
(it is saved). Keep pickups out of the pit: E there launches the ship.
