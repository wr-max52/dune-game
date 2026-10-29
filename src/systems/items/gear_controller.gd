class_name GearController
extends Node
## Gear in a scene (M13). The thin node over the pure Inventory and Jetpack:
##   - places the location's pickups (content/core/pickups/<location>.json) and
##     knows where its vendors stand (content/core/vendors/*.json),
##   - puts Oda's smuggling drop out once the player takes her job
##     (WorldState.smuggle_drop()), and swaps it when she lines up the next one,
##   - shows a prompt when the player is in reach and acts on `interact` (E):
##     pick up, sell, buy,
##   - attaches and detaches gear on `gear_toggle` (G),
##   - gives the player node a Jetpack while one is on its back, puts the pack's
##     look on the body's chest joint, and lights its flames while thrusting,
##   - issue #148: owning an item with a "blade_color" (the red saber from the
##     wreck) turns the player's energy sword that colour,
##   - draws the fuel meter, and
##   - catches a player who flew out over the walls (the town has no ground there)
##     and puts them back where they last stood.
##
## The headless trace calls interact() and toggle_gear() directly: the same code
## path the keys use. All words come from content/core/flow/gear.json.

const CoreContent := preload("res://src/systems/dataload/core_content.gd")
const Jetpack := preload("res://src/systems/player/jetpack.gd")
const PickupNode := preload("res://src/systems/items/pickup_node.gd")
const LABELS_PATH := "res://content/core/flow/gear.json"
const SLOT_BACK := "back"
const FALL_MARGIN := 20.0       ## metres below the lowest floor before a rescue

var content
var town                        ## TownLayout (marker_pos, boxes)
var player: CharacterBody3D
var rig_node: Node              ## camera rig node (first-person check), optional
var location_id := "port_town"
var items: ItemKit
var hud: GearHud
var inventory_panel: InventoryPanel
var labels: Dictionary = {}
var pickups: Array = []         ## PickupNode
var drop                        ## PickupNode: Oda's smuggling drop, while one is lying out there
var vendors: Array = []         ## { cfg, pos }
var worn: Node3D                ## the attached item's look on the body
var worn_id := ""
var focus: Dictionary = {}      ## what E would act on: { kind: "pickup"|"vendor", ... }
var recoveries := 0
var lowest_floor := 0.0
## Ground height under (x, z), when the scene has terrain (the town's desert).
## Unset: the town's lowest floor stands in for the ground everywhere.
var ground_at := Callable()
## Issue #93: the world's ground (the ship's), set once the ship is built. Out on the home
## planet's ball the fall guard asks it how high you are over the ground along its up,
## because the flat (x, z) line above is wrong past the equator.
var ground: WorldGround
## Whether the stall at a vendor marker trades right now: (marker: String) -> bool.
## Unset: always open. The town's locals close a stall while they fight, or for good
## once its keeper is dead (Townsfolk.vendor_open).
var vendor_open := Callable()
## What a closed stall says: (marker: String) -> String ("" = the "closed" label).
var closed_line := Callable()

var _packs: Dictionary = {}     ## item id -> Jetpack (fuel survives a detach)
var _last_safe := Vector3.ZERO


func setup(p_content, p_town, p_player: CharacterBody3D, p_rig: Node = null, p_location: String = "port_town") -> void:
	content = p_content
	town = p_town
	player = p_player
	rig_node = p_rig
	location_id = p_location


func inv() -> Inventory:
	return WorldState.inventory


func _ready() -> void:
	name = "Gear"
	if content == null:
		content = CoreContent.new()
		content.load_from()
	var raw = ItemKit._read_json(LABELS_PATH)
	labels = raw.get("labels", {}) if raw is Dictionary else {}
	items = ItemKit.new()
	hud = GearHud.new()
	hud.fuel_label = _l("fuel")
	add_child(hud)
	# M15: what you are carrying, on I.
	inventory_panel = InventoryPanel.new()
	inventory_panel.content = content
	inventory_panel.name_of = _shown
	add_child(inventory_panel)
	lowest_floor = _lowest_floor()
	if player != null:
		_last_safe = player.global_position
	_build_pickups()
	_build_vendors()
	sync_gear()


