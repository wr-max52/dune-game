#!/usr/bin/env python3
"""Lays out the round port (issue #237): content/core/towns/port_round.json.

    python3 tools/town/gen_port_round.py          # write the layout (and its pickup spots)
    python3 tools/town/gen_port_round.py --check  # report only, write nothing

Every number comes from the "round" block of content/core/planets/town_kit.json;
code never holds them. The square port (content/core/towns/port_square.json) is
the start: its districts are carried into the round town by the kit's `moves`
(their boxes, markers and routes keep their shape, so everything that points at
them still works), and the rest is built new:

  - a round wall (one `ring` box, src/systems/world/ring_wall.gd) with the front
    gate at 0 deg and the back gate round the back, two gate towers, each manned
  - the spaceport: a wider bowl with longer ramps, and surface pads round it
  - the ground, the main street, the ring road round the spaceport, the back lane
  - the two neighbourhoods, packed along winding lanes by gen_neighborhoods.pack:
    huts (residential_w) and towers (residential_e) wrapping round the back until
    they nearly meet behind the cantina, with only the back lane between them

A walk check (0.25 m grid, player radius, the wall in the way) proves every door
and hiding place can be reached on foot from its district's resident, and the
layout is run through docs/town/validate_town.py. Fixed seeds: the same town
every run.
"""
import copy, json, math, random, subprocess, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gen_neighborhoods as gn   # noqa: E402  (pack, walk_grid, bridges, looks)

ROOT = Path(__file__).resolve().parents[2]
SQUARE = ROOT / "content/core/towns/port_square.json"
KIT = ROOT / "content/core/planets/town_kit.json"
PICKUPS = ROOT / "content/core/pickups/port_town.json"
VALIDATE = ROOT / "docs/town/validate_town.py"

# The square port's districts that move as a block, and the routes inside them.
GROUP_ZONES = {"barracks": "barracks", "market": "market", "cantina": "cantina", "cantina_square": "cantina",
	"main_street": "gate"}
GROUP_ROUTES = {"patrol_gate_n": "gate", "patrol_gate_s": "gate", "patrol_yard_a": "barracks", "patrol_yard_b": "barracks",
	"stroll_market_1": "market", "stroll_market_2": "market", "cantina_to_lookout": "cantina"}
REBUILT_ROUTES = ("gate_to_cantina", "cantina_to_gate", "spawn_to_cantina", "backgap_to_cantina",
	"stroll_resident_w", "stroll_resident_w_2", "stroll_resident_e")
REBUILT = ("ground_", "desert_apron", "backgap_apron", "wall_", "gate_lintel", "watchtower", "house_", "bridge_", "well_")


def pol(r, deg):
	a = math.radians(deg)
	return (r * math.cos(a), r * math.sin(a))


def polar(x, z):
	return math.hypot(x, z), math.degrees(math.atan2(z, x))


def r2(v):
	return round(v * 100) / 100


def half(v):
	return round(v * 2) / 2


def in_sector(deg, sector):
	a0, a1 = sector
	return (deg - a0) % 360.0 <= (a1 - a0) % 360.0 + 1e-9


def box(id_, zone, kind, mn, mx, **extra):
	b = {"id": id_, "zone": zone, "kind": kind, "min": [r2(v) for v in mn], "max": [r2(v) for v in mx]}
	b.update(extra)
	return b


def moved(b, d):
	b = copy.deepcopy(b)
	b["min"] = [r2(b["min"][0] + d[0]), b["min"][1], r2(b["min"][2] + d[1])]
	b["max"] = [r2(b["max"][0] + d[0]), b["max"][1], r2(b["max"][2] + d[1])]
	return b


def rect_of(b):
	return (b["min"][0], b["min"][2], b["max"][0], b["max"][2])


def grow(r, m):
	return (r[0] - m, r[1] - m, r[2] + m, r[3] + m)


def bbox(rects):
	return (min(r[0] for r in rects), min(r[1] for r in rects), max(r[2] for r in rects), max(r[3] for r in rects))


def overlaps(a, b):
	return a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]


def arc(r, d0, d1, step):
	n = max(1, int(math.ceil(abs(d1 - d0) / step)))
	return [tuple(r2(v) for v in pol(r, d0 + (d1 - d0) * i / n)) for i in range(n + 1)]


