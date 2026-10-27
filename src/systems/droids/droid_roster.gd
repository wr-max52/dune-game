class_name DroidRoster
extends RefCounted
## Companion droids (issue #51). Pure and headless-testable: which droids the
## player runs (up to max_owned), what each cargo droid carries, which broken
## droids are lying out in the desert, and the range remote's taming streak.
##
## It never touches nodes. Money comes back as numbers; the caller (DroidController)
## moves the credits in WorldState. Kinds, variants and prices come from
## content/core/droids/droids.json.
##
## Lives in WorldState.droids, so it survives town -> flight -> town and is saved
## with the rest of the world. A droid's cargo is NOT in WorldState.inventory:
## that is the point. The gate searches the inventory, never the droid.

const DATA := "res://content/core/droids/droids.json"

static var _cfg: Dictionary = {}

var owned: Array = []       ## [{ uid, kind, variant, cargo: { item id -> count } }]
var wrecks: Array = []      ## [{ uid, kind, variant, pos: [x, y, z] }]
var streak := 0             ## range remote bolts blocked in a row
var next_uid := 1


static func config() -> Dictionary:
	if _cfg.is_empty():
		var f := FileAccess.open(DATA, FileAccess.READ)
		if f != null:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_cfg = d
	return _cfg


static func kind_cfg(kind: String) -> Dictionary:
	return (config().get("kinds", {}) as Dictionary).get(kind, {})


static func variant_cfg(kind: String, variant: String) -> Dictionary:
	var vs: Dictionary = kind_cfg(kind).get("variants", {})
	if vs.has(variant):
		return vs[variant]
	return vs.values()[0] if not vs.is_empty() else {}


static func label(kind: String) -> String:
	return str(kind_cfg(kind).get("label", kind))


static func price(kind: String) -> int:
	return int(kind_cfg(kind).get("price", 0))


static func resale(kind: String) -> int:
	return int(kind_cfg(kind).get("resale", 0))


static func max_owned() -> int:
	return int(config().get("max_owned", 3))


## A random look for a droid the player gets (never the Remnant's colours).
static func pick_variant(kind: String, rng: RandomNumberGenerator) -> String:
	var vs: Array = (config().get("player_variants", {}) as Dictionary).get(kind, [])
	if vs.is_empty():
		vs = (kind_cfg(kind).get("variants", {}) as Dictionary).keys()
	return str(vs[rng.randi() % vs.size()]) if not vs.is_empty() else ""


# ---- owning -------------------------------------------------------------------

func is_full() -> bool:
	return owned.size() >= max_owned()


func find(uid: int) -> Dictionary:
	for d in owned:
		if int(d.uid) == uid:
			return d
	return {}


## Take on a droid. Returns its entry, or {} when the roster is full or the kind
## is unknown.
func add(kind: String, variant: String) -> Dictionary:
	if is_full() or kind_cfg(kind).is_empty():
		return {}
	var d := { "uid": next_uid, "kind": kind, "variant": variant, "cargo": {} }
	next_uid += 1
	owned.append(d)
	return d


## Let a droid go. Its cargo goes with it. Returns false if it was not ours.
func remove(uid: int) -> bool:
	var d := find(uid)
	if d.is_empty():
		return false
	owned.erase(d)
	return true


# ---- trade ----------------------------------------------------------------------

## Buy a droid of `kind` with `credits` available. Returns { cost, droid }, or
## { error: "full" | "cant_afford" | "unknown" }.
func buy(kind: String, variant: String, credits: int) -> Dictionary:
	if kind_cfg(kind).is_empty():
		return { "error": "unknown" }
	if is_full():
		return { "error": "full" }
	if price(kind) > credits:
		return { "error": "cant_afford" }
	return { "cost": price(kind), "droid": add(kind, variant) }


## Sell a droid back to the merchant. Returns the credits paid, or -1.
func sell(uid: int) -> int:
	var d := find(uid)
	if d.is_empty():
		return -1
	remove(uid)
	return resale(str(d.kind))


# ---- cargo ----------------------------------------------------------------------

## Move n of an item from the player's pockets into a cargo droid. Worn gear comes
## off first. Returns false if the droid cannot carry or the pockets are short.
func stash(uid: int, inv: Inventory, item_id: String, n: int = 1) -> bool:
	var d := find(uid)
	if d.is_empty() or not bool(kind_cfg(str(d.kind)).get("carries", false)):
		return false
	if not inv.remove(item_id, n):
		return false
	d.cargo[item_id] = int(d.cargo.get(item_id, 0)) + n
	return true


