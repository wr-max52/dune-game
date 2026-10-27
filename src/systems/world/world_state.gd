class_name WorldState
extends RefCounted
## What is true in the world right now (M12): faction standing, town flags,
## counters, the job board, credits and a short log of recent events.
##
## Static, like GameFlow, so it survives scene changes (town -> flight -> town)
## without an autoload. Systems write to it when something actually happens
## (a fight won, shots fired in the street, a job accepted); the bartender only
## ever reads it. That is what keeps her rumors true: a rumor is shown to her
## only when its conditions hold here (see rumors()).
##
## Saved and restored through SaveSystem (to_save / from_save).

const RUMOR_DIR := "res://content/core/rumors"
const BOARD_PATH := "res://content/core/board/bar_board.json"
const PICKUP_DIR := "res://content/core/pickups"
const ITEM_DIR := "res://content/core/items"
const FACTIONS := ["imperial_remnant", "locals", "smuggler"]
const DEFAULT_STANDING := { "imperial_remnant": -10, "locals": 5, "smuggler": 20 }

static var standing: Dictionary = DEFAULT_STANDING.duplicate()
static var flags: Dictionary = {}          ## name -> true
static var counters: Dictionary = {}       ## name -> int
static var events: Array = []              ## [{ t, text }] newest last, capped
static var credits := 60
static var time_of_day := "golden"
static var jobs_taken: Dictionary = {}     ## job id -> "active" | "done"
static var clock := 0.0                    ## seconds of play, for cooldowns
static var inventory := Inventory.new()    ## M13: the player's gear (owned, attached, taken, vendor stock)
static var names := NameBook.new()         ## issue #15: every name given out, so each one is unique
static var smuggle: Dictionary = {}        ## Oda's drop: { run, item, count, area, hint, marker, offset, ground, out }

static var _rumors: Array = []
static var _board: Array = []
static var _cooldowns: Dictionary = {}
static var _items: Dictionary = {}         ## item id -> its content/core/items entry (cache)

const MAX_EVENTS := 12


static func reset() -> void:
	standing = DEFAULT_STANDING.duplicate()
	flags = {}
	counters = {}
	events = []
	credits = 60
	time_of_day = "golden"
	jobs_taken = {}
	clock = 0.0
	_cooldowns = {}
	inventory = Inventory.new()
	names = NameBook.new()
	smuggle = {}


# ------------------------------------------------------------------ writes

static func set_flag(name: String, on: bool = true) -> void:
	if on:
		flags[name] = true
	else:
		flags.erase(name)


static func has_flag(name: String) -> bool:
	return flags.has(name)


static func bump(counter: String, by: int = 1) -> int:
	counters[counter] = int(counters.get(counter, 0)) + by
	return counters[counter]


static func count(counter: String) -> int:
	return int(counters.get(counter, 0))


static func change_standing(faction: String, delta: int, why: String = "") -> void:
	standing[faction] = clampi(int(standing.get(faction, 0)) + delta, -100, 100)
	if why != "":
		log_event(why)


static func log_event(text: String) -> void:
	events.append({ "t": clock, "text": text })
	while events.size() > MAX_EVENTS:
		events.pop_front()


## True at most once per `seconds` per key (so spamming an action cannot farm
## or tank standing).
static func cooldown_ok(key: String, seconds: float) -> bool:
	if clock - float(_cooldowns.get(key, -INF)) < seconds:
		return false
	_cooldowns[key] = clock
	return true


static func tick(dt: float) -> void:
	clock += dt


# ------------------------------------------------------------------ things that happen

## The player fired a blaster. `in_range` = on the sanctioned range in the pit.
static func on_player_fired(in_range: bool) -> void:
	if in_range:
		bump("range_shots")
		return
	bump("street_shots")
	set_flag("shots_in_street")
	if cooldown_ok("street_shots", 45.0):
		change_standing("imperial_remnant", -3, "Somebody fired a blaster in the street.")
		change_standing("locals", -1)


## M15: the gate checkpoint. Every outcome lands here so the bartender (and any
## later system) reads it from one place.
static func on_gate_bribe(price: int) -> void:
	credits = maxi(0, credits - price)
	bump("gate_bribes")
	set_flag("bribed_gate")
	log_event("Paid off the east gate (%d cr)." % price)


## A Remnant guard died. `all_down`: that was the last one at the gate.
static func on_guard_killed(delta: int, all_down: bool) -> void:
	bump("guards_killed")
	change_standing("imperial_remnant", delta, "A Remnant gate guard was killed.")
	change_standing("locals", 1)
	if all_down:
		set_flag("gate_guards_down")
		set_flag("gate_checkpoint_up", false)
		log_event("The east gate checkpoint is down. Nobody is on it.")


## Knocked out at the gate and dragged to the pit: they help themselves to a
## share of your credits. Returns what was taken.
static func on_player_downed(share: float = 0.2, minimum: int = 5) -> int:
	var take := mini(credits, maxi(minimum, int(credits * share)))
	credits -= take
	bump("times_downed")
	log_event("Woke up in the pit, %d cr lighter." % take)
	return take


