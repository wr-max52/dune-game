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

static var _rumors: Array = []
static var _board: Array = []
static var _cooldowns: Dictionary = {}

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


static func job(id: String) -> Dictionary:
	for j in board():
		if str(j.get("id", "")) == id:
			return j
	return {}


## Jobs the bartender can offer at this trust tier, not yet taken.
static func open_jobs(tier: String) -> Array:
	var out: Array = []
	for j in board():
		if jobs_taken.has(str(j.id)):
			continue
		if _conditions_hold(j.get("requires", {}), tier):
			out.append(j)
	return out


static func accept_job(id: String) -> bool:
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


static func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())
