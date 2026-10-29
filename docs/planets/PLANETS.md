# Planets (issue #45)

A planet is **one small JSON file**. The planet generator turns it into a town of
the size you ask for, a world of the type you ask for, in the style you ask for,
hanging in another planet's sky so you can fly there. No new code.

## Make a new planet (the whole job)

1. Write `content/core/planets/<id>.json`:

   ```json
   {
     "id": "frost_reach",
     "name": "Frost Reach",
     "type": "snow",
     "town_size": 18,
     "style": "pale blue glossy ceramic with gold trim",
     "near": "port_desert",
     "at": [-12000, 6000, 4000]
   }
   ```

2. Add `"frost_reach"` to `"planets"` in `content/core/manifest.json`.
3. Run `./scripts/ci.sh`. `tests/test_planets.gut.gd` builds every planet in the
   manifest and validates its town.

That is it. Take off from the port, climb into space, and Frost Reach is in the sky
where `at` puts it. Fly into it to land there.

### The fields

| Field | What it does |
|---|---|
| `id` | Lower case, underscores. Also the key its name is saved under. |
| `name` | The planet's name. Leave it `""` and the name generator makes one (unique in the game). |
| `type` | `sand`, `snow`, `red_desert` (biome planets: the town sits on dunes); `water`, `lava`, `gas` (element planets) and `asteroid` (a station on a rock ball). Element towns float on a platform; an asteroid town sits on top of its rock, under a glass dome. |
| `town_size` | 1 to 100. 50 is the port's scale, 100 is 5x its area, and 1 is just a cantina (with its stage), one Remnant guard at its door, a merchant in front of the cantina, three locals walking the street, and a landing bay. |
| `style` | How the town looks: `desert` (the port's own), `metallic`, `snowy`, `pastel`, or plain words like `red matte metal`. See below. Default: the type's own. |
| `seed` | Optional. A different number lays the same size of town out differently. |
| `near` / `at` | The planet whose sky it hangs in, and where in that sky, in metres from that planet's port: `[east, up, south]`. The return trip is automatic. `home_at` overrides where `near` appears from here. |
| `town_name` | Optional. The town's name; otherwise generated. |
| `cantina_owner` | Optional. `{ "card": "npcs/<file>.json", "look": "<archetype>" }`: who runs the cantina (their AI card) and how they look. With no `card`, a generated planet gets its own Oda (see below). The port's is Oda Vell. |
| `encounter` | Optional. The space fight when you climb out of this planet's atmosphere (`"orbital_skirmish"`), or `""` for a quiet sky. Default: the landing pad's. |
| `features` | The port only: `training_range`, `speeders`, `landforms`, `pickups`. |
| `town` / `world` | The port only: use a hand-built town and world instead of generated ones. |

## Planet types

The types are defined in `content/core/planets/types.json`, and each one sets the
following:

- **ground:** `terrain` puts the town on the seamless dunes, recoloured by `sand`
  and `rock`. `platform` floats it on a deck closed underneath. `ball` (the
  asteroid, issue #99) makes the planet a real ball like the home planet: rock all
  the way round, gravity toward its centre, flown and walked all the way round
  (`src/systems/planets/asteroid_sphere.gd`, drawn by `PlanetTerrain` in
  `moon_rock.gdshader`).
- **surface (platforms and balls):** what lies below the deck (sea, lava, cloud
  decks), or the ball itself: its radius, how far the town's flat ground reaches,
  rock colours (`look`), three sizes of crater, the swell and roughness, and the
  boulders round the station.
- **landing_bay:** `pit` puts the port's own round landing pit outside the gate
  instead of bays inside the walls (the asteroid).
- **enclosed** and **station (balls):** a sealed station (see below): its wall
  height, gate and hallway width, the dome's height, and the pit liner's height.
- **space.handoff (balls):** how close to its surface (metres) its own scene takes
  over from its parent's in mid-flight, with no fade (see "One map" below).
- **sky:** colours laid over every time of day, so the clock and F11 still work.
  The asteroid's sky is grey.
- **atmosphere:** where space begins. It is 700 m on the asteroid and 4 km on the
  port.
- **body:** how the planet looks from a neighbour's sky.
- **arrival:** where a ship arriving from space appears.
- **town_naming:** the name grammar for its towns. A station gets "Grit Hold", not
  "Dustwell".
- **fall_text:** what you are told when you go over the edge.

On a platform, a **glass enclosure** rises from the town walls. It is solid to people
and ships and open above, so ships can lift straight out. The gate stays open, with
a translucent **energy shield** across it that you walk straight through. Go over
the edge of the deck and you die, then wake up by the landing bay.

On the asteroid (issue #99) the station is **sealed**: the locals cannot breathe
outside. A **round wall** goes round the whole town, with a **glass dome** springing
from its top, solid to people and ships. The **gate** is a gap in the wall on the
main street, closed by a transparent **energy shield** you walk through. Beyond it
a **covered hallway** runs out to the landing pit. It has wide windows for walls,
glowing strips and lamps along its ceiling, and a roof. It goes in through a
**door in the pit's liner**: the pit's round wall carried up 13 m above the rock.
Then it runs down over the pit's ramp and opens onto the pit floor through a
**round energy shield**. An **energy shield over the top of the pit** lets ships
fly in and out. The rock outside is ground all the way round the ball, strewn with
blocky boulders near the station. You can only get out onto it by flying.

**Walking the planet:** on every planet except water, lava and gas worlds, you can
walk out of the town and keep going: the dunes on biome planets, the rock on an
asteroid.

**One map (issue #99).** Every planet's scene is the same space, shifted so its
own port is the origin. There is no turn, so the sun and the stars agree in all
of them. A planet's port sits on top of its ball, so a neighbour's port is at its
`at` plus its radius straight up.
- **From the home planet,** the asteroid is drawn as its real ball, in its own
  rock, with its station on top: the same shapes its scene builds, only coarse.
- **Flying to it,** come within `space.handoff` metres of its surface and its
  scene takes over on the spot. The ship carries on exactly where it was, with the
  same heading, speed and throttle and the same time of day. Nothing fades.
- **Leaving it,** climb more than that far off it (plus 300 m) and the home
  planet's scene takes over the same way.
- **Only the detail changes:** the near rock, the collider and the town come in
  as you arrive.

A new type is a new entry in `types.json`, with no code change, as long as its
ground is `terrain`, `platform` or `ball` and its surface is one of `water`,
`lava`, `gas` or `rock`.

## What every generated planet has (issue #75)

- **Merchants in front of the cantina:** every merchant's stall is in the square
  outside the cantina door, both sides of the street. Stalls nobody keeps go to
  the market.
- **Locals walking the street:** at least three, who fight back like every local
  if you hurt one (`roamers` in `town_kit.json`), on top of the residents.
- **A stage in the cantina,** against the side wall, off the path to the bar.
- **Its own Oda:** with no `card` set, the cantina owner is a new iteration of Oda,
  built by `src/systems/planets/planet_owner.gd` from Oda's card and
  `content/core/npcs/planet_owner.json`:
  - Her last name comes from the name generator, and is the same every time.
  - The planet's and the town's names are in her prompt.
  - She has her own card id (`cantina_owner_<planet id>`). That gives her her own
    brain, her own relationship with you, her own save entry and her own
    transcripts. Nothing is shared with the port's Oda.
- **Smuggling and contracts, always:** off the home planet, the board's smuggling
  run and the contract on a Remnant officer are open without waiting on the
  port's story. The drop and the outposts are still the port's, so the job takes
  you back there.
- **Z lands you:** flying near your bay (within `bay_land_radius` in
  `launch_pads.json`, 4 km, below space), on any planet including home, press **Z**.
  The ship flies itself over the bay and lands on its own pad. Press Z again to
  take back control, or C to land where you are.

## Town styles

A style is one line, parsed by `src/systems/planets/town_style.gd`:

- **A preset:** `desert` (the port's own look), `metallic` (brushed steel, cyan
  trim), `snowy` (white walls under snow, ice trim, snow drifts instead of sand),
  or `pastel` (every building a different soft colour).
- **Or plain words:**
  - A **colour** (`red`, `teal`, `gold`, `ivory`...) sets the walls.
  - A **second colour**, or one after `with` / `trim` / `accent`, sets the trims
    and painted bands.
  - A **shade** before a colour changes it: `pale`, `light`, `dark`, `deep`,
    `bright`, `dusty`, `faded`, `pastel`.
  - A **finish** sets the shine: `matte`, `satin`, `glossy`, `polished`,
    `brushed`, `weathered`, `rusty`, `clean`, `frosted`.
  - A **material** sets what the walls are: `metal`, `steel`, `chrome`,
    `plaster`, `stone`, `concrete`, `ceramic`, `adobe`.
  - Examples: `red matte metal`, `pale blue glossy ceramic with gold trim`,
    `snowy dark steel`.

The words live in `content/look/town_styles.json`, so adding a colour or a finish
is one line. Unknown words are ignored, and the tests list them so typos show up.
The style restyles every material the town's look is made of (walls, paving,
metal trim, props and awnings) through `LookMaterials`, so no building had to
change.

## How it works

- `PlanetGen` (`src/systems/planets/planet_gen.gd`) turns a config into a town, a
  world, a style, a sky and a list of neighbours. It is pure and cached.
- `TownGen` (`town_gen.gd`) lays out a town of any size, using the port's own box
  and marker conventions. The cantina's ids, the pad's `ship` box and the gate
  markers mean the decor, the bar, the guards, the locals and the ship all work
  unchanged. Every size from 1 to 100 passes the town validator (V1 to V8). Its
  numbers are in `content/core/planets/town_kit.json`.
- `PlatformWorld` (`platform_world.gd`) builds the deck, keel, glass, shield,
  sea, lava or clouds, and handles falling off. `AsteroidWorld`
  (`asteroid_world.gd`) is its asteroid version: the rock ball (one height
  function shared by the collider, the look and the ships' ground), the boulders,
  the dome and the fall off its side.
- `SpaceTravel` (`space_travel.gd`) draws the neighbours in the sky, labels them
  with their distance, and starts the trip: a seamless handoff for a planet with
  `space.handoff`, otherwise a fade when you fly into it.
- `GameFlow.travel()` reloads the same town scene as the other planet. A planet
  is data, not a scene, so you arrive flying the same ship above its bay.
- The town scene (`scenes/town_demo.gd`) asks `GameFlow.planet()` what to build.
  The home planet is `port_desert` (`types.json` `home`).

## The test planet: Grit Station

`content/core/planets/grit_station.json` is the planet the issue asks for:

- An asteroid with a size-1 town, in `metallic`, 12 km from the port and 5 km up.
- The rock is a real ball 3 km across (radius 1500 m), cratered all the way
  round. The sealed station is on top, with the port's landing pit at the end of
  its hallway.
- Its cantina is run by its own Oda, with a generated last name (issue #75; until
  then it was Ilka Vell, on a card of her own).
- She wears Oda's model re-tinted steel-blue with cyan goggles (archetype
  `cantina_owner_station` in `content/look/characters.json`).

`scenes/planets_trace.gd` flies the whole trip in CI. It takes off and flies to
the station, whose scene takes over in mid-flight with no fade. It drops under
the station's edge of space, presses Z and is landed in the pit, then walks:
- out of the ring through the gate's shield;
- down the hallway (its windows hold) and through its round shield into the pit;
- on the rock, and on the far side of the ball.
It finds the dome solid, and flies home the same way.

Review stills: `./tools/planets/shoot_planets.sh scenes=grit_station,port_desert`.
A sheet is in `docs/planets/issue_99_station.jpg`.
