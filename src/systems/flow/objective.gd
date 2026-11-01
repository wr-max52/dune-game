class_name Objective
extends RefCounted
## What to do next, and where (the HUD's objective pointer), and every job you
## have on (the job log on I). Pure and static, like Story: it only reads
## WorldState and the content, and never rolls a job or moves the story on.
##
## Most urgent first: a bounty to collect, a bounty to hunt, contraband to sell,
## a drop to find, supplies for the locals (issue #187), then what the story's
## chapter wants (home planet only).
##
## A target is a word the town scene turns into a place (ObjectiveHud.where):
## npc:<marker>, marker:<marker>, drop:<marker>, range, remote, pad, outpost:<location
## id>, cruiser, droid_post, and the F11 map's map:<x>,<z> and planet:<id>.
## Issue #251: the drop's target is a spot near it (within WorldState.DROP_NEAR,
## its area's marker until the drop is placed), not the exact spot: the last few
## metres are still a search. The general's run takes its goods to him, not the fence.
##
## Every line: content/core/story/main.json "objectives".

const VENDOR_DIR := "res://content/core/vendors"

static var _vendors: Array = []


static func cfg() -> Dictionary:
	return Story.data().get("objectives", {})


static func line(key: String) -> String:
	return str(cfg().get(key, ""))


static func home() -> bool:
	return GameFlow.current_planet_id() == PlanetGen.home_id()


## { text, target } for the pointer, or {} when there is nothing to point at.
## Issue #201: an optional quest whose waypoint the player switched on comes first,
## and before it a waypoint set on the F11 map (GlobeMap; only one is ever on).
static func current() -> Dictionary:
	var mark := GlobeMap.waypoint()
	if not mark.is_empty():
		return mark
	var quest := Quests.waypoint()
	if not quest.is_empty():
		return quest
	var b := WorldState.bounty
	if WorldState.bounty_collectable() and home():
		var fence := fence_marker(true)
		return { "text": line("collect") % str(b.name), "target": "marker:" + fence if fence != "" else "" }
	if not WorldState.bounty_target().is_empty():
		var where := Story.outpost_label(str(b.outpost))
		if not home():
			return { "text": line("hunt_away") % [str(b.name), where], "target": "" }
		return { "text": line("hunt") % [str(b.name), where], "target": "outpost:" + str(b.outpost) }
	if WorldState.carrying_contraband():
		if for_general():
			return { "text": line("general_bring"), "target": "npc:general" }
		var fence := fence_marker()
		return { "text": line("sell"), "target": "marker:" + fence if fence != "" else "" }
	var drop := WorldState.smuggle_drop()
	if not drop.is_empty() and str(drop.location) == WorldState.current_town_id():
		var hint := str(WorldState.smuggle.get("hint", ""))
		return { "text": run_line("drop") % hint, "target": "drop:" + str(drop.marker) }
	if not home():
		return {}
	var to := Territory.supply_out()
	if to != "":
		return { "text": Territory.line("objective") % Story.outpost_label(to), "target": "outpost:" + to }
	return chapter_objective()


## What the story's chapter wants: its own objective once its teller has told
## it, before that "go and talk to them" (the first chapter points at Oda
## from the start: T-89 only says where she is).
## Issue #303: on the dark master's oath, clearing the barracks comes before Oda.
static func chapter_objective() -> Dictionary:
	var c := Story.chapter_cfg()
	if c.is_empty():
		return {}
	var mine: Dictionary = cfg().get("chapters", {}).get(str(c.id), {})
	if str(c.id) == "debrief" and DarkPact.joined() and DarkPact.oath_open():
		mine = cfg().get("chapters", {}).get(DarkPact.QUEST, mine)
		return { "text": DarkPact.fill(str(mine.get("text", ""))), "target": str(mine.get("target", "")) }
	var told := bool(WorldState.story.get("told", false)) or str(c.get("teller", "")) != "cantina_owner"
	var o: Dictionary = mine if told and not mine.is_empty() else cfg().get("teller", {})
	return { "text": str(o.get("text", "")), "target": str(o.get("target", "")) } if str(o.get("text", "")) != "" else {}


