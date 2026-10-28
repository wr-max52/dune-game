# Shooter feel (issue #65)

Make on-foot combat feel like a shooter. Four work packages, each on its own
branch, merged into `claude/issue-65-planning-49ce46` and shipped as one PR.

## Done looks like (from the issue)

1. Zoom uses the weapon's scope or iron sights, lined up with the crosshair.
2. All guns are dark variants of what they are now. Scopes and sights work.
3. Rifle zooms 2x more than the pistol and has a scope. Pistol: iron sights.
4. Crouch while sprinting slides. It stands back up on its own, so sprint,
   slide, sprint flows without a break.
5. Any damage dealt shows a hit marker on the crosshair and plays a thud.
6. Enemies show health bars over their heads, not names.
7. First person arms: standard but more realistic, in the game's style, not
   overdone. Black gloves and black sleeves for every outfit for now.

## Packages

### A. Aim down sights, scope, dark guns
Files: `src/systems/player/player_avatar.gd` (ready/ADS transform, sight
meshes), `src/systems/combat/player_weapons.gd` (aiming -> zoom, crosshair),
`content/look/hand_weapons.json` (`ads` block per gun, dark tint),
`src/systems/camera/camera_rig_node.gd` only if needed.
- Each gun gets an `ads` block in data: the sight point in model space (rear
  sight / scope eyepoint), the eye distance, and the magnification. Pistol 1.25x,
  rifle 2.5x (2x the pistol's zoom). Camera FOV = base / magnification.
- In first person with aim on, the weapon blends (~0.15 s) to a pose that puts
  the sight line on the camera's centre line, so the front post / reticle sits
  on the crosshair. Solve it from the camera, not by hand-tuned numbers, so it
  stays true at any pitch.
- Rifle: a procedural scope (tube, rings, lens, reticle) mounted on top. Pistol:
  front post + rear notch if the model has none that reads.
- The crosshair hides while aimed in (the sight is the crosshair); hip fire
  keeps it. Third person keeps today's over-the-shoulder zoom with the new
  per-gun magnification.
- Dark variants: the guns render darker (retint or a darkening multiplier on
  their own textures), glow accents kept.

### B. Slide
Files: `src/systems/player/character_controller.gd` (pure slide state),
`src/systems/player/character_body.gd` (short capsule while sliding),
`src/systems/camera/camera_rig_node.gd` (eye drop + small roll),
`src/systems/anim/body_animator.gd` (slide pose).
- Pressing crouch (edge, not held) while sprinting on the ground above walk
  speed starts a slide: a speed boost, then friction over ~0.75 s, steering
  limited. Jump cancels it.
- When it ends the pose returns to standing even if crouch is still held
  (crouch has to be pressed again), and sprint resumes at once if held. Stays
  down if there is no room to stand.
- Guards share the body: they must never slide unless their command asks.

### C. Hit markers, thud, enemy health bars
Files: new `src/ui/hit_marker.gd`, a few lines in `player_weapons.gd`
(`hit_something` already fires for bolts and sword), a thud sound (generate
with a `tools/audio` script, like the others), `src/systems/npc/npc_body.gd`
(health bar replaces the nameplate).
- Any damage the player deals: four short diagonal ticks around the crosshair
  for ~0.2 s, red and bigger on a kill, plus a thud (a heavier one on a kill).
- Health bars: a billboarded bar over the head of NPCs that are enemies (hostile
  to the player, or hurt by them), not names. Hidden at full health when calm,
  hidden when dead.

### D. First person arms
Files: new `src/systems/look/fpv_arms.gd`, a small hook in `player_avatar.gd`.
- Proper forearms and hands for first person: tapered black sleeve with a cuff,
  black glove with a palm, knuckles, thumb and fingers wrapped round the grip.
  Muted, slightly rough materials. Replaces the primitive forearms the view shows
  today, for every outfit.

## Proof
Each package ships GUT tests (pure parts unit tested; scene parts in a trace or
a headless scene test), and `./scripts/ci.sh` passes after the merge.