def marker_group(m, sq_zones):
	mid = m["id"]
	if mid in ("trooper_tower", "back_gap") or mid.startswith("resident"):
		return "special"
	x, _, z = m["pos"]
	if x >= 86 and abs(z) <= 14:
		return "gate"
	for zid, grp in GROUP_ZONES.items():
		zr = sq_zones[zid]
		if zr["min"][0] - 3 <= x <= zr["max"][0] + 3 and zr["min"][1] - 3 <= z <= zr["max"][1] + 3:
			return grp
	return "stay"


def route_group(r, sq_zones):
	"""A route not named in GROUP_ROUTES moves with the district it lies wholly
	inside (the club's strolls in the cantina), or is rebuilt (None)."""
	if r["id"] in REBUILT_ROUTES:
		return None
	for zid, grp in GROUP_ZONES.items():
		zr = sq_zones[zid]
		if grp != "gate" and all(zr["min"][0] - 3 <= p[0] <= zr["max"][0] + 3 and zr["min"][1] - 3 <= p[1] <= zr["max"][1] + 3 for p in r["points"]):
			return grp
	return None


# ------------------------------------------------------------------ pieces

def wall_and_gates(cfg, sq_boxes, boxes, markers):
	"""The ring, the gate lintel, the two gate towers and their trooper posts."""
	R = cfg["radius"]
	wall = KIT_DATA["wall"]
	t = wall["thickness"]
	Ro = R + t
	fg, bg = cfg["front_gate"], cfg["back_gate"]
	boxes.append(box("town_wall", "perimeter", "ring", [-Ro, 0, -Ro], [Ro, wall["height"], Ro], hollow=True,
		thickness=t, piece=cfg["wall_piece"], gaps=[{"id": "front_gate", "deg": fg["deg"], "half": fg["half"]},
			{"id": "back_gate", "deg": bg["deg"], "half": bg["half"]}],
		note="Issue #237: the round town wall (src/systems/world/ring_wall.gd), open at the front gate and the back gate."))
	boxes.append(box("gate_lintel", "perimeter", "overhead", [R, wall["height"] - 1.0, -fg["half"]], [Ro, wall["height"], fg["half"]]))
	gt = cfg["gate_towers"]
	sq = {b["id"]: b for b in sq_boxes}
	look = {k: sq["watchtower"][k] for k in ("look", "face", "style") if k in sq["watchtower"]}
	post = next(m for m in SQ["markers"] if m["id"] == "trooper_tower")
	for suffix, sign in (("", 1), ("_s", -1)):
		z0, z1 = sorted((sign * (gt["z"] - gt["size"] / 2), sign * (gt["z"] + gt["size"] / 2)))
		far = max(abs(z0), abs(z1))
		x1 = math.floor((math.sqrt(R * R - far * far) - gt["inset"]) * 2) / 2
		boxes.append(box("watchtower" + suffix, "perimeter", "solid", [x1 - gt["size"], 0, z0], [x1, gt["height"], z1], **look))
		m = copy.deepcopy(post)
		m["id"] = "trooper_tower" + suffix
		m["pos"] = [r2(x1 - gt["size"] / 2), gt["height"], r2((z0 + z1) / 2)]
		markers.append(m)
	bp = pol(R + t / 2, bg["deg"])
	markers.append({"id": "back_gap", "pos": [r2(bp[0]), 0, r2(bp[1])], "role": "waypoint"})