func _l(key: String) -> String:
	return str(labels.get(key, key))


func floor_below(p: Vector3) -> float:
	if ground_at.is_valid():
		return minf(float(ground_at.call(p.x, p.z)), lowest_floor if _over_town(p) else INF)
	return lowest_floor


## Fallen out of the world: under the ground by FALL_MARGIN. Away from the town on the
## ball that is measured along the ground's up; everywhere else, on world y as before.
func fell_out_of_world(p: Vector3) -> bool:
	if ground != null and ground.sphere() != null and not _town_here(p):
		return ground.height_above(p) < -FALL_MARGIN
	return p.y < floor_below(p) - FALL_MARGIN


## Over the town's footprint and on its side of the ball (not the same x, z through the
## planet on the far side).
func _town_here(p: Vector3) -> bool:
	return _over_town(p) and (ground == null or ground.sphere() == null or ground.up_at(p).y > 0.5)


func _over_town(p: Vector3) -> bool:
	if town == null:
		return false
	var b: Dictionary = town.data.get("bounds", {})
	return not b.is_empty() and p.x >= float(b.min[0]) and p.x <= float(b.max[0]) \
		and p.z >= float(b.min[1]) and p.z <= float(b.max[1])


func _lowest_floor() -> float:
	var y := 0.0
	if town != null:
		for b in town.boxes():
			y = minf(y, float(b.min[1]))
	return y


# ------------------------------------------------------------------ world

func _build_pickups() -> void:
	for entry in content.get_pickups(location_id):
		if inv().is_taken(str(entry.get("id", ""))):
			continue
		var item: Dictionary = content.get_item(str(entry.get("item", "")))
		if item.is_empty():
			push_warning("GearController: pickup %s names an unknown item" % str(entry.get("id", "")))
			continue
		var node = PickupNode.new()
		node.setup(items, entry, item, _place(entry))
		# Issue #148: one a droid carries stays hidden (and out of reach) until
		# its carrier puts it on its back (DroidController._haul).
		node.visible = not bool(entry.get("carried", false))
		add_child(node)
		pickups.append(node)


## Issue #64: one loot box at a time. Contraband lying in the world (the desert
## cache) only shows in free play, and only while no drop of Oda's is out and
## the player carries none: it never gets in the way of the story's runs.
func _sync_loose_contraband() -> void:
	var allowed := Story.chapter() == "free" and WorldState.smuggle_drop().is_empty() and not WorldState.carrying_contraband()
	for n in pickups:
		if is_instance_valid(n) and bool(content.get_item(str(n.pickup.get("item", ""))).get("contraband", false)):
			n.visible = allowed


## Make the world match Oda's drop: place it when she puts one out, clear it
## once it is taken. Cheap; called every frame.
func sync_drop() -> void:
	_sync_loose_contraband()
	var want := WorldState.smuggle_drop()
	if str(want.get("location", "")) not in ["", location_id]:
		want = {}               # issue #75: taken on another planet; the drop is in its own town
	var have := str(drop.pickup.get("id", "")) if drop != null and is_instance_valid(drop) else ""
	if str(want.get("id", "")) == have:
		return
	if have != "":
		drop.queue_free()
	drop = null
	if want.is_empty():
		return
	var item: Dictionary = content.get_item(str(want.item))
	if item.is_empty():
		push_warning("GearController: smuggling drop names an unknown item")
		return
	drop = PickupNode.new()
	drop.setup(items, want, item, _place(want))
	add_child(drop)


func _build_vendors() -> void:
	for v in content.vendors_in(location_id):
		vendors.append({ "cfg": v, "pos": _place(v) })