static func on_flight_returned(arrival: Dictionary) -> void:
	if arrival.is_empty():
		return
	if str(arrival.get("outcome", "")) == "complete":
		bump("patrols_beaten")
		set_flag("remnant_patrol_beaten")
		set_flag("ship_limped_home", false)
		change_standing("imperial_remnant", -15, "A Remnant patrol in orbit was shot to pieces.")
		change_standing("locals", 4)
		change_standing("smuggler", 5)
		credits += int(arrival.get("payout", 0))
		_complete_jobs("flight_complete")
	else:
		set_flag("ship_limped_home")
		log_event("A ship came back into the pit trailing smoke.")


static func on_range_record(seconds: float) -> void:
	set_flag("range_record")
	log_event("Someone cleared the practice range in %.1f seconds." % seconds)
	_complete_jobs("range_record")


static func on_deflection() -> void:
	bump("deflections")
	if count("deflections") >= 5:
		set_flag("blade_trained")


# ------------------------------------------------------------------ jobs

static func board() -> Array:
	if _board.is_empty():
		var d = _read_json(BOARD_PATH)
		if d is Dictionary:
			_board = d.get("jobs", [])
	return _board


## A job as the bartender shows it. A smuggling job comes back with its text
## and pay filled in from the drop she has lined up.
static func job(id: String) -> Dictionary:
	for j in board():
		if str(j.get("id", "")) == id:
			return _smuggle_job(j) if str(j.get("kind", "")) == "smuggle" else j
	return {}


## Jobs the bartender can offer at this trust tier, not yet taken.
static func open_jobs(tier: String) -> Array:
	var out: Array = []
	for j in board():
		if jobs_taken.has(str(j.id)):
			continue
		if str(j.get("kind", "")) == "smuggle" and not smuggle_ready():
			continue
		if _conditions_hold(j.get("requires", {}), tier):
			out.append(job(str(j.id)))
	return out


static func accept_job(id: String) -> bool:
	if str(job(id).get("kind", "")) == "smuggle":
		return _start_smuggle(job(id))
	if job(id).is_empty() or jobs_taken.has(id):
		return false
	jobs_taken[id] = "active"
	log_event("Took the job: " + str(job(id).get("title", id)))
	return true


static func _complete_jobs(trigger: String) -> void:
	for id in jobs_taken.keys():
		var j := job(id)
		if jobs_taken[id] == "active" and str(j.get("completes_on", "")) == trigger:
			jobs_taken[id] = "done"
			credits += int(j.get("pays", 0))
			set_flag("job_done_" + id)
			log_event("Finished the job: " + str(j.get("title", id)))


# ------------------------------------------------------------------ smuggling

## Oda's repeating job (kind "smuggle"). She lines up a drop of contraband in
## one of the town's hiding places (pickups/<location>.json "drops"); taking the
## job puts it there. She lines up the next one once that drop is picked up and
## the player carries no contraband (sold to the fence, or lost at the gate),
## so the loop runs for as long as anyone plays.

## The drop lying in the world, as a pickup entry, or {} when there is none.
static func smuggle_drop() -> Dictionary:
	if not bool(smuggle.get("out", false)):
		return {}
	var id := "smuggle_%d" % int(smuggle.run)
	if inventory.is_taken(id):
		return {}
	return {
		"id": id, "item": smuggle.item, "count": int(smuggle.count), "marker": smuggle.marker,
		"offset": smuggle.offset, "ground": bool(smuggle.get("ground", false)), "hidden": true, "reach": 2.0,
	}


## Can she line up a new drop? Not while one is lying out there, and not while
## the player still has contraband to get rid of.
static func smuggle_ready() -> bool:
	return smuggle_drop().is_empty() and not carrying_contraband()


static func carrying_contraband() -> bool:
	for id in inventory.item_ids():
		if bool(_item(str(id)).get("contraband", false)):
			return true
	return false


static func _smuggle_job(j: Dictionary) -> Dictionary:
	if smuggle.is_empty() or (bool(smuggle.get("out", false)) and smuggle_ready()):
		_roll_smuggle(j)
	if smuggle.is_empty():
		return {}
	var out := j.duplicate()
	var n := int(smuggle.count)
	var goods := {}
	for g in j.get("goods", []):
		if str(g.get("item", "")) == str(smuggle.item):
			goods = g
	var what := str(goods.get("say_one", goods.get("say", "%d"))) if n == 1 else str(goods.get("say", "%d"))
	if what.contains("%d"):
		what = what % n
	out["text"] = str(j.get("text", "%s %s")) % [what, str(smuggle.hint)]
	out["pays"] = n * int(_item(str(smuggle.item)).get("value", 0))
	return out


