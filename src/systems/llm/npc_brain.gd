class_name NpcBrain
extends RefCounted
## An AI character's turn logic (M12; shared since #42). One brain per character,
## built from that character's card (the Cantina Owner's by default, Skrugs's at
## the outpost): who they are, what they may do, their canned lines. Originally
## the cantina owner's turn logic (M12). Replaces the M6 scaffold (cantina_owner_ai.gd,
## kept only for the M6/M7 traces): this one actually sends the player's words to
## a model, streams the answer, and turns the model's proposals into game effects
## only after they pass the validator.
##
##   player text -> screen -> PromptBuilder (persona, rules, briefing from
##   WorldState + Relationship, last 8 turns) -> LLMService (local -> ollama ->
##   cloud) -> ReplyParser (streams "say") -> OutputFilter -> ActionValidator ->
##   apply (rumors known, jobs offered, drinks charged, trust) -> remember
##
## If every provider fails she still answers, from canned lines that use real
## data (a true rumor, a real job), so the bar never dead-ends.

signal thinking(bark: String)                 ## no first word yet: a beat to cover it
signal line_delta(text_so_far: String)        ## streamed, filtered subtitle
signal line_done(turn: Dictionary)            ## final { say, mood, kept, dropped, ... }
signal job_offered(job: Dictionary)
signal drink_poured(drink: Dictionary)
signal sale_offered(item: Dictionary)          ## issue #42: { id, name, price }; the player confirms
signal ended(reason: String)

const CoreContent := preload("res://src/systems/dataload/core_content.gd")
const CARD_PATH := "res://content/core/npcs/cantina_owner_card.json"   ## the default card
const BRIEF_PATH := "res://content/core/llm/world_briefing.json"
const SCHEMA_PATH := "res://content/core/llm/reply_schema.json"
const LOG_ROOT := "user://logs"         ## transcripts go to <root>/<card id>/
const BARK_AFTER_MS := 900

var llm: LLMService
var card: Dictionary
var builder: PromptBuilder
var filter: OutputFilter
var rel := Relationship.new()
var _world_cache: Dictionary = {}    ## the world this bar is in (issue #15: names its town and planet)
var history: Array = []              ## this visit: [{ role, content }]
var insults := 0
var busy := false
var talking := false
var log_transcripts := true
var log_dir := LOG_ROOT + "/cantina_owner"
var last_turn: Dictionary = {}       ## for the debug overlay
var turns: Array = []                ## every finished turn this session (tests read it)

var _turn_id := -1
var _raw := ""
var _shown := ""
var _ids: Dictionary = {}
var _messages: Array = []
var _player_text := ""
var _hostile := false
var _t0 := 0
var _barked := false
var _rng := RandomNumberGenerator.new()
var _summary_id := -1


func _init(service: LLMService = null, card_path: String = CARD_PATH) -> void:
	card = _read(card_path)
	log_dir = LOG_ROOT + "/" + id()
	builder = PromptBuilder.new(card, _read(BRIEF_PATH), _read(SCHEMA_PATH))
	filter = OutputFilter.new(card)
	_rng.seed = 7
	if service != null:
		attach(service)


## The card's id ("cantina_owner", "skrugs"): the key for this character's
## relationship in the save and for their transcript folder.
func id() -> String:
	return str(card.get("id", "npc"))


func attach(service: LLMService) -> void:
	llm = service
	llm.delta.connect(_on_delta)
	llm.finished.connect(_on_finished)
	llm.fallback.connect(_on_fallback)
	if llm.config != null:
		log_transcripts = bool(llm.config.data.get("debug", {}).get("log_transcripts", true))


# ------------------------------------------------------------------ visits

## The player stepped up to the bar. Returns her greeting (no model call: instant).
func begin_visit() -> String:
	var returning := rel.visits > 0
	rel.begin_visit()
	history.clear()
	insults = 0
	talking = true
	if returning:
		rel.add_trust(1, "came back to the bar")
	_credit_jobs()
	rel.mood = baseline_mood()
	var g: Array = card.get("greetings", {}).get(rel.tier(), ["Yeah?"])
	var line := str(g[_rng.randi() % g.size()])
	history.append({ "role": "assistant", "content": JSON.stringify({ "say": line, "then": [], "tone": rel.mood }) })
	return line


