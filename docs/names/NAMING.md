# The naming system (issue #15)

Everything in the game that needs a name gets one from **one engine**, with **no
LLM**: people (by culture), pilots' callsigns, ships, equipment and its makers,
towns, planets, moons and stars. Names are **deterministic**: the same world seed
and the same thing always get the same name, on every machine. They are also
**unique across the game**: each new name is checked against every name already
given out (and the authored ones) before it is saved.

## How a name is made

1. **A library of terms** (`content/core/names/*.json`, about 2,300 hand-written
   and all original): given names, family names and clans for three cultures,
   ranks, nicknames, callsigns, ship words, makers, product names, town parts and
   planet words.
2. **Tongues**: the sounds of each culture (onsets, vowels, endings). The engine
   builds new words from them syllable by syllable, so a culture never runs out
   of names and its made-up words sound like they belong together:
   - `hard`: the Remnant, clipped and closed ("Dogrin", "Pivtaerk").
   - `dune`: the desert's people, open, with the odd glottal stop ("Qa'rim").
   - `drift`: spacers, short and punchy ("Zot").
   - `astral`: worlds and stars ("Namlunyn").
3. **A grammar** (`kinds.json`): each kind of name is a weighted list of
   templates, built from these pieces:

   | Token | Means | Example |
   |---|---|---|
   | `{list}` | a term from a list | `{remnant_given}` |
   | `{@rule}` | a shared sub-template | `{@clan}` |
   | `{~tongue}` | a made-up word | `{~astral}` |
   | `{#lo-hi}` | a number | `{#2-9}` |
   | `:mod` | `cap`, `title`, `upper`, `lower`, `first`, `roman`, `plural` | `{#2-9:roman}` |
   | `[p\|text]` | optional text, kept with chance p | `[0.25\| {dune_epithet}]` |
   | `%(key)` | a value from the caller | `{product_%(class)}` |

4. **Checks**: a name that is too short or too long, contains a rude fragment
   (`config.json`), or contains a franchise name (`ip_blocklist.json`: `terms`
   anywhere, `name_terms` as whole words) is thrown away and re-rolled.
5. **The name book** (`NameBook`, in `WorldState.names`, saved with the game). It
   seeds the engine from (world seed, kind, key, attempt). If the name is already
   taken, it tries the next attempt. Otherwise it writes the name down for that
   key. Asking for the same key again returns the same name.

## What gets named, and where it is shown

A thing's data says how it is named, in a `naming` block. Code never picks a kind.

| Thing | Data | Key | Shown |
|---|---|---|---|
| Gate guards (any soldier) | `soldiers/*.json` `naming` (kind, `titles` list, `nameplate_range`) | `npc:<town>/<marker>` | floating over them within 8 m; F4 debug line; the bartender knows them |
| Pilots in space | `ships/*.json` `naming` (kind, titles, `callsign`) | `pilot:<encounter>/<sortie>/<id>` | the kill banner: `Kill · "Wasp" Lieutenant Selma Sakete` |
| Your ship | `ships/interceptor.json` `naming.vessel` | `vessel:player/<ship>` | the board prompt, the flight HUD, the same name in space |
| The jetpack | `items/jetpack.json` `naming` (equipment, class) | `item:<id>` | pick up / buy / sell prompts: `Jetpack (Embry XR-76 Skylark)` |
| The town and planet | `worlds/port_desert.json` `naming` | `town:<id>`, `planet:<world>` | a place card on arrival, the space banner, "Leaving <planet>...", the bartender's briefing |
| The bartender | authored ("Oda Vell") | `npc:bartender` | reserved in `config.json`, so it is never generated for anyone else |

Each sortie brings new pilots, keyed by a sortie counter in WorldState.

## Adding to it

- **More words:** edit `tools/names/lexicon_source.py`, run
  `python3 tools/names/lexicon_source.py`, and commit both. `tests/test_names.gut.gd`
  fails if a term is a franchise name, or if a grammar names a list that does not
  exist.
- **A new culture:** add a tongue and its lists, then a `person_<culture>` kind.
  Point a soldier's or ship's `naming.kind` at it.
- **A new kind of thing** (a moon, a cantina, a gang): add a kind to `KINDS`, then
  call `WorldState.names.name_for("<kind>", "<stable key>")`, or a `NameHooks`
  helper, when it spawns.
- **A different world:** `config.world_seed` changes every generated name at once.
  It is saved with the game, so a future "new game" can roll a fresh one.

## Why not train on a game's names

The issue suggested training on another game's NPC names. Those names belong to a
franchise, and this repo must stay IP-neutral (`tests/test_ip_neutral.gut.gd`). So
the library is original. It is written in the same spirit (military surnames,
desert clans, spacer nicknames, punchy callsigns), and a list of franchise names
(`name_terms`) keeps the generator from stumbling onto one.
