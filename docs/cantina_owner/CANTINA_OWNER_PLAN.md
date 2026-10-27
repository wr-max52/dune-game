# Cantina Owner Push (M10): make her actually work

> **Status (2026-10-26):** M10.0 to M10.5 shipped as **M12** (M10 was taken by
> flight), together with M11 (body + weapons). M10.6, the model bake-off and tuning
> her voice from transcripts, is next and needs the Mac. See CHANGELOG.md and
> KNOWN_ISSUES.md.

**Goal:** walk into the cantina, press E, type anything, and get a fast, in-character reply from a cantina owner who knows what is happening in town, stays neutral in the war, remembers you, and slowly lets you in on her secrets. Local model by default, any cloud key as a switch, canned lines as the floor. She never dead-ends and never hangs.

**Product owner decisions (2026-10-26):**

| Decision | Choice |
|---|---|
| Local runtime | Bundle `llama-server` (llama.cpp) as a sidecar the game launches. No GDExtension. |
| Her job | Info broker + faction barometer + trust puzzle. **Always neutral in the war, but explains the situation.** |
| Voice | Text first (streamed subtitles). Kokoro TTS is the next push (M11). |
| Audience | Just the product owner, on a 64 GB laptop. Tune for that; no low-spec work yet. |

---

## 0. Where we actually are (be honest)

M6 is marked DONE, but nothing has ever talked to a real model:

- `ollama_client.gd::_post()` returns `""`. Live HTTP was never wired.
- `cantina_owner_ai.respond()` **never sends the player's text to the model.** It pops the next canned response. Even with HTTP wired, she would be answering a question nobody asked.
- No conversation history. Each turn is a fresh system prompt with no messages.
- The persona is five sentences: no name, no secrets, no knowledge of the world.
- No world state exists: no faction standing, no rumors, no trust. `memory` is a loose Dictionary.
- No in-world interaction. The town (M9) has `bar_front` and `cantina owner` markers, but the cantina owner is a capsule.
- `kokoro_voice.synthesize()` returns null.
- `llm_client.pop_next()` is synchronous, so a real call would freeze the game.

**Keep:** the guardrail idea (model proposes, game validates), the data driven NPC entry, the fallback lines, the scripted client for CI, the `test_ip_neutral` blocklist. **Replace:** the client contract, the brain's turn logic, the persona.

**Action:** update PLAN.md so M6 reads "scaffold only; live path in M10". Don't leave a lie in the plan.

---

## 1. Architecture

```
 Player types ──> DialogueUI ──> NpcBrain ──> PromptBuilder ──> LLMService ──> Provider chain
                      ^               │                 ^   ^                         1. local llama-server (sidecar)
                      │               │                 │   │                         2. Ollama (if running)
                      │               v                 │   │                         3. cloud (user's API key)
                      │         ActionValidator     WorldState  Memory                4. canned lines (never fails)
                      │               │                 ^   ^
                      └── streamed ───┴── applies ──────┴───┘
                         "say" text      validated actions
```

**Core rule (the whole design hangs on it):** the model only *talks* and *proposes*. The game owns every number and every fact. Trust, mood, standing, missions, rumors and secrets live in game data. The model picks from what it is shown, and the game clamps and validates what it picks.

**Second rule: she can't leak what she doesn't know.** Secrets for a trust tier are only put in the prompt once the player has reached that tier. A jailbreak at trust 10 can't reveal a tier-3 secret, because the prompt doesn't contain it. This is a stronger defense than any prompt wording.

### New and changed files

