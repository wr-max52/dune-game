class_name SpeederShop
extends Node
## Issue #295: a speeder parts shop, the one Dorrin Vask ran alone (issue #95),
## now shared: Dorrin at his yard in the desert (MechanicYard) and, in free roam,
## Skrugs at his garage bench (SpeederPost). One menu, one price list.
##
##   talk()  -- [E] at the counter or bench: the menu (paint, looks, performance,
##              the Grav Lifter, selling the speeder for scrap), or "bring one
##              round" with no speeder in the bay.
##
## It only works on a speeder of yours parked in its bay (within bay_radius of the
## bay point). Parts are paid for here and fitted at once (SpeederPost.refit
## rebuilds the speeder where it stands). The fit is saved per speeder
## (WorldState.speeder_fits). Words, prices and parts:
## content/core/vehicles/speeder_upgrades.json (SpeederUpgrades.shop).
##
## The headless tests call talk(), buy(), scrap() and the menu's choose() directly:
## the same code paths as the keys.

var demo                              ## town_demo.gd (its speeder_post owns the speeders)
var gear: GearController              ## for its HUD (toasts)
var player: CharacterBody3D
var cfg: Dictionary = {}              ## SpeederUpgrades.shop(id): name, bay_radius, voice, lines, labels
var bay: Callable                     ## () -> Vector3: the bay, in the world
var speaker: Node3D                   ## who says the lines (his voice comes from there), may be null
var menu: DroidMenu
var said := ""                        ## the last line, for tests
var fitted := 0                       ## parts sold this session (tests, traces)
var _was_locked := false


func setup(p_demo, p_gear: GearController, p_cfg: Dictionary, p_bay: Callable) -> void:
	demo = p_demo
	gear = p_gear
	cfg = p_cfg
	bay = p_bay
	player = demo._player if demo != null and "_player" in demo else null
	name = "SpeederShop"
	menu = DroidMenu.new()
	add_child(menu)
	menu.option_selected.connect(_on_option_selected)


func npc_name() -> String:
	return str(cfg.get("name", "the mechanic"))


func label(key: String) -> String:
	return str(cfg.get("labels", {}).get(key, key))


func _line(key: String) -> String:
	return str(cfg.get("lines", {}).get(key, ""))


## True while the menu is up. Once it closes, the player it locked is let go.
func busy() -> bool:
	if menu.is_open():
		return true
	if _was_locked and player != null:
		player.locked = false
		_was_locked = false
	return false


# ------------------------------------------------------------------ the bay

## Your speeder parked in the bay (the nearest one to it), or null.
func speeder_in_bay() -> SpeederNode:
	var post: SpeederPost = demo.speeder_post if demo != null and "speeder_post" in demo else null
	if post == null or not bay.is_valid():
		return null
	var at: Vector3 = bay.call()
	var best: SpeederNode = null
	var best_d := float(cfg.get("bay_radius", 16.0))
	for s in post.speeders:
		if not is_instance_valid(s) or s.riding:
			continue
		var d: float = s.model.position.distance_to(at)
		if d <= best_d:
			best = s
			best_d = d
	return best


func _fit(s: SpeederNode) -> Dictionary:
	return demo.speeder_post.fit_for(int(s.get_meta("slot", 0)))


# ------------------------------------------------------------------ the menu

## [E]: the top menu, or "bring one round" with no speeder in the bay.
func talk() -> void:
	var s := speeder_in_bay()
	if s == null:
		_say(_line("no_speeder"))
		return
	_open(_line("hello"), top_options(), _on_top)


func top_options() -> Array:
	var s := speeder_in_bay()
	if s == null:
		return []
	var fit := _fit(s)
	var opts := [
		{ "id": "group:paint", "text": label("menu_paint") },
		{ "id": "group:looks", "text": label("menu_looks") },
		{ "id": "group:performance", "text": label("menu_performance") },
	]
	for p in SpeederUpgrades.in_group("lifter"):
		opts.append(_row(fit, p))
	opts.append({ "id": "scrap", "text": label("menu_scrap") % SpeederUpgrades.scrap_value(fit) })
	return opts


