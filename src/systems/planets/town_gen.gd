class_name TownGen
extends RefCounted
## A town of any size, from data (issue #45). Pure: returns the same layout
## dictionary content/core/locations/port_town.json holds (boxes, markers,
## routes, zones, garrison, locals), so TownLayout loads it, validates it rule for
## rule, and town_demo builds, dresses and populates it exactly like the port.
##
## size 1..100. 50 is the port's scale; the area inside the walls grows as
## (size / 50) ^ area_power (5x at 100). Size 1 is the smallest compound that holds
## what every town needs: a cantina with its owner, a Remnant guard at its door, a
## merchant out back, and a landing bay. Every number is in
## content/core/planets/town_kit.json.
##
## Layout, west to east along the main street (gate in the east wall, like the
## port): [back yard] [cantina] [square] [landing bays both sides of the street]
## [market south / barracks north] ... [gate]. Everything else inside the walls is
## a grid of lots, each holding one hut or tower, with lanes between them that the
## residents stroll round. Nothing overlaps by construction: every block is a
## rectangle, and a lot is only used if it keeps a lane clear of every block.
##
## Ids follow the port's, so the decor, the cantina dressing, the bar and the
## launch pad find what they look for: cantina_wall_w/n/s/e_s/e_n,
## cantina_door_lintel, cantina_roof, bar_counter; markers player_spawn, gate,
## desert_exit, cantina_door, bar_front, cantina_owner; the pad's box is "ship".

const KIT_PATH := "res://content/core/planets/town_kit.json"

var kit: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _boxes: Array = []
var _markers: Array = []
var _routes: Array = []
var _zones: Array = []
var _core: Array = []           ## Rect2s (x, z) nothing else may use (plus a lane)


func _init(kit_data: Dictionary = {}) -> void:
	kit = kit_data if not kit_data.is_empty() else _read(KIT_PATH)


## The town's layout. `opts`:
##   cantina_card / cantina_look  -- who runs its cantina (on the cantina_owner marker)
##   vendor_marker_prefix         -- merchants' marker ids (default "vendor_")
static func generate(town_id: String, size: int, seed: int = 1, opts: Dictionary = {}, kit_data: Dictionary = {}) -> Dictionary:
	var g := TownGen.new(kit_data)
	return g.build(town_id, size, seed, opts)


## How much bigger than the port, by area (1.0 at 50, 5.0 at 100).
func area_factor(size: int) -> float:
	return pow(clampf(float(size), 1.0, 100.0) / 50.0, float(kit.get("area_power", 2.3219)))


## How many of something a town of this size holds ("guards", "stalls"...).
func count(what: String, size: int) -> int:
	var c: Dictionary = kit.get("counts", {}).get(what, {})
	var n := int(round(float(c.get("per", 0)) * area_factor(size)))
	return clampi(n, int(c.get("min", 0)), int(c.get("max", 999)))


