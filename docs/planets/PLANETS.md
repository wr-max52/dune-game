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
| `type` | `sand`, `snow`, `red_desert` (biome planets: the town sits on dunes); `water`, `lava`, `gas` (element planets) and `asteroid` (a station on a rock). Element and asteroid towns float on a platform. |
| `town_size` | 1 to 100. 50 is the port's scale, 100 is 5x its area, and 1 is just a cantina, one Remnant guard at its door, a merchant out back, and a landing bay. |
| `style` | How the town looks: `desert` (the port's own), `metallic`, `snowy`, `pastel`, or plain words like `red matte metal`. See below. Default: the type's own. |
| `seed` | Optional. A different number lays the same size of town out differently. |
| `near` / `at` | The planet whose sky it hangs in, and where in that sky, in metres from that planet's port: `[east, up, south]`. The return trip is automatic. `home_at` overrides where `near` appears from here. |
| `town_name` | Optional. The town's name; otherwise generated. |
| `cantina_owner` | Optional. `{ "card": "npcs/<file>.json", "look": "<archetype>" }`: who runs the cantina (their AI card) and how they look. Default: Oda. |
| `encounter` | Optional. The space fight when you climb out of this planet's atmosphere (`"orbital_skirmish"`), or `""` for a quiet sky. Default: the landing pad's. |
| `features` | The port only: `training_range`, `speeders`, `landforms`, `pickups`. |
| `town` / `world` | The port only: use a hand-built town and world instead of generated ones. |

## Planet types

The types are defined in `content/core/planets/types.json`, and each one sets the
following:

- **ground:** `terrain` puts the town on the seamless dunes, recoloured by `sand`
  and `rock`. `platform` floats it on a deck closed underneath.
- **surface (platforms only):** what lies below the deck: sea, lava, cloud decks,
  or the asteroid's own rock with debris drifting round it.
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

A new type is a new entry in `types.json`, with no code change, as long as its
ground is `terrain` or `platform` and its surface is one of `water`, `lava`, `gas`
or `rock`.

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
  sea, lava, clouds or asteroid, and handles falling off.
- `SpaceTravel` (`space_travel.gd`) draws the neighbours in the sky, labels them
  with their distance, and starts the trip when you fly into one.
- `GameFlow.travel()` reloads the same town scene as the other planet. A planet
  is data, not a scene, so you arrive flying the same ship above its bay.
- The town scene (`scenes/town_demo.gd`) asks `GameFlow.planet()` what to build.
  The home planet is `port_desert` (`types.json` `home`).

## The test planet: Grit Station

`content/core/planets/grit_station.json` is the planet the issue asks for:

- An asteroid with a size-1 town, in `metallic`, 12 km from the port and 5 km up.
- Its cantina is run by **Ilka Vell**, Oda's younger sister, on her own AI card
  (`content/core/npcs/station_owner_card.json`).
- She wears Oda's model re-tinted steel-blue with cyan goggles (archetype
  `cantina_owner_station` in `content/look/characters.json`).

`scenes/planets_trace.gd` flies the whole trip in CI. It takes off, flies to the
station, lands, walks out through the shield, falls off the edge, finds the glass
solid, and flies home.