def ground(cfg, boxes, pit_r):
	"""Floor slabs in strips under the whole round town, open over the bowl, and
	aprons outside both gates (the desert exit, the dunes past the back gate)."""
	Ro = cfg["radius"] + KIT_DATA["wall"]["thickness"]
	step = cfg["ground_strip"]
	edges = [-pit_r, -pit_r / 2, 0.0, pit_r / 2, pit_r]
	z = pit_r
	# Thinner strips toward the wall, so none sticks out past it by more than `overhang`.
	while z < Ro:
		dz = step
		while dz > 0.5 and math.sqrt(max(0.0, Ro * Ro - z * z)) - math.sqrt(max(0.0, Ro * Ro - min(Ro, z + dz) ** 2)) > cfg["ground_overhang"]:
			dz /= 2
		z = min(Ro, half(z + dz) if half(z + dz) > z else z + dz)
		edges.append(z)
		edges.insert(0, -z)
	k = 0
	for z0, z1 in zip(edges, edges[1:]):
		zn = 0.0 if z0 < 0 < z1 else min(abs(z0), abs(z1))
		X = math.ceil(math.sqrt(max(0.0, Ro * Ro - zn * zn)) * 2) / 2
		spans = [(-X, -pit_r), (pit_r, X)] if -pit_r <= z0 and z1 <= pit_r else [(-X, X)]
		for x0, x1 in spans:
			k += 1
			boxes.append(box("ground_%02d" % k, "ground", "floor", [x0, -0.5, z0], [x1, 0, z1]))
	fa = cfg["front_apron"]
	boxes.append(box("desert_apron", "ground", "floor", [Ro, -0.5, -fa["half"]], [Ro + fa["length"], 0, fa["half"]]))
	ba = cfg["back_apron"]
	bx, bz = pol(Ro, cfg["back_gate"]["deg"])
	z0, z1 = half(bz - ba["half"]), half(bz + ba["half"])
	inner = max(-b["min"][0] for b in boxes if b["zone"] == "ground" and b["min"][2] < z1 and z0 < b["max"][2] and b["min"][0] < 0)
	boxes.append(box("backgap_apron", "ground", "floor", [-(inner + ba["length"]), -0.5, z0], [-inner, 0, z1]))


def spaceport(cfg, sq_boxes, boxes):
	pk = cfg["pit"]
	r = pk["radius"]
	for b in sq_boxes:
		if b["zone"] != "spaceport":
			continue
		b = copy.deepcopy(b)
		if b["id"] == "pit_floor":
			b["min"] = [-r, b["min"][1], -r]
			b["max"] = [r, b["max"][1], r]
		elif b["id"] == "pit_bowl":
			b["min"] = [-r, b["min"][1], -r]
			b["max"] = [r, b["max"][1], r]
		elif b["id"] == "ramp_ne":
			b["min"][0] = pk["ramp_from"]
			b["max"][0] = r
		elif b["id"] == "ramp_sw":
			b["min"][0] = -r
			b["max"][0] = -pk["ramp_from"]
		elif b["id"] == "dock_booth":
			db = cfg["dock_booth"]
			(x, z), (w, h, d) = db["at"], db["size"]
			b["min"] = [x - w / 2, 0, z - d / 2]
			b["max"] = [x + w / 2, h, z + d / 2]
		boxes.append(b)
	pads = cfg["pads"]
	for k in range(pads["count"]):
		a = pads["first_deg"] + k * 360.0 / pads["count"]
		x, z = pol(pads["ring"], a)
		h = pads["diameter"] / 2
		boxes.append(box("surface_pad_%d" % (k + 1), "spaceport", "pad", [x - h, 0, z - h], [x + h, 0.03, z + h],
			shape="round", parked_yaw_deg=round((a + 180.0) % 360.0 - 180.0, 1),
			note="Issue #237: a surface pad on the ring round the bowl. No collision: you walk across it."))


def lanes_for(dcfg, rng):
	out = []
	for a in dcfg["arcs"]:
		d0, d1 = a["deg"]
		n = max(3, int(abs(d1 - d0) / 6))
		pts = [pol(a["r"] + rng.uniform(-dcfg["wobble"], dcfg["wobble"]), d0 + (d1 - d0) * i / n) for i in range(n + 1)]
		out.append(([tuple(r2(v) for v in p) for p in pts], a["width"]))
	for s in dcfg["spokes"]:
		r0, r1 = s["r"]
		pts = [pol(r0 + (r1 - r0) * i / 4, s["deg"] + (rng.uniform(-3, 3) if 0 < i < 4 else 0)) for i in range(5)]
		out.append(([tuple(r2(v) for v in p) for p in pts], s["width"]))
	return out


def district_zone(dcfg):
	pts = []
	a0, a1 = dcfg["sector"]
	r0, r1 = dcfg["radii"]
	span = (a1 - a0) % 360.0
	for i in range(41):
		a = a0 + span * i / 40
		r_in = dcfg["curl"]["inner"] if in_sector(a, dcfg["curl"]["sector"]) else r0
		pts += [pol(r_in, a), pol(r1, a)]
	return (math.floor(min(p[0] for p in pts)), math.floor(min(p[1] for p in pts)),
		math.ceil(max(p[0] for p in pts)), math.ceil(max(p[1] for p in pts)))