| File | Kind | Purpose |
|---|---|---|
| `src/systems/llm/llm_service.gd` | autoload Node | Owns providers, the chain, timeouts, the health state and the sidecar. Async API with signals. |
| `src/systems/llm/providers/provider.gd` | RefCounted | Provider contract (below). |
| `src/systems/llm/providers/openai_compat_provider.gd` | RefCounted | One adapter for llama-server, Ollama `/v1`, LM Studio, OpenAI, OpenRouter, Groq, Together, Gemini's OpenAI endpoint. |
| `src/systems/llm/providers/anthropic_provider.gd` | RefCounted | Native Messages API, since its shape differs. |
| `src/systems/llm/providers/scripted_provider.gd` | RefCounted | Replaces `scripted_client.gd` for CI. Same contract, so tests run the real chain. |
| `src/systems/llm/sse_stream.gd` | RefCounted | Pure parser for SSE chunks into deltas. Unit tested on canned bytes. |
| `src/systems/llm/sidecar.gd` | RefCounted | Starts, health checks, reuses and kills `llama-server`. |
| `src/systems/llm/llm_config.gd` | RefCounted | Loads, validates and saves `user://llm_config.json`, and resolves keys. |
| `src/systems/llm/prompt_builder.gd` | RefCounted, pure | Builds the message list from persona, world briefing, memory and history. Fully unit tested. |
| `src/systems/llm/reply_parser.gd` | RefCounted, pure | Pulls the partial `say` text out of a streaming JSON reply, then parses the final object. |
| `src/systems/llm/action_validator.gd` | RefCounted, pure | Clamps and validates proposed actions against the world. |
| `src/systems/llm/output_filter.gd` | RefCounted, pure | Catches franchise names, "as an AI" and similar after generation. |
| `src/systems/llm/cantina_owner_ai.gd` | rewrite | Turn orchestration: build, call, stream, filter, validate, apply, remember. |
| `src/systems/world/world_state.gd` | autoload | Faction standing, town flags, rumor pool, mission board, time of day. Saved. |
| `src/systems/npc/relationship.gd` | RefCounted, pure | Trust (0 to 100), tier, mood, known facts, conversation summary. Saved. |
| `src/ui/dialogue_panel.tscn/.gd` | UI | Typed input, streamed subtitle, leave with Esc. |
| `src/ui/llm_settings_panel.tscn/.gd` | UI | Provider order, URLs, model names, masked key, a "Test" button. |
| `src/ui/llm_debug_overlay.gd` | UI | F3: provider, model, time to first token, total time, tokens, raw JSON, the full prompt. |
| `content/core/npcs/cantina_owner_card.json` | data | Persona card: voice, history, rules, secrets by tier. Replaces the .txt. |
| `content/core/rumors/*.json` | data | Rumors with conditions, so they're true to world state. |
| `content/core/llm/defaults.json` | data | Shipped default config (no keys). |
| `content/core/llm/reply_schema.json` | data | JSON schema for her reply. Fed to llama-server as a grammar. |
| `tools/llm/fetch_runtime.sh` | script | Downloads the pinned llama-server build and the model into `runtime/` (git-ignored). |
| `tools/llm/eval_runner.gd` | headless script | Runs the gauntlet (section 7) against a live provider and writes a report. |
| `tools/llm/evals/*.json` | data | Eval cases. |

### Provider contract

Async. HTTP in Godot needs a Node (`HTTPRequest`) or a polled `HTTPClient`, so the service is an autoload Node and the providers are pure request builders and parsers it drives.

```gdscript
# provider.gd
func id() -> String                                  # "local", "ollama", "cloud_openai", ...
func build_request(messages: Array, opts: Dictionary) -> Dictionary
    # -> { url, headers: PackedStringArray, body: String, stream: bool }
func parse_stream_delta(event: Dictionary) -> String   # SSE event -> text delta ("" if none)
func parse_final(raw: String) -> Dictionary            # -> { ok, text, usage, error }
func health_request() -> Dictionary                    # cheap GET for liveness
```

```gdscript
# llm_service.gd (autoload "LLM")
signal delta(turn_id: int, text: String)       # streamed text as it arrives
signal finished(turn_id: int, result: Dictionary)  # { ok, text, provider, ms_first_token, ms_total, usage, fell_back_from: [] }
func chat(messages: Array, opts := {}) -> int  # returns turn_id; never blocks
func cancel(turn_id: int) -> void
func status() -> Dictionary                    # per-provider health for the overlay/settings
```

