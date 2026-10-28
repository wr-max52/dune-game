# Hyper3D prompts for the player, guard and cantina owner (issue #79)

Three whole-body costumes for the character kit, built the way the locals and
the issue #48 kit were (`content/look/character_models.json`, `local` and `kit`):

1. Generate each costume whole with Rodin Gen-2.5 (`rodin_generate`).
2. Rig it with the human template, turn it to the base body's rest pose, fit it
   onto the base body and cut it at the base body's head/torso/legs seams
   (`tools/look/fit_parts.gd`, `dress`). That keeps every outfit's cuts in the
   same place, so pieces mix.
3. Colour variants are texture recolours (`tools/look/recolor_fitted.gd`), not
   new generations, so each accent is one clean saturated hue.

What the prompts do for the split, since Rodin can't hand back labelled pieces
with a rig (BANG splits lose the rig, see DECISIONS.md):

- Ask for a hard visual break at the two seams the fitter cuts at: a collar ring
  at the base of the neck and a thick belt at the waist. The cut then lands on a
  material edge instead of through the middle of a jacket or a cape.
- Keep everything that belongs to one piece on that side of the seam: the guard's
  cape stops above the belt, the hat brim stays a head item.
- A-pose with space under the arms and between the legs, so arm and leg triangles
  don't fuse with the body (the issue's "arms and body are separate").
- Lead with silhouette and main colour, keep it short (round 2 of #25 showed long
  prompts drift to familiar archetypes). Each full prompt fits Rodin's 1024
  character limit.

Settings for all three: `tier` Gen-2.5-High, `mesh_mode` Raw, `quality_override`
60000 (the fitter decimates to 40–45k; the 500k defaults had to be cut down
before), `geometry_file_format` glb.

## Shared tail

Appended to every prompt:

> Full-body game character in a relaxed A-pose, arms angled down and away from
> the body with clear space under the arms, legs apart, empty gloved hands. Face
> fully covered, no skin showing. A distinct collar ring at the base of the neck
> and a thick belt at the waist give clean horizontal breaks between head, upper
> body and lower body. Gritty painterly realism, simple bold shapes, worn dusty
> finish, matte materials, no greebles, no text, no logos. Original design.
> Single character, centred, neutral background.

## 1. Player (`player`)

> A rugged, battle-worn space pilot. A worn dark brown-black leather jacket,
> open at the front, over a cream undershirt. Khaki cargo pants with side
> pockets, tucked into dark lace-up combat boots, black gloves, a dark leather
> belt. His face is fully covered by a dark cloth mask pulled up to the eyes,
> with bright glowing cyan round goggles. A dark hat with a modest brim that
> stays close to the head and a glowing cyan band around the crown; the head and
> hat are normal human scale.

Input: the concept's front and back views, cropped, plus this prompt. The
concept's colours win (owner's call), and the brim is kept modest so the head
piece fits on the guard's body.

## 2. Guard (`guard`)

> An interstellar marine in slim, close-fitting gunmetal grey armour plates over
> a dark undersuit, with armoured boots. Red accent paint on both shoulder pads
> and the upper chest plate. A matching gunmetal helmet covers the whole face,
> with one narrow horizontal eye slit glowing red and a short antenna on one
> side. A short ragged red cloth half-cape hangs from the shoulders down the back
> and ends above the belt. Dark utility belt with pouches.

Input: the concept's front and back views, cropped into two images, plus this
prompt. Concept and text agree, and the face is covered in both views.

## 3. Cantina owner (`cantina_owner`)

> A space-born adventurer woman. A rounded grey pilot helmet with ear cups and a
> short antenna, a full-face breathing mask with ribbed hoses curving down to the
> collar, and a wide ski-goggle visor in reflective yellow. A short mustard
> yellow tunic with a draped cowl hood around the shoulders, over a long-sleeved
> dark brown leather jacket; the tunic ends at the waist under the belt, nothing
> hangs below the belt. Brown leather pants, worn grey lace-up boots, grey
> gloves.

Input: the concept's front and back views, cropped, plus this prompt. The
concept's tunic is long and references tend to win over the prompt, so if it
still comes back long it gets trimmed at the belt in the fit step
(`trim_below`), keeping her legs mixable with anyone's.

## Decisions (owner, before generating)

1. **Player colours follow the concept**: dark leather jacket, cream undershirt,
   khaki pants. The concept views go in as references.
2. **Cantina owner's tunic ends at the belt**, so her legs mix with anyone's.
3. **All three characters** are in scope.
4. **The player's head must fit a guard's body**, so the hat brim is modest and
   the head is normal scale.

## Generations

| Piece | Generation | Rig (human template) | Source |
|---|---|---|---|
| player | d8edcd4d-c677-4a2d-a9d6-9bf95511e919 | 87225e2b-cd02-4690-8eea-7b1a0cf82873 | `player_full.glb` |
| guard | 6c15f9cd-8d84-4775-856f-638447246a19 | 2a576a9e-5b48-47d3-8f2e-2fbe975977f7 | `guard_full.glb` |
| cantina owner | ee1da12c-527b-4b87-be46-5ff9d73d57f8 | 2ca5dd83-1250-433d-b08f-e2c3e4750d87 | `cantina_owner_full.glb` |
| cantina owner legs | 593757f4-e787-45ab-b8ee-b0a139aebdd6 | (fitted, no rig) | `cantina_owner_legs.glb` |

Sources are in `assets/characters/kit/source/`.

**Guard: the first, de-lit run is the one used.** It came back white (texture
de-lighting bleached the gunmetal). A re-run without de-lighting
(acc0e2ef-a987-439f-b7a8-1d35db3d09c4) was gunmetal but too detailed for the game's
look, so the owner picked the simple white one. The fit bakes its white armour to
gunmetal grey (`recolor` in the kit's `dress.guard`).

**Player:** an earlier prompt-only run with the issue text's colours
(9412b9a3-0841-4bd0-ac01-6c479a7b2544) went out before decision 1 and is not used.

**Cantina owner's legs are their own piece.** Her tunic came back mid-thigh (the
references won over the prompt) and there is no body under it, so cutting at the
belt left a hole. The tunic hem goes to her upper body (`move` in `dress`, by
colour), front half only: the back of the hem is dropped (`drop_back`), so it hangs
like a tattered apron. Her legs are a separate prompt-only generation fitted into
the legs slot, so they go under anyone's torso. The prompt:

> A single pair of skin-tight dark brown leather riding trousers with pale grey-tan
> lace-up combat boots, displayed empty and standing on their own, a plain fitted
> waistband at the top. Slim close-fitting legs with subtle stitched knee panels,
> smooth worn leather, no pockets, no holsters, no straps, no belt. Nothing above
> the waistband: no body, no skin, no torso, no arms, no hands. Gritty painterly
> realism, simple bold shapes, matte materials, no text. Single object, centred,
> neutral background.

Two earlier tries are not used: "lower body only" came back on a bare mannequin
torso with arms (2cdc52de-0f37-43a1-aa91-849c8fe00d52), and a looser retry had
holsters and baggy legs (7f432ad5-37de-4558-b932-ee42f0fb676e). The picked one
stands turned about 30 degrees, so the fit turns it back (`yaw`) and trims the
strip of bare skin above its waistband (`trim_top`).

Raw review sheet: `docs/kit/79_raw.png` (`tools/look/sheets/19_issue79_raw.json`).
