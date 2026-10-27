class_name DroidController
extends Node3D
## Companion droids in the town (issue #51). The node over the pure DroidRoster
## (WorldState.droids):
##   - your droids follow you on foot, vanish while you fly the ship and come
##     back beside you when you climb out,
##   - an assassin droid of yours shoots whoever the town is fighting you with,
##   - a cargo droid holds items the gate never searches ([E] near it),
##   - the droid merchant in the market buys and sells all three kinds,
##   - broken droids turn up in the desert now and then; [E] and ten seconds
##     beside one fixes it, and it follows you,
##   - the range remote follows you once you block its bolts five times in a row,
##   - the Remnant's own two droids patrol the main street, call the alarm and
##     fight when the garrison would,
##   - issue #64: each desert outpost keeps an assassin droid walking round it
##     (RemnantOutposts.droid_specs). Destroyed Remnant droids come back like the
##     troopers do (behind the barracks / at their outpost); after the fleet is
##     beaten the town's two are gone and the outposts' shoot on sight.
## Up to max_owned droids: a fourth asks which one to sell to make room.
## Words, prices and tuning: content/core/droids/droids.json. Looks: DroidKit.
##
## The headless test calls interact() and the menu's choose() directly: the same
## code path as the keys.

const BoltScene := preload("res://scenes/entities/bolt.tscn")
const DROID_LAYER := 2              ## bolts' sweep rays find them; bodies walk through them

var demo                            ## the town scene (town, terrain, garrison, npcs, training_range)
var player: CharacterBody3D
var gear: GearController            ## for its HUD (prompt, toast) and its focus (E is shared)
var ground_at := Callable()         ## (x, z) -> sand height
var cfg: Dictionary = {}
var labels: Dictionary = {}
var menu: DroidMenu
var companions: Dictionary = {}     ## uid -> DroidUnit (yours, following)
var wreck_nodes: Dictionary = {}    ## uid -> DroidUnit (broken, in the desert)
var remnant: Array = []             ## DroidUnit (the Remnant's patrol)
var vendor_pos := Vector3.INF
var focus: Dictionary = {}          ## what E would act on: { kind: "vendor"|"wreck"|"cargo", uid }
var fixing: Dictionary = {}         ## { uid, left }
var rng := RandomNumberGenerator.new()
var shots_fired := 0
var _wreck_clock := 0.0
var _heading := Vector3.FORWARD
var _mats: LookMaterials
var _was_locked := false


func setup(p_demo, p_player: CharacterBody3D, p_gear: GearController) -> void:
	demo = p_demo
	player = p_player
	gear = p_gear


func _ready() -> void:
	name = "Droids"
	cfg = DroidRoster.config()
	labels = cfg.get("labels", {})
	_mats = LookMaterials.new()
	rng.randomize()
	menu = DroidMenu.new()
	add_child(menu)
	if gear != null and gear.ground_at.is_valid():
		ground_at = gear.ground_at
	if demo != null and "town" in demo and demo.town != null:
		var v: Dictionary = cfg.get("vendor", {})
		if not demo.town.get_marker(str(v.get("marker", ""))).is_empty():
			var off: Array = v.get("offset", [0, 0, 0])
			vendor_pos = demo.town.marker_pos(str(v.marker)) + Vector3(float(off[0]), float(off[1]), float(off[2]))
	for w in roster().wrecks:
		_build_wreck(w)
	_build_remnant()
	if demo != null and "training_range" in demo and demo.training_range != null:
		demo.training_range.remote_tamed.connect(_on_remote_tamed)


func roster() -> DroidRoster:
	return WorldState.droids


func _l(key: String) -> String:
	return str(labels.get(key, key))


# ------------------------------------------------------------------ frame

func _physics_process(dt: float) -> void:
	if player == null:
		return
	if player.piloting:
		_despawn_companions()          # they wait while you fly
		fixing = {}
		focus = {}
	else:
		_sync_companions()
		_follow(dt)
		_companion_guns(dt)
		_tick_fix(dt)
		_tick_focus()
	_remnant_step(dt)
	_tick_wrecks(dt)
	_chirps(dt)