## Everything in a cargo droid back into the pockets. Returns how many items moved.
func unload(uid: int, inv: Inventory) -> int:
	var d := find(uid)
	if d.is_empty():
		return 0
	var moved := 0
	for id in d.cargo:
		inv.add(str(id), int(d.cargo[id]))
		moved += int(d.cargo[id])
	d.cargo = {}
	return moved


## Every item every droid is carrying: item id -> count.
func all_cargo() -> Dictionary:
	var out := {}
	for d in owned:
		for id in d.cargo:
			out[id] = int(out.get(id, 0)) + int(d.cargo[id])
	return out


# ---- taming ---------------------------------------------------------------------

## A range remote bolt was blocked or deflected. Returns true when that makes the
## streak (taming.streak in a row).
func on_remote_blocked() -> bool:
	streak += 1
	return streak >= int(config().get("taming", {}).get("streak", 5))


func on_remote_hit_player() -> void:
	streak = 0


# ---- wrecks ---------------------------------------------------------------------

func has_wreck_of(kind: String) -> bool:
	for w in wrecks:
		if str(w.kind) == kind:
			return true
	return false


func find_wreck(uid: int) -> Dictionary:
	for w in wrecks:
		if int(w.uid) == uid:
			return w
	return {}


## Maybe strand one more broken droid in the desert: a kind not already out there,
## at a spot in the ring around `center`, far from the other wrecks. `ground` maps
## (x, z) to the sand height (invalid = flat at center.y). Returns the wreck or {}.
func roll_wreck(rng: RandomNumberGenerator, center: Vector3, ground: Callable = Callable(), force := false) -> Dictionary:
	var wc: Dictionary = config().get("wrecks", {})
	if wrecks.size() >= int(wc.get("max_out", 3)):
		return {}
	if not force and rng.randf() >= float(wc.get("chance", 0.4)):
		return {}
	var kinds: Array = []
	for k in (config().get("kinds", {}) as Dictionary):
		if not has_wreck_of(str(k)):
			kinds.append(str(k))
	if kinds.is_empty():
		return {}
	var kind: String = kinds[rng.randi() % kinds.size()]
	var sep := float(wc.get("min_separation", 180.0))
	for _try in 24:
		var a := rng.randf() * TAU
		var r := rng.randf_range(float(wc.get("min_radius", 160.0)), float(wc.get("max_radius", 520.0)))
		var p := center + Vector3(cos(a) * r, 0.0, sin(a) * r)
		var clear := true
		for w in wrecks:
			if Vector2(p.x - float(w.pos[0]), p.z - float(w.pos[2])).length() < sep:
				clear = false
				break
		if not clear:
			continue
		if ground.is_valid():
			p.y = float(ground.call(p.x, p.z))
		var w := { "uid": next_uid, "kind": kind, "variant": pick_variant(kind, rng), "pos": [p.x, p.y, p.z] }
		next_uid += 1
		wrecks.append(w)
		return w
	return {}


## A fixed wreck resets and joins the roster. Returns the new droid, or {} when
## the roster is full (the wreck stays where it is).
func fix_wreck(uid: int) -> Dictionary:
	var w := find_wreck(uid)
	if w.is_empty() or is_full():
		return {}
	wrecks.erase(w)
	return add(str(w.kind), str(w.variant))


# ---- save -----------------------------------------------------------------------

func to_save() -> Dictionary:
	return { "owned": owned.duplicate(true), "wrecks": wrecks.duplicate(true), "streak": streak, "next_uid": next_uid }


func from_save(d: Dictionary) -> void:
	owned = []
	for o in d.get("owned", []):
		if not kind_cfg(str(o.get("kind", ""))).is_empty() and owned.size() < max_owned():
			owned.append({ "uid": int(o.uid), "kind": str(o.kind), "variant": str(o.get("variant", "")),
				"cargo": (o.get("cargo", {}) as Dictionary).duplicate() })
	wrecks = []
	for w in d.get("wrecks", []):
		wrecks.append({ "uid": int(w.uid), "kind": str(w.kind), "variant": str(w.get("variant", "")),
			"pos": (w.get("pos", [0, 0, 0]) as Array).duplicate() })
	streak = int(d.get("streak", 0))
	next_uid = int(d.get("next_uid", 1))
	for o in owned + wrecks:
		next_uid = maxi(next_uid, int(o.uid) + 1)