func build(town_id: String, size: int, seed: int, opts: Dictionary = {}) -> Dictionary:
	size = clampi(size, 1, 100)
	_rng.seed = seed * 7919 + size
	_boxes = []
	_markers = []
	_routes = []
	_zones = []
	_core = []
	var lane := float(kit.get("lane", 5.0))
	var margin := float(kit.get("margin", 3.0))
	var sh := float(kit.get("street_half", 6.0))
	var bay := float(kit.get("bay", 16.0))
	var wall: Dictionary = kit.get("wall", {})
	var wt := float(wall.get("thickness", 2.0))
	var guards := count("guards", size)
	var residents := count("residents", size)
	var stalls := count("stalls", size)
	var merchants := mini(count("merchants", size), stalls)
	var bays := count("bays", size)
	var ccfg: Dictionary = kit.get("cantina", {})
	var full := size >= int(ccfg.get("full_from_size", 20))
	var cdim: Dictionary = ccfg.get("full" if full else "small", {})
	var cl := float(cdim.get("length", 18.0))
	var cw := float(cdim.get("width", 14.0))
	var market := stalls >= 2                  # one stall goes out back instead
	var barracks := size >= int(kit.get("barracks_from_size", 25)) and guards >= 3
	var tower := size >= int(kit.get("tower_from_size", 35)) and guards >= 4
	var cols := int(ceil(bays / 2.0))
	var market_w := ceili(stalls / 2.0) * 8.0 if market else 0.0
	var district_need := maxf(market_w, 32.0 if barracks else 0.0) + 16.0      # + gate clearance
	var backyard := 0.0 if market else float(kit.get("backyard", 10.0))
	# Inside the walls: big enough for the area factor and for what must fit.
	var area := float(kit.get("area_at_50", 30000.0)) * area_factor(size)
	var aspect := float(kit.get("aspect", 1.333))
	var w_need := margin + backyard + cl + float(kit.get("square", 8.0)) + cols * bay + district_need + margin
	var d_need := maxf(cw + 2.0 * (lane + margin), 2.0 * (sh + 1.0 + bay) + 2.0 * margin)
	if market:
		d_need = maxf(d_need, 2.0 * (sh + 21.0) + 2.0 * margin)
	if barracks:
		d_need = maxf(d_need, 2.0 * (sh + lane + 20.0) + 2.0 * margin)
	var w := snappedf(maxf(sqrt(area * aspect), w_need), 1.0)
	var d := snappedf(maxf(sqrt(area / aspect), d_need), 2.0)
	var xi0 := -w * 0.5
	var xi1 := w * 0.5
	var zi0 := -d * 0.5
	var zi1 := d * 0.5

	_ground(town_id, xi0 - wt, xi1 + wt, zi0 - wt, zi1 + wt, wt, wall)
	var x := xi0 + margin
	# The back yard: the merchant "out back" when there is no market.
	if not market:
		_backyard(x, backyard, cw)
		x += backyard
	var cantina := _cantina(x, cl, cw, float(cdim.get("height", 5.5)), float(ccfg.get("door_half", 2.0)), opts,
		size >= int(ccfg.get("patrons_from_size", 10)))
	x = cantina.end + float(kit.get("square", 8.0))
	var sp := _spaceport(x, cols, bays, sh, bay)
	x += cols * bay
	var district_x0 := x + lane
	if market:
		_market(district_x0, stalls, merchants, sh, opts)
	else:
		_stall_out_back(cantina, cw, opts)
	var tower_rect := Rect2()
	if barracks:
		_barracks(xi1 - 16.0 - 30.0, sh + lane)
	if tower:
		tower_rect = _watchtower(xi1)
	_street(cantina.end, xi1, sh)
	_guards(guards, cantina, xi1, sh, district_x0, tower)
	_lots(xi0, xi1, zi0, zi1, sh, residents)
	var zones := _zone_list(xi0, xi1, zi0, zi1, sh)
	var klaxon := ""
	for m in _markers:
		if str(m.get("role", "")) == "trooper_post":
			klaxon = str(m.id) if klaxon == "" or str(m.id) == "trooper_tower" else klaxon
	var alarms: Dictionary = kit.get("alarms", {})
	return {
		"id": town_id,
		"kind": "port",
		"units": "meters",
		"generated": { "by": "TownGen", "size": size, "seed": seed, "area_factor": snappedf(area_factor(size), 0.0001) },
		"note": "Generated by src/systems/planets/town_gen.gd (issue #45) from content/core/planets/town_kit.json. Do not edit: change the planet's town_size or seed.",
		"bounds": { "min": [xi0 - wt, zi0 - wt], "max": [xi1 + wt, zi1 + wt] },
		"player_clearance": 0.6,
		"walk_speed_hint": 4.5,
		"blocking_kinds": ["wall", "solid", "cover", "counter", "ship"],
		"zones": zones,
		"boxes": _boxes,
		"markers": _markers,
		"routes": _routes,
		"garrison": { "alarm": alarms.get("garrison", {}), "klaxon_marker": klaxon },
		"locals": { "alarm": alarms.get("locals", {}) },
		"counts": { "guards": guards, "residents": residents, "stalls": stalls, "merchants": merchants, "bays": bays },
	}


# ------------------------------------------------------------------ blocks