## Ten seconds beside a wreck fixes it; walking off cancels.
func _tick_fix(dt: float) -> void:
	if fixing.is_empty():
		return
	var n: DroidUnit = wreck_nodes.get(int(fixing.uid))
	if n == null or _flat_dist(n.global_position, player.global_position) > float(cfg.get("fix_reach", 2.6)) + 1.0:
		if n != null and gear != null and gear.hud != null:
			gear.hud.toast(_l("fix_cancelled") % DroidRoster.label(n.kind).to_lower())
		fixing = {}
		return
	fixing.left = float(fixing.left) - dt
	if float(fixing.left) <= 0.0:
		_finish_fix(int(fixing.uid))


func _tick_focus() -> void:
	if menu.is_open():
		return
	if _was_locked:
		player.locked = false
		_was_locked = false
	focus = {} if (gear != null and not gear.focus.is_empty()) else _find_focus()
	var text := prompt_text()
	if text != "" and gear != null and gear.hud != null:
		gear.hud.set_prompt(text)
	if not player.locked and focus.size() > 0 and InputMap.has_action("interact") and Input.is_action_just_pressed("interact"):
		interact()


func _find_focus() -> Dictionary:
	var p := player.global_position
	if vendor_pos != Vector3.INF and _flat_dist(p, vendor_pos) <= float(cfg.get("vendor", {}).get("reach", 3.5)) \
			and absf(p.y - vendor_pos.y) <= 2.0 and _vendor_open():
		return { "kind": "vendor" }
	for uid in wreck_nodes:
		if _flat_dist(p, wreck_nodes[uid].global_position) <= float(cfg.get("wrecks", {}).get("reach", 3.0)):
			return { "kind": "wreck", "uid": uid }
	for uid in companions:
		var d := roster().find(uid)
		if bool(DroidRoster.kind_cfg(str(d.get("kind", ""))).get("carries", false)) \
				and _flat_dist(p, companions[uid].global_position) <= 2.4:
			return { "kind": "cargo", "uid": uid }
	return {}


func _vendor_open() -> bool:
	if gear == null:
		return true
	return gear.is_open(cfg.get("vendor", {}))


func prompt_text() -> String:
	if not fixing.is_empty():
		var n: DroidUnit = wreck_nodes.get(int(fixing.uid))
		var total := float(cfg.get("fix_seconds", 10.0))
		if n != null:
			return _l("fixing") % [DroidRoster.label(n.kind).to_lower(), int(100.0 * (1.0 - float(fixing.left) / total))]
	match str(focus.get("kind", "")):
		"vendor":
			return _l("trade") % str(cfg.get("vendor", {}).get("label", "droid merchant")).to_lower()
		"wreck":
			var w := roster().find_wreck(int(focus.uid))
			return _l("fix") % [DroidRoster.label(str(w.get("kind", ""))).to_lower(), int(cfg.get("fix_seconds", 10.0))]
		"cargo":
			return _l("hold")
	return ""


# ------------------------------------------------------------------ actions

## Act on whatever is in reach. Returns "menu", "fixing", or "".
func interact() -> String:
	if focus.is_empty():
		focus = _find_focus()
	match str(focus.get("kind", "")):
		"vendor":
			_open_menu(_l("menu_trade") % [str(cfg.get("vendor", {}).get("label", "")), WorldState.credits,
				roster().owned.size(), DroidRoster.max_owned()], trade_options(), _on_trade)
			return "menu"
		"wreck":
			var uid := int(focus.uid)
			if roster().is_full():
				_ask_make_room(func(): start_fix(uid))
				return "menu"
			return "fixing" if start_fix(uid) else ""
		"cargo":
			var opts := hold_options(int(focus.uid))
			if opts.is_empty():
				_toast(_l("empty_hold"))
				return ""
			_open_menu(_l("menu_hold"), opts, _on_hold.bind(int(focus.uid)))
			return "menu"
	return ""


func _open_menu(title: String, opts: Array, pick: Callable) -> void:
	menu.open(title, opts, pick)
	if not player.locked:
		player.locked = true
		_was_locked = true


func trade_options() -> Array:
	var out := []
	for kind in cfg.get("vendor", {}).get("stock", []):
		out.append({ "id": "buy:" + str(kind), "text": _l("buy") % [DroidRoster.label(str(kind)), DroidRoster.price(str(kind))] })
	for d in roster().owned:
		out.append({ "id": "sell:%d" % int(d.uid), "text": _l("sell") % [DroidRoster.label(str(d.kind)), DroidRoster.resale(str(d.kind))] })
	return out


