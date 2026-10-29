class_name PlanetOwner
extends RefCounted
## Issue #75: the cantina owner of a generated planet, a new iteration of Oda.
## Oda's own card (content/core/npcs/cantina_owner_card.json: her voice, drinks,
## actions, canned lines) with:
##
##   - a last name from the name generator: the last word of a person_drift name
##     the name book gives this planet's owner (so it never changes, and nothing
##     else gets it)
##   - the planet's and the town's names (and the kind of planet) in her prompt
##   - her own card id, cantina_owner_<planet id>: her own brain, relationship,
##     save entry and transcripts; nothing is shared with the port's Oda or any
##     other planet's
##   - no secrets of the port's, and rules that point at this town's landmarks
##
## Texts: content/core/npcs/planet_owner.json.

const TEMPLATE := "res://content/core/npcs/cantina_owner_card.json"
const CFG := "res://content/core/npcs/planet_owner.json"


static func card_id(planet_id: String) -> String:
	return "cantina_owner_" + planet_id


## Her card, ready for NpcBrain.
static func card(planet: Dictionary, book: NameBook = null) -> Dictionary:
	var b := book if book != null else WorldState.names
	var cfg := TownGen._read(CFG)
	var c := TownGen._read(TEMPLATE).duplicate(true)
	var pid := str(planet.get("id", "planet"))
	var first := str(cfg.get("first_name", "Oda"))
	var surname := surname_for(pid, b, str(cfg.get("name_kind", "person_drift")))
	var full := first + " " + surname
	b.reserve(full, "npc:" + card_id(pid))
	var world: Dictionary = planet.get("world", {})
	var ctx := {
		"name": full, "first": first, "surname": surname,
		"planet": PlanetGen.display_name(planet, b),
		"town": NameHooks.town(world, b),
		"kind": str(planet.get("type_cfg", {}).get("label", "planet")),
	}
	ctx["a_kind"] = ("an " if "aeiou".contains(str(ctx.kind).left(1).to_lower()) else "a ") + str(ctx.kind)
	if str(ctx.town) == "":
		ctx.town = "the town"
	c["id"] = card_id(pid)
	c["voice_role"] = "planet_owner"   # issue #164: a woman's voice of her own, by planet
	c["name"] = full
	c["note"] = "Generated (issue #75) by src/systems/planets/planet_owner.gd for planet %s." % pid
	for k in ["identity", "backstory", "people"]:
		c[k] = fill(str(cfg.get(k, c.get(k, ""))), ctx)
	var rules: Array = []
	for r in c.get("rules", []):
		var keep := true
		for w in cfg.get("rules_drop", []):
			if str(r).contains(str(w)):
				keep = false
		if keep:
			rules.append(str(r))
	for r in cfg.get("rules_add", []):
		rules.insert(rules.size() - 1, fill(str(r), ctx))
	c["rules"] = rules
	c["secrets"] = []               # the port's secrets are the port's
	c["mood_rules"] = []
	var acts: Array = c.get("actions", [])
	if not acts.has("offer_job"):
		acts.append("offer_job")
	c["actions"] = acts
	return c


## Her last name: the last word of the person_drift name the book gives her
## (generated once per planet, the same every time after).
static func surname_for(planet_id: String, book: NameBook, kind: String = "person_drift") -> String:
	var n := book.name_for(kind, "surname:" + card_id(planet_id))
	var words := n.replace("\"", "").split(" ", false)
	return words[words.size() - 1] if words.size() > 0 else "Vell"


static func fill(text: String, ctx: Dictionary) -> String:
	for k in ctx:
		text = text.replace("{" + str(k) + "}", str(ctx[k]))
	return text