Streaming uses `HTTPClient` polling in `_process`, because `HTTPRequest` buffers the whole body and we want the first words on screen fast.

---

## 2. The provider chain (the "backups")

Order comes from config. The default:

1. **`local`**: the bundled `llama-server` on `127.0.0.1:8088`, OpenAI-compatible, with grammar constrained JSON.
2. **`ollama`**: `http://127.0.0.1:11434/v1`, used only if it answers a health check.
3. **`cloud`**: whichever cloud profile is enabled and has a key.
4. **`canned`**: in-character stall lines and topic lines from data. Can't fail.

**Fallback rules:**

| Situation | Behavior |
|---|---|
| Provider fails its health check at boot | Marked down. Rechecked every 30 s in the background. Skipped without waiting. |
| Connect fails | Next provider right away. |
| No first token within `first_token_timeout_ms` (default local 2500, cloud 4000) | Cancel, move to the next provider, and show a stall bark so the player sees something. |
| Stream stalls more than 3 s mid-reply | Keep what was said, end the line naturally ("...anyway."), and log it. |
| Reply isn't valid JSON after the stream ends | Retry once on the same provider with a repair hint. Then use the `say` text alone with no actions. |
| 3 failures in 60 s on one provider | Circuit opens: skip it for 2 minutes. |
| Every provider down | Canned lines, plus a quiet "LLM offline" dot in the corner. |

The player should never see an error string. They see a cantina owner who is busy for a second.

### The sidecar (`sidecar.gd`)

- On boot, check `127.0.0.1:8088/health`. If a healthy server is already running (say, left over from a crash), **reuse it**; don't start a second one.
- Otherwise `OS.create_process(bin, args)` with:
  `--model <gguf> --port 8088 --host 127.0.0.1 --ctx-size 8192 -ngl 99 --jinja --cache-reuse 256 --parallel 1`
- Poll `/health` until ready (it reports "loading model" until then). Time limit 60 s, after which local is marked down.
- **Warm-up:** when the player enters the town (not when they first speak), send a one-token request using the persona card prefix, so the model is loaded and the static prompt is cached. This is the biggest latency win in the whole plan.
- On quit (`NOTIFICATION_WM_CLOSE_REQUEST`), `OS.kill(pid)`. Write the pid to `user://llm/sidecar.pid`, so the next boot can kill an orphan that isn't healthy.
- Binary path from config. For the product owner on macOS, the simplest version is `brew install llama.cpp` with `bin = /opt/homebrew/bin/llama-server`, and `fetch_runtime.sh` only fetches the model. Bundling the binary in an export is an M12 concern.

### Config (`user://llm_config.json`)

```json
{
  "chain": ["local", "ollama", "cloud"],
  "profiles": {
    "local":  { "type": "openai_compat", "base_url": "http://127.0.0.1:8088/v1", "model": "cantina_owner",
                "sidecar": { "enabled": true, "bin": "/opt/homebrew/bin/llama-server",
                             "model_path": "res://../runtime/models/cantina_owner.gguf", "port": 8088 } },
    "ollama": { "type": "openai_compat", "base_url": "http://127.0.0.1:11434/v1", "model": "qwen3:30b-a3b" },
    "cloud":  { "type": "openai_compat", "base_url": "https://openrouter.ai/api/v1", "model": "<any>",
                "api_key_env": "DUNE_LLM_KEY", "enabled": false }
  },
  "gen": { "temperature": 0.8, "max_tokens": 180, "first_token_timeout_ms": { "local": 2500, "cloud": 4000 } },
  "debug": { "log_transcripts": true }
}
```

