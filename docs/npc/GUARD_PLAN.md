# Guards on foot (M15)

**Goal:** the gate guards feel like people with a job. They stand their post,
notice you, challenge you or wave you through depending on how the Remnant feels
about you, and fight properly when it goes wrong. What happens at the gate changes
the town, and the bartender hears about it.

**Product owner decisions (2026-10-26):**

| Decision | Choice |
|---|---|
| LLM? | **No.** Guards are authored barks and choices. The bartender stays the only LLM NPC. |
| Architecture | **The fighter pattern.** A pure brain writes a command; the body (on the player's own movement code) carries it out. |
| Default gate behavior | **Driven by standing with the Imperial Remnant** (`WorldState.standing.imperial_remnant`). |
| Order | Steps 1 to 3 first, check in and test, then continue. |

## The ten steps

| # | Step | Status |
|---|---|---|
| 1 | NPC body node | **DONE** (part 1, `src/systems/npc/npc_body.gd`) |
| 2 | Navmesh from town data | **DONE** (part 1, `src/systems/world/town_nav.gd`) |
| 3 | Perception | **DONE** (part 1, `perception.gd`, `noise_events.gd`; footsteps in part 2) |
| 4 | Guard brain | **DONE** (part 2, `src/systems/ai/guard_brain.gd`) |
| 5 | Soldier profile data | **DONE** (`gate_guard.json`: weapon, combat, patrol, checkpoint blocks) |
| 6 | Hostility from standing | **DONE** (`src/systems/ai/checkpoint.gd`) |
| 7 | Gate dialogue: barks + choice card | **DONE** (`gate_guard_lines.json`, `src/ui/checkpoint_hud.gd`) |
| 8 | Combat (shoot back, cover, alert) | **DONE** (`cover_picker.gd`, rifle on `NpcBody`, `gate_checkpoint.gd`) |
| 9 | Outcomes write the world | **DONE** (`WorldState.on_gate_bribe / on_guard_killed / on_player_downed`, 3 new rumors) |
| 10 | Headless trace + play test | trace **DONE** (`scenes/combat_trace.gd`); play test is yours |

**Product owner decisions for part 2 (2026-10-26):** the four standing bands as
drafted; bribes work one band lower after dark; kill the guards and run, and your
standing drops, but you can win.

## How part 2 is built

```
GateCheckpoint (node, the director)          one per gate, in town_demo
  reads bodies + WorldState  ->  Checkpoint (pure)    wave / papers / search / bribe / warn / hostile
                             ->  GuardBrain x2 (pure) patrol / attend / combat / search / return
  writes   body.command, aim, fire_at()   card + subtitles (CheckpointHud)   WorldState
  owns     cover spots (CoverPicker, from the town boxes), the player's knockout
```

The rules that decide what happens at the gate never touch a node, and the
brains never decide gate policy. Everything is a number in the profile.

**A fight, step by step:** warning (3 s) -> both guards fire an opening burst ->
each sprints to its own cover spot (a box between it and you, on its own side of
the gate) -> crouch 1.2 to 2.4 s -> stand, wind up 0.35 s -> burst of 3 to 5 only
if it can see you -> back down. No sight for 3 s: find a better spot or push to
where it last saw you. No cover at all: fight standing, sidestepping. Low health:
hides longer. A shot that hits: interrupts the burst. Guards never hurt each other.

**You win:** both down. Standing -10 for the fight, -15 per guard. The
checkpoint is no longer up, and Oda has two new rumors.
**You run:** out of sight and 70 m away for 12 s. They search near the gate
(on a 22 m leash), give up, and go back to their loops. Standing -5. They
remember your face for 5 minutes and open fire if they see you again.
**You lose:** knocked out, dragged to the pit, 20% of your credits gone
(5 minimum), full health, 3 s of grace. They stand down but remember.

## What part 1 gives a brain to work with

```
NpcBody                         (extends the player's character_body.gd)
  command.go_to / face / sprint / crouch      <- the brain writes these
  go_to(p), stop(), face_point(p), clear_face(), arrived(), is_moving()
  perception: Perception        -> visible, in_cone, awareness, noticed,
                                   last_seen_pos, since_seen, saw_weapon,
                                   heard, heard_pos, heard_kind, since_heard
  health (hp), dead, hits_taken; signals: hurt, died, noticed_target, lost_target
  nav: TownNav                  -> path(a, b), closest(p), is_ready
  post_id, post_pos, post_facing
```

Rules already true: a body with no orders holds its post and faces the way it was
placed; a dead body ignores orders; paths to unreachable points are flagged
(`last_path_ok = false`); a guard that stops making progress along its path skips
the corner and repaths.

## Part 2 as first planned (kept for the record)

### 4. `src/systems/ai/guard_brain.gd` (pure, RefCounted)

Same shape as `fighter_brain.gd`: `_init(profile, rng_seed)`, situation fields the
body fills each frame (perception summary, standing, flags, time of day, distance
to the player, own hp), `update(dt) -> state`, outputs the body reads (`go_to`,
`face`, `sprint`, `bark`, `fire`, `aim_point`, `alert`).

States: POST, PATROL (optional, from the profile), NOTICE, CHALLENGE, WARN,
COMBAT (hands off to `trooper_brain` + `squad_coordinator` for cover and fire),
SEARCH (walk to `last_seen_pos` or `heard_pos`, look around), RETURN (to post).

### 6. Hostility from Remnant standing (the decided default)

Thresholds live in the profile, not in code. A first cut:

| Remnant standing | On noticing you |
|---|---|
| 40 and up | Nod you through. |
| 0 to 39 | Challenge: "Papers." |
| -39 to -1 | Challenge, harder: papers **and** a search, or a bribe. |
| -40 and below | Hostile on sight: warn once, then open fire. |

Modifiers (each a profile number): a drawn weapon within 10 m escalates one step;
shots fired in the street (`shots_in_street`) escalate one step for a while; after
dark (`time_of_day`) the bribe works for one band lower (makes the
`r_east_gate` rumor true in play); range shots (`shot_range`) are ignored.

### 7. Gate dialogue

Authored barks in `content/core/dialogue/gate_guard_lines.json`, picked by state,
standing band and mood. The challenge opens the existing job/choice card UI:
[Show papers] [Bribe N cr] [Walk away] [Mouth off]. No free text.

### 8. Combat

Guards fire bolts through `WeaponActor` from the rifle's muzzle with aim error from
the profile, take cover through the squad coordinator, and alert every guard
within `alert_radius` (and the tower post once it is live). Hit reactions
(flinch, stagger on big hits) and `notify_hit()` like the fighter brain.

### 9. Outcomes

Through WorldState only: waved through, bribed (credits, a flag), searched, fought
(standing down, `gate_fight` flag, event log line), guard killed (bigger drop,
counter). The bartender reads it all for free.

### 10. Acceptance (part 2 trace)

Three scripted runs with real physics: high standing gets waved through, a bribe
after dark works, hostile standing becomes a firefight where both guards take
cover and the player can win. Then the product owner plays it with F4 on.

## Known limits carried into part 2

See KNOWN_ISSUES.md ("After M15 part 1"). The ones that matter for part 2: no
avoidance between NPCs, the navmesh stops at the town apron, eyes follow the body
not the head, and the tower and yard troopers are still statues.
