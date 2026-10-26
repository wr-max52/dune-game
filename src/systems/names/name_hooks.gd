class_name NameHooks
extends RefCounted
## How things in the game get their names (issue #15). Every spawner calls one of
## these with the thing's data and a stable key; what kind of name it gets comes
## from that data's "naming" block, never from code:
##
##   soldier / ship profile   "naming": { "kind": "person_remnant", "titles": "remnant_rank" }
##   ship (the craft itself)  "naming": { ..., "vessel": "vessel" }
##   item                     "naming": { "kind": "equipment", "class": "jetpack" }
##   world                    "naming": { "town": "town", "planet": "planet" }
##
## Names go into WorldState.names (the NameBook), so they are unique across the
## game, saved with it, and the same thing keeps its name across scenes.

## A person (an NPC on foot, a pilot): "<title> <name>" when the naming block lists
## titles (a list in the name library, e.g. remnant_rank), else just the name.
## "" when the data has no naming block.
static func person(naming: Dictionary, key: String, book: NameBook = null) -> String:
	if naming.is_empty() or not naming.has("kind"):
		return ""
	var b := book if book != null else WorldState.names
	if b.labels.has(key):
		return b.labels[key]
	var n := b.name_for(str(naming.kind), key, naming.get("ctx", {}))
	if n == "":
		return ""
	var title := ""
	if naming.has("titles"):
		title = b.pick(key, b.engine.lists.get(str(naming.titles), []), "title")
	var shown := ("%s %s" % [title, n]) if title != "" else n
	b.labels[key] = shown
	return shown


## A pilot's callsign (separate from their name, unique among callsigns too).
static func callsign(naming: Dictionary, key: String, book: NameBook = null) -> String:
	if not bool(naming.get("callsign", false)):
		return ""
	var b := book if book != null else WorldState.names
	return b.name_for("callsign", key + "#callsign")


## A ship's own name ("Restless Ledger"), from the ship data's naming.vessel kind.
static func vessel(ship_cfg: Dictionary, key: String, book: NameBook = null) -> String:
	var kind := str(ship_cfg.get("naming", {}).get("vessel", ""))
	if kind == "":
		return ""
	var b := book if book != null else WorldState.names
	return b.name_for(kind, key)


## An item's make and model ("Redfern BX-14 Wingbeat"). One per item id: every
## jetpack of that id is the same model.
static func equipment(item_cfg: Dictionary, item_id: String, book: NameBook = null) -> String:
	var naming: Dictionary = item_cfg.get("naming", {})
	if naming.is_empty():
		return ""
	var b := book if book != null else WorldState.names
	return b.name_for(str(naming.get("kind", "equipment")), "item:" + item_id, { "class": str(naming.get("class", "tool")) })


## The town a world is built around, and the planet it is on.
static func town(world: Dictionary, book: NameBook = null) -> String:
	return _place(world, "town", "town:" + str(world.get("town", "")), book)


static func planet(world: Dictionary, book: NameBook = null) -> String:
	return _place(world, "planet", "planet:" + str(world.get("id", "")), book)


static func _place(world: Dictionary, what: String, key: String, book: NameBook) -> String:
	var kind := str(world.get("naming", {}).get(what, ""))
	if kind == "":
		return ""
	var b := book if book != null else WorldState.names
	return b.name_for(kind, key)


## Everyone named so far whose key starts with `prefix` ("npc:"), as shown
## (with titles). For the bartender's briefing: she knows the town's people.
static func known(prefix: String, book: NameBook = null) -> PackedStringArray:
	var b := book if book != null else WorldState.names
	var out := PackedStringArray()
	var keys := b.labels.keys()
	keys.sort()
	for k in keys:
		if str(k).begins_with(prefix):
			out.append(str(b.labels[k]))
	return out
