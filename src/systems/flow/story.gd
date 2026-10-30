class_name Story
extends RefCounted
## The main story line (issue #64). Pure and static, like WorldState, and its
## state lives there (WorldState.story, saved with the world):
##
##   T-89 says talk to Oda -> she sends you to practice at the range -> she pays
##   for it and tells you about the sparring droid (optional: go to the pit and
##   come back, on your honour) -> two smuggling runs
##   (the first with her old jetpack if she is amused or warm) -> Skrugs and a
##   bounty at a Remnant outpost -> the Remnant fleet in orbit (the port's ships
##   unlock; winning pays 5000) -> issue #193: the Remnant's star cruiser far out
##   east in orbit (company on the way up; kill its general on the bridge) -> free
##   play: smuggling runs and bounty contracts on repeat.
##
## Chapters and every line: content/core/story/main.json. Systems report what
## happened with event() (WorldState does most of it); a teller asks beat() when
## the player talks to them and says the line it gets back.
##
## The Remnant follow the story too: before the fleet is beaten the town's
## garrison respawns behind the barracks; after, the town is free of them, and
## the desert outposts are always hostile.

const PATH := "res://content/core/story/main.json"
const OUTPOSTS := ["remnant_outpost_near", "remnant_outpost_mid", "remnant_outpost_far"]
const JETPACK := "jetpack"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f != null else null
		_data = d if d is Dictionary else {}
	return _data


static func chapters() -> Array:
	return data().get("chapters", [])


static func chapter_ids() -> Array:
	return chapters().map(func(c): return str(c.id))


static func chapter() -> String:
	return str(WorldState.story.get("chapter", chapter_ids()[0] if not chapters().is_empty() else ""))


static func chapter_cfg(id: String = "") -> Dictionary:
	if id == "":
		id = chapter()
	for c in chapters():
		if str(c.id) == id:
			return c
	return {}


static func index(id: String) -> int:
	return chapter_ids().find(id)


## The story has got as far as `id` (or past it).
static func reached(id: String) -> bool:
	return index(chapter()) >= index(id) and index(id) >= 0


## A fresh story: the first chapter, nothing told.
static func fresh() -> Dictionary:
	return { "chapter": str(chapter_ids()[0]) if not chapters().is_empty() else "", "told": false }


## Jump straight to a chapter (settings, tests). Earlier chapters' unlocks apply.
static func skip_to(id: String) -> void:
	if index(id) < 0:
		return
	WorldState.story = { "chapter": id, "told": false }
	if reached("fleet"):
		WorldState.set_flag("ships_unlocked")
	if id == "free":
		WorldState.story.told = true
		WorldState.set_flag("remnant_fleet_beaten")
		WorldState.set_flag("cruiser_taken")


# ------------------------------------------------------------------ events

## Something happened. Moves the story on when it is what this chapter waits for.
## Returns true if it did.
static func event(name: String) -> bool:
	var c := chapter_cfg()
	if c.is_empty() or str(c.get("done_on", "")) != name or name == "":
		return false
	var ids := chapter_ids()
	var next := str(ids[mini(index(chapter()) + 1, ids.size() - 1)])
	WorldState.story = { "chapter": next, "told": false }
	WorldState.log_event("Story: " + next.replace("_", " ") + ".")
	# Issue #193: done before it was asked (the cruiser taken before Oda sent you).
	var flag := str(chapter_cfg(next).get("done_flag", ""))
	if flag != "" and WorldState.has_flag(flag):
		event(str(chapter_cfg(next).get("done_on", "")))
	return true


# ------------------------------------------------------------------ tellers