func _on_trade(id: String) -> void:
	if id.begins_with("buy:"):
		buy(id.substr(4))
	elif id.begins_with("sell:"):
		sell(int(id.substr(5)))


## Buy a droid from the merchant. Returns "bought", "full", "cant_afford" or "".
func buy(kind: String) -> String:
	var r := roster().buy(kind, DroidRoster.pick_variant(kind, rng), WorldState.credits)
	match str(r.get("error", "")):
		"full":
			_toast(_l("full") % DroidRoster.max_owned())
			return "full"
		"cant_afford":
			_toast(_l("cant_afford") % [DroidRoster.label(kind), DroidRoster.price(kind), WorldState.credits])
			return "cant_afford"
		"unknown":
			return ""
	WorldState.credits -= int(r.cost)
	WorldState.log_event(_l("event_bought") % DroidRoster.label(kind).to_lower())
	var at := vendor_pos if vendor_pos != Vector3.INF else player.global_position
	_spawn_companion(r.droid, at)
	_toast(_l("bought") % [DroidRoster.label(kind), int(r.cost)])
	return "bought"


## Sell one of your droids at the merchant's price. It leaves (de-spawns); what
## a cargo droid carried goes back in your pockets first. Returns the price or -1.
func sell(uid: int) -> int:
	var d := roster().find(uid)
	if d.is_empty():
		return -1
	var moved := roster().unload(uid, WorldState.inventory)
	var price := roster().sell(uid)
	WorldState.credits += price
	_free_companion(uid)
	var msg := _l("sold") % [DroidRoster.label(str(d.kind)), price]
	if moved > 0:
		msg += "  " + _l("unloaded_on_sale") % moved
	_toast(msg)
	return price


## At the cap: pick one droid to sell (merchant price) and then `then` runs.
## Walking away runs `declined` instead.
func _ask_make_room(then: Callable, declined := Callable()) -> void:
	var opts := []
	for d in roster().owned:
		opts.append({ "id": str(d.uid), "text": _l("sell") % [DroidRoster.label(str(d.kind)), DroidRoster.resale(str(d.kind))] })
	_open_menu(_l("make_room") % DroidRoster.max_owned(), opts, _on_make_room.bind(then, declined))


func _on_make_room(id: String, then: Callable, declined: Callable) -> void:
	if id != "" and sell(int(id)) >= 0:
		then.call()
	elif declined.is_valid():
		declined.call()


func hold_options(uid: int) -> Array:
	var out := []
	var inv := WorldState.inventory
	for id in inv.item_ids():
		var it: Dictionary = WorldState._item(str(id))
		out.append({ "id": "stash:" + str(id), "text": _l("stash") % [str(it.get("label", id)), inv.count(str(id))] })
	var d := roster().find(uid)
	var held: Array = []
	for id in d.get("cargo", {}):
		held.append("%s x%d" % [str(WorldState._item(str(id)).get("label", id)), int(d.cargo[id])])
	if not held.is_empty():
		out.append({ "id": "unload", "text": _l("unload") % ", ".join(held) })
	return out


func _on_hold(id: String, uid: int) -> void:
	if id == "unload":
		var moved := roster().unload(uid, WorldState.inventory)
		_toast(_l("unloaded") % moved)
	elif id.begins_with("stash:"):
		var item := id.substr(6)
		if roster().stash(uid, WorldState.inventory, item, WorldState.inventory.count(item)):
			_toast(_l("stashed") % str(WorldState._item(item).get("label", item)))
			if gear != null:
				gear.sync_gear()        # a stashed jetpack comes off your back
	_beep(companions.get(uid))


# ------------------------------------------------------------------ wrecks

func start_fix(uid: int) -> bool:
	if not wreck_nodes.has(uid) or roster().is_full():
		return false
	fixing = { "uid": uid, "left": float(cfg.get("fix_seconds", 10.0)) }
	Sound.play("droid_fix", wreck_nodes[uid].global_position)
	return true


func _finish_fix(uid: int) -> void:
	fixing = {}
	var n: DroidUnit = wreck_nodes.get(uid)
	var d := roster().fix_wreck(uid)
	if d.is_empty() or n == null:
		return
	var at := n.global_position
	wreck_nodes.erase(uid)
	n.queue_free()
	var u := _spawn_companion(d, at)
	Sound.play("droid_wake", at)
	_beep(u)
	WorldState.log_event(_l("event_found") % DroidRoster.label(str(d.kind)).to_lower())
	_toast(_l("fixed") % DroidRoster.label(str(d.kind)).to_lower())


