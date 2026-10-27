class_name ShipSalesman
extends Node3D
## T-89, the ship salesman in the pit (issue #58). A droid on the assassin droid's
## frame that never fights:
##   - nothing hurts him: his body is solid (you walk round him, bolts stop on
##     him) but nothing on him takes damage,
##   - once every time the game starts he says hello and offers the tutorial: the
##     controls and how things work, a page at a time. The player already spawns
##     armed; he only explains the weapons,
##   - [E] beside him opens his shop: every ship in content/core/ships that flies
##     in the atmosphere. A bought ship lands on the spare pad and is yours to fly
##     like any other parked ship (ShipPilot.add_berth); one at a time, and he buys
##     it back at resale_rate. WorldState.hangar keeps it across saves.
## Words, prices and his spot: content/core/npcs/t89.json. Looks: DroidKit.
##
## The headless test calls greet(), talk(), buy(), sell() and the menu's choose()
## directly: the same code paths as the keys. A headless run never greets on its own.

const CFG_PATH := "res://content/core/npcs/t89.json"
const CoreContent := preload("res://src/systems/dataload/core_content.gd")

static var greeted := false          ## the hello happens once per run of the game

var demo                             ## the town scene (town, decor, pilot, bar)
var player: CharacterBody3D
var gear: GearController             ## for its HUD (prompt, toast) and its focus (E is shared)
var cfg: Dictionary = {}
var labels: Dictionary = {}
var lines: Dictionary = {}
var content
var menu: DroidMenu
var body: StaticBody3D               ## T-89 himself
var pos := Vector3.INF
var in_reach := false
var page := -1                       ## the tutorial page showing, -1 = none
var bought_ship: Node3D              ## your ship on the spare pad (model, or a stand-in in the greybox)
var said := ""                       ## his last line, for tests
var _greet_left := -1.0
var _was_locked := false


func setup(p_demo, p_player: CharacterBody3D, p_gear: GearController) -> void:
	demo = p_demo
	player = p_player
	gear = p_gear


func _ready() -> void:
	name = "ShipSalesman"
	var f := FileAccess.open(CFG_PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f != null else null
	cfg = d if d is Dictionary else {}
	labels = cfg.get("labels", {})
	lines = cfg.get("lines", {})
	content = CoreContent.new()
	content.load_from()
	menu = DroidMenu.new()
	add_child(menu)
	_build_body()
	park_owned()
	if not greeted and DisplayServer.get_name() != "headless":
		_greet_left = float(cfg.get("greet_delay", 1.5))


func npc_name() -> String:
	return str(cfg.get("name", "T-89"))


func _l(key: String) -> String:
	return str(labels.get(key, key))


func _line(key: String) -> String:
	return str(lines.get(key, key))


# ------------------------------------------------------------------ body

## Where the marker says, facing its "face" point. The look is the assassin
## droid's, in his own colours; the collision box is on the default layer, so the
## player walks round him.
func _build_body() -> void:
	var town = demo.town if demo != null and "town" in demo else null
	var mk := str(cfg.get("marker", "t89"))
	if town == null or town.get_marker(mk).is_empty():
		push_warning("ShipSalesman: no marker " + mk)
		return
	pos = town.marker_pos(mk)
	body = StaticBody3D.new()
	body.name = "T89"
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 2.2, 0.45)
	cs.shape = box
	cs.position = Vector3(0, 1.1, 0)
	body.add_child(cs)
	var look_cfg: Dictionary = cfg.get("look", {})
	var mats: LookMaterials = demo._flat_mats() if demo.has_method("_flat_mats") else LookMaterials.new()
	var look := DroidKit.build(str(look_cfg.get("kind", "assassin")), look_cfg, mats)
	_disarm(look)
	body.add_child(look)
	DroidKit.set_awake(look, true)
	add_child(body)
	body.global_position = pos
	var m: Dictionary = town.get_marker(mk)
	if m.has("face"):
		_face(Vector3(float(m.face[0]), float(m.face[1]), float(m.face[2])) - pos)