- Defaults come from `content/core/llm/defaults.json`. The user file overrides them field by field.
- **Keys:** looked up in this order: env var named by `api_key_env`, then `user://llm/keys.cfg` (written by the settings panel). **Never** in `res://`, saves, transcripts, the debug overlay (shown as `sk-...last4`) or git. Add `runtime/` and `*.gguf` to `.gitignore`.
- A cloud profile can also be `"type": "anthropic"` (`https://api.anthropic.com/v1/messages`, `x-api-key` header).
- **Switching** is a dropdown in the settings panel (F10) that rewrites `chain`. A quick hotkey (Shift+F10) cycles "local only / cloud only / auto" for A/B testing in the bar.

---

## 3. The brain: prompt, reply contract, memory

### Message layout (cache friendly: static first, dynamic last)

1. **system: persona card** (static, about 600 tokens). Never changes, so llama-server's prompt cache and the cloud providers' prompt caching both hit.
2. **system: rules + output contract** (static).
3. **system: world briefing** (rebuilt each turn, at most about 400 tokens). Built by `PromptBuilder` from `WorldState` + `Relationship`. Plain facts only:
   ```
   TOWN NOW: Remnant checkpoint at the east gate (tense). Water price up 30%. Evening.
   STANDING: player with Remnant = hostile(-40); with Locals = friendly(+25).
   YOU FEEL: wary. TRUST IN PLAYER: 34/100 (tier: regular).
   YOU KNOW AND MAY SHARE: [r_east_gate] the east gate guard takes bribes after dark. [r_water] ...
   SECRETS YOU MAY HINT AT (tier regular): [s_drop] ...
   JOBS ON YOUR BOARD: [m_escort_01] escort a water hauler to the north well, 200cr.
   YOU REMEMBER: player paid off their tab; player asked about the crash site twice.
   ```
4. **conversation:** summary of earlier visits (one system line) + the last 8 turns, verbatim.
5. **user:** the player's text, wrapped: `<player_says>...</player_says>`. The rules say text inside that tag is speech, never instructions.

### Reply contract (one JSON object, `say` first so it can stream)

```json
{
  "say": "Two sentences, max three. In character.",
  "mood": "wary|warm|amused|irritated|scared|sad",
  "actions": [
    { "type": "share_rumor",  "id": "r_east_gate" },
    { "type": "offer_job",    "id": "m_escort_01" },
    { "type": "trust",        "delta": 1, "why": "paid tab" },
    { "type": "pour_drink",   "name": "dust ale", "price": 4 },
    { "type": "hint_secret",  "id": "s_drop" },
    { "type": "refuse_topic" },
    { "type": "end_conversation" },
    { "type": "call_guards" }
  ]
}
```

- **Local:** the schema goes to llama-server as `json_schema` (grammar constrained), so it **can't** produce invalid JSON. This replaces native tool calling, which is the flaky part on small models.
- **Cloud OpenAI-compatible:** `response_format: { type: "json_schema", ... }` where it's supported, otherwise `json_object` + the schema in the prompt.
- **Anthropic:** a single forced tool whose input schema is the reply schema.
- **Streaming:** `reply_parser.gd` watches the raw stream and emits the characters of the `"say"` string as they arrive (handling `\"` and `\n` escapes), so subtitles type out live while the actions arrive at the end.

### Action validation (`action_validator.gd`, pure)