## Now and then one more broken droid turns up out in the desert.
func _tick_wrecks(dt: float) -> void:
	_wreck_clock += dt
	if _wreck_clock < float(cfg.get("wrecks", {}).get("check_seconds", 300.0)):
		return
	_wreck_clock = 0.0
	spawn_wreck(false)


## Roll for a wreck now (force: skip the chance). Returns its uid or -1.
func spawn_wreck(force := true) -> int:
	var w := roster().roll_wreck(rng, Vector3.ZERO, ground_at, force)
	if w.is_empty():
		return -1
	_build_wreck(w)
	return int(w.uid)


func _build_wreck(w: Dictionary) -> void:
	var u := _make_unit(str(w.kind), str(w.variant))
	u.broken = true
	u.uid = int(w.uid)
	add_child(u)
	u.global_position = Vector3(float(w.pos[0]), float(w.pos[1]), float(w.pos[2]))
	u.rotation.y = rng.randf() * TAU
	_lay_down(u)
	wreck_nodes[int(w.uid)] = u


## Broken or dead: eyes dark, and down on the sand (the assassin flat on its back).
func _lay_down(u: DroidUnit) -> void:
	DroidKit.set_awake(u.look, false)
	var model := u.look.get_node("Model") as Node3D
	match u.kind:
		"assassin":
			# A rigged assassin plays its fall and stays down; the old look tips over.
			if DroidKit.play_anim(u.look, "die"):
				if u.broken:
					DroidKit.finish_anim(u.look)
				u.shape.rotation.x = PI * 0.5
				u.shape.position = Vector3(0, 0.15, 1.1)
				if u.hum != null:
					u.hum.stop()
				return
			model.rotation.x = PI * 0.5
			model.position.y = 0.12
			u.shape.rotation.x = PI * 0.5
			u.shape.position = Vector3(0, 0.15, 1.1)
		"floating":
			u.look.position.y = 0.25
			u.shape.position.y = 0.25
			model.rotation.z = 0.5
		"cargo":
			model.rotation.z = 0.35
	if u.hum != null:
		u.hum.stop()


# ------------------------------------------------------------------ taming

## The range remote wants to follow you (TrainingRange.remote_tamed).
func _on_remote_tamed() -> void:
	if roster().is_full():
		_ask_make_room(_take_remote, _decline_remote)
		return
	_take_remote()


func _decline_remote() -> void:
	roster().streak = 0
	_toast(_l("tame_declined"))


func _take_remote() -> void:
	var at: Vector3 = demo.training_range.release_remote() if demo != null and demo.training_range != null else Vector3.INF
	var d := roster().add("floating", "range")
	if d.is_empty():
		return
	var u := _spawn_companion(d, at if at != Vector3.INF else player.global_position)
	_beep(u)
	_toast(_l("tamed"))


# ------------------------------------------------------------------ companions

## Bring every owned droid that has no body yet, beside the player.
func _sync_companions() -> void:
	for d in roster().owned:
		if not companions.has(int(d.uid)):
			_spawn_companion(d, player.global_position - _heading * 2.0)
	for uid in companions.keys():
		if roster().find(uid).is_empty():
			_free_companion(uid)


func _spawn_companion(d: Dictionary, at: Vector3) -> DroidUnit:
	var u := _make_unit(str(d.kind), str(d.variant))
	u.uid = int(d.uid)
	add_child(u)
	u.global_position = Vector3(at.x, _ground_y(at), at.z)
	DroidKit.set_awake(u.look, true)
	companions[int(d.uid)] = u
	return u


func _free_companion(uid: int) -> void:
	var u: DroidUnit = companions.get(uid)
	companions.erase(uid)
	if u != null and is_instance_valid(u):
		u.queue_free()


func _despawn_companions() -> void:
	for uid in companions.keys():
		_free_companion(uid)