## Issue #64: the story's line instead of the greeting begin_visit() picked.
func replace_greeting(line: String) -> void:
	if not history.is_empty():
		history[history.size() - 1] = { "role": "assistant", "content": JSON.stringify({ "say": line, "then": [], "tone": rel.mood }) }


## The player walked off. Summarize the visit in the background (if online).
func end_visit() -> void:
	talking = false
	if llm == null or history.size() < 3:
		return
	_summary_id = llm.chat(builder.summary_messages(rel, history), { "max_tokens": 80, "temperature": 0.3 })


## Can she serve right now? (false after she threw the player out)
func serving() -> bool:
	return WorldState.clock >= rel.banned_until


## Warm the local model's prompt cache with the static prefix (call on town entry).
func warm_up() -> void:
	if llm == null:
		return
	llm.chat([builder.persona_message(), builder.rules_message(), { "role": "user", "content": "<player_says>...</player_says>" }], { "max_tokens": 1 })


func baseline_mood() -> String:
	for r in card.get("mood_rules", []):
		var all_ok := true
		for f in r.get("if_flags", []):
			if not WorldState.has_flag(str(f)):
				all_ok = false
		if all_ok:
			return str(r.mood)
	return "warm" if rel.tier() in ["trusted", "confidant"] else "wary"


# ------------------------------------------------------------------ a turn

## The player said something. Returns false if she is mid-answer.
func say(text: String) -> bool:
	text = text.strip_edges()
	if busy or text == "":
		return false
	busy = true
	_player_text = text
	_hostile = filter.is_hostile(text)
	if _hostile:
		insults += 1
	var tier := rel.tier()
	var rumors := WorldState.rumors(tier, rel.known_rumors, 4)
	var jobs := WorldState.open_jobs(tier)
	var world := {
		"flags": WorldState.flags, "standing": WorldState.standing, "time": WorldState.time_of_day,
		"events": WorldState.events, "credits": WorldState.credits,
		"place": _place(), "people": NameHooks.known("npc:"),
		"story": Story.brief(id()),
	}
	var built := builder.build(world, rel, rumors, jobs, history, text)
	_messages = built.messages
	_ids = built.ids
	_raw = ""
	_shown = ""
	_barked = false
	_t0 = Time.get_ticks_msec()
	if llm == null:
		_finish_turn({ "ok": false, "text": "", "provider": "none", "fell_back_from": [], "error": "no llm" })
		return true
	var opts := { "schema": builder.schema }
	if card.has("temperature"):
		opts["temperature"] = float(card.temperature)
	_turn_id = llm.chat(_messages, opts)
	return true


## Call every frame while busy (the scene does): emits the thinking beat.
func tick() -> void:
	if busy and not _barked and _shown == "" and Time.get_ticks_msec() - _t0 > BARK_AFTER_MS:
		_barked = true
		thinking.emit(_pick(card.get("stall_barks", ["Mm."])))


func _on_fallback(turn_id: int, _from: String, _reason: String) -> void:
	if turn_id == _turn_id and not _barked:
		_barked = true
		thinking.emit(_pick(card.get("stall_barks", ["Mm."])))


func _on_delta(turn_id: int, text: String) -> void:
	if turn_id != _turn_id:
		return
	_raw += text
	var s := ReplyParser.say_partial(_raw)
	if filter.has_meta_talk(s):
		return                         # hold the line; the final filter replaces it
	s = filter.scrub_terms(s.replace("*", ""))
	if s != _shown:
		_shown = s
		line_delta.emit(s)


func _on_finished(turn_id: int, result: Dictionary) -> void:
	if turn_id == _summary_id:
		_summary_id = -1
		if bool(result.ok):
			for line in str(result.text).split("\n"):
				var f := filter.scrub_terms(line.strip_edges().trim_prefix("-").strip_edges())
				if f.length() > 3 and f.length() < 90 and not filter.has_meta_talk(f):
					rel.remember(f)
		return
	if turn_id != _turn_id:
		return
	_finish_turn(result)


