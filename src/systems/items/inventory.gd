class_name Inventory
extends RefCounted
## The player's gear (M13). Pure and headless-testable: what the player owns, what
## is attached in each body slot, which pickups in the world are already taken, and
## what each vendor holds after the player has traded with them.
##
## It never touches money or nodes. Prices come back as numbers; the caller
## (GearController) moves the credits in WorldState and updates the world. Item,
## vendor and pickup facts come from content/core (items/, vendors/, pickups/), so a
## new item is a JSON file, not code.
##
## Lives in WorldState.inventory, so it survives town -> flight -> town and is saved
## with the rest of the world.

var owned: Dictionary = {}      ## item id -> count
var attached: Dictionary = {}   ## slot -> item id ("back" -> "jetpack")
var taken: Dictionary = {}      ## pickup id -> true
var stock: Dictionary = {}      ## vendor id -> Array of item ids (once traded with)


# ---- owning -------------------------------------------------------------------

func count(id: String) -> int:
	return int(owned.get(id, 0))


func has(id: String) -> bool:
	return count(id) > 0


func add(id: String, n: int = 1) -> void:
	owned[id] = count(id) + n


## Remove n of an item. Returns false (and changes nothing) when there are fewer.
## Removing the last one also takes it off the body.
func remove(id: String, n: int = 1) -> bool:
	if count(id) < n:
		return false
	owned[id] = count(id) - n
	if owned[id] <= 0:
		owned.erase(id)
		detach(id)
	return true


func item_ids() -> Array:
	var ids := owned.keys()
	ids.sort()
	return ids


# ---- attaching ------------------------------------------------------------------

## Put an owned item in its body slot (from the item's "slot"). Whatever was in that
## slot comes off. Returns false for items you do not own or that have no slot.
func attach(id: String, item_cfg: Dictionary) -> bool:
	var slot := str(item_cfg.get("slot", ""))
	if slot == "" or not has(id):
		return false
	attached[slot] = id
	return true


## Take an item off the body. It stays owned. Returns false if it was not attached.
func detach(id: String) -> bool:
	for slot in attached.keys():
		if attached[slot] == id:
			attached.erase(slot)
			return true
	return false


func is_attached(id: String) -> bool:
	return attached.values().has(id)


func in_slot(slot: String) -> String:
	return str(attached.get(slot, ""))


# ---- pickups --------------------------------------------------------------------

func is_taken(pickup_id: String) -> bool:
	return taken.has(pickup_id)


## Take a pickup placed in the world. Returns false if it was already taken.
func pick_up(pickup: Dictionary) -> bool:
	var pid := str(pickup.get("id", ""))
	if pid == "" or is_taken(pid):
		return false
	taken[pid] = true
	add(str(pickup.get("item", "")), maxi(1, int(pickup.get("count", 1))))
	return true


# ---- trade ----------------------------------------------------------------------

## What a vendor has for sale: its data stock until the player trades with it, then
## whatever trading left there.
func vendor_stock(vendor_cfg: Dictionary) -> Array:
	var vid := str(vendor_cfg.get("id", ""))
	if stock.has(vid):
		return stock[vid]
	return (vendor_cfg.get("stock", []) as Array).duplicate()


## Credits a vendor pays for an item, or -1 if it does not buy that kind.
static func sell_price(item_cfg: Dictionary, vendor_cfg: Dictionary) -> int:
	var kinds: Array = vendor_cfg.get("buys", [])
	if not kinds.has(str(item_cfg.get("kind", ""))):
		return -1
	return int(round(float(item_cfg.get("value", 0)) * float(vendor_cfg.get("buy_rate", 0.5))))


## Credits a vendor asks for an item.
static func buy_price(item_cfg: Dictionary, vendor_cfg: Dictionary) -> int:
	return int(round(float(item_cfg.get("value", 0)) * float(vendor_cfg.get("sell_rate", 1.0))))


## Sell one of an item. Returns the credits earned, or -1 when you do not own it or
## the vendor does not buy it. The vendor stocks what it bought.
func sell(id: String, item_cfg: Dictionary, vendor_cfg: Dictionary) -> int:
	var price := sell_price(item_cfg, vendor_cfg)
	if price < 0 or not has(id):
		return -1
	remove(id)
	var s := vendor_stock(vendor_cfg)
	s.append(id)
	stock[str(vendor_cfg.get("id", ""))] = s
	return price


## Buy one of an item with `credits` available. Returns the cost, or -1 when the
## vendor does not have it or you cannot afford it.
func buy(id: String, item_cfg: Dictionary, vendor_cfg: Dictionary, credits: int) -> int:
	var s := vendor_stock(vendor_cfg)
	var cost := buy_price(item_cfg, vendor_cfg)
	if not s.has(id) or cost > credits:
		return -1
	s.erase(id)
	stock[str(vendor_cfg.get("id", ""))] = s
	add(id)
	return cost


# ---- save -------------------------------------------------------------------

func to_save() -> Dictionary:
	return {
		"owned": owned.duplicate(),
		"attached": attached.duplicate(),
		"taken": taken.keys(),
		"stock": stock.duplicate(true),
	}


func from_save(d: Dictionary) -> void:
	owned = {}
	for k in (d.get("owned", {}) as Dictionary):
		var n := int(d.owned[k])
		if n > 0:
			owned[str(k)] = n
	attached = {}
	for slot in (d.get("attached", {}) as Dictionary):
		var id := str(d.attached[slot])
		if has(id):                      # never wear something you do not own
			attached[str(slot)] = id
	taken = {}
	for pid in d.get("taken", []):
		taken[str(pid)] = true
	stock = {}
	var st: Dictionary = d.get("stock", {})
	for vid in st:
		stock[str(vid)] = (st[vid] as Array).duplicate()
