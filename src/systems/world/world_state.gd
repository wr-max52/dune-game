class_name WorldState
extends RefCounted
## What is true in the world right now (M12): faction standing, town flags,
## counters, the job board, credits and a short log of recent events.
##
## Static, like GameFlow, so it survives scene changes (town -> flight -> town)
## without an autoload. Systems write to it when something actually happens
## (a fight won, shots fired in the street, a job accepted); the cantina owner only
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
static var droids := DroidRoster.new()     ## issue #51: the player's companion droids, their cargo, desert wrecks
static var hangar := ""                    ## issue #58: the ship id you bought from T-89 (on the spare pad), "" = none
static var story: Dictionary = {}          ## issue #64: { chapter, told } (Story); {} = the first chapter
static var bounty: Dictionary = {}         ## issue #64: { run, key, name, crime, outpost, pay, state: "rolled"|"out"|"dead" }

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
	droids = DroidRoster.new()
	hangar = ""
	story = {}
	bounty = {}


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


## M15: the gate checkpoint. Every outcome lands here so the cantina owner (and any
## later system) reads it from one place.
static func on_gate_bribe(price: int) -> void:
	credits = maxi(0, credits - price)
	bump("gate_bribes")
	set_flag("bribed_gate")
	log_event("Paid off the front gate (%d cr)." % price)


## A Remnant guard died. `all_down`: that was the last one at the gate.
static func on_guard_killed(delta: int, all_down: bool) -> void:
	bump("guards_killed")
	change_standing("imperial_remnant", delta, "A Remnant gate guard was killed.")
	change_standing("locals", 1)
	if all_down:
		set_flag("gate_guards_down")
		set_flag("gate_checkpoint_up", false)
		log_event("The front gate checkpoint is down. Nobody is on it.")


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
		if Story.chapter() == "fleet":
			# Issue #64: the Remnant fleet. The locals' purse, and the garrison leaves town.
			credits += Story.fleet_reward()
			set_flag("remnant_fleet_beaten")
			log_event("The Remnant fleet in orbit was broken. The garrison is pulling out of town.")
			Story.event("fleet_beaten")
		else:
			credits += int(arrival.get("payout", 0))
		_complete_jobs("flight_complete")
	else:
		set_flag("ship_limped_home")
		log_event("A ship came back into the pit trailing smoke.")


## Issue #64: the player is on the practice range (Oda's honour system: going
## there is the practice).
static func on_range_visited() -> void:
	Story.event("range_visited")


## Issue #64: every target on the range down at once (any time; the record is
## the bet's business).
static func on_range_cleared() -> void:
	bump("range_clears")


## Issue #64: something contraband went to the fence. The run is over once the
## drop was picked up and nothing contraband is left on you or your droids.
## Only a run Oda gave you in this chapter counts: goods found or carried in from
## before the story asked for them do not move it on.
static func on_contraband_sold() -> void:
	if smuggle_drop().is_empty() and not carrying_contraband():
		bump("smuggle_sold")
		if bool(story.get("took_run", false)):
			Story.event("smuggle_sold")


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


## A job as the cantina owner shows it. A smuggling job comes back with its text
## and pay filled in from the drop she has lined up.
static func job(id: String) -> Dictionary:
	for j in board():
		if str(j.get("id", "")) == id:
			match str(j.get("kind", "")):
				"smuggle":
					return _smuggle_job(j)
				"bounty":
					return _bounty_job(j)
			return j
	return {}


## Jobs the cantina owner can offer at this trust tier, not yet taken.
static func open_jobs(tier: String) -> Array:
	var out: Array = []
	for j in board():
		if jobs_taken.has(str(j.id)):
			continue
		if str(j.get("kind", "")) == "smuggle" and not smuggle_ready():
			continue
		if str(j.get("kind", "")) == "bounty" and not (bounty_ready() and Story.bounties_open()):
			continue
		if _conditions_hold(j.get("requires", {}), tier):
			out.append(job(str(j.id)))
	return out


static func accept_job(id: String) -> bool:
	if str(job(id).get("kind", "")) == "smuggle":
		return _start_smuggle(job(id))
	if str(job(id).get("kind", "")) == "bounty":
		return _start_bounty(job(id))
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
		"marked": bool(smuggle.get("marked", false)),
	}


## Can she line up a new drop? Not while one is lying out there, and not while
## the player still has contraband to get rid of.
static func smuggle_ready() -> bool:
	return smuggle_drop().is_empty() and not carrying_contraband()


## Pockets or a cargo droid (issue #51): the gate never finds what a droid
## carries, but Oda still waits until it is sold.
static func carrying_contraband() -> bool:
	for id in inventory.item_ids() + droids.all_cargo().keys():
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
		"marked": bool(a.get("marked", false)),
	}