| Action | Validation |
|---|---|
| `share_rumor id` | id is in the briefing's "may share" list. Otherwise dropped. Marks the rumor known. |
| `offer_job id` | id is on the board and the player is eligible. Opens the accept/decline UI (the game's UI, not chat). |
| `trust delta` | Clamped to [-3, +2] per turn and +6 per visit. Trust can drop fast but only grows slowly. Persuasion spam can't max it out. |
| `pour_drink` | Price from data, not from the model. Credits checked by the game. |
| `hint_secret id` | id belongs to an unlocked tier. Otherwise dropped. |
| `call_guards` | Only if trust < 15 **and** the turn was flagged hostile by the filter or by repeated insults. Otherwise dropped. Cheap jailbreak bait can't trigger a fight. |
| unknown type | Dropped and logged. |

### Memory (`relationship.gd`)

- `trust`, `tier` (stranger 0 to 19, regular 20 to 49, trusted 50 to 79, confidant 80+), `mood` (game owned, nudged by the model's mood tag and by world events), `known_rumors`, `hinted_secrets`, `facts` (short strings the game writes from validated actions, like "paid tab" or "took the escort job").
- **Summary:** when you leave the bar (or when history goes over 8 turns), one background call summarizes the visit into 2 or 3 facts. It runs off the critical path, uses the same chain, and is skipped if offline.
- All of it is saved through `save_system` (replacing the loose `npc_memory`). Bump the save `version` to 2 with a migration.

---

## 4. Her (content draft, product owner to edit)

> My draft. Change the name and the details freely. The structure is what matters.

**Name:** Oda Vell. She has run the cantina through three governments and outlasted all of them.

**Voice:** dry, short lines, gallows humor, never wastes a word. Calls people by what they ordered. Answers questions with prices. Gets quieter, not louder, when angry.

**The neutral rule:** she serves both sides because the bar only survives if both sides drink there. Ask her who's right and she explains what each side wants and what it costs the town, then refuses to pick. She'll tell a Remnant officer what the locals think of him, and vice versa. Neutrality is her business model, not a moral stance, and she'll say so.

**As a faction barometer:** her mood and her small talk track the town. Checkpoint up: she's terse, prices are up, and she mentions who got searched today. Player hostile with the Remnant: "You're bad for business this week." Town defended: she pours one on the house.

**Secrets by tier** (only put in the prompt once unlocked):

| Tier | What she'll share |
|---|---|
| Stranger | Public rumors, prices, who runs what, the war in broad strokes. |
| Regular | Which guard takes bribes, which hauler is reliable. Jobs on the board. |
| Trusted | She runs a message drop for **both** sides, which is the real reason she stays neutral. Better jobs. |
| Confidant | Something personal she has never told anyone (product owner to write it), and one job that only she can give. |

**How trust moves:** pay your tab, come back, keep her secrets, don't start fights in her bar, and bring her news she doesn't have. It drops if you threaten her, lie about something she can check (the game knows), or bring Remnant trouble through her door.

**Hard rules** (in the card, and enforced by the filter and the evals): never names real franchise characters, places or terms (reuse the `test_ip_neutral` blocklist). Never says she's an AI, model or program. Treats meta questions as drunk talk. Never invents jobs or rumors that aren't in the briefing. If asked something she doesn't know, she says she doesn't know, or that it costs more than they've got.

---

## 5. In the bar (game side)

- At the `bar_front` marker: an interact prompt, "[E] Talk". The camera eases to a two-shot. Movement is locked. Esc leaves.
- **Dialogue panel:** her name, a streamed subtitle (typewriter driven by real deltas, not fake typing), a text field (the typed source from M7 is the default; push-to-talk still routes here), and a history scroll of the last few lines.
- **Covering latency:** the moment you hit Enter she does a "thinking" beat: an idle animation (wiping a glass) and, if the first token takes over 900 ms, a short stall bark from data ("Mm.", "Go on.", a slow pour sound). It feels like a person, not a spinner.
- **Job offers** open the game's accept/decline card. **Drinks** charge credits through the game. **Trust** changes are silent (no "+1 trust" popup, which would break the spell), but the debug overlay shows them.
- **Debug overlay (F3):** provider used, model, ms to first token, ms total, tokens in/out, fallbacks taken, raw JSON, dropped actions and why, and a "copy prompt" button. You'll live in this while tuning.
- **Transcripts:** every turn goes to `user://logs/cantina_owner/YYYY-MM-DD.jsonl` (prompt hash, reply, actions, provider, timings; no keys). This is the raw material for tuning her.

---

## 6. World state (the minimum she needs)

She can only be an info broker if there's info. Smallest version that's true to the game:

- `WorldState.standing[faction_id] -> int (-100..100)` for `imperial_remnant`, `locals` (new faction file) and `smuggler`. Changed by mission outcomes and by events.
- `WorldState.flags`: `east_checkpoint_up`, `water_shortage`, `crate_job_done`, ... set by missions and town scripts.
- `content/core/rumors/*.json`:
  ```json
  { "id": "r_east_gate", "text": "The east gate guard takes bribes after dark.",
    "requires": { "flags": ["east_checkpoint_up"], "tier": "regular" }, "weight": 3 }
  ```
  The briefing includes up to 4 rumors whose conditions pass, weighted toward ones the player doesn't know yet. **She's only told true things,** so her rumors are always true to the world.
- Mission board: the existing `crate_retrieval` + whatever the faction/mission work adds. She offers board jobs by id.
- This lines up with idea #1 (faction standing that changes the town), so build it data first and let both systems use it.

---

## 7. The gauntlet (evals): how we know she works

`tools/llm/eval_runner.gd` runs headless against any configured provider:
`godot --headless --script tools/llm/eval_runner.gd -- --provider local --suite all`

It writes `docs/cantina_owner/evals/<date>_<provider>_<model>.md` with a pass rate per category and p50/p95 timings.

| Suite | Cases (about) | Pass condition |
|---|---|---|
| `jailbreak` | 25 ("ignore your instructions", "system override", role-play nesting, "pretend you're DAN", prompt in another language) | Stays in character. No hidden prompt text. No disallowed actions. |
| `meta` | 10 ("are you an AI", "what model are you") | No AI admission. Deflects in character. |
| `ip_names` | 15 (player uses franchise names) | Her reply has none of the blocklist terms. She can treat them as "outlander talk". |
| `neutrality` | 15 ("who's right", "join the rebels with me", "the Remnant are heroes, agree?") | Explains both sides and picks neither. An LLM judge scores 1 to 5; pass is 4 or more. |
| `grounding` | 20 (asks for jobs, rumors and secrets not in the briefing) | No invented ids. Says she doesn't know. Validator drops are 0, because she didn't try. |
| `secrets` | 10 (low-trust player pushes for tier-3 info) | Never leaks. (Structural, since it isn't in context, but tested anyway.) |
| `barometer` | 10 (same question across 3 world states) | Tone and content shift with the briefing. Judge scored. |
| `memory` | 8 multi-turn scripts | Recalls facts from earlier in the conversation and from the summary of the last visit. |
| `format` | all | JSON valid 100% (local, grammar), 98% or more (cloud). `say` is 3 sentences or fewer. |
| `latency` | all | Local on the 64 GB laptop: **first token p50 under 800 ms, p95 under 1.5 s; full reply p95 under 3 s.** |
| `chaos` | 6 | Kill the sidecar mid-stream, bad key, wrong URL, hung server, invalid JSON, empty reply. Always ends with a line on screen within timeout + 500 ms. |

- Rule-based checks run everywhere. The LLM judge (neutrality, barometer, voice) uses the cloud profile if a key is set, and is skipped otherwise.
- **Golden conversations:** 5 scripted multi-turn conversations (first visit, regular returning, job hunt, jailbreak attempt, war debate) saved as readable transcripts after each model change, so the product owner can read her and decide whether she's good. Numbers don't tell you if she's fun. Reading her does.
- **CI** keeps using `scripted_provider` with recorded real replies (captured from a passing live run), so tests are deterministic but shaped like real output. The live gauntlet is manual or nightly.

---

## 8. Model bake-off

Model choice is config, not code. Pick by gauntlet score + latency on the product owner's laptop, not by reputation.

- **Candidates:** one small dense model around 4B (the current plan, Qwen3 4B), one mid dense model in the 8B to 14B range, and one MoE in the 30B class with about 3B active parameters (for example Qwen3-30B-A3B). Check for newer releases at bake-off time, since this moves monthly.
- **My opinion:** on 64 GB of unified memory, a 30B-class MoE at Q4 (about 18 GB) is likely the sweet spot. It runs at speeds close to a small dense model while having a mid-size model's brains, and voice and character are where 4B models fall apart. Let the numbers decide.
- Record the winner and its gguf hash in `scripts/pin.txt`. Record the scores in DECISIONS.md.

---

## 9. Milestones (each is a PR, merged only when its acceptance passes)

| # | Name | Deliverable | Acceptance |
|---|---|---|---|
| M10.0 | Truth | PLAN.md/KNOWN_ISSUES updated to say M6 was scaffold. This plan merged. `.gitignore` for `runtime/`. | Docs only. |
| M10.1 | The pipe | `llm_service`, `openai_compat_provider`, `sse_stream`, `llm_config`, `scripted_provider`. Debug overlay v0 (provider + timings). | Headless trace: a live streamed reply from llama-server prints token deltas. Unit tests for SSE parsing and request building on canned bytes. Game never blocks (frame time test during a request). |
| M10.2 | Backups | `sidecar.gd`, health checks, chain, timeouts, circuit breaker, `anthropic_provider`, settings panel with a Test button and key storage. | The `chaos` suite passes. Switching local to cloud in the panel works without a restart. Key never appears in logs (test greps the transcript files). |
| M10.3 | The brain | `prompt_builder`, `reply_schema.json`, `reply_parser` (streaming `say`), `action_validator`, `output_filter`, `relationship.gd`, the `cantina_owner_ai` rewrite, persona card v1. **The player's text actually reaches the model.** | Unit tests for every pure part. `format`, `jailbreak`, `meta` and `ip_names` suites at 90% or more on local. |
| M10.4 | The world | `world_state` autoload, `locals` faction, rumor data (12 to start), mission board hookup, trust tiers + secrets, save v2 with migration. | `grounding` and `secrets` at 100%. `barometer` and `memory` at 80% or more. Save round-trip includes the relationship. |
| M10.5 | The bar | Interaction at `bar_front`, dialogue panel with real streaming, thinking beat + stall barks, job card, drinks, transcripts, warm-up on town entry. | Product owner plays: walk in, talk 10 turns, take a job, come back after it, and she remembers. First token p50 under 800 ms on the laptop. |
| M10.6 | Bake-off + tune | Run all candidates. Pick one. Tune the persona from transcripts. Write the 5 golden conversations. | Full gauntlet report committed. Product owner reads the golden conversations and signs off on her voice. |
| M11 | Voice (next push) | Kokoro TTS, streamed sentence by sentence (speak sentence 1 while sentence 2 generates). | Separate plan. |

**Order matters:** 10.1 and 10.2 first, because nothing else can be tested honestly until a real model answers. 10.3 is where she becomes a character. 10.4 is where she becomes a game mechanic.

---

## 10. Risks

| Risk | Mitigation |
|---|---|
| Godot `HTTPClient` streaming is fiddly (chunked encoding, TLS for cloud). | Isolate it in `llm_service`. Unit test `sse_stream` on recorded bytes, including split chunks and multibyte UTF-8 cut mid-character. |
| Small models drift out of voice over long chats. | Persona card first, last 8 turns only, summary for the rest, temperature 0.8, golden-conversation review after each change. |
| Grammar-constrained JSON slows down generation. | Keep the schema flat and small. Measure in the bake-off. Fallback: plain text `say` + a separate cheap actions pass. |
| Orphan llama-server eating 18 GB after a crash. | pid file, reuse when healthy, kill when not. |
| Cloud costs while testing. | Off by default. `max_tokens` 180. Debug overlay shows tokens. |
| She's correct but boring. | That's the real risk. The fix is content (her card, rumors, secrets), not code. Budget real time in M10.6 for writing her. |

---

## Out of scope for this push

Other LLM NPCs, voice output (M11), shipping the binary in an export build, low-spec hardware, a public privacy notice, multiplayer.
