class_name Relationship
extends RefCounted
## What one npc thinks of the player (M12). Pure, saved.
##
## Trust is 0..100 and only the game changes it: the model can PROPOSE a small
## change, which ActionValidator clamps (at most -3..+2 a turn, +6 a visit), and
## the game adds its own for things it can verify (paying, coming back, finishing
## a job she gave). Trust drops fast and grows slow, so sweet talk cannot max it.

const TIERS := ["stranger", "regular", "trusted", "confidant"]
const TIER_MIN := { "stranger": 0, "regular": 20, "trusted": 50, "confidant": 80 }
const MAX_FACTS := 14

var trust := 5
var mood := "wary"
var visits := 0
var turns_total := 0
var trust_this_visit := 0
var known_rumors: Array = []
var hinted_secrets: Array = []
var facts: Array = []            ## short strings the game wrote, oldest first
var tab := 0                     ## credits owed
var drinks_this_visit := 0
var credited_jobs: Array = []    ## jobs she gave that the game already thanked you for
var banned_until := -1.0         ## WorldState.clock time; she will not serve before it


func tier() -> String:
	return tier_for(trust)


static func tier_for(t: int) -> String:
	var out := "stranger"
	for name in TIERS:
		if t >= int(TIER_MIN[name]):
			out = name
	return out


static func tier_index(name: String) -> int:
	return TIERS.find(name)


## Game-applied trust (verified events). Still capped per visit for gains.
func add_trust(delta: int, why: String = "") -> int:
	if delta > 0:
		delta = mini(delta, maxi(0, 6 - trust_this_visit))
		trust_this_visit += delta
	trust = clampi(trust + delta, 0, 100)
	if why != "" and delta != 0:
		remember(why)
	return delta


func remember(fact: String) -> void:
	fact = fact.strip_edges()
	if fact == "" or facts.has(fact):
		return
	facts.append(fact)
	while facts.size() > MAX_FACTS:
		facts.pop_front()


func begin_visit() -> void:
	visits += 1
	trust_this_visit = 0
	drinks_this_visit = 0


func to_save() -> Dictionary:
	return {
		"trust": trust, "mood": mood, "visits": visits, "turns_total": turns_total,
		"known_rumors": known_rumors.duplicate(), "hinted_secrets": hinted_secrets.duplicate(),
		"facts": facts.duplicate(), "tab": tab, "credited_jobs": credited_jobs.duplicate(),
		"banned_until": banned_until,
	}


func from_save(d: Dictionary) -> void:
	trust = int(d.get("trust", 5))
	mood = str(d.get("mood", "wary"))
	visits = int(d.get("visits", 0))
	turns_total = int(d.get("turns_total", 0))
	known_rumors = d.get("known_rumors", []).duplicate()
	hinted_secrets = d.get("hinted_secrets", []).duplicate()
	facts = d.get("facts", []).duplicate()
	tab = int(d.get("tab", 0))
	credited_jobs = d.get("credited_jobs", []).duplicate()
	banned_until = float(d.get("banned_until", -1.0))