static func _start_smuggle(j: Dictionary) -> bool:
	if j.is_empty() or not smuggle_ready() or bool(smuggle.get("out", false)):
		return false
	smuggle.out = true
	story["took_run"] = true            # issue #64: this chapter's run is under way
	bump("smuggle_runs")
	log_event("Oda set up a drop: " + str(j.get("text", "")))
	return true


static func _item(id: String) -> Dictionary:
	if not _items.has(id):
		var d = _read_json(ITEM_DIR + "/" + id + ".json")
		_items[id] = d if d is Dictionary else {}
	return _items[id]


# ------------------------------------------------------------------ bounties (issue #64)

## Oda's other repeating job (kind "bounty"): a named Remnant officer at one of
## the three desert outposts (Story.OUTPOSTS). Taking it puts them there
## (RemnantOutposts spawns whoever bounty_target() names); killing them makes the
## bounty collectable at the fence. One at a time.

## No contract out and none waiting to be paid.
static func bounty_ready() -> bool:
	return not ["out", "dead"].has(str(bounty.get("state", "")))


## The officer to put at an outpost, or {} when there is none to hunt.
static func bounty_target() -> Dictionary:
	return bounty if str(bounty.get("state", "")) == "out" else {}


## The fence has a bounty to pay out.
static func bounty_collectable() -> bool:
	return str(bounty.get("state", "")) == "dead"


static func on_bounty_killed() -> void:
	if str(bounty.get("state", "")) != "out":
		return
	bounty.state = "dead"
	bump("bounties_killed")
	change_standing("imperial_remnant", -5)
	change_standing("locals", 3)
	log_event(str(Story.bounty_cfg().get("event_killed", "%s was found dead.")) % str(bounty.name))


## Paid at the fence. Returns the credits, or 0 when nothing is owed.
static func collect_bounty() -> int:
	if not bounty_collectable():
		return 0
	var pay := int(bounty.pay)
	credits += pay
	bump("bounties_paid")
	bounty = { "run": int(bounty.run), "outpost": str(bounty.outpost), "state": "" }
	Story.event("bounty_paid")
	return pay


static func _bounty_job(j: Dictionary) -> Dictionary:
	if str(bounty.get("state", "")) == "":
		_roll_bounty()
	var out := j.duplicate()
	var cfg := Story.bounty_cfg()
	out["text"] = str(cfg.get("offer", "%s %s %s %d")) % [str(bounty.name), Story.outpost_label(str(bounty.outpost)),
		str(bounty.crime), int(bounty.pay)]
	out["pays"] = int(bounty.pay)
	return out


## The next contract: a fresh name, a crime, one of the three outposts (the first
## one is the nearest), and the pay (the story's first bounty pays less).
static func _roll_bounty() -> void:
	var cfg := Story.bounty_cfg()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var run := int(bounty.get("run", 0)) + 1
	var key := "npc:bounty/%d" % run
	var crimes: Array = cfg.get("crimes", ["They did something unforgivable."])
	var span: Array = cfg.get("pay", [900, 1600])
	var first := count("bounties_paid") == 0
	var last := str(bounty.get("outpost", ""))
	var choices := Story.OUTPOSTS.filter(func(o): return o != last)
	var who := NameHooks.person(Story.target_naming(), key)
	bounty = {
		"run": run, "key": key, "name": who if who != "" else "the officer",
		"crime": str(crimes[rng.randi() % crimes.size()]),
		"outpost": Story.OUTPOSTS[0] if first else str(choices[rng.randi() % choices.size()]),
		"pay": int(cfg.get("first_pay", 600)) if first else rng.randi_range(int(span[0]), int(span[1])),
		"state": "rolled",
	}


static func _start_bounty(j: Dictionary) -> bool:
	if j.is_empty() or str(bounty.get("state", "")) != "rolled":
		return false
	bounty.state = "out"
	bump("bounties_taken")
	log_event("Took a contract on " + str(bounty.name) + ".")
	return true


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


## requires: { flags: [..], not_flags: [..], tier: "regular", story: "<chapter reached>",
##   standing: { faction: [min, max] }, counters: { name: min }, time: [..] }
static func _conditions_hold(req: Dictionary, tier: String) -> bool:
	if req.has("story") and not Story.reached(str(req.story)):
		return false
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
		"droids": droids.to_save(),
		"hangar": hangar,
		"story": story.duplicate(),
		"bounty": bounty.duplicate(),
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
	droids = DroidRoster.new()
	droids.from_save(d.get("droids", {}))
	hangar = str(d.get("hangar", ""))
	story = d.get("story", {}).duplicate()
	if not d.has("story"):
		smuggle = {}           # issue #64: a save from before the story; its old drop goes with it
	bounty = d.get("bounty", {}).duplicate()


static func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())