def district_inside(dcfg, keep_out):
	r0, r1 = dcfg["radii"]

	def ok(r):
		for x, z in ((r[0], r[1]), (r[2], r[1]), (r[0], r[3]), (r[2], r[3]), ((r[0] + r[2]) / 2, (r[1] + r[3]) / 2)):
			rr, aa = polar(x, z)
			if rr > r1 or rr < r0:
				return False
			if in_sector(aa, dcfg["curl"]["sector"]):
				if rr < dcfg["curl"]["inner"]:
					return False
			elif not in_sector(aa, dcfg["sector"]):
				return False
		return not any(overlaps(r, k) for k in keep_out)
	return ok


def nearest_on(lanes, target):
	best = None
	for pts, _ in lanes:
		for i, p in enumerate(pts):
			d = math.dist(p, target)
			if best is None or d < best[0]:
				best = (d, pts, i)
	return best[1], best[2]


def wall_blockers(cfg):
	"""The ring as little squares, for the walk grid (it only knows rects)."""
	R = cfg["radius"]
	t = KIT_DATA["wall"]["thickness"]
	out = []
	n = int(2 * math.pi * R)
	for i in range(n):
		a = 360.0 * i / n
		if any(abs((a - g["deg"] + 180) % 360 - 180) < math.degrees(g["half"] / (R + t / 2)) for g in (cfg["front_gate"], cfg["back_gate"])):
			continue
		x, z = pol(R + t / 2, a)
		out.append((x - t / 2, z - t / 2, x + t / 2, z + t / 2))
	return out


# ------------------------------------------------------------------ main

