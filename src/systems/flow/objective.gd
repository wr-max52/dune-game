class_name Objective
extends RefCounted
## What to do next, and where (the HUD's objective pointer), and every job you
## have on (the job log on I). Pure and static, like Story: it only reads
## WorldState and the content, and never rolls a job or moves the story on.
##
## Most urgent first: a bounty to collect, a bounty to hunt, contraband to sell,
## a drop to find, then what the story's chapter wants (home planet only).
##
## A target is a word the town scene turns into a place (ObjectiveHud.where):
## npc:<marker>, marker:<marker>, range, remote, pad, outpost:<location id>, cruiser,
## droid_post.
## The drop's target is its area's marker, not the exact spot: finding it is the job.
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
## Issue #201: an optional quest whose waypoint the player switched on comes first.
static func current() -> Dictionary:
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
		var fence := fence_marker()
		return { "text": line("sell"), "target": "marker:" + fence if fence != "" else "" }
	var drop := WorldState.smuggle_drop()
	if not drop.is_empty() and str(drop.location) == WorldState.current_town_id():
		var hint := str(WorldState.smuggle.get("hint", ""))
		return { "text": line("drop") % hint, "target": "marker:" + str(drop.marker) if str(drop.marker) != "" else "" }
	if not home():
		return {}
	return chapter_objective()


## What the story's chapter wants: its own objective once its teller has told
## it, before that "go and talk to them" (the first chapter points at Oda
## from the start: T-89 only says where she is).
static func chapter_objective() -> Dictionary:
	var c := Story.chapter_cfg()
	if c.is_empty():
		return {}
	var mine: Dictionary = cfg().get("chapters", {}).get(str(c.id), {})
	var told := bool(WorldState.story.get("told", false)) or str(c.get("teller", "")) != "cantina_owner"
	var o: Dictionary = mine if told and not mine.is_empty() else cfg().get("teller", {})
	return { "text": str(o.get("text", "")), "target": str(o.get("target", "")) } if str(o.get("text", "")) != "" else {}


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
		if say == "":
			say = str(chapter_objective().get("text", ""))
		if say != "":
			out.append({ "title": line("log_story"), "text": say })
	var drop := WorldState.smuggle_drop()
	if WorldState.carrying_contraband():
		out.append({ "title": line("log_smuggle"), "text": line("log_carry") })
	elif not drop.is_empty():
		out.append({ "title": line("log_smuggle"),
			"text": line("log_drop") % [WorldState.smuggle_goods_text(), str(WorldState.smuggle.get("hint", ""))] })
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