## Pick the next drop: goods from the job, a hiding place from the location's
## drops (never the same area twice running).
static func _roll_smuggle(j: Dictionary) -> void:
	var goods: Array = j.get("goods", [])
	var d = _read_json(PICKUP_DIR + "/" + str(j.get("location", "")) + ".json")
	var areas: Array = d.get("drops", {}).get("areas", []) if d is Dictionary else []
	var last := str(smuggle.get("area", ""))
	var choices := areas.filter(func(a): return str(a.get("id", "")) != last and not (a.get("spots", []) as Array).is_empty())
	if goods.is_empty() or choices.is_empty():
		smuggle = {}
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var g: Dictionary = goods[rng.randi() % goods.size()]
	var a: Dictionary = choices[rng.randi() % choices.size()]
	var spots: Array = a.spots
	var span: Array = g.get("count", [1, 1])
	smuggle = {
		"run": int(smuggle.get("run", 0)) + 1, "item": str(g.item),
		"count": rng.randi_range(int(span[0]), int(span[1])),
		"area": str(a.id), "hint": str(a.get("hint", "")), "marker": str(a.get("marker", "")),
		"offset": spots[rng.randi() % spots.size()], "ground": bool(a.get("ground", false)), "out": false,
	}


static func _start_smuggle(j: Dictionary) -> bool:
	if j.is_empty() or not smuggle_ready() or bool(smuggle.get("out", false)):
		return false
	smuggle.out = true
	bump("smuggle_runs")
	log_event("Oda set up a drop: " + str(j.get("text", "")))
	return true


static func _item(id: String) -> Dictionary:
	if not _items.has(id):
		var d = _read_json(ITEM_DIR + "/" + id + ".json")
		_items[id] = d if d is Dictionary else {}
	return _items[id]


# ------------------------------------------------------------------ rumors

static func all_rumors() -> Array:
	if _rumors.is_empty():
		var da := DirAccess.open(RUMOR_DIR)
		if da != null:
			for f in da.get_files():
				if f.ends_with(".json"):
					var d = _read_json(RUMOR_DIR + "/" + f)
					if d is Dictionary and d.has("rumors"):
						_rumors.append_array(d.rumors)
	return _rumors


## Rumors whose conditions hold right now, for a trust tier. Unknown ones first,
## then by weight, at most `limit`.
static func rumors(tier: String, known: Array = [], limit: int = 4) -> Array:
	var ok: Array = []
	for r in all_rumors():
		if _conditions_hold(r.get("requires", {}), tier):
			ok.append(r)
	ok.sort_custom(func(a, b):
		var ka := known.has(a.id)
		var kb := known.has(b.id)
		if ka != kb:
			return not ka
		return float(a.get("weight", 1)) > float(b.get("weight", 1)))
	return ok.slice(0, limit)


const TIERS := ["stranger", "regular", "trusted", "confidant"]


## requires: { flags: [..], not_flags: [..], tier: "regular",
##   standing: { faction: [min, max] }, counters: { name: min }, time: [..] }
static func _conditions_hold(req: Dictionary, tier: String) -> bool:
	for f in req.get("flags", []):
		if not flags.has(str(f)):
			return false
	for f in req.get("not_flags", []):
		if flags.has(str(f)):
			return false
	if req.has("tier") and TIERS.find(tier) < TIERS.find(str(req.tier)):
		return false
	var st: Dictionary = req.get("standing", {})
	for fac in st:
		var v := int(standing.get(fac, 0))
		var rng: Array = st[fac]
		if v < int(rng[0]) or v > int(rng[1]):
			return false
	var cs: Dictionary = req.get("counters", {})
	for c in cs:
		if count(str(c)) < int(cs[c]):
			return false
	var times: Array = req.get("time", [])
	if not times.is_empty() and not times.has(time_of_day):
		return false
	return true


static func standing_label(v: int) -> String:
	if v <= -50:
		return "hostile"
	if v <= -15:
		return "unfriendly"
	if v < 15:
		return "neutral"
	if v < 50:
		return "friendly"
	return "allied"


# ------------------------------------------------------------------ save

static func to_save() -> Dictionary:
	return {
		"standing": standing.duplicate(), "flags": flags.duplicate(), "counters": counters.duplicate(),
		"events": events.duplicate(true), "credits": credits, "time_of_day": time_of_day,
		"jobs_taken": jobs_taken.duplicate(), "clock": clock,
		"inventory": inventory.to_save(),
		"names": names.to_save(),
		"smuggle": smuggle.duplicate(true),
	}


static func from_save(d: Dictionary) -> void:
	reset()
	standing = d.get("standing", DEFAULT_STANDING).duplicate()
	flags = d.get("flags", {}).duplicate()
	counters = d.get("counters", {}).duplicate()
	events = d.get("events", []).duplicate(true)
	credits = int(d.get("credits", 60))
	time_of_day = str(d.get("time_of_day", "golden"))
	jobs_taken = d.get("jobs_taken", {}).duplicate()
	clock = float(d.get("clock", 0.0))
	inventory = Inventory.new()
	inventory.from_save(d.get("inventory", {}))
	names = NameBook.new()
	names.from_save(d.get("names", {}))
	smuggle = d.get("smuggle", {}).duplicate(true)


static func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())