def main():
	global SQ, KIT_DATA
	check = "--check" in sys.argv
	SQ = json.loads(SQUARE.read_text())
	KIT_DATA = json.loads(KIT.read_text())
	cfg = KIT_DATA["round"]
	pickups = json.loads(PICKUPS.read_text())
	R = cfg["radius"]
	Ro = R + KIT_DATA["wall"]["thickness"]
	moves = cfg["moves"]
	sq_zones = {z["id"]: z for z in SQ["zones"]}

	boxes, markers, routes, zones = [], [], [], []
	wall_and_gates(cfg, SQ["boxes"], boxes, markers)
	ground(cfg, boxes, cfg["pit"]["radius"])
	spaceport(cfg, SQ["boxes"], boxes)

	# ---- the districts that move as a block
	for b in SQ["boxes"]:
		grp = GROUP_ZONES.get(b["zone"])
		if grp is None or str(b["id"]).startswith(REBUILT):
			continue
		boxes.append(moved(b, moves[grp]))
	for m in SQ["markers"]:
		grp = marker_group(m, sq_zones)
		if grp == "special":
			continue
		m = copy.deepcopy(m)
		if grp in moves:
			d = moves[grp]
			m["pos"] = [r2(m["pos"][0] + d[0]), m["pos"][1], r2(m["pos"][2] + d[1])]
			if isinstance(m.get("face"), list) and len(m["face"]) == 3:      # a point it looks at (issue #261's club)
				m["face"] = [r2(m["face"][0] + d[0]), m["face"][1], r2(m["face"][2] + d[1])]
		markers.append(m)
	for r in SQ["routes"]:
		grp = GROUP_ROUTES.get(r["id"]) or route_group(r, sq_zones)
		if grp:
			d = moves[grp]
			routes.append({"id": r["id"], "points": [[r2(p[0] + d[0]), r2(p[1] + d[1])] for p in r["points"]]})
	for zid, grp in GROUP_ZONES.items():
		if zid == "main_street":
			continue
		z = sq_zones[zid]
		d = moves[grp]
		zones.append({"id": zid, "min": [z["min"][0] + d[0], z["min"][1] + d[1]], "max": [z["max"][0] + d[0], z["max"][1] + d[1]]})
	ms = cfg["main_street"]
	zones.append({"id": "main_street", "min": [ms["from"], -ms["half"]], "max": [Ro, ms["half"]]})
	pz = cfg["pads"]["ring"] + cfg["pads"]["diameter"] / 2 + 3
	db = cfg["dock_booth"]
	pz = math.ceil(max(pz, abs(db["at"][0]) + db["size"][0], abs(db["at"][1]) + db["size"][2]))
	zones.append({"id": "spaceport", "min": [-pz, -pz], "max": [pz, pz]})

	# ---- streets: the routes the story walks
	mk = {m["id"]: m for m in markers}
	rr = cfg["ring_road"]
	gate_in = [[mk["desert_exit"]["pos"][0], 0], [mk["gate"]["pos"][0], 0]] + [list(p) for p in ms["bends"]] + [[ms["from"] + 1, 0]]
	around = [list(p) for p in arc(rr["radius"], 0, 180, rr["step_deg"])]
	sq_route = {r["id"]: r["points"] for r in SQ["routes"]}
	dc = moves["cantina"]
	tail = [[r2(p[0] + dc[0]), r2(p[1] + dc[1])] for p in sq_route["gate_to_cantina"][6:]]   # into the cantina, to the bar
	routes.append({"id": "gate_to_cantina", "points": gate_in + around + tail})
	routes.append({"id": "cantina_to_gate", "points": list(reversed(gate_in + around + tail))})
	sp = mk["player_spawn"]["pos"]
	routes.append({"id": "spawn_to_cantina", "points": [[sp[0], sp[2]], [sp[0], 0], [-cfg["pit"]["radius"] - 1, 0]] + tail})
	bl = cfg["back_lane"]
	lane_pts = [pol(r, a) for r, a in bl["points_deg"]] + [pol(R + 1, cfg["back_gate"]["deg"])]
	bg_out = pol(Ro + 4, cfg["back_gate"]["deg"])
	door = tail[0]
	sq_w = sq_zones["cantina_square"]
	sx = sq_w["min"][0] + dc[0] + 3                     # down the square's back edge, clear of the cantina
	bz = sq_w["min"][1] - 4
	routes.append({"id": "backgap_to_cantina", "points": [[r2(bg_out[0]), r2(bg_out[1])]]
		+ [[r2(p[0]), r2(p[1])] for p in list(reversed(lane_pts))[:-1]] + [[sx - 6, bz], [sx, bz + 6], [sx, 0]] + tail})
	patrol = gate_in[1:] + [list(p) for p in arc(rr["radius"], 0, 120, rr["step_deg"])]
	routes.append({"id": "street_patrol", "points": patrol + list(reversed(patrol))[1:]})

	# ---- the neighbourhoods
	keep = [grow(bbox([rect_of(b) for b in boxes if b["zone"] in (z,)]), 3.0) for z in ("cantina", "cantina_square", "market", "barracks")]
	keep.append(grow(bbox([rect_of(b) for b in boxes if b["id"].startswith("watchtower")]), 3.0))
	back_lane = ([tuple(r2(v) for v in p) for p in lane_pts], bl["width"])
	results = {}
	for zid, kit, weights, seed in (("residential_w", gn.HUTS, gn.HUT_WEIGHTS, 2371), ("residential_e", gn.TOWERS, gn.TOWER_WEIGHTS, 2372)):
		dcfg = cfg[zid]
		rng = random.Random(seed)
		lanes = lanes_for(dcfg, rng) + [back_lane]
		zr = district_zone(dcfg)
		zones.append({"id": zid, "min": [zr[0], zr[1]], "max": [zr[2], zr[3]]})
		res = {}
		for mid, (r, a) in dcfg["residents"].items():
			pts, i = nearest_on(lanes[:-1], pol(r, a))
			res[mid] = (pts, i)
		wr, wa = dcfg["well"]
		well = pol(wr, wa)
		reserved = [(well[0], well[1], 3.6)] + [(pts[i][0], pts[i][1], 1.8) for pts, i in res.values()]
		placed = gn.pack(rng, ((zr[0], zr[1]), (zr[2], zr[3])), lanes, kit, weights, gap=dcfg["gap"], reach=dcfg["reach"],
			reserved=reserved, attempts=dcfg["attempts"], keep_out={}, inside=district_inside(dcfg, keep))
		results[zid] = {"placed": placed, "lanes": lanes, "res": res, "well": well, "zone": zr}
	other = [b for b in boxes]

	def build_res():
		out = []
		huts = sorted(results["residential_w"]["placed"], key=lambda h: (h["rect"][1], h["rect"][0]))
		towers = sorted(results["residential_e"]["placed"], key=lambda h: (h["rect"][1], h["rect"][0]))
		for zid, items, tag in (("residential_w", huts, "w"), ("residential_e", towers, "e")):
			for i, h in enumerate(items):
				extra = {"look": h["look"], "face": h["face"]}
				if h["look"] in gn.ROUND:
					extra["shape"] = "round"
				out.append(box("house_%s_%02d" % (tag, i + 1), zid, "solid", [h["rect"][0], 0, h["rect"][1]], [h["rect"][2], h["h"], h["rect"][3]], **extra))
			wx, wz = results[zid]["well"]
			out.append(box("well_" + tag, zid, "cover", [half(wx) - 1, 0, half(wz) - 1], [half(wx) + 1, 1.0, half(wz) + 1], look="cistern", shape="round"))
		for i, s in enumerate(gn.bridges(towers, random.Random(7))):
			r = s["rect"]
			out.append(box("bridge_e_%02d" % (i + 1), "residential_e", "overhead", [r[0], s["top"] - 0.6, r[1]], [r[2], s["top"], r[3]],
				look="bridge", axis=s["axis"]))
		return out

	walls = wall_blockers(cfg)

	def blockers(all_boxes):
		return [rect_of(b) for b in all_boxes if b["kind"] in SQ["blocking_kinds"] and b["min"][1] < 1.8] + walls

	errors = []
	oks = {}
	for _ in range(10):
		all_boxes = other + build_res()
		gone = 0
		for zid, res in results.items():
			start_pts, start_i = next(iter(res["res"].values()))
			zr = grow(res["zone"], 6.0)
			_, ok = gn.walk_grid(((zr[0], zr[1]), (zr[2], zr[3])), blockers(all_boxes), start_pts[start_i])
			oks[zid] = ok
			keep_p = [h for h in res["placed"] if ok(*h["step"])]
			gone += len(res["placed"]) - len(keep_p)
			res["placed"] = keep_p
		if not gone:
			break
		print("dropped %d building(s) with no way to their door" % gone)
	all_boxes = other + build_res()
	for zid, res in results.items():
		for mid, (pts, i) in res["res"].items():
			if not oks[zid](*pts[i]):
				errors.append("%s cannot walk to %s's start" % (mid, zid))

	# ---- residents, their strolls, hiding places
	for zid, res in results.items():
		for mid, (pts, i) in res["res"].items():
			src = next(m for m in SQ["markers"] if m["id"] == mid)
			m = copy.deepcopy(src)
			m["pos"] = [pts[i][0], 0, pts[i][1]]
			markers.append(m)
			walk = [list(p) for p in (pts[i:i + 4] if i + 3 < len(pts) else list(reversed(pts[max(0, i - 3):i + 1])))]
			routes.append({"id": "stroll_" + mid, "points": walk + list(reversed(walk))[1:]})

	def tucked(x, z, rects, ok, lanes, need):
		if not ok(x, z) or gn.lane_dist((x, z), lanes) < 1.0:
			return False
		return sum(1 for r in rects if gn.rect_dist(x, z, r) < 1.6) >= need
	rng = random.Random(2373)
	alley = []
	for zid, want, need in (("residential_w", 3, 2), ("residential_e", 2, 1)):
		res = results[zid]
		rects = [h["rect"] for h in res["placed"]]
		cands = []
		for r in rects:
			for p in ((r[0] - 0.7, (r[1] + r[3]) / 2), (r[2] + 0.7, (r[1] + r[3]) / 2), ((r[0] + r[2]) / 2, r[1] - 0.7), ((r[0] + r[2]) / 2, r[3] + 0.7)):
				p = (round(p[0] * 4) / 4, round(p[1] * 4) / 4)
				if tucked(p[0], p[1], rects, oks[zid], res["lanes"], need):
					cands.append(p)
		rng.shuffle(cands)
		picked = []
		for p in cands:
			if all(math.dist(p, q) > 25 for q in picked):
				picked.append(p)
			if len(picked) == want:
				break
		alley += picked
	roofs = [h for h in results["residential_w"]["placed"] if h["look"] in ("hut_block", "hut_long") and h["h"] <= 4.0]
	rng.shuffle(roofs)
	roof_pts = []
	for h in roofs:
		c = ((h["rect"][0] + h["rect"][2]) / 2, (h["rect"][1] + h["rect"][3]) / 2)
		if all(math.dist(c, (q[0], q[2])) > 20 for q in roof_pts):
			roof_pts.append((c[0], h["h"], c[1]))
		if len(roof_pts) == 4:
			break
	res_w = next(m for m in markers if m["id"] == "resident_w")["pos"]

	def rel(p3):
		return [r2(p3[0] - res_w[0]), r2(p3[1] - res_w[1]), r2(p3[2] - res_w[2])]
	layout = cfg["layout"]
	for a in pickups["drops"]["areas"]:
		if a["id"] == "alleys":
			a.setdefault("layouts", {})[layout] = {"marker": "resident_w", "spots": [rel((x, 0.0, z)) for x, z in alley]}
		if a["id"] == "rooftops":
			a.setdefault("layouts", {})[layout] = {"marker": "resident_w", "spots": [rel(p) for p in roof_pts]}
	for p in pickups["pickups"]:
		if p["id"] == "pit_jetpack":
			# The pit hauler's first stop (droids.json pit_hauler), on the wider bowl's floor.
			p.setdefault("layouts", {})[layout] = {"offset": [0.0, 0.0, -13.0]}
	if len(alley) < 3 or len(roof_pts) < 3:
		errors.append("too few hiding places: %d alleys, %d roofs" % (len(alley), len(roof_pts)))

	order = {m["id"]: i for i, m in enumerate(SQ["markers"])}
	markers.sort(key=lambda m: (order.get(m["id"], 999), m["id"]))
	rorder = {r["id"]: i for i, r in enumerate(SQ["routes"])}
	routes.sort(key=lambda r: (rorder.get(r["id"], 999), r["id"]))
	zorder = [z["id"] for z in SQ["zones"]]
	zones.sort(key=lambda z: zorder.index(z["id"]) if z["id"] in zorder else 99)
	town = {
		"id": layout,
		"size": cfg["size"],
		"kind": SQ["kind"],
		"units": SQ["units"],
		"note": "Issue #237: the round port. Generated by tools/town/gen_port_round.py from the round block of content/core/planets/town_kit.json and the districts of port_square.json: do not edit by hand, change the kit and run the tool. +X is the front gate side.",
		"bounds": {"min": [-Ro, -Ro], "max": [Ro, Ro]},
		"player_clearance": SQ["player_clearance"],
		"walk_speed_hint": SQ["walk_speed_hint"],
		"blocking_kinds": SQ["blocking_kinds"],
		"zones": zones,
		"boxes": all_boxes,
		"markers": markers,
		"routes": routes,
		"chunks": [dict(c, load_ms=18.0, kind="port") for c in cfg["chunks"]],
	}
	for k, v in SQ.items():          # the rest as the square port has it (garrison, locals, club...)
		town.setdefault(k, copy.deepcopy(v))
	missing = sorted(set(m["id"] for m in SQ["markers"]) - set(m["id"] for m in markers))
	missing += sorted(set(r["id"] for r in SQ["routes"]) - set(r["id"] for r in routes))
	if missing:
		errors.append("missing from the round port: " + ", ".join(missing))

	print("huts: %d  towers: %d  alley spots: %d  roof spots: %d" % (len(results["residential_w"]["placed"]),
		len(results["residential_e"]["placed"]), len(alley), len(roof_pts)))
	print("boxes: %d  markers: %d  routes: %d" % (len(all_boxes), len(markers), len(routes)))
	inside = math.pi * R * R
	print("inside the wall: %.0f m2 (square port: %.0f m2)" % (inside, 196 * 146))
	out = ROOT / "content/core/towns" / (layout + ".json")
	tmp = ROOT / "test_results" / (layout + ".check.json")
	tmp.parent.mkdir(exist_ok=True)
	tmp.write_text(json.dumps(town, indent=1, ensure_ascii=False) + "\n")
	v = subprocess.run([sys.executable, str(VALIDATE), str(tmp)], capture_output=True, text=True)
	print(v.stdout.strip().splitlines()[-1] if v.stdout.strip() else v.stderr)
	if "OK, 0 errors" not in v.stdout:
		errors += [l.strip() for l in v.stdout.splitlines() if l.startswith("  ")][:40]
	for e in errors:
		print("ERROR:", e)
	if errors:
		sys.exit(1)
	if not check:
		out.write_text(tmp.read_text())
		PICKUPS.write_text(gn.inline_numbers(json.dumps(pickups, indent=2, ensure_ascii=False)) + "\n")
		print("wrote", out.relative_to(ROOT), "and", PICKUPS.relative_to(ROOT))


if __name__ == "__main__":
	main()
