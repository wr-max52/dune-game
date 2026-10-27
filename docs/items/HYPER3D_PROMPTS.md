# Hyper3D prompts for gear and droids (issue #25)

Eight models, written against `docs/ART_DIRECTION.md`:

- Shapes over surfaces: big readable forms, a few sharp details, no greebles.
- Palette: gunmetal `#4A4E54`, brass, worn leather, with one accent (saffron
  `#D99A2B`, teal `#1F7A78`, madder `#A8322A`, oxblood `#6B1E1E`).
- Original, always: no tube hilts, no film blasters, no ball droids with blaster
  ports, no skull faces, no tube-headed hunter droids, no missile on a jetpack.
- Polygon budgets are set with `quality_override` (the characters came out at 500k
  triangles and had to be decimated; game props stay small).

Droids come in colour variants (`content/core/droids/droids.json`), so their main
panels are asked for in pale enamel, which the game tints per variant. Cargo cases
are one model, tinted per cargo. Glowing eyes, the blade's energy and the jetpack's
flames stay in code, so the models carry only the hardware.

Every generation id, retry and pick is in `content/look/gear_models.json`.

## Shared tail

Appended to every prompt:

> Stylized hard-surface game prop, big clean readable shapes, a few sharp details,
> no greebles, no text, no logos. Worn, sun-bleached desert finish, scuffed edges,
> matte metal. Original design, not from any film or game. Single object, centred,
> neutral background.

## 1. Pistol (`pistol`, coil pistol, ~10k)

> A compact heavy frontier energy pistol for a desert smuggler. Chunky gunmetal grey
> body like an old heavy revolver frame, with a copper induction coil wound around a
> short thick barrel shroud, a stubby muzzle ending in an orange emitter ring. Grip
> raked back like a revolver, wrapped in worn dark-brown leather, brass trigger guard
> and brass heel cap. No scope, no stock. Side profile reads as a revolver crossed
> with a coil.

## 2. Rifle (`rifle`, repeater, ~12k)

> A long frontier energy rifle. Gunmetal grey receiver with an oxblood red painted
> panel, long ribbed barrel shroud with three round cooling fins near the muzzle, a
> short brass-rimmed optic on a top rail, a boxy energy cell magazine in front of the
> trigger, a vertical fore grip under the barrel, and a straight skeletal stock with a
> worn leather cheek wrap. Long horizontal silhouette, not a real-world firearm.

## 3. Energy sword (`sword`, ~8k)

> A long straight one-handed sword, standing upright, point up. The blade is a narrow
> blackened forged-steel spine with a central fuller, about four and a half times as
> long as the hilt. Brass crossguard with short down-swept quillons, a grip wrapped in
> dark leather, a round brass pommel. A real sword, not a glowing tube, not a
> cylinder hilt.

## 4. Jetpack (`jetpack`, ~12k)

> A rugged twin-tank rocket backpack. Two upright brushed steel fuel cylinders with
> flat caps and saffron yellow bands, bolted to a dark flat backplate frame with brown
> leather strap anchors, two flared exhaust nozzles under the tanks with soot-black
> rims, and a small control box with one amber lamp between the tank tops. No missile,
> no rocket nose cone, no dome caps. The flat backplate is the side worn against the
> back.

## 5. Cargo case (`cargo_case`, ~6k)

> A rugged smuggler's cargo case: a low rectangular hard-shell crate with rounded
> dented corners, a light grey painted shell, chunky brass corner caps, two folding
> side carry handles, two heavy front latches, and a recessed window strip running
> around the lid seam. One faded saffron stripe across the lid.

## 6. Floating droid (`droid_floating`, ~10k)

> A small hovering scout drone. A body shaped like a smooth river stone, wider than
> tall, in pale off-white enamel panels with dark grey seams. One large round lens
> eye on the front in a thick brass bezel, two short stubby stabilizer fins on the
> sides, a ring-shaped hover thruster underneath, and a thin whip antenna bent back
> from the top. Friendly and rugged. Not a sphere, no gun ports.

## 7. Cargo droid (`droid_cargo`, ~15k)

> A squat cargo hauler robot, knee height. An open-top cargo bin body like a small mine
> cart, painted pale off-white with dark grey trim and one saffron stripe, riding on
> two short rubber tank treads. A small sensor head block at the front with one round
> lamp eye, and two short stub arms gripping the bin rim. Boxy, sturdy, friendly.

## 8. Assassin droid (`droid_assassin`, ~25k)

> A tall gaunt hunter robot, standing, slightly hunched forward. Long thin limbs of
> exposed pistons and dark joints, a narrow shield-shaped chest plate and shoulder
> plates in pale bone-white enamel. The head is a flat horizontal wedge like a hooded
> blade with one thin glowing slit, no face, no skull. The right forearm is an
> integrated long-barrel rifle held level and pointing forward; the left hand is a
> three-fingered claw hanging at the side. A tattered madder red cloth sash on the
> hip.

## Round 2 (shorter prompts; what the owner picked)

Round 1 drifted toward familiar archetypes: a red sniper rifle, an ornate fantasy
sword, a quadcopter, a wheeled rover. The pistol, jetpack and cargo case calls
timed out and were not re-sent. Round 2 led with the silhouette and the main
colour, in fewer words:

- **Rifle (picked):** "Sci-fi energy rifle, matte dark gunmetal grey all over, one
  small oxblood red stripe on the stock only. Long barrel shroud with three round
  cooling fins at the muzzle, a short boxy energy cell magazine, a small round brass
  iron sight, a simple straight stock. No telescopic scope. ..."
- **Floating droid (picked):** "Small hovering robot drone with no propellers and no
  legs. A smooth flattened egg-shaped shell like a river stone, off-white, with one
  big round camera eye in a brass ring ..." (it still grew legs)
- **Cargo droid (picked):** "Small cargo robot riding on two tank treads
  (caterpillar tracks), no wheels. Its body is an open-top metal bin like a mine
  cart ..." (it came out yellow; prep washes it grey)
- **Assassin droid:** round 2 made a spindly mantis; the owner picked round 1's
  plated humanoid.
- **Sword:** round 2 ("plain utilitarian sword ...") made three crossed katanas.
  Two laser-sword tries followed (a hilt alone, then a sword "whose blade is solid
  light"); both broke apart. The sword stays code-built.

Lesson: Rodin text mode is good at chunky, compact objects and bad at long thin
ones. Use agentic mode with reference renders for anything blade-shaped.