## Each droid holds its ground until the player gets `leash` metres away (its
## kind's "follow"), then walks to its slot beside / behind the player and stops
## there (within `settle` m). It catches up faster when far behind, and jumps to
## the slot if it was left a long way back (a jetpack hop, a speeder ride).
func _follow(dt: float) -> void:
	var v := Vector3(player.velocity.x, 0, player.velocity.z)
	if v.length() > 0.6:
		_heading = v.normalized()
	var right := _heading.cross(Vector3.UP).normalized()
	var i := 0
	for uid in companions:
		var u: DroidUnit = companions[uid]
		var f: Dictionary = DroidRoster.kind_cfg(u.kind).get("follow", {})
		var slot := player.global_position + right * (float(f.get("side", 1.0)) + 0.6 * (i % 2)) \
			- _heading * (float(f.get("back", 1.5)) + 0.9 * i)
		i += 1
		var to := Vector3(slot.x - u.global_position.x, 0, slot.z - u.global_position.z)
		var dist := to.length()
		if not u.following and _flat_dist(u.global_position, player.global_position) > float(f.get("leash", 5.0)):
			u.following = true
		elif u.following and dist <= float(f.get("settle", 0.35)):
			u.following = false
		var pos: Vector3 = u.global_position
		var speed := 0.0
		if dist > 40.0:
			pos = slot
		elif u.following:
			speed = float(f.get("speed", 7.0)) * (2.0 if dist > 8.0 else clampf(dist / 1.5, 0.3, 1.0))
			pos += to / dist * minf(speed * dt, dist)
			_face(u, to)
		elif u.kind != "assassin" or u.target == null:
			_face(u, player.global_position - u.global_position)
		pos.y = _ground_y(pos)
		u.global_position = pos
		u.walk(dt, u.following, speed)


## Your assassin droid: deadly aim at whoever the town is fighting you with.
func _companion_guns(dt: float) -> void:
	for uid in companions:
		var u: DroidUnit = companions[uid]
		if u.kind != "assassin":
			continue
		u.gun_cd -= dt
		u.target = _enemy_near(u, float(DroidRoster.kind_cfg("assassin").get("gun", {}).get("range", 34.0)))
		if u.target == null:
			continue
		var aim := _chest(u.target)
		_face(u, aim - u.global_position)
		if u.gun_cd <= 0.0:
			u.gun_cd = float(DroidRoster.kind_cfg("assassin").get("gun", {}).get("interval", 0.9))
			fire(u, aim, DroidRoster.kind_cfg("assassin").get("gun", {}))


func _enemy_near(u: DroidUnit, reach: float) -> Node3D:
	var best: Node3D = null
	var best_d := reach
	var cands: Array = []
	for r in remnant:
		if not r.dead and r.provoked:
			cands.append(r)
	var g = _garrison()
	if g != null and g.alarm.active() and demo != null:
		for n in demo.npcs:
			if is_instance_valid(n) and not n.dead:
				cands.append(n)
	for c in cands:
		var d: float = u.global_position.distance_to(c.global_position)
		if d < best_d and _clear_shot(u, c):
			best = c
			best_d = d
	return best


# ------------------------------------------------------------------ the Remnant's droids

func _build_remnant() -> void:
	var rc: Dictionary = cfg.get("remnant", {})
	var pts: Array = rc.get("patrol", [])
	if not pts.is_empty() and Story.town_garrison():
		var route: Array = pts.map(func(p): return _v3(p))
		for spec in rc.get("units", []):
			var sp: Dictionary = spec.duplicate()
			sp["patrol"] = route
			_spawn_remnant(sp, int(spec.get("start", 0)) % route.size())
	var outposts = demo.outposts if demo != null and "outposts" in demo else null
	if outposts == null:
		return
	var oc: Dictionary = rc.get("outpost_unit", {})
	for o in outposts.droid_specs():
		if (o.patrol as Array).is_empty():
			continue
		var sp: Dictionary = oc.duplicate()
		sp["patrol"] = o.patrol
		sp["outpost"] = o.outpost
		_spawn_remnant(sp, 0)