## No pistol: the assassin frame's gun arm keeps only its arm, and lets it hang.
static func _disarm(look: Node3D) -> void:
	var arm := look.find_child("GunArm", true, false) as Node3D
	if arm == null:
		return
	for i in range(arm.get_child_count() - 1, 0, -1):
		var c := arm.get_child(i)
		arm.remove_child(c)
		c.free()
	arm.name = "Arm"
	arm.rotation.x = -PI * 0.45


## The look faces -Z.
func _face(dir: Vector3) -> void:
	if body != null and Vector2(dir.x, dir.z).length() > 0.01:
		body.rotation.y = atan2(-dir.x, -dir.z)


# ------------------------------------------------------------------ frame

func _physics_process(dt: float) -> void:
	if player == null or body == null:
		return
	if _greet_left >= 0.0:
		_greet_left -= dt
		if _greet_left < 0.0:
			if _busy():
				_greet_left = 0.25        # wait until nothing else has the player
			else:
				greet()
	if _flat_dist(player.global_position, pos) < 10.0:
		var to := player.global_position - pos
		var want := atan2(-to.x, -to.z)
		body.rotation.y = lerp_angle(body.rotation.y, want, minf(1.0, dt * 4.0))
	_tick_focus()


## Something else has the player: flying, a menu, a conversation.
func _busy() -> bool:
	if player.piloting or player.locked or menu.is_open():
		return true
	return demo != null and demo.bar != null and demo.bar.is_talking()


func _tick_focus() -> void:
	if menu.is_open():
		return
	if _was_locked:
		player.locked = false
		_was_locked = false
	var p := player.global_position
	in_reach = not player.piloting and _flat_dist(p, pos) <= float(cfg.get("reach", 3.2)) \
		and absf(p.y - pos.y) <= 2.0 and (gear == null or gear.focus.is_empty())
	if not in_reach:
		return
	if gear != null and gear.hud != null:
		gear.hud.set_prompt(_l("talk") % npc_name())
	if not player.locked and InputMap.has_action("interact") and Input.is_action_just_pressed("interact"):
		talk()


# ------------------------------------------------------------------ talk

## The hello at startup, and the offer of the tutorial.
func greet() -> void:
	greeted = true
	_greet_left = -1.0
	_beep()
	_open(str(cfg.get("greeting", "")) + "\n\n" + str(cfg.get("offer_tutorial", "")),
		[{ "id": "yes", "text": _l("yes_tutorial") }, { "id": "no", "text": _l("no_tutorial") }], _on_offer)


func _on_offer(id: String) -> void:
	if id == "yes":
		start_tutorial()
	else:
		_say(_line("skipped"))


## [E] beside him: the shop, and the tutorial again.
func talk() -> void:
	_beep()
	var opts := shop_options()
	opts.append({ "id": "tutorial", "text": _l("tutorial") })
	_open(_line("hello_again"), opts, _on_shop)


func _open(text: String, opts: Array, pick: Callable) -> void:
	said = text
	menu.open(_l("menu_title") % [npc_name(), WorldState.credits], opts, pick, text)
	if player != null and not player.locked:
		player.locked = true
		_was_locked = true


func _say(text: String) -> void:
	said = text
	if gear != null and gear.hud != null and text != "":
		gear.hud.toast("%s: %s" % [npc_name(), text], 4.5)


# ------------------------------------------------------------------ tutorial

func tutorial_pages() -> Array:
	return cfg.get("tutorial", [])


func start_tutorial() -> void:
	page = 0
	_show_page()


func _show_page() -> void:
	var pages := tutorial_pages()
	if page < 0 or page >= pages.size():
		page = -1
		return
	var last := page == pages.size() - 1
	var opts := [{ "id": "done", "text": _l("done") }] if last \
		else [{ "id": "next", "text": _l("next") }, { "id": "skip", "text": _l("skip") }]
	_open("(%d/%d)  %s" % [page + 1, pages.size(), str(pages[page])], opts, _on_page)


func _on_page(id: String) -> void:
	if id == "next":
		page += 1
		_show_page()
		return
	var finished := id == "done"
	page = -1
	if not finished:
		_say(_line("skipped"))


# ------------------------------------------------------------------ shop

