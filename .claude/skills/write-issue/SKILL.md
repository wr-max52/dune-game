---
name: write-issue
description: Write a GitHub issue for this game from what the player (the user) wants. Use whenever the user asks to write, file, draft, open, split or scope an issue, a feature, a milestone or an epic, or describes something they want in the game ("I want a lava planet", "add a bounty hunter in the cantina"). Builds the request out of the game's existing parts (planets, towns, cantinas, outposts, native packs, the NPC kit) with as few new renders as possible, asks follow-up questions to settle must-haves and could-haves, and never re-architects the game.
---

# Writing an issue

The game is a box of lego. Almost everything a player asks for is a new
arrangement of parts that already exist: a planet config, a town size, a
cantina with a club block, a soldier profile on the NPC kit, an AI card, a
location file. Your job is to find those parts, ask the user what really
matters, and write an issue that says what the player will see and which parts
build it.

## The steps

1. **Say back what the player wants**, in one plain sentence, in the player's
   terms (what they see and do in the game, not how it is coded).
2. **Find the parts.** Go through the parts list below. For each one that fits,
   open its doc or file and check it still does what this skill says (grep the
   class, read the header comment). Check what happens in the game today
   ("Right now there is none: `CharacterBody` emits `landed` and nothing checks
   the speed").
3. **Sort every piece of the request** into one of four:
   - **data only**: a config, a profile, a card, a manifest line. Cheapest.
   - **small code on an existing part**: a new mode, a new block, a new action.
   - **a new part**: only when nothing in the list can do it. Build it in the
     same pattern as its neighbours (a planet component, a director, a pure
     brain) so the next issue can reuse it.
   - **architecture**: it needs one of the things in "What can NOT change".
     Do not put it in the issue. Tell the user why and offer the nearest thing
     the parts can do.
4. **Ask follow-up questions** (see "Questions"), with AskUserQuestion. Do this
   before drafting, every time, even when the request looks complete.
5. **Draft the issue** in the format below and show it to the user.
6. **Create it** with `gh issue create` once the user has okayed the draft,
   with labels (below). If it is size XL, write a parent issue and one child
   issue per PR, each child saying `Part of #N`.

You only write the issue. Do not start building it, branch or commit.

## Questions

Ask until you know the **must-haves** and the **could-haves**. Two or three
rounds of AskUserQuestion, up to four questions each, is normal.

- **Must have**: the issue fails without it. These become "Done looks like".
- **Could have**: wanted, but the issue ships without it. Put these in their
  own "Could have" section so the builder does them only if they come cheap.
- **Nice to have**: leave it out, unless it is easy, meaning it is data only or
  falls out of a part you are already using (a town style word, a second
  colour variant, one more line in a card). Easy ones go in "Could have"; the
  rest go in "Not in this issue".

Good questions are about what the player experiences, with the options drawn
from the parts that already exist:

- Where is it? (which planet, the town or the desert, an outpost, the cantina)
- Who is there? (locals, Remnant, a native pack, droids; armed or not; do they
  share the town brain and fight back)
- Do they talk? (an AI character with a card, or authored barks only)
- What does the player get or lose? (credits, an item, standing, a story flag)
- How does it end, and does it come back? (respawn on next visit, gone for good,
  saved with the world)
- What must it look like, and is a kit look good enough? (offer a mix of
  existing kit pieces and colours before a new render)

Recommend an option in each question (first, marked "(Recommended)"),
usually the one that reuses a part. When a request needs architecture, ask it
as a choice between the nearest buildable options, and say in one line why the
original cannot be done.

## Renders: as few as possible

A Hyper3D (Rodin) generation is the expensive step. Before writing one into an
issue, go down this list and stop at the first that works:

1. **Data only**: an existing model, archetype or look id.
2. **Mix and recolour**: kit pieces on the one skeleton (any head, torso,
   legs), colour variants, a `tint` on a model (Ilka is Oda's rig, tinted), a
   `base` archetype listing only what differs. The club band is "player
   torso and legs in black, white guard helmet", with no new render.
3. **Simple shapes**: props built from primitives in code, like the bottles,
   the DJ desk and the camp's tents (`LookMeshKit`, `ClubProps`,
   `NativeCamp`).
4. **One new render**: only if 1 to 3 cannot read right. Then name exactly what
   is rendered, prefer something that becomes a reusable kit piece (fitted
   onto the mannequin: `docs/kit/HYPER3D_PROMPTS.md`), and ask the user first.

Write which one you chose into the issue ("Built from existing NPC parts, not
new Hyper3D renderings").

## The parts (what to build with)

Check paths before citing them; things move.

### Planets
- **What:** a whole planet is one JSON file: type, town size 1 to 100, style,
  where it hangs in another planet's sky. No new scene, no new code.
- **Why:** a new place is a config, and every planet gets a town, a cantina
  with a stage, merchants, locals, its own Oda, a landing bay, smuggling and
  contracts for free.
- **Where:** `content/core/planets/<id>.json` + `content/core/manifest.json`;
  types in `content/core/planets/types.json` (sand, snow, red_desert, water,
  lava, gas, asteroid); `src/systems/planets/planet_gen.gd`;
  `docs/planets/PLANETS.md`. Grit Station is the reference small planet.
- **Planet components** a planet turns on with a block in its file: `natives`,
  `beast` (`planet_beast.gd`, `content/core/hazards/beast.json`), `barge`
  (`party_barge.gd`, `content/core/barges/`), `club`, `cantina_owner`,
  `encounter`. A new thing that lives on some planets should be another block
  like these.

### Towns and buildings
- **What:** a town is boxes, markers, routes and zones. It is either generated
  at any size (`TownGen`) or built to a saved layout (`port_round`,
  `port_square`).
- **Why:** valid by construction (validator V1 to V9), and the decor, guards,
  locals, nav, bar and ship all work on any town unchanged. A style restyles
  every material from one line of words.
- **Where:** `src/systems/planets/town_gen.gd`, `content/core/planets/town_kit.json`
  (counts, sizes, huts, towers, barracks from size), `content/core/towns/`,
  `src/systems/world/town_layout.gd` (the only reader and the validator),
  `docs/town/TOWN_PLAN.md`. Styles: `town_style.gd`,
  `content/look/town_styles.json`.
- **Building kit:** `town_buildings.gd` (doors, windows, building variants from
  a box's `look`), `town_market.gd` (stalls from `look: "stall"`),
  `stair_tower.gd`, `ring_wall.gd`, `pit_bowl.gd`, `town_decor.gd` (lamps,
  props; visual only).

### Cantinas and clubs
- **What:** every town has a cantina with a bar, a stage and its owner. A
  `club` block (`style`, `bpm`) dresses it as a club with a band, a crowd and
  the club mix.
- **Why:** the cantina is the game's hub: jobs, rumors, the AI owner, music.
  New social scenes belong here first.
- **Where:** `cantina_dressing.gd`, `club_dressing.gd`, `club_props.gd`
  (`dj_desk`, `drum_kit`, `upright_bass`, booths, neon, mirror ball);
  `src/systems/audio/sound.gd` + `club_music.gd` and `content/look/sound.json`
  (playlists, `club.moods`, `set_club_live`, `club_vibe`); performers and
  patrons are soldier profiles (`club_dj`, `club_drummer`, `club_bassist`,
  `local_patron`, `local_raver`, `cantina_dancer`); `docs/club/`.

### Outposts and places in the desert
- **What:** a footprint in world data plus a node that dresses it and stands
  people in it.
- **Why:** ships and speeders already collide with anything in world data; the
  node only adds the look, the ground and the people.
- **Where:** `content/core/locations/*.json` and landmarks in
  `content/core/worlds/port_desert.json`. Existing ones to copy:
  `remnant_outposts.gd` (seven Remnant outposts with troopers),
  `droid_merchant_outposts.gd` (huts, antennas, a keeper),
  `speeder_post.gd` (Skrugs's stall), `mechanic_yard.gd` (Dorrin's yard),
  `training_range.gd`, `starcruiser_wreck.gd`, `remnant_cruiser.gd`.
  Who holds a place: `src/systems/flow/territory.gd`.

### Native packs and animals
- **What:** a people that roams in packs with camps, trade, a hostile mode and
  reputation of its own; wild animals you can hunt.
- **Why:** a new people, weapons, colours, routes, trade goods or an animal of
  the sand pig's shape is data only.
- **Where:** `content/core/species/<id>.json` (templates with `base`),
  `content/core/fauna/<id>.json`, a planet's or type's `natives` block;
  `src/systems/natives/` (`natives_director.gd`, `native_camp.gd`);
  `docs/natives/NATIVES.md`.

### The NPC building framework
Every person in the game is built from the same five layers. A new NPC is
usually a new profile plus a look, on directors that already exist.

1. **Look:** `CharacterKit` archetypes in `content/look/characters.json`
   (`base` + only what differs; `model.parts` picks head, torso and legs as
   `piece:colour`, e.g. `guard:white`, `player:black`). Pieces and colours:
   `content/look/character_models.json` (`kit.part_colors`; the locals' three
   parts in six colours). `src/systems/look/character_kit.gd`,
   `skinned_body.gd`.
2. **Body:** `src/systems/npc/npc_body.gd`: the player's own movement,
   Health, Perception, path following, ragdoll death.
3. **Profile:** `content/core/soldiers/<id>.json` (with `base`): hit points,
   speeds, senses, weapons, patrol, props like `drinks`.
4. **Director and brain:** `Garrison` (Remnant: `checkpoint.gd`,
   `town_alarm.gd`, `guard_brain.gd`), `Townsfolk` (locals: shared town alarm,
   so hurting one makes the town fight), `NativesDirector` (packs). Animation
   loops: `club_moves.gd`, `native_moves.gd`, `body_animator.gd`.
5. **Talk (optional):** an AI character is a card
   (`content/core/npcs/<id>_card.json`) run by `NpcBrain`, placed with a
   `TalkSpot` on the town's `ConversationHost`; a body like `MerchantNPC` acts
   it out. Game effects only through actions checked by `ActionValidator`.
   Generated planets get an Oda variant from `planet_owner.gd`. Voices:
   `content/core/npcs/voice_profiles.json`.

Names for anything that spawns come from the name engine
(`src/systems/names/`, `docs/names/NAMING.md`), never typed by hand.

### Droids
- `content/core/droids/droids.json`, `src/systems/droids/` (`droid_kit.gd`:
  assassin, cargo and floating models, tinted per variant, primitives as
  fallback).

### Items, vendors, pickups
- `content/core/items/`, `content/core/vendors/`, `content/core/pickups/`,
  looks in `content/look/items.json`; `src/systems/items/`;
  `docs/ADDING_ITEMS.md`. A new item, shop or drop is data.

### Ships, guns, pilots, fights, vehicles
- `content/core/ships/`, `weapons/`, `pilots/`, `encounters/`,
  `content/core/flow/launch_pads.json`, looks in `content/look/ships.json`;
  `src/systems/flight/` (`ship_upgrades.gd`, `dogfight.gd`);
  `docs/ADDING_SHIPS.md`.
- Speeders: `content/core/vehicles/`, `src/systems/vehicles/`
  (`hover_model.gd`: the barge drives on it too).

### Story, jobs, rumors, world state
- Story chapters and optional quests: `content/core/story/main.json`,
  `src/systems/flow/story.gd`, `quests.gd`. Jobs on the board (smuggle,
  contract, supply): `content/core/board/bar_board.json`. Rumors:
  `content/core/rumors/`. What is true right now: `WorldState`
  (`src/systems/world/world_state.gd`). Saved with the world by
  `src/systems/save/save_system.gd`.

### Sound and effects
- `content/look/sound.json`, `src/systems/audio/sound.gd`,
  `content/look/npc_sounds.json`; `src/systems/look/explosion_fx.gd`,
  `look_materials.gd`, `engine_flame.gd`.

## What can NOT change

These are load-bearing. An issue never asks to replace, fork or work around
them. If a request needs one, say so to the user and offer what the parts can
do instead. Reasons are in `DECISIONS.md`.

1. **One scene for every planet.** `scenes/town_demo.tscn` builds whatever
   `GameFlow.planet()` says; travel reloads it as another planet. No scene per
   planet, town or level.
2. **Space is the town's own sky.** Take-off, space fights and re-entry run in
   the town scene (`SpaceFight`, `dogfight.gd`). No separate space scene for
   gameplay, no loading-screen hops.
3. **Planets are round and walkable all the way round** (planet's own up,
   issue #77), with seamless handoffs between them. No flat maps or cutaways.
4. **The town data format.** Boxes, markers, routes and zones, read only by
   `TownLayout` and passing the validator. Generated towns use the port's
   conventions (cantina ids, the pad's `ship` box, gate markers). Decor never
   moves a box or adds collision beyond props.
5. **The look layer is optional.** Gameplay never depends on art;
   `use_look = false` (the greybox) must still play. Styles restyle materials
   through `LookMaterials`, never per building.
6. **One movement for player and NPCs, one flight model for player and AI
   ships.** No NPC that moves, climbs or flies by its own rules.
7. **Pure brains, directors that run them.** Behaviour is a pure brain or a
   mode inside one, run by `Garrison`, `Townsfolk`, `NativesDirector` or the
   dogfight director. No second AI framework.
8. **`WorldState` is the one truth**, static and saved with the world.
   Systems write it when things happen; AI characters only read it. `Story`,
   `Quests` and `Territory` keep their state there. No second save or state
   store.
9. **One LLM pipe.** `ConversationHost` + `TalkSpot` + `NpcBrain` from a card;
   every game effect goes through `ActionValidator` and the output filter. A new
   AI character is a card, not a new pipeline.
10. **One human skeleton.** Every person is kit pieces on the one mannequin
    rig, recoloured. No new rigs or one-off skeletons.
11. **The data layer and IP neutrality.** Names, dialogue, weapons and numbers
    live in `content/core/`, looks in `content/look/`; generic terms only, no
    franchise names anywhere (`tests/test_ip_neutral.gut.gd`).
12. **The engine.** Godot 4.7.2, GDScript only. Classes are static or nodes;
    the only autoload is `NpcVoice`. No new autoloads, C# or plugins without the
    user saying so.

## The format

Match the issues already in the repo (#272, #274, #276, #291 are good ones).
Plain English, short sentences, the player's view first.

```markdown
<Title: Thing: what the player sees, in a few words>

Part of #N. / Follows #N. / Split out of #N.   (when it has one)

# What and why
Two or three sentences: what the player gets and why it matters.
Say what happens today if it helps ("Right now there is none").

# Done looks like
## <group, when there are several>
* **Bold lead-in:** one behaviour the player can see or do.
* Numbers (sizes, speeds, prices) are tunable in content data, not code.
* **Headless test:** a concrete scenario and its outcome
  (drop from three heights → no damage, some damage, dead).

# Could have
* Wanted, but the issue ships without it.

# Built from
The parts and files: `planet_gen.gd`, a `club` block, the `local_patron`
profile, kit pieces `guard:white` + `player:black`. Say which render level
(data / mix / shapes / one new render).

# Not in this issue
* Deferred nice-to-haves and the separate issues they belong to.

# Still open
* Only questions the user chose to leave for later.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

Rules for the text:
- Must-haves in "Done looks like", could-haves in "Could have", nothing else
  slips in.
- Every behaviour is something the player can check, not an implementation
  step.
- Link related issues by number (`#77`, `#104`) so the builder can read them.
- Use the game's own names for things (Oda, Skrugs, Grit Station, the pit, the
  Remnant), never franchise names.
- Give a check: a headless trace or test, and a still or clip when it is
  visual.

## Labels

- One type: `enhancement` or `bug`.
- One size: `size: S` (one focused PR, a day or less), `size: M` (one solid
  PR, a few days), `size: L` (two or three PRs), `size: XL` (epic: split into
  child issues before building).
- Areas that fit: `area: world`, `area: cantina`, `area: visuals`,
  `area: llm-npcs`, `area: saves`, `area: performance`.
- `blocked` if it waits on another issue.