## One of the Remnant's droids from its spec ({ kind, variant, hp, gun, patrol:
## [Vector3], outpost }), standing at patrol point `start`.
func _spawn_remnant(spec: Dictionary, start: int, at := Vector3.INF) -> DroidUnit:
	var rc: Dictionary = cfg.get("remnant", {})
	var u := _make_unit(str(spec.get("kind", "assassin")), str(spec.get("variant", "remnant")))
	u.faction = str(rc.get("faction", "imperial_remnant"))
	u.max_hp = float(spec.get("hp", 40))
	u.hp = u.max_hp
	u.gun = spec.get("gun", DroidRoster.kind_cfg(u.kind).get("gun", {}))
	u.spec = spec
	u.patrol = spec.get("patrol", [])
	u.patrol_i = start % maxi(1, u.patrol.size())
	add_child(u)
	var p: Vector3 = at if at != Vector3.INF else (u.patrol[u.patrol_i] if not u.patrol.is_empty() else Vector3.ZERO)
	u.global_position = Vector3(p.x, _ground_y(p), p.z)
	DroidKit.set_awake(u.look, true)
	remnant.append(u)
	return u


## Issue #64: the fleet is beaten; the town's droids leave with the garrison.
func withdraw_town_remnant() -> void:
	for u in remnant.duplicate():
		if not u.spec.has("outpost"):
			remnant.erase(u)
			u.queue_free()


## A destroyed Remnant droid comes back: in town behind the barracks a minute
## later while the garrison holds the town, at its outpost after a few minutes.
func _tick_remnant_respawns(dt: float) -> void:
	for u in remnant.duplicate():
		if not u.dead or u.respawn_left < 0.0:
			continue
		u.respawn_left -= dt
		if u.respawn_left > 0.0:
			continue
		var at := Vector3.INF
		if not u.spec.has("outpost"):
			if not Story.town_garrison():
				u.respawn_left = -1.0
				continue
			var mk := str(Story.remnant_cfg().get("town_respawn_marker", "remnant_respawn"))
			if demo != null and not demo.town.get_marker(mk).is_empty():
				at = demo.town.marker_pos(mk)
		remnant.erase(u)
		u.queue_free()
		_spawn_remnant(u.spec, u.patrol_i, at)


func _garrison():
	return demo.garrison if demo != null and "garrison" in demo else null


## They turn on you exactly when the garrison would: the alarm is up, your Remnant
## standing is in the hostile band, or you shot at them.
func remnant_hostile(u: DroidUnit) -> bool:
	if u.provoked or Story.remnant_hostile():
		return true
	var g = _garrison()
	if g == null:
		return false
	return g.alarm.active() or g.checkpoint.base_band(int(WorldState.standing.get("imperial_remnant", 0))) == "hostile"


func _remnant_step(dt: float) -> void:
	var rc: Dictionary = cfg.get("remnant", {})
	_tick_remnant_respawns(dt)
	for u in remnant:
		if u.dead:
			continue
		var pts: Array = u.patrol
		u.gun_cd -= dt
		var sees := false
		if remnant_hostile(u) and not player.piloting:
			var d: float = u.global_position.distance_to(player.global_position)
			sees = d <= float(rc.get("sight", 22.0)) and _clear_shot(u, player)
		if sees:
			var aim := _chest(player)
			_face(u, aim - u.global_position)
			u.walk(dt, false)
			var g = _garrison()
			if g != null and not g.alarm.active():
				g._raise("droid")
			if u.gun_cd <= 0.0:
				u.gun_cd = float(u.gun.get("interval", 1.0))
				fire(u, aim, u.gun)
			continue
		if pts.is_empty():
			continue
		var goal: Vector3 = pts[u.patrol_i]
		var to := Vector3(goal.x - u.global_position.x, 0, goal.z - u.global_position.z)
		if to.length() < 0.6:
			u.patrol_i = (u.patrol_i + 1) % pts.size()
			continue
		var pos: Vector3 = u.global_position + to.normalized() * minf(float(rc.get("walk_speed", 2.2)) * dt, to.length())
		pos.y = _ground_y(pos)
		u.global_position = pos
		_face(u, to)
		u.walk(dt, true, float(rc.get("walk_speed", 2.2)))