func _ground(_town_id: String, x0: float, x1: float, z0: float, z1: float, wt: float, wall: Dictionary) -> void:
	var h := float(wall.get("height", 6.0))
	var gh := float(wall.get("gate_width", 12.0)) * 0.5
	var apron := float(kit.get("apron", 30.0))
	_box("ground", "ground", "floor", [x0, -0.5, z0], [x1, 0, z1])
	_box("gate_apron", "ground", "floor", [x1, -0.5, z0], [x1 + apron, 0, z1])
	_box("wall_east_s", "perimeter", "wall", [x1 - wt, 0, z0], [x1, h, -gh])
	_box("wall_east_n", "perimeter", "wall", [x1 - wt, 0, gh], [x1, h, z1])
	_box("gate_lintel", "perimeter", "overhead", [x1 - wt, h - 1.0, -gh], [x1, h, gh])
	_box("wall_west", "perimeter", "wall", [x0, 0, z0], [x0 + wt, h, z1])
	_box("wall_north", "perimeter", "wall", [x0 + wt, 0, z1 - wt], [x1 - wt, h, z1])
	_box("wall_south", "perimeter", "wall", [x0 + wt, 0, z0], [x1 - wt, h, z0 + wt])
	_marker("gate", [x1 - wt * 0.5, 0, 0], "waypoint")
	_marker("desert_exit", [x1 + 6.0, 0, 0], "waypoint")


func _cantina(x0: float, l: float, w: float, h: float, door: float, opts: Dictionary, patrons: bool) -> Dictionary:
	var x1 := x0 + l
	var z0 := -w * 0.5
	var z1 := w * 0.5
	_box("cantina_wall_w", "cantina", "wall", [x0, 0, z0], [x0 + 0.5, h, z1])
	_box("cantina_wall_n", "cantina", "wall", [x0 + 0.5, 0, z1 - 0.5], [x1 - 0.5, h, z1])
	_box("cantina_wall_s", "cantina", "wall", [x0 + 0.5, 0, z0], [x1 - 0.5, h, z0 + 0.5])
	_box("cantina_wall_e_s", "cantina", "wall", [x1 - 0.5, 0, z0], [x1, h, -door])
	_box("cantina_wall_e_n", "cantina", "wall", [x1 - 0.5, 0, door], [x1, h, z1])
	_box("cantina_door_lintel", "cantina", "overhead", [x1 - 0.5, 3.0, -door], [x1, h, door])
	_box("cantina_roof", "cantina", "roof", [x0, h, z0], [x1, h + 0.3, z1])
	var cx0 := x0 + 0.5 + maxf(4.0, l * 0.25)
	var cz0 := snappedf(-w * 0.3, 0.1)
	var cz1 := snappedf(w * 0.18, 0.1)
	_box("bar_counter", "cantina", "counter", [cx0, 0, cz0], [cx0 + 2.0, 1.1, cz1])
	var owner := { "id": "cantina_owner", "pos": [cx0 - 2.0, 0, 0], "role": "npc", "npc": "cantina_owner" }
	if opts.has("cantina_card"):
		owner["card"] = str(opts.cantina_card)
	if opts.has("cantina_look"):
		owner["look"] = str(opts.cantina_look)
	_markers.append(owner)
	_marker("bar_front", [cx0 + 3.5, 0, 0], "interact")
	_marker("cantina_door", [x1 + 1.0, 0, 0], "waypoint")
	if patrons:
		var n := 1
		for z in [cz0 + 3.2, cz1 - 1.6]:
			_markers.append({ "id": "patron_%d" % n, "pos": [cx0 + 2.75, 0, snappedf(z, 0.1)], "role": "ambient",
				"face": [cx0 - 2.0, 0, 0] })
			n += 1
	_core.append(Rect2(x0, z0, l, w))
	_zones.append({ "id": "cantina", "min": [x0, z0], "max": [x1, z1] })
	return { "x0": x0, "end": x1, "z0": z0, "z1": z1 }


func _backyard(x0: float, depth: float, cw: float) -> void:
	_core.append(Rect2(x0, -cw * 0.5, depth, cw))