func group_options(group: String) -> Array:
	var s := speeder_in_bay()
	if s == null:
		return []
	var fit := _fit(s)
	var out: Array = []
	for p in SpeederUpgrades.in_group(group):
		out.append(_row(fit, p))
	out.append({ "id": "back", "text": label("back") })
	return out


func _row(fit: Dictionary, p: Dictionary) -> Dictionary:
	var id := str(p.get("id", ""))
	var why := SpeederUpgrades.why_not(fit, id)
	var text := label("buy") % [str(p.get("label", id)), int(p.get("price", 0))]
	if why == "owned":
		text = label("owned") % str(p.get("label", id))
	elif why.begins_with("needs:"):
		text = label("locked") % [str(p.get("label", id)), int(p.get("price", 0)),
			str(SpeederUpgrades.part(why.substr(6)).get("label", why.substr(6)))]
	return { "id": "buy:" + id, "text": text }


func _on_top(id: String) -> void:
	if id.begins_with("group:"):
		var g := id.substr(6)
		_open(_line("hello"), group_options(g), _on_group.bind(g))
	elif id.begins_with("buy:"):
		buy(id.substr(4))
		_reopen(top_options(), _on_top)
	elif id == "scrap":
		var s := speeder_in_bay()
		if s != null:
			_open(label("confirm_scrap") % SpeederUpgrades.scrap_value(_fit(s)),
				[{ "id": "yes", "text": label("yes_scrap") }, { "id": "no", "text": label("no_scrap") }], _on_scrap)


func _on_group(id: String, group: String) -> void:
	if id == "back":
		talk()
	elif id.begins_with("buy:"):
		buy(id.substr(4))
		_reopen(group_options(group), _on_group.bind(group))


## After a buy: the same menu again, with what was said and the new prices, the
## cursor where it was. Esc walks away.
func _reopen(opts: Array, pick: Callable) -> void:
	if speeder_in_bay() != null:
		menu.open(label("menu_title") % [npc_name(), WorldState.credits], opts, pick, said, true)


func _on_scrap(id: String) -> void:
	if id == "yes":
		scrap()
	else:
		talk()


# ------------------------------------------------------------------ trade

## Buy part `id` for the speeder in the bay and fit it now. Returns "bought",
## "cant_afford", "no_speeder", "owned", "needs:<part>" or "unknown".
func buy(id: String) -> String:
	var s := speeder_in_bay()
	if s == null:
		_say(_line("no_speeder"))
		return "no_speeder"
	var fit := _fit(s)
	var why := SpeederUpgrades.why_not(fit, id)
	if why != "":
		return why
	var p := SpeederUpgrades.part(id)
	var price := int(p.get("price", 0))
	if WorldState.credits < price:
		_say(_line("too_poor"))
		return "cant_afford"
	WorldState.credits -= price
	SpeederUpgrades.fit_part(fit, id)
	fitted += 1
	WorldState.log_event(label("event_bought") % str(p.get("label", id)).to_lower())
	demo.speeder_post.refit(s)
	_say(_line("bought"))
	return "bought"


## Sell the speeder in the bay for scrap. Returns the credits paid (0 = none there).
func scrap() -> int:
	var s := speeder_in_bay()
	if s == null:
		_say(_line("no_speeder"))
		return 0
	var pay := SpeederUpgrades.scrap_value(_fit(s))
	WorldState.credits += pay
	demo.speeder_post.remove(s)
	WorldState.log_event(label("event_scrapped"))
	_say(_line("scrapped"))
	return pay


# ------------------------------------------------------------------ talking

func _open(text: String, opts: Array, pick: Callable) -> void:
	said = text
	menu.open(label("menu_title") % [npc_name(), WorldState.credits], opts, pick, text)
	_speak(text)
	if player != null and not player.locked:
		player.locked = true
		_was_locked = true


func _say(text: String) -> void:
	said = text
	if gear != null and gear.hud != null and text != "":
		gear.hud.toast("%s: %s" % [npc_name(), text], 4.5)
	_speak(text)


func _speak(text: String) -> void:
	if speaker != null and is_instance_valid(speaker):
		NpcVoice.speak(text, NpcVoice.profile_for_npc(str(cfg.get("voice", "mechanic")), {}), "warm", speaker)


func _on_option_selected(_id: String) -> void:
	if speaker != null and is_instance_valid(speaker):
		NpcVoice.stop(speaker)