## A bolt hit a droid. Yours and wrecks shrug it off; the Remnant's take damage
## from anyone outside the Remnant, turn on you, and call it in.
func on_unit_hit(u: DroidUnit, amount: float, shooter: Node) -> void:
	_beep(u)
	if u.faction == "" or u.dead:
		return
	if shooter is DroidUnit and (shooter as DroidUnit).faction == u.faction:
		return
	if shooter != null and "faction" in shooter and str(shooter.faction) == u.faction:
		return
	u.provoked = true
	u.hp -= amount
	var g = _garrison()
	if g != null and not g.alarm.active():
		g._raise("droid_shot")
	if u.hp <= 0.0:
		u.dead = true
		_lay_down(u)
		u.collision_layer = 0
		var rsc := Story.remnant_cfg()
		u.respawn_left = float(rsc.get("outpost_respawn_s" if u.spec.has("outpost") else "town_respawn_s", 60.0))
		WorldState.change_standing(u.faction, int(cfg.get("remnant", {}).get("kill_standing", -6)), "A Remnant patrol droid was destroyed.")
		WorldState.log_event(_l("event_remnant_droid"))


# ------------------------------------------------------------------ guns

## A bolt from a droid's gun (its kind's "gun" block) at a point.
func fire(u: DroidUnit, aim: Vector3, gun: Dictionary) -> Node:
	var origin := u.muzzle()
	var dir := (aim - origin).normalized()
	var spread := deg_to_rad(float(gun.get("spread_deg", 0.5)))
	dir = dir.rotated(Vector3.UP, rng.randf_range(-spread, spread))
	var axis := dir.cross(Vector3.UP)
	if axis.length() > 0.01:
		dir = dir.rotated(axis.normalized(), rng.randf_range(-spread, spread))
	var b = BoltScene.instantiate()
	b.direction = dir
	b.speed = float(gun.get("bolt_speed", 30.0))
	b.damage = float(gun.get("damage", 10.0))
	b.range_m = float(gun.get("range", 30.0)) + 15.0
	b.shooter = u
	b.stylize = true
	b.sweep = true
	b.color = Color(str(gun.get("color", "#ff5a3a")))
	var parent: Node = demo if demo is Node else self
	parent.add_child(b)
	b.global_position = origin
	shots_fired += 1
	Sound.play("droid_shot", origin)
	return b


## Nothing solid between the droid's muzzle and the target's chest (the player
## and other droids in the way count as solid, so it never shoots through you).
func _clear_shot(u: DroidUnit, target: Node3D) -> bool:
	if not is_inside_tree():
		return true
	var q := PhysicsRayQueryParameters3D.create(u.muzzle(), _chest(target))
	q.exclude = [u.get_rid()]
	q.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return true
	var c: Object = hit.collider
	return c == target or (c is Node and (target.is_ancestor_of(c) or (c as Node).is_ancestor_of(target)))


func _chest(t: Node3D) -> Vector3:
	if t is DroidUnit:
		return (t as DroidUnit).center()
	if t.has_method("eye_position"):
		return t.eye_position() - Vector3(0, 0.3, 0)
	return t.global_position + Vector3(0, 1.2, 0)


# ------------------------------------------------------------------ helpers

func _make_unit(kind: String, variant: String) -> DroidUnit:
	var u := DroidUnit.new()
	u.ctl = self
	u.kind = kind
	u.variant = variant
	u.collision_layer = DROID_LAYER
	u.collision_mask = 0
	u.shape = CollisionShape3D.new()
	var kc := DroidRoster.kind_cfg(kind)
	match kind:
		"floating":
			var s := SphereShape3D.new()
			s.radius = 0.3
			u.shape.shape = s
			u.look_lift = float(kc.get("hover", 1.7))
			u.shape.position = Vector3(0, u.look_lift, 0)
		"cargo":
			var b := BoxShape3D.new()
			b.size = Vector3(0.66, 0.7, 0.76)
			u.shape.shape = b
			u.shape.position = Vector3(0, 0.38, 0)
		_:
			var b := BoxShape3D.new()
			b.size = Vector3(0.55, float(kc.get("height", 2.3)) - 0.1, 0.4)
			u.shape.shape = b
			u.shape.position = Vector3(0, b.size.y * 0.5, 0)
	u.add_child(u.shape)
	u.look = DroidKit.build(kind, DroidRoster.variant_cfg(kind, variant), _mats, cfg.get("kinds", {}).get(kind, {}).get("look", {}))
	u.look.position.y = u.look_lift
	u.add_child(u.look)
	if kind == "floating":
		u.hum = Sound.loop("droid_hum", u)
		if u.hum != null:
			u.hum.autoplay = true
	return u