## Every ship that flies in the atmosphere and has a model, cheapest first.
func stock() -> Array:
	var out := []
	for id in content.ships:
		var s: Dictionary = content.ships[id]
		if s.has("atmosphere") and str(s.get("look", "")) != "":
			out.append(str(id))
	out.sort_custom(func(a, b): return price(a) < price(b) or (price(a) == price(b) and a < b))
	return out


func price(ship_id: String) -> int:
	return int(cfg.get("prices", {}).get(ship_id, cfg.get("default_price", 1500)))


func resale(ship_id: String) -> int:
	return int(round(price(ship_id) * float(cfg.get("resale_rate", 0.6))))


func ship_label(ship_id: String) -> String:
	return str(content.get_ship(ship_id).get("label", ship_id))


func shop_options() -> Array:
	var out := []
	var taken := WorldState.hangar != ""
	for id in stock():
		out.append({ "id": "buy:" + id, "text": _l("buy_taken" if taken else "buy") % [ship_label(id), price(id)] })
	if taken:
		out.append({ "id": "sell", "text": _l("sell") % [ship_label(WorldState.hangar), resale(WorldState.hangar)] })
	return out


func _on_shop(id: String) -> void:
	if id.begins_with("buy:"):
		buy(id.substr(4))
	elif id == "sell":
		sell()
	elif id == "tutorial":
		start_tutorial()


## Buy a ship: it lands on the spare pad. Returns "bought", "taken",
## "cant_afford" or "" (not for sale).
func buy(ship_id: String) -> String:
	if not stock().has(ship_id):
		return ""
	if WorldState.hangar != "":
		_say(_line("pad_taken") % ship_label(WorldState.hangar))
		return "taken"
	var cost := price(ship_id)
	if WorldState.credits < cost:
		_say(_line("cant_afford") % [ship_label(ship_id), cost, WorldState.credits])
		return "cant_afford"
	WorldState.credits -= cost
	WorldState.hangar = ship_id
	WorldState.log_event(_l("event_bought") % ship_label(ship_id))
	park_owned()
	Sound.play("droid_wake", pos)
	_say(_line("bought") % ship_label(ship_id))
	return "bought"


## Sell your bought ship back. Not while you fly it. Returns the price or -1.
func sell() -> int:
	var id := WorldState.hangar
	if id == "":
		return -1
	var pilot = demo.pilot if demo != null else null
	if bought_ship != null and pilot != null:
		var last: int = pilot.berths.size() - 1
		if last <= 0 or pilot.berths[last].visual != bought_ship:
			return -1
		if not pilot.remove_last_berth():
			_say(_line("flying_it") % ship_label(id))
			return -1
	elif bought_ship != null:
		if demo != null and demo.decor != null:
			demo.decor.parked_ships.erase(bought_ship)
		bought_ship.queue_free()
	bought_ship = null
	var paid := resale(id)
	WorldState.credits += paid
	WorldState.hangar = ""
	_say(_line("sold") % paid)
	return paid


## Put WorldState.hangar's ship on the spare pad (bought now, or loaded from a
## save) and make it boardable.
func park_owned() -> void:
	if WorldState.hangar == "" or bought_ship != null or demo == null:
		return
	var box: Dictionary = demo.town.get_box(str(cfg.get("pad", "spare_pad")))
	if box.is_empty():
		push_warning("ShipSalesman: no pad box " + str(cfg.get("pad", "")))
		return
	if demo.decor != null:
		bought_ship = demo.decor.park_ship(WorldState.hangar, box)
	if bought_ship == null:
		# The greybox: no models, so a bare node stands in (as ShipPilot does for the pit ship).
		bought_ship = Node3D.new()
		bought_ship.name = "Parked_" + str(box.id)
		demo.add_child(bought_ship)
		bought_ship.global_position = Vector3((float(box.min[0]) + float(box.max[0])) * 0.5, float(box.min[1]),
			(float(box.min[2]) + float(box.max[2])) * 0.5)
		bought_ship.rotation.y = deg_to_rad(float(box.get("parked_yaw_deg", 0.0)))
	if demo.pilot != null:
		demo.pilot.add_berth(bought_ship, WorldState.hangar, str(box.id))


# ------------------------------------------------------------------ helpers

func _beep() -> void:
	if body != null:
		Sound.play("assassin_beep", pos)


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