## A data entry's world position: its town marker plus its offset.
func _place(entry: Dictionary) -> Vector3:
	var off: Array = entry.get("offset", [0, 0, 0])
	var at := Vector3.ZERO
	if town != null and not town.get_marker(str(entry.get("marker", ""))).is_empty():
		at = town.marker_pos(str(entry.get("marker", "")))
	at += Vector3(float(off[0]), float(off[1]), float(off[2]))
	# Out in the desert the sand is not flat: sit on it, never under it.
	if bool(entry.get("ground", false)) and ground_at.is_valid():
		at.y = maxf(at.y, float(ground_at.call(at.x, at.z)))
	return at


func pickup_node(pickup_id: String) -> Node3D:
	for n in pickups:
		if is_instance_valid(n) and str(n.pickup.get("id", "")) == pickup_id:
			return n
	return null


# ------------------------------------------------------------------ frame

func _physics_process(dt: float) -> void:
	if player == null:
		return
	if player.piloting:
		focus = {}
		if hud != null:
			hud.set_prompt("")
			hud.set_fuel(0.0, false, false)
		return
	sync_drop()
	focus = _find_focus()
	if hud != null:
		hud.set_prompt(prompt_text())
	if not player.locked:
		if InputMap.has_action("interact") and Input.is_action_just_pressed("interact"):
			interact()
		if InputMap.has_action("gear_toggle") and Input.is_action_just_pressed("gear_toggle"):
			toggle_gear()
	sync_gear()                 # cheap; catches a body attached later or a save loaded
	_update_worn_view()
	var jet = player.jetpack
	if worn != null:
		ItemKit.set_flames(worn, jet != null and jet.thrusting, 1.0)
	if hud != null:
		hud.set_fuel(jet.fraction() if jet != null else 0.0, jet != null, jet != null and jet.thrusting)
	_guard_fall()


func _find_focus() -> Dictionary:
	var p := player.global_position
	for n in pickups:
		if is_instance_valid(n) and n.visible and n.in_reach(p):
			return { "kind": "pickup", "node": n }
	if drop != null and is_instance_valid(drop) and drop.in_reach(p):
		return { "kind": "pickup", "node": drop }
	for v in vendors:
		var vp: Vector3 = v.pos
		if Vector2(p.x - vp.x, p.z - vp.z).length() <= float(v.cfg.get("reach", 3.0)) and absf(p.y - vp.y) <= 2.0:
			return { "kind": "vendor", "cfg": v.cfg }
	return {}


## An item as a prompt shows it: its label and its make and model, "Jetpack
## (Redfern BX-14 Wingbeat)" (issue #15; just the label when it has no naming).
func _shown(item: Dictionary, id: String) -> String:
	var label := str(item.get("label", id))
	var model := NameHooks.equipment(item, id)
	return ("%s (%s)" % [label, model]) if model != "" else label


## What the prompt says right now ("" when nothing is in reach).
func prompt_text() -> String:
	if focus.is_empty():
		return ""
	if focus.kind == "pickup":
		var item: Dictionary = content.get_item(str(focus.node.pickup.get("item", "")))
		return _l("pick_up") % _shown(item, str(focus.node.pickup.get("item", "")))
	var v: Dictionary = focus.cfg
	if not is_open(v):
		var said: String = closed_line.call(str(v.get("marker", ""))) if closed_line.is_valid() else ""
		return said if said != "" else _l("closed") % str(v.get("label", "vendor")).to_lower()
	if bool(v.get("bounties", false)) and WorldState.bounty_collectable():
		return str(Story.bounty_cfg().get("collect", "%s %d")) % [str(WorldState.bounty.name), int(WorldState.bounty.pay)]
	var sell_id := _sellable(v)
	if sell_id != "":
		var it: Dictionary = content.get_item(sell_id)
		return _l("sell") % [_shown(it, sell_id), str(v.get("label", "vendor")).to_lower(),
			Inventory.sell_price(it, v)]
	for id in inv().vendor_stock(v):
		var it: Dictionary = content.get_item(str(id))
		var cost := Inventory.buy_price(it, v)
		if cost <= WorldState.credits:
			return _l("buy") % [_shown(it, str(id)), str(v.get("label", "vendor")).to_lower(), cost]
		return _l("cant_afford") % [str(it.get("label", id)), cost, WorldState.credits]
	if v.has("pitch"):
		return str(v.pitch) % str(v.get("label", "vendor")).to_lower()
	return _l("nothing_to_trade") % str(v.get("label", "vendor")).to_lower()