func _ground_y(p: Vector3) -> float:
	var top := (player.global_position.y if player != null else p.y) + 2.5
	top = maxf(top, p.y + 1.0)
	if is_inside_tree():
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, top, p.z), Vector3(p.x, top - 60.0, p.z), 1)
		if player != null:
			q.exclude = [player.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			return hit.position.y
	if ground_at.is_valid():
		return float(ground_at.call(p.x, p.z))
	return player.global_position.y if player != null else p.y


func _face(u: DroidUnit, dir: Vector3) -> void:
	var flat := Vector3(dir.x, 0, dir.z)
	if flat.length() > 0.05:
		u.rotation.y = atan2(-flat.x, -flat.z)
	if u.kind == "floating":
		var m := u.look.get_node("Model") as Node3D
		m.rotation.x = clampf(atan2(dir.y, flat.length()), -0.8, 0.8)


## Idle chatter: each droid near the player beeps in its own voice now and then.
func _chirps(dt: float) -> void:
	for u in companions.values() + remnant:
		if not is_instance_valid(u) or u.dead:
			continue
		u.chirp_cd -= dt
		if u.chirp_cd <= 0.0:
			u.chirp_cd = rng.randf_range(6.0, 14.0)
			if u.global_position.distance_to(player.global_position) <= 25.0:
				_beep(u)


func _beep(u) -> void:
	if u != null and is_instance_valid(u):
		Sound.play(str(DroidRoster.kind_cfg(u.kind).get("sound", "droid_beep")), u.center())


func _toast(text: String) -> void:
	if gear != null and gear.hud != null:
		gear.hud.toast(text, 4.0)


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func _v3(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## One droid in the world: a shootable body with its look. Origin on the ground.
class DroidUnit extends StaticBody3D:
	var ctl
	var uid := -1
	var kind := ""
	var variant := ""
	var faction := ""               ## "" = yours or a wreck; else the Remnant's
	var look: Node3D
	var shape: CollisionShape3D
	var look_lift := 0.0            ## a floating droid hovers this high
	var hum: Node
	var broken := false
	var dead := false
	var provoked := false
	var hp := 1.0
	var max_hp := 1.0
	var gun: Dictionary = {}
	var gun_cd := 0.0
	var chirp_cd := 4.0
	var patrol_i := 0
	var patrol: Array = []          ## Vector3 points it walks (the Remnant's)
	var spec: Dictionary = {}       ## how to build it again (the Remnant's)
	var respawn_left := -1.0        ## seconds until a dead one comes back (< 0 = never)
	var target: Node3D
	var following := false          ## closing the gap to its slot (else it holds still)
	var _t := 0.0

	func center() -> Vector3:
		match kind:
			"floating":
				return look.global_position
			"cargo":
				return global_position + Vector3(0, 0.45, 0)
		return global_position + Vector3(0, 1.5, 0)

	func muzzle() -> Vector3:
		var m := look.find_child("Muzzle", true, false) as Node3D
		if m != null:
			return m.global_position
		return center() + (-global_basis.z) * 0.35

	## Bob (floating), roll the wheels (cargo), walk or run (assassin: its rigged
	## clips, timed to `speed` in m/s; without a rig, a sway).
	func walk(dt: float, moving: bool, speed := 0.0) -> void:
		_t += dt
		var model := look.get_node("Model") as Node3D
		match kind:
			"floating":
				look.position.y = look_lift + sin(_t * 2.1) * 0.12
			"cargo":
				model.rotation.z = sin(_t * 18.0) * 0.02 if moving else 0.0
			"assassin":
				var a: Dictionary = DroidRoster.kind_cfg(kind).get("look", {})
				var played := false
				if not moving:
					played = DroidKit.play_anim(look, "idle")
				elif speed >= float(a.get("run_from", 3.5)):
					played = DroidKit.play_anim(look, "run", clampf(speed / float(a.get("run_speed", 5.0)), 0.6, 1.8))
				else:
					played = DroidKit.play_anim(look, "walk", clampf(maxf(speed, 1.0) / float(a.get("walk_speed", 1.6)), 0.6, 1.8))
				if not played:
					model.rotation.x = sin(_t * 7.0) * 0.03 if moving else 0.0

	func apply_damage_from(amount: float, shooter: Node) -> void:
		if ctl != null:
			ctl.on_unit_hit(self, amount, shooter)

	func apply_damage(amount: float) -> void:
		apply_damage_from(amount, null)