func _finish_turn(result: Dictionary) -> void:
	_turn_id = -1
	var parsed := ReplyParser.parse(str(result.get("text", ""))) if bool(result.get("ok", false)) else { "ok": false }
	var source := "model"
	var say_text := ""
	var proposed: Array = []
	var mood := ""
	if bool(parsed.get("ok", false)):
		say_text = str(parsed.say)
		proposed = parsed.actions
		mood = str(parsed.mood)
	else:
		source = "canned"
		var c := canned_reply(_player_text)
		say_text = c.say
		proposed = c.actions
	var cleaned := filter.clean(say_text, _rng.randi())
	if (cleaned.flags as Array).has("empty"):
		source = "canned"
		var c2 := canned_reply(_player_text)
		cleaned = filter.clean(c2.say)
		proposed = c2.actions
	var v := ActionValidator.validate(proposed, _ids, {
		"trust": rel.trust, "trust_this_visit": rel.trust_this_visit, "hostile": _hostile, "insults": insults,
	})
	if mood in ["wary", "warm", "amused", "irritated", "scared", "sad"]:
		rel.mood = mood
	var applied := _apply(v.kept)
	rel.turns_total += 1
	history.append({ "role": "user", "content": PromptBuilder.wrap_player(_player_text) })
	history.append({ "role": "assistant", "content": JSON.stringify({ "say": cleaned.say, "then": v.kept, "tone": rel.mood }) })
	var turn := {
		"player": _player_text, "say": cleaned.say, "mood": rel.mood, "kept": v.kept, "dropped": v.dropped,
		"applied": applied, "filter": cleaned.flags, "source": source, "repaired": parsed.get("repaired", false),
		"provider": str(result.get("provider", "")), "model": str(result.get("model", "")),
		"ms_first_token": int(result.get("ms_first_token", -1)), "ms_total": int(result.get("ms_total", 0)),
		"usage": result.get("usage", {}), "fell_back_from": result.get("fell_back_from", []),
		"stalled": bool(result.get("stalled", false)), "error": str(result.get("error", "")),
		"raw": str(result.get("text", "")), "trust": rel.trust, "tier": rel.tier(),
		"prompt": _messages,
	}
	last_turn = turn
	turns.append(turn)
	busy = false
	_log(turn)
	line_done.emit(turn)
	if applied.has("end_conversation") or applied.has("call_guards"):
		ended.emit("call_guards" if applied.has("call_guards") else "end_conversation")


## Apply validated actions. Returns the list of action types applied.
func _apply(kept: Array) -> Array:
	var applied: Array = []
	for a in kept:
		var t := str(a.type)
		match t:
			"share_rumor":
				if not rel.known_rumors.has(str(a.id)):
					rel.known_rumors.append(str(a.id))
			"hint_secret":
				if not rel.hinted_secrets.has(str(a.id)):
					rel.hinted_secrets.append(str(a.id))
					rel.remember("you let slip " + str(a.id))
			"offer_job":
				var j := WorldState.job(str(a.id))
				if not j.is_empty():
					job_offered.emit(j)
			"trust":
				rel.trust = clampi(rel.trust + int(a.delta), 0, 100)
				if int(a.delta) > 0:
					rel.trust_this_visit += int(a.delta)
			"pour_drink":
				_pour(a)
			"offer_speeder":
				sale_offered.emit({ "id": a.id, "name": a.name, "price": int(a.price) })
			"call_guards":
				rel.banned_until = WorldState.clock + 90.0
				rel.add_trust(-5, "threatened you in your own bar")
				WorldState.change_standing("locals", -2, "Someone got thrown out of the cantina.")
			"end_conversation", "refuse_topic":
				pass
		applied.append(t)
	return applied


func _pour(a: Dictionary) -> void:
	var price := int(a.price)
	var paid := false
	if WorldState.credits >= price + rel.tab:
		WorldState.credits -= price + rel.tab
		if rel.tab > 0:
			rel.add_trust(2, "paid off their tab")
			rel.tab = 0
		paid = true
		rel.drinks_this_visit += 1
		if rel.drinks_this_visit == 1:
			rel.add_trust(1, "pays for drinks")
	else:
		rel.tab += price
		rel.remember("drinks on the tab")
	drink_poured.emit({ "id": a.id, "name": a.name, "price": price, "paid": paid, "credits": WorldState.credits, "tab": rel.tab })


## The game thanks her for jobs she gave that are now done (verified by WorldState).
func _credit_jobs() -> void:
	for id in WorldState.jobs_taken:
		if WorldState.jobs_taken[id] == "done" and not rel.credited_jobs.has(id):
			rel.credited_jobs.append(id)
			rel.add_trust(5, "finished the job " + str(WorldState.job(id).get("title", id)))