## The first owned item this vendor buys (the attached one first).
func _sellable(v: Dictionary) -> String:
	var ids := inv().item_ids()
	var back := inv().in_slot(SLOT_BACK)
	if back != "":
		ids.erase(back)
		ids.push_front(back)
	for id in ids:
		if Inventory.sell_price(content.get_item(str(id)), v) >= 0:
			return str(id)
	return ""


# ------------------------------------------------------------------ actions

## Act on whatever is in reach. Returns what happened: "picked_up", "sold",
## "bought", "cant_afford", "bounty" (paid one out), or "" for nothing.
func interact() -> String:
	if focus.is_empty() and player != null:
		focus = _find_focus()
	if focus.is_empty():
		return ""
	if focus.kind == "pickup":
		return _take(focus.node)
	return _trade(focus.cfg)


func _take(node) -> String:
	var entry: Dictionary = node.pickup
	if not inv().pick_up(entry):
		return ""
	var id := str(entry.get("item", ""))
	var item: Dictionary = content.get_item(id)
	if str(entry.get("taken_flag", "")) != "":
		WorldState.set_flag(str(entry.taken_flag))
	pickups.erase(node)
	if node == drop:
		drop = null
	node.queue_free()
	focus = {}
	var msg := _l("picked_up") % str(item.get("label", id))
	# Wear it straight away if its slot is free.
	if inv().in_slot(str(item.get("slot", ""))) == "" and inv().attach(id, item):
		msg = _l("attached") % str(item.get("label", id))
	sync_gear()
	if hud != null:
		hud.toast(msg, 4.0)
	return "picked_up"


## False while the stall's keeper will not deal (see vendor_open).
func is_open(v: Dictionary) -> bool:
	return not vendor_open.is_valid() or bool(vendor_open.call(str(v.get("marker", ""))))


func _trade(v: Dictionary) -> String:
	if not is_open(v):
		return ""
	if bool(v.get("bounties", false)) and WorldState.bounty_collectable():
		# Issue #64: the fence pays Oda's bounties.
		var who := str(WorldState.bounty.name)
		var pay := WorldState.collect_bounty()
		if hud != null:
			hud.toast(str(Story.bounty_cfg().get("collected", "%d %s")) % [pay, who], 4.0)
		return "bounty"
	var sell_id := _sellable(v)
	if sell_id != "":
		var it: Dictionary = content.get_item(sell_id)
		var price := inv().sell(sell_id, it, v)
		if price < 0:
			return ""
		WorldState.credits += price
		WorldState.log_event(_l("event_sold") % str(it.get("label", sell_id)).to_lower())
		_packs.erase(sell_id)
		sync_gear()
		if bool(it.get("contraband", false)):
			WorldState.on_contraband_sold()     # issue #64: a smuggling run done?
		if hud != null:
			hud.toast(_l("sold") % [str(it.get("label", sell_id)), price])
		return "sold"
	for id in inv().vendor_stock(v):
		var it: Dictionary = content.get_item(str(id))
		var cost := inv().buy(str(id), it, v, WorldState.credits)
		if cost < 0:
			return "cant_afford"
		WorldState.credits -= cost
		WorldState.log_event(_l("event_bought") % str(it.get("label", id)).to_lower())
		if inv().in_slot(str(it.get("slot", ""))) == "":
			inv().attach(str(id), it)
		sync_gear()
		if hud != null:
			hud.toast(_l("bought") % [str(it.get("label", id)), cost])
		return "bought"
	return ""