## Issue #251: the run on is the general's and he is there to take its goods
## (dead or away, the fence still buys them).
static func for_general() -> bool:
	return WorldState.smuggle_to() == "general" and home() and GeneralPost.station() != ""


## A smuggling-run line, in the general's words ("general_<key>") while his run is on.
static func run_line(key: String) -> String:
	return line("general_" + key) if WorldState.smuggle_to() == "general" and cfg().has("general_" + key) else line(key)


## The marker of the stall that buys contraband in this town (or, with
## `bounties`, the one that pays bounties), or "".
static func fence_marker(bounties: bool = false) -> String:
	var here := WorldState.current_town_id()
	for v in vendors():
		if str(v.get("location", "")) != here or not "contraband" in v.get("buys", []):
			continue
		if bounties and not bool(v.get("bounties", false)):
			continue
		return str(v.get("marker", ""))
	return ""


static func vendors() -> Array:
	if _vendors.is_empty():
		var da := DirAccess.open(VENDOR_DIR)
		if da != null:
			for f in da.get_files():
				if f.ends_with(".json"):
					var fa := FileAccess.open(VENDOR_DIR + "/" + f, FileAccess.READ)
					var d = JSON.parse_string(fa.get_as_text()) if fa != null else null
					if d is Dictionary:
						_vendors.append(d)
	return _vendors


# ------------------------------------------------------------------ the job log

## The job log, one entry per thing on: [{ title, text }], the story first.
## Always at least one entry (log_none when nothing is on).
static func log_entries() -> Array:
	var out: Array = []
	if home():
		var c := Story.chapter_cfg()
		var say := str(c.get("remind", ""))
		if str(c.get("id", "")) == "debrief" and DarkPact.joined() and DarkPact.oath_open():
			say = str(chapter_objective().get("text", ""))
		if say == "":
			say = str(chapter_objective().get("text", ""))
		if say != "":
			out.append({ "title": line("log_story"), "text": say })
	var drop := WorldState.smuggle_drop()
	if WorldState.carrying_contraband():
		out.append({ "title": run_line("log_smuggle"), "text": line("general_log_carry") if for_general() else line("log_carry") })
	elif not drop.is_empty():
		out.append({ "title": run_line("log_smuggle"),
			"text": run_line("log_drop") % [WorldState.smuggle_goods_text(), str(WorldState.smuggle.get("hint", ""))] })
	var b := WorldState.bounty
	if not WorldState.bounty_target().is_empty():
		out.append({ "title": line("log_bounty"),
			"text": line("log_hunt") % [str(b.name), Story.outpost_label(str(b.outpost)), int(b.pay), str(b.crime)] })
	elif WorldState.bounty_collectable():
		out.append({ "title": line("log_bounty"), "text": line("log_collect") % [str(b.name), int(b.pay)] })
	var gear_line := GearUpgrades.owned_line()
	if gear_line != "":
		out.append({ "title": line("log_gear"), "text": gear_line })    # issue #208
	var ships := ShipUpgrades.owned_lines()
	if not ships.is_empty():
		out.append({ "title": line("log_ships"), "text": "\n".join(PackedStringArray(ships)) })    # issue #207
	for id in WorldState.jobs_taken:
		if WorldState.jobs_taken[id] == "active":
			var j := WorldState.job(str(id))
			out.append({ "title": str(j.get("title", id)).to_upper(), "text": str(j.get("text", "")) })
	if out.is_empty():
		out.append({ "title": "", "text": line("log_none") })
	return out


## "Runs sold: 3    Bounties paid: 1"
static func tally() -> String:
	return line("log_tally") % [WorldState.count("smuggle_sold"), WorldState.count("bounties_paid")]