## What `teller` says when the player walks up, if the story has something to
## say: { say, job } (job = a job id whose card goes with it, or ""), else {}.
## Talking to Oda for the first time finishes "meet_oda" and starts the range.
static func beat(teller: String) -> Dictionary:
	if teller == "cantina_owner" and chapter() == "meet_oda":
		event("met_oda")
	var c := chapter_cfg()
	if c.is_empty() or str(c.get("teller", "")) != teller:
		return {}
	var first := not bool(WorldState.story.get("told", false))
	WorldState.story.told = true
	if first and int(c.get("pays", 0)) > 0:
		WorldState.credits += int(c.pays)
		WorldState.log_event("Oda paid %d cr for the practice." % int(c.pays))
	if chapter() == "fleet":
		WorldState.set_flag("ships_unlocked")
	if chapter() == "free":
		return _free_beat(first)
	var job := str(c.get("job", ""))
	var job_open := job != "" and WorldState.open_jobs("confidant").any(func(j): return str(j.id) == job)
	var say := str(c.get("intro" if first else "remind", ""))
	if job_open and not first:
		say = str(c.get("intro", ""))       # the job is on offer again: say what it is
	if job == "j_bounty" and job_open:
		say += " " + str(WorldState.job(job).get("text", ""))
	if say == "":
		return {}
	return { "say": say, "job": job if job_open else "" }


## After the fleet: a bounty contract whenever none is out, else nothing (she
## talks as usual, and the smuggling job is hers to offer).
static func _free_beat(first: bool) -> Dictionary:
	var c := chapter_cfg()
	var lead := str(c.get("intro", "")) + " " if first else ""
	if WorldState.open_jobs("confidant").any(func(j): return str(j.id) == "j_bounty"):
		return { "say": lead + str(WorldState.job("j_bounty").get("text", "")), "job": "j_bounty" }
	return { "say": lead.strip_edges(), "job": "" } if lead != "" else {}


## Extra lines for the teller's model briefing: what the story wants right now.
static func brief(teller: String) -> String:
	var c := chapter_cfg()
	if str(c.get("teller", "")) != teller:
		return ""
	var out := str(c.get("remind", ""))
	if chapter() == "smuggle_1" and not WorldState.has_flag("story_jetpack_given"):
		out += " " + str(c.get("jetpack_hint", ""))
	return out.strip_edges()


## Oda's mood after a line (or when the player takes her job). In the first
## smuggling run, amused or warm, she lends the player her jetpack, once.
## Returns her line about it, or "".
static func on_owner_mood(mood: String) -> String:
	if chapter() != "smuggle_1" or WorldState.has_flag("story_jetpack_given") or not mood in ["amused", "warm"]:
		return ""
	WorldState.set_flag("story_jetpack_given")
	if not WorldState.inventory.has(JETPACK):
		WorldState.inventory.add(JETPACK)
	WorldState.log_event("Oda lent out her old jetpack.")
	return str(chapter_cfg().get("jetpack_line", ""))


## Oda has bounty contracts: the story's first one, then after the fleet, on repeat.
static func bounties_open() -> bool:
	return chapter() in ["bounty", "free"]


# ------------------------------------------------------------------ the Remnant

## The port's ships fly (Oda told you about the fleet).
static func ships_unlocked() -> bool:
	return WorldState.has_flag("ships_unlocked")


## The fleet is beaten: the garrison has left town and the outposts shoot on sight.
static func remnant_hostile() -> bool:
	return WorldState.has_flag("remnant_fleet_beaten")


static func town_garrison() -> bool:
	return not remnant_hostile()


## Issue #193: the cruiser's general is dead; nobody is left aboard.
static func cruiser_taken() -> bool:
	return WorldState.has_flag("cruiser_taken")


## Oda has sent you to the cruiser and it is not taken yet: climbing out meets its escort.
static func cruiser_mission() -> bool:
	return chapter() == "cruiser" and not cruiser_taken()


static func remnant_cfg() -> Dictionary:
	return data().get("remnant", {})


static func fleet_reward() -> int:
	return int(data().get("fleet_reward", 5000))


static func line(key: String) -> String:
	return str(data().get(key, key))


static func bounty_cfg() -> Dictionary:
	return data().get("bounty", {})


## What the outpost is called in a line ("the dry wash outpost"): its location's label.
static func outpost_label(id: String) -> String:
	var f := FileAccess.open("res://content/core/locations/%s.json" % id, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f != null else null
	return str(d.get("label", id)) if d is Dictionary else id


## The bounty target's soldier profile (content/core/soldiers/bounty_target.json).
static func target_profile() -> Dictionary:
	var f := FileAccess.open("res://content/core/soldiers/bounty_target.json", FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f != null else null
	return d if d is Dictionary else {}


static func target_naming() -> Dictionary:
	return target_profile().get("naming", {})