## Put the back-slot gear on, or take it off. Returns "attached", "detached" or "".
func toggle_gear() -> String:
	var on := inv().in_slot(SLOT_BACK)
	if on != "":
		inv().detach(on)
		sync_gear()
		if hud != null:
			hud.toast(_l("detached") % str(content.get_item(on).get("label", on)))
		return "detached"
	for id in inv().item_ids():
		var it: Dictionary = content.get_item(str(id))
		if str(it.get("slot", "")) == SLOT_BACK and inv().attach(str(id), it):
			sync_gear()
			if hud != null:
				hud.toast(_l("attached") % str(it.get("label", id)))
			return "attached"
	if hud != null:
		hud.toast(_l("nothing_to_attach"))
	return ""


# ------------------------------------------------------------------ gear -> player

## Make the player match the inventory: a Jetpack on the node while a jetpack is
## on the back, and the worn look on the chest. Safe to call any time.
func sync_gear() -> void:
	if player == null:
		return
	var back := inv().in_slot(SLOT_BACK)
	var item: Dictionary = content.get_item(back) if back != "" else {}
	if item.has("jetpack"):
		if not _packs.has(back):
			_packs[back] = Jetpack.new(item.jetpack)
		player.jetpack = _packs[back]
	else:
		player.jetpack = null
	_mount_worn(back, item)
	var avatar := player.get_node_or_null("Avatar")
	var color := blade_color()
	if avatar != null and avatar.has_method("set_blade_color") and color.a > 0.0:
		avatar.set_blade_color(color)


## Issue #148: the energy sword's colour from what the player owns (an item with
## "blade_color"), or alpha 0 for the default.
func blade_color() -> Color:
	for id in inv().owned:
		var item: Dictionary = content.get_item(str(id))
		if inv().has(str(id)) and item.has("blade_color"):
			return Color(str(item.blade_color))
	return Color(0, 0, 0, 0)


func _mount_worn(id: String, item: Dictionary) -> void:
	var avatar := player.get_node_or_null("Avatar")
	var want := id if avatar != null else ""
	if want == worn_id and (worn == null) == (want == ""):
		return
	if worn != null:
		worn.queue_free()
		worn = null
	worn_id = want
	if want == "":
		return
	var look_id := str(item.get("look", id))
	worn = items.build(look_id)
	worn.name = "Worn_" + id
	var chest: Node3D = avatar.joints.get("chest") if "joints" in avatar else null
	if chest == null:
		chest = avatar
	chest.add_child(worn)
	worn.transform = items.on_back_transform(look_id)
	_update_worn_view()


## First person: the worn pack casts a shadow but is not drawn (like the body).
## Checked per mesh every tick rather than on a cached view flag: the flag could
## fall out of step with the meshes and leave the pack's shoulder straps drawn
## right beside the first-person camera.
func _update_worn_view() -> void:
	if worn == null:
		return
	var fp := false
	if rig_node != null and "rig" in rig_node and rig_node.rig != null:
		fp = rig_node.rig.is_first_person()
	var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if fp else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for m in PlayerAvatar._meshes_under(worn):
		if not str(m.get_parent().get_parent().name).begins_with("Flames") and m.get_parent().name != "Flames" \
				and (m as GeometryInstance3D).cast_shadow != mode:
			(m as GeometryInstance3D).cast_shadow = mode


# ------------------------------------------------------------------ safety

## A safety net for falling through the world. With terrain, "the world" is the
## ground under the player (out in the desert that can be well below the town);
## without it, the town has ground only inside its walls, so the lowest floor
## stands in. Drop FALL_MARGIN below that and you are put back where you stood.
func _guard_fall() -> void:
	if player.is_on_floor():
		_last_safe = player.global_position
		return
	if fell_out_of_world(player.global_position):
		var up := PlanetSphere.current.up_at(_last_safe) if PlanetSphere.current != null else Vector3.UP
		player.global_position = _last_safe + up * 0.1
		if player.has_method("align_to_ground"):
			player.call("align_to_ground", true)
		else:
			player.velocity = Vector3.ZERO
			player.controller.velocity = Vector3.ZERO
			player.controller.body_pos = player.global_position
		recoveries += 1
		if hud != null:
			hud.toast(_l("recovered"), 4.0)