## The player accepted a job she offered (from the job card).
func accept_job(id: String) -> bool:
	if not WorldState.accept_job(id):
		return false
	rel.add_trust(1, "took the job " + str(WorldState.job(id).get("title", id)))
	return true


# ------------------------------------------------------------------ offline

## A real answer without a model: keyword topic + true data. Only topics whose
## action this character has (no job board at Skrugs's stall, no drinks).
func canned_reply(text: String) -> Dictionary:
	var c: Dictionary = card.get("canned", {})
	var topic := _topic(text)
	var can: Array = builder.actions()
	var needs := { "smuggle": "offer_job", "job": "offer_job", "drink": "pour_drink", "buy": "offer_speeder", "rumor": "share_rumor" }
	if needs.has(topic) and not can.has(needs[topic]):
		topic = ""
	match topic:
		"rumor":
			var rs := WorldState.rumors(rel.tier(), rel.known_rumors, 1)
			if rs.is_empty():
				return { "say": _pick(c.get("no_rumor", ["Quiet week."])), "actions": [] }
			return { "say": _pick(c.get("rumor", ["%s"])) % str(rs[0].text), "actions": [{ "type": "share_rumor", "id": rs[0].id }] }
		"smuggle":
			var sj := WorldState.open_jobs(rel.tier()).filter(func(j): return str(j.get("kind", "")) == "smuggle")
			if sj.is_empty():
				return { "say": _pick(c.get("no_smuggle", ["Nothing lined up."])), "actions": [] }
			return { "say": _pick(c.get("job", ["%s"])) % str(sj[0].text), "actions": [{ "type": "offer_job", "id": sj[0].id }] }
		"job":
			var js := WorldState.open_jobs(rel.tier())
			if js.is_empty():
				return { "say": _pick(c.get("no_job", ["Nothing."])), "actions": [] }
			return { "say": _pick(c.get("job", ["%s"])) % str(js[0].text), "actions": [{ "type": "offer_job", "id": js[0].id }] }
		"war":
			return { "say": _pick(c.get("war", ["Both sides drink here."])), "actions": [] }
		"drink":
			return { "say": "Dust ale. You look like a dust ale.", "actions": [{ "type": "pour_drink", "name": "dust ale" }] }
		"buy":
			return { "say": _pick(c.get("sell", ["Yours for the price on the board."])), "actions": [{ "type": "offer_speeder" }] }
		"bye":
			return { "say": _pick(c.get("bye", ["Go on."])), "actions": [{ "type": "end_conversation" }] }
	return { "say": _pick(c.get("default", ["Hold on."])), "actions": [] }


func _topic(text: String) -> String:
	var low := text.to_lower()
	var tw: Dictionary = card.get("topic_words", {})
	for topic in ["bye", "buy", "smuggle", "job", "rumor", "drink", "war"]:
		for w in tw.get(topic, []):
			if low.contains(str(w)):
				return topic
	return ""


func _pick(arr: Array) -> String:
	if arr.is_empty():
		return ""
	return str(arr[_rng.randi() % arr.size()])


# ------------------------------------------------------------------ transcripts

func _log(turn: Dictionary) -> void:
	if not log_transcripts:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(log_dir))
	var path := log_dir + "/" + Time.get_date_string_from_system() + ".jsonl"
	var f := FileAccess.open(path, FileAccess.READ_WRITE) if FileAccess.file_exists(path) else FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	var row := turn.duplicate()
	row.erase("prompt")
	row["prompt_hash"] = str(JSON.stringify(_messages).hash())
	row["time"] = Time.get_datetime_string_from_system()
	f.store_line(JSON.stringify(row))


static func _read(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


## Issue #15: the town and planet she works in, by name. The world is the one the
## briefing names ("world" in world_briefing.json); generated once, saved, the same
## names the place card and the flight HUD show.
func _place() -> Dictionary:
	if _world_cache.is_empty():
		var cc := CoreContent.new()
		cc.load_from()
		_world_cache = cc.get_world(str(builder.world_text.get("world", "")))
	if _world_cache.is_empty():
		return {}
	return { "town": NameHooks.town(_world_cache), "planet": NameHooks.planet(_world_cache) }