## Size-1 towns (and any town with only one stall): the merchant works a stall in
## the yard behind the cantina, facing the back wall's lane.
func _stall_out_back(cantina: Dictionary, cw: float, _opts: Dictionary) -> void:
	var xb := float(cantina.x0) - float(kit.get("backyard", 10.0))
	var z := -2.0
	_box("stall_back_1_back", "backyard", "solid", [xb + 0.3, 0, z - 2.0], [xb + 0.7, 2.6, z + 2.0], { "look": "stall_back" })
	_box("stall_back_1", "backyard", "cover", [xb + 3.3, 0, z - 2.0], [xb + 4.3, 1.1, z + 2.0], { "look": "stall", "face": "+x" })
	_markers.append({ "id": "vendor_1", "pos": [xb + 2.0, 0, z], "role": "ambient", "soldier": "local_merchant",
		"face": [xb + 8.0, 0, z] })
	_zones.append({ "id": "backyard", "min": [xb, -cw * 0.5], "max": [float(cantina.x0), cw * 0.5] })


func _spaceport(x0: float, cols: int, bays: int, sh: float, cell: float) -> Dictionary:
	var sizes: Dictionary = kit.get("ship_boxes", {})
	var ships: Array = kit.get("bay_ships", ["freighter"])
	var z_n0 := sh + 1.0
	var z_s1 := -sh - 1.0
	for i in bays:
		var col := i / 2
		var north := i % 2 == 0
		var cx := x0 + col * cell + cell * 0.5
		var cz := (z_n0 + cell * 0.5) if north else (z_s1 - cell * 0.5)
		var ship_id := "" if i == 0 else str(ships[(i - 1) % ships.size()])
		var dims: Array = sizes.get("pad" if i == 0 else ship_id, [9.0, 2.5, 8.0])
		var hx := float(dims[0]) * 0.5
		var hz := float(dims[2]) * 0.5
		var extra := {}
		if i > 0:
			extra = { "ship": ship_id, "parked_yaw_deg": 90 if north else -90 }
		var id := "ship" if i == 0 else "ship_%d" % (i + 1)
		_box(id, "spaceport", "ship", [snappedf(cx - hx, 0.01), 0, snappedf(cz - hz, 0.01)],
			[snappedf(cx + hx, 0.01), float(dims[1]), snappedf(cz + hz, 0.01)], extra)
		if i == 0:
			_marker("player_spawn", [cx, 0, z_n0 + 1.5], "spawn")
	var z0 := (z_s1 - cell) if bays > 1 else z_n0
	_core.append(Rect2(x0, z_n0, cols * cell, cell))
	if bays > 1:
		_core.append(Rect2(x0, z_s1 - cell, cols * cell, cell))
	_zones.append({ "id": "spaceport", "min": [x0, z0], "max": [x0 + cols * cell, z_n0 + cell] })
	return { "x0": x0, "x1": x0 + cols * cell }


## Two rows of stalls facing an aisle south of the main street, the port's own
## stall (a counter on the aisle, a back panel, the merchant between them).
func _market(x0: float, stalls: int, merchants: int, sh: float, _opts: Dictionary) -> void:
	var za := -(sh + 10.0)
	var per_row := ceili(stalls / 2.0)
	var placed := 0
	var vendor := 0
	for row in 2:
		var north := row == 0
		for i in per_row:
			if placed >= stalls:
				break
			placed += 1
			var sx := x0 + i * 8.0
			var id := "stall_%s%d" % ["n" if north else "s", i + 1]
			if north:
				_box(id, "market", "cover", [sx, 0, za + 4.0], [sx + 4.0, 1.1, za + 5.0], { "look": "stall", "face": "-z" })
				_box(id + "_back", "market", "solid", [sx, 0, za + 8.6], [sx + 4.0, 2.6, za + 9.0], { "look": "stall_back" })
			else:
				_box(id, "market", "cover", [sx, 0, za - 5.0], [sx + 4.0, 1.1, za - 4.0], { "look": "stall", "face": "+z" })
				_box(id + "_back", "market", "solid", [sx, 0, za - 9.0], [sx + 4.0, 2.6, za - 8.6], { "look": "stall_back" })
			if vendor < merchants:
				vendor += 1
				var mz := za + 7.3 if north else za - 7.3
				_markers.append({ "id": "vendor_%d" % vendor, "pos": [sx + 2.0, 0, mz], "role": "ambient",
					"soldier": "local_merchant", "face": [sx + 2.0, 0, za] })
	var w := per_row * 8.0
	_core.append(Rect2(x0 - 1.0, za - 10.0, w + 2.0, 20.0))
	_zones.append({ "id": "market", "min": [x0 - 1.0, za - 10.0], "max": [x0 + w + 1.0, za + 10.0] })


