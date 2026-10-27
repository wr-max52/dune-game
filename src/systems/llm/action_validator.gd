class_name ActionValidator
extends RefCounted
## The model proposes, the game decides (M12). Pure.
##
## Every action in a reply is checked against what the cantina owner was actually
## shown this turn (the briefing) and against game rules. Anything that fails is
## dropped with a reason (the debug overlay shows them). The validator never
## invents: it only keeps or clamps.

const TRUST_MIN := -3
const TRUST_MAX := 2
const TRUST_PER_VISIT := 6
const GUARDS_MAX_TRUST := 15

## briefing: the ids she was shown { rumors: [..], jobs: [..], secrets: [..], drinks: {id: {name, price}} }
## ctx: { trust, trust_this_visit, hostile (bool), insults (int) }
## -> { kept: [..], dropped: [{action, why}] }
static func validate(actions: Array, briefing: Dictionary, ctx: Dictionary) -> Dictionary:
	var kept: Array = []
	var dropped: Array = []
	var seen_types := {}
	var trust_left := TRUST_PER_VISIT - int(ctx.get("trust_this_visit", 0))
	for a in actions:
		if not (a is Dictionary):
			dropped.append({ "action": a, "why": "not an object" })
			continue
		var t := str(a.get("type", ""))
		var why := ""
		var out: Dictionary = a.duplicate()
		var allowed: Array = briefing.get("allowed", [])
		if not allowed.is_empty() and not allowed.has(t):
			dropped.append({ "action": a, "why": "not something this character does" })
			continue
		match t:
			"share_rumor":
				if not (briefing.get("rumors", []) as Array).has(str(a.get("id", ""))):
					why = "rumor not in briefing"
			"offer_job":
				if not (briefing.get("jobs", []) as Array).has(str(a.get("id", ""))):
					why = "job not on the board"
			"hint_secret":
				if not (briefing.get("secrets", []) as Array).has(str(a.get("id", ""))):
					why = "secret not unlocked"
			"trust":
				var d := clampi(int(a.get("delta", 0)), TRUST_MIN, TRUST_MAX)
				if d > 0:
					d = mini(d, maxi(0, trust_left))
				if d == 0:
					why = "no trust change left" if int(a.get("delta", 0)) > 0 else "zero"
				else:
					trust_left -= maxi(d, 0)
					out["delta"] = d
					out["why"] = str(a.get("why", "")).substr(0, 60)
			"pour_drink":
				var menu: Dictionary = briefing.get("drinks", {})
				var id := _drink_id(menu, a)
				if id == "":
					why = "not on the menu"
				else:
					out["id"] = id
					out["name"] = str(menu[id].name)
					out["price"] = int(menu[id].price)      # the game's price, never the model's
			"offer_speeder":
				var sale: Dictionary = briefing.get("sale", {})
				if sale.is_empty():
					why = "nothing for sale"
				else:
					out["id"] = str(sale.get("id", ""))
					out["name"] = str(sale.get("name", ""))
					out["price"] = int(sale.get("price", 0))      # the game's price, never the model's
			"refuse_topic", "end_conversation":
				pass
			"call_guards":
				if int(ctx.get("trust", 0)) >= GUARDS_MAX_TRUST:
					why = "trust too high to throw them out"
				elif not bool(ctx.get("hostile", false)) and int(ctx.get("insults", 0)) < 2:
					why = "player was not hostile"
			_:
				why = "unknown action"
		if why == "" and seen_types.has(t) and t != "share_rumor":
			why = "duplicate"
		if why != "":
			dropped.append({ "action": a, "why": why })
		else:
			seen_types[t] = true
			kept.append(out)
	return { "kept": kept, "dropped": dropped }


static func _drink_id(menu: Dictionary, a: Dictionary) -> String:
	var want := str(a.get("id", a.get("name", ""))).to_lower().strip_edges()
	for id in menu:
		if id == want or str(menu[id].name).to_lower() == want:
			return id
	return ""
