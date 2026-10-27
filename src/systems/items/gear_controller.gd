class_name GearController
extends Node
## Gear in a scene (M13). The thin node over the pure Inventory and Jetpack:
##   - places the location's pickups (content/core/pickups/<location>.json) and
##     knows where its vendors stand (content/core/vendors/*.json),
##   - shows a prompt when the player is in reach and acts on `interact` (E):
##     pick up, sell, buy,
##   - attaches and detaches gear on `gear_toggle` (G),
##   - gives the player node a Jetpack while one is on its back, puts the pack's
##     look on the body's chest joint, and lights its flames while thrusting,
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
var vendors: Array = []         ## { cfg, pos }
var worn: Node3D                ## the attached item's look on the body
var worn_id := ""
var focus: Dictionary = {}      ## what E would act on: { kind: "pickup"|"vendor", ... }
var recoveries := 0
var lowest_floor := 0.0
## Ground height under (x, z), when the scene has terrain (the town's desert).
## Unset: the town's lowest floor stands in for the ground everywhere.
var ground_at := Callable()

var _packs: Dictionary = {}     ## item id -> Jetpack (fuel survives a detach)
var _last_safe := Vector3.ZERO
var _first_person := false


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
		add_child(node)
		pickups.append(node)


func _build_vendors() -> void:
	for v in content.vendors_in(location_id):
		vendors.append({ "cfg": v, "pos": _place(v) })


## A data entry's world position: its town marker plus its offset.
func _place(entry: Dictionary) -> Vector3:
	var off: Array = entry.get("offset", [0, 0, 0])
	var at := Vector3.ZERO
	if town != null and not town.get_marker(str(entry.get("marker", ""))).is_empty():
		at = town.marker_pos(str(entry.get("marker", "")))
	return at + Vector3(float(off[0]), float(off[1]), float(off[2]))


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
		if is_instance_valid(n) and n.in_reach(p):
			return { "kind": "pickup", "node": n }
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
## "bought", "cant_afford", or "" for nothing.
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
	pickups.erase(node)
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


func _trade(v: Dictionary) -> String:
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
	_first_person = not _first_person      # force the view pass below to apply
	_update_worn_view()


## First person: the worn pack casts a shadow but is not drawn (like the body).
func _update_worn_view() -> void:
	var fp := false
	if rig_node != null and "rig" in rig_node and rig_node.rig != null:
		fp = rig_node.rig.is_first_person()
	if fp == _first_person or worn == null:
		_first_person = fp
		return
	_first_person = fp
	var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if fp else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for m in PlayerAvatar._meshes_under(worn):
		if not str(m.get_parent().get_parent().name).begins_with("Flames") and m.get_parent().name != "Flames":
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
	if player.global_position.y < floor_below(player.global_position) - FALL_MARGIN:
		player.global_position = _last_safe + Vector3(0, 0.1, 0)
		player.velocity = Vector3.ZERO
		player.controller.velocity = Vector3.ZERO
		player.controller.body_pos = player.global_position
		recoveries += 1
		if hud != null:
			hud.toast(_l("recovered"), 4.0)