func _barracks(x0: float, z0: float) -> void:
	_box("barracks_hall", "barracks", "solid", [x0, 0, z0 + 2.0], [x0 + 30.0, 6.0, z0 + 20.0],
		{ "look": "hall", "face": "-z", "style": "garrison" })
	_core.append(Rect2(x0, z0, 30.0, 22.0))
	_zones.append({ "id": "barracks", "min": [x0, z0], "max": [x0 + 30.0, z0 + 22.0] })


func _watchtower(xi1: float) -> Rect2:
	var r := Rect2(xi1 - 10.0, 13.0, 6.0, 6.0)
	_box("watchtower", "gatehouse", "solid", [r.position.x, 0, r.position.y], [r.end.x, 12.0, r.end.y],
		{ "look": "watchtower", "face": "-x", "style": "garrison" })
	_core.append(r)
	_zones.append({ "id": "gatehouse", "min": [r.position.x, r.position.y], "max": [r.end.x, r.end.y] })
	return r


func _street(x0: float, x1: float, sh: float) -> void:
	_zones.append({ "id": "main_street", "min": [x0, -sh], "max": [x1, sh] })


## Remnant posts, most important first: the gate pair, the cantina door, the
## tower, then along the north side of the street.
func _guards(n: int, cantina: Dictionary, xi1: float, sh: float, district_x0: float, tower: bool) -> void:
	var posts: Array = []
	var door := float(cantina.end)
	if n >= 2:
		posts.append({ "id": "trooper_gate_n", "pos": [xi1 - 3.0, 0, 9.0], "soldier": "gate_guard" })
		posts.append({ "id": "trooper_gate_s", "pos": [xi1 - 3.0, 0, -9.0], "soldier": "gate_guard" })
	posts.append({ "id": "trooper_door", "pos": [door + 1.5, 0, 3.5], "soldier": "gate_guard",
		"face": [door + 20.0, 0, 3.5] })
	if tower:
		posts.append({ "id": "trooper_tower", "pos": [xi1 - 7.0, 12.0, 16.0], "soldier": "tower_sentry" })
	var x := district_x0 + 4.0
	var k := 1
	while posts.size() < n and x < xi1 - 16.0:
		posts.append({ "id": "trooper_street_%d" % k, "pos": [snappedf(x, 0.1), 0, sh + 1.2], "soldier": "yard_trooper",
			"face": [snappedf(x, 0.1), 0, 0] })
		x += 18.0
		k += 1
	for i in mini(n, posts.size()):
		var p: Dictionary = posts[i]
		p["role"] = "trooper_post"
		_markers.append(p)


