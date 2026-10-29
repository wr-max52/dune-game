# Native peoples and wild animals (issue #96)

![The friendly Red Wind pack, and the Bone Teeth on the attack](packs.jpg)

Every planet with breathable ground can have its own native people, who travel in
packs, and its own wild animals. They come from the planet generator, the same way
a planet gets its town, its style and its sky.

## Where they come from

`NativesData.resolve` (`src/systems/natives/natives_data.gd`) gives each planet a
`natives` block (`PlanetGen.build(id).natives`):

- **A planet's own config** can list them outright. The home planet does this in
  `content/core/planets/port_desert.json`: its people, each pack (attitude, size,
  children, style, route) and its animals. `"natives": false` means none.
- **Otherwise its type** decides (`content/core/planets/types.json`, `natives`).
  The type names a people *template*, how many packs there are, how big they are,
  how many are hostile, how many are adults only, how far out they roam, and
  which animals live there. The generator lays all of this out from the planet's
  seed, so a planet always gets the same packs.
  - Each planet makes its own people from the template, named by the name engine
    and keyed to the planet, with the pack colours in its own order. The home
    planet's dune people never turn up anywhere else.
- **Platform and ball planets** (water, lava, gas, the asteroid) get none: there is
  nowhere to live.

## The data

- **A people:** `content/core/species/<id>.json`. A template lists only what
  differs from its `base`. A people has:
  - `body`: the character archetype, the children's scale (0.6), and the
    leader's helmet and pole;
  - `styles`: per-pack colours of the kit pieces already in the game (head
    Goggles, upper body Cantina Owner, lower body Player; the leader wears the
    Cantina Owner head);
  - `soldier`: hit points, speeds and senses, as for a guard;
  - `weapons`: melee and thrown only;
  - `pack`, `trade` (food in, quartz out), `hostile` (the horn, the 5-minute
    survival), `voice` (yells and gestures: they do not speak the port's
    language) and `lines`.
- **An animal:** `content/core/fauna/<id>.json`. The sand pig has hit points,
  speeds, how far it wanders, when it bolts, and the food it gives.
- **Items:** `food` (sold without end at the food stall in the market) and
  `quartz` (the packs give it for food; the food stall buys it).

## In play

`NativesDirector` (`src/systems/natives/natives_director.gd`) is built by the town
scene when the planet has natives.

- **Packs:**
  - Each member is an `NpcBody`, the guards' body, senses and health. It walks
    open ground without a navmesh (`free_walk`).
  - Far from the player, members are slid along the ground with no physics, so a
    pack can cross the desert where there is no collider under it.
  - The leader walks the route and the rest follow in rows. The leader's pole
    shows where a pack is from far off.
- **Friendly packs:** the leader comes over and gestures. Press **E** to gesture
  back: one food for one quartz, or two from an adults-only pack. Each trade
  raises that pack's reputation (`WorldState.native_pack`, saved).
- **Hostile packs:**
  - They blow a battle horn and come at you on sight, and fight to the last.
  - They use clubs, spears and knives up close, and throw sticks and light
    spears from 5 to 18 m.
  - They chase a speeder on foot.
  - **Winning them over:** survive 5 minutes without killing any of them and
    without being downed. They stop, offer trade, and are friendly from then on.
  - **A kill is permanent:** kill one and that pack is hostile for good.
  - **Downed:** you wake as from any other death, and they go back to their
    route.
- **Reputation:** how a pack treats you is its own business, never your standing
  with the Remnant.
- **Animals:** each roams alone and bolts when shot or when you run at it. Kill
  one, then press **E** at the carcass to cut food from it.

## Adding a people or an animal

1. Write `content/core/species/<id>.json` (or a template with a `base`), or
   `content/core/fauna/<id>.json`, and list it in `content/core/manifest.json`.
2. Add it to a planet's config (`natives`), or to a planet type's `natives`, so
   every generated planet of that type gets one of its own.

No code changes are needed for another people, other weapons, colours, pack
sizes, routes, trade goods or animals with the sand pig's shape of data.

## Not yet (later milestones)

The data has room for these, but the code does not do them yet:

- camps with tents and fires that move with the season;
- resting in a friendly tent, and stealing from tents;
- packs fighting each other and the Remnant;
- hiding from sandstorms;
- stealing and stripping vehicles.

`scenes/natives_trace.gd` runs the first milestone headless.
