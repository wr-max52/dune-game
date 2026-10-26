# Plan — Desert Spaceport Vertical Slice

The 8 milestones for the slice, in build order. After each, stop and report in
the milestone-report format (plain English): what works, how to see it, what is
faked or stubbed, what broke, what is needed from the user, and confidence the
next milestone fits its scope.

Status:
- DONE = merged to main, tests passing in CI.
- WIP  = in progress on a feature branch (tests passing locally, not yet merged).
- TODO = not started.

| # | Milestone | Done means | Status |
|---|---|---|---|
| M0 | Project setup | Repo, pinned Godot version, folder structure, data layer loader, test framework (GUT), headless CI script, README with run instructions | DONE |
| M1 | Movement and cameras | Player walks the greybox port; FPV/TPV toggle works; headless move+toggle trace | DONE |
| M2 | Ranged combat | Both blasters work; 1 trooper uses cover and fights back; headless combat trace | DONE |
| M3 | Melee and deflection | Energy blade, stamina, block, timed deflection; duelist enemy; headless melee trace | DONE |
| M4 | World streaming | Walk port to desert with no hitch over 50ms; outpost built; frame-time log | DONE |
| M5 | Mission loop and save | Fixer, contract, crate, payout, save/load all working end to end; bot playthrough on every merge | DONE |
| M6 | LLM bartender (text) | Typed conversation, memory, 4 tools, guardrails, fallback, Kokoro voice | DONE |
| M7 | Voice input | whisper.cpp push-to-talk with the bartender; latency measured | DONE |
| M8 | Polish pass | Bug list cleared, performance report, 3 minute gameplay recording | DONE |
| M9 | Port town greybox | Town built from data, validated, 4 routes walked headless with real collision, worst frame < 50ms; light art dressing (decor layer); the town is the one demo and its pit launches the dogfight | DONE |
| M10 | Starfighter flight and dogfights | Data-driven ships, guns, pilots and encounters; flight model; shields + hull; fixed guns + lock-on seekers; fighter AI (pursue, attack, break, extend, evade); playable dogfight scene with HUD; any ship design swaps in from data; headless dogfight trace won end to end | WIP |

## Notes

- M9 is the port town, planned in `docs/town/TOWN_PLAN.md` (plus the decor
  addendum). M10 was numbered after it. Since M9 the town is the single demo:
  `run/main_scene` is `scenes/town_demo.tscn`, and flight is entered from the pit.

- One feature per branch, off the latest main; merge only when tests pass.
- Each gameplay system ships a headless trace/log plus GUT assertions; that trace
  is the CI proof. A rendered clip (scripts/record.sh) is the secondary proof.
- Bartender is the only LLM-driven NPC; all others use authored data-layer lines.
- The M5 bot playthrough talks to a deterministic stub, never real inference.
  Real LLM inference (M6) is a manual + recorded check.
- See DECISIONS.md for why; CHANGELOG.md for what shipped; KNOWN_ISSUES.md for
  what is faked or outstanding.