## The rest of the town: a grid of lots, each a hut (or now and then a tower),
## and the residents strolling round some of them.
func _lots(xi0: float, xi1: float, zi0: float, zi1: float, sh: float, residents: int) -> void:
	var lane := float(kit.get("lane", 5.0))
	var lot := float(kit.get("lot", 14.0))
	var pitch := lot + lane
	var inner := Rect2(xi0 + lane, zi0 + lane, (xi1 - xi0) - 2.0 * lane, (zi1 - zi0) - 2.0 * lane)
	var gate_clear := Rect2(xi1 - 16.0, -16.0, 16.0, 32.0)
	var street := Rect2(xi0, -sh, xi1 - xi0, 2.0 * sh)
	var lots: Array = []
	var z := zi0 + lane
	while z + lot <= zi1 - lane:
		var x := xi0 + lane
		while x + lot <= xi1 - lane:
			var r := Rect2(x, z, lot, lot)
			var grown := r.grow(lane - 0.01)
			var ok := inner.encloses(r) and not grown.intersects(street) and not r.grow(2.0).intersects(gate_clear)
			for c in _core:
				if grown.intersects((c as Rect2).grow(0.5)):
					ok = false
					break
			if ok:
				lots.append(r)
			x += pitch
		z += pitch
	var towers_ok := residents >= 3
	var share := float(kit.get("tower_share", 0.3))
	var n := 0
	for r in lots:
		n += 1
		var north: bool = (r as Rect2).get_center().y > 0.0
		var pool: Array = kit.get("towers", []) if towers_ok and north and _rng.randf() < share else kit.get("huts", [])
		_building("house_%s_%02d" % ["e" if north else "w", n], r, _weighted(pool), north)
	# Residents stroll round a lot each, along the lanes.
	var order := range(lots.size())
	for i in range(order.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t = order[i]
		order[i] = order[j]
		order[j] = t
	for i in mini(residents, lots.size()):
		var r: Rect2 = (lots[order[i]] as Rect2).grow(lane * 0.5)
		var id := "resident_%d" % (i + 1)
		var pts := [[r.position.x, r.position.y], [r.end.x, r.position.y], [r.end.x, r.end.y], [r.position.x, r.end.y],
			[r.position.x, r.position.y]]
		_routes.append({ "id": "stroll_" + id, "points": pts })
		_markers.append({ "id": id, "pos": [r.position.x, 0, r.position.y], "role": "ambient",
			"soldier": "local_resident", "patrol": "stroll_" + id })


func _building(id: String, lot: Rect2, look: Dictionary, north: bool) -> void:
	var wr: Array = look.get("w", [5, 7])
	var round := bool(look.get("round", false))
	var bw := float(_rng.randi_range(int(wr[0]), int(wr[1])))
	var dr: Array = look.get("d", wr)
	var bd := bw if round else float(_rng.randi_range(int(dr[0]), int(dr[1])))
	var hr: Array = look.get("h", [4.0, 5.0])
	var h := snappedf(_rng.randf_range(float(hr[0]), float(hr[1])), 0.5)
	var slack_x := (lot.size.x - bw) * 0.5 - 1.0
	var slack_z := (lot.size.y - bd) * 0.5 - 1.0
	var c := lot.get_center() + Vector2(_rng.randf_range(-slack_x, slack_x), _rng.randf_range(-slack_z, slack_z))
	c = Vector2(snappedf(c.x, 0.5), snappedf(c.y, 0.5))
	var extra := { "look": str(look.look), "face": "-z" if north else "+z" }
	if round:
		extra["shape"] = "round"
	_box(id, "residential_e" if north else "residential_w", "solid",
		[c.x - bw * 0.5, 0, c.y - bd * 0.5], [c.x + bw * 0.5, h, c.y + bd * 0.5], extra)


func _zone_list(xi0: float, xi1: float, zi0: float, zi1: float, _sh: float) -> Array:
	var out := _zones.duplicate()
	out.append({ "id": "residential_e", "min": [xi0, 0.0], "max": [xi1, zi1] })
	out.append({ "id": "residential_w", "min": [xi0, zi0], "max": [xi1, 0.0] })
	return out


# ------------------------------------------------------------------ helpers

func _box(id: String, zone: String, kind: String, mn: Array, mx: Array, extra: Dictionary = {}) -> void:
	var b := { "id": id, "zone": zone, "kind": kind, "min": mn, "max": mx }
	for k in extra:
		b[k] = extra[k]
	_boxes.append(b)


func _marker(id: String, pos: Array, role: String) -> void:
	_markers.append({ "id": id, "pos": pos, "role": role })


func _weighted(pool: Array) -> Dictionary:
	var total := 0.0
	for p in pool:
		total += float(p.get("weight", 1))
	var r := _rng.randf() * total
	for p in pool:
		r -= float(p.get("weight", 1))
		if r <= 0.0:
			return p
	return pool.back()


static func _read(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}
