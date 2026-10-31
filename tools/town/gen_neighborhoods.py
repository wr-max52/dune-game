#!/usr/bin/env python3
"""Lays out port_town's two residential districts and the barracks blocks.

    python3 tools/town/gen_neighborhoods.py          # rewrite the data in place
    python3 tools/town/gen_neighborhoods.py --check  # report only, write nothing

Writes boxes into content/core/towns/port_square.json and the alley / rooftop
hiding places into content/core/pickups/port_town.json. Fixed seed: the same town
every run. Code never holds these numbers; this tool is how they were made.

  residential_w (beside the market): small huts packed close along crooked lanes.
  residential_e (beside the barracks): tall towers with bridges between roofs.

Every building is one of a few looks (`look`, read by town_buildings.gd) with a
door side (`face`). A building only goes where its door has a lane to open on to.
A walk check (0.25 m grid, player radius) proves every door and hiding place can
be reached on foot from the district's resident marker.
"""
import json, math, random, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOWN = ROOT / "content/core/towns/port_square.json"
PICKUPS = ROOT / "content/core/pickups/port_town.json"

GENERATED = ("house_", "bridge_", "well_", "barracks_bunk", "barracks_upper", "barracks_bridge")

# look id -> footprint (w along x, d along z) before turning, and the heights it comes in.
HUTS = {
	"hut_round":   [((5, 5), (3.5, 4.0, 4.5)), ((6, 6), (4.5, 5.0))],
	"hut_block":   [((5, 4), (3.5, 4.0, 5.0)), ((6, 5), (3.5, 4.5))],
	"hut_stepped": [((7, 5), (4.0, 4.5))],
	"hut_long":    [((8, 4), (3.5, 4.0))],
}
HUT_WEIGHTS = {"hut_round": 4, "hut_block": 4, "hut_stepped": 3, "hut_long": 2}
TOWERS = {
	"tower_block": [((8, 8), (12.0, 15.0, 18.0)), ((7, 6), (10.0, 14.0))],
	"tower_round": [((8, 8), (13.0, 17.0, 20.0))],
	"tower_wide":  [((10, 7), (10.0, 12.0))],
}
TOWER_WEIGHTS = {"tower_block": 3, "tower_round": 4, "tower_wide": 2}
ROUND = ("hut_round", "tower_round")


def seg_dist(p, a, b):
	ax, az = a; bx, bz = b; px, pz = p
	dx, dz = bx - ax, bz - az
	L = dx * dx + dz * dz
	t = 0.0 if L == 0 else max(0.0, min(1.0, ((px - ax) * dx + (pz - az) * dz) / L))
	return math.hypot(px - ax - t * dx, pz - az - t * dz)


def lane_dist(p, lanes):
	"""Distance from p to the nearest lane edge (negative = on the lane)."""
	best = 1e9
	for pts, width in lanes:
		for a, b in zip(pts, pts[1:]):
			best = min(best, seg_dist(p, a, b) - width * 0.5)
	return best


def rect_dist(x, z, r):
	"""2D distance from (x, z) to rect r = (x0, z0, x1, z1); 0 inside."""
	dx = max(r[0] - x, 0, x - r[2])
	dz = max(r[1] - z, 0, z - r[3])
	return math.hypot(dx, dz)


def rect_gap(a, b):
	dx = max(a[0] - b[2], b[0] - a[2], 0)
	dz = max(a[1] - b[3], b[1] - a[3], 0)
	return math.hypot(dx, dz)


def rect_lane_clear(r, lanes, margin):
	"""True if no lane comes within `margin` of the rect (sampled on its outline)."""
	x0, z0, x1, z1 = r
	n = 8
	for i in range(n + 1):
		t = i / n
		for p in ((x0 + (x1 - x0) * t, z0), (x0 + (x1 - x0) * t, z1), (x0, z0 + (z1 - z0) * t), (x1, z0 + (z1 - z0) * t)):
			if lane_dist(p, lanes) < margin:
				return False
	# A lane can also pass straight through the middle.
	for pts, width in lanes:
		for a, b in zip(pts, pts[1:]):
			for k in range(11):
				t = k / 10
				q = (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
				if rect_dist(q[0], q[1], r) < width * 0.5 + margin:
					return False
	return True


def door_side(r, lanes):
	"""The face whose door step is nearest a lane, and that distance."""
	cx, cz = (r[0] + r[2]) / 2, (r[1] + r[3]) / 2
	steps = {"+x": (r[2] + 1.0, cz), "-x": (r[0] - 1.0, cz), "+z": (cx, r[3] + 1.0), "-z": (cx, r[1] - 1.0)}
	best = min(steps, key=lambda k: lane_dist(steps[k], lanes))
	return best, lane_dist(steps[best], lanes), steps[best]


def pack(rng, zone, lanes, kit, weights, gap, reach, reserved, attempts, keep_out):
	"""Buildings along both sides of every lane first (doors on the street), then
	darts into what is left. Returns list of dicts with rect/look/h/face."""
	(zx0, zz0), (zx1, zz1) = zone
	looks = [k for k in kit for _ in range(weights[k])]
	placed = []

	def fits(r):
		if r[0] < zx0 + keep_out.get("x0", 0.4) or r[2] > zx1 - keep_out.get("x1", 0.4) \
				or r[1] < zz0 + keep_out.get("z0", 0.4) or r[3] > zz1 - keep_out.get("z1", 0.4):
			return False
		if any(rect_gap(r, p["rect"]) < gap for p in placed):
			return False
		if not rect_lane_clear(r, lanes, 0.0):
			return False
		return not any(rect_dist(px, pz, r) < pr for (px, pz, pr) in reserved)

	def try_add(r, look, heights):
		r = tuple(round(v * 2) / 2 for v in r)            # half-metre snap, still off-grid
		if not fits(r):
			return False
		face, dist, step = door_side(r, lanes)
		if dist > reach:
			return False
		placed.append({"rect": r, "look": look, "h": rng.choice(heights), "face": face, "step": step})
		return True

	# Frontage: walk each lane, set a building back from its edge on both sides.
	for pts, width in lanes:
		for a, b in zip(pts, pts[1:]):
			L = math.dist(a, b)
			ux, uz = (b[0] - a[0]) / L, (b[1] - a[1]) / L
			for side in (1, -1):
				nx, nz = -uz * side, ux * side
				along_x = abs(ux) >= abs(uz)
				t = rng.uniform(0.0, 1.5)
				while t < L:
					look = rng.choice(looks)
					(w, d), heights = rng.choice(kit[look])
					fw, fd = (max(w, d), min(w, d)) if along_x else (min(w, d), max(w, d))   # long side on the street
					run = fw if along_x else fd
					cx, cz = a[0] + ux * (t + run / 2), a[1] + uz * (t + run / 2)
					back = width * 0.5 + rng.uniform(0.3, 1.4)
					if along_x:
						z0 = cz + (back if nz > 0 else -back - fd)
						r = (cx - fw / 2, z0, cx + fw / 2, z0 + fd)
					else:
						x0 = cx + (back if nx > 0 else -back - fw)
						r = (x0, cz - fd / 2, x0 + fw, cz + fd / 2)
					if try_add(r, look, heights):
						t += run + gap + rng.uniform(0.0, 1.2)
					else:
						t += 0.5
	# Darts into the back lots.
	for _ in range(attempts):
		look = rng.choice(looks)
		(w, d), heights = rng.choice(kit[look])
		if rng.random() < 0.5:
			w, d = d, w
		x0 = rng.uniform(zx0, zx1 - w)
		z0 = rng.uniform(zz0, zz1 - d)
		try_add((x0, z0, x0 + w, z0 + d), look, heights)
	return placed


def walk_grid(zone, blockers, start, radius=0.5, cell=0.25):
	"""Flood fill of standable cells (player radius) from start. Returns set of (i, j)."""
	(zx0, zz0), (zx1, zz1) = zone
	nx = int((zx1 - zx0) / cell) + 1
	nz = int((zz1 - zz0) / cell) + 1
	# Precompute blocked cells by rasterising each blocker's grown rect.
	blocked = set()
	for b in blockers:
		i0 = max(0, int((b[0] - radius - zx0) / cell) - 1); i1 = min(nx - 1, int((b[2] + radius - zx0) / cell) + 1)
		j0 = max(0, int((b[1] - radius - zz0) / cell) - 1); j1 = min(nz - 1, int((b[3] + radius - zz0) / cell) + 1)
		for i in range(i0, i1 + 1):
			for j in range(j0, j1 + 1):
				x, z = zx0 + i * cell, zz0 + j * cell
				if rect_dist(x, z, b) <= radius:
					blocked.add((i, j))
	si, sj = round((start[0] - zx0) / cell), round((start[1] - zz0) / cell)
	seen = {(si, sj)}
	todo = [(si, sj)]
	while todo:
		i, j = todo.pop()
		for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
			n = (i + di, j + dj)
			if 0 <= n[0] < nx and 0 <= n[1] < nz and n not in seen and n not in blocked:
				seen.add(n)
				todo.append(n)
	return seen, (lambda x, z: (round((x - zx0) / cell), round((z - zz0) / cell)) in seen)


def box(id_, zone, kind, r, y0, y1, **extra):
	b = {"id": id_, "zone": zone, "kind": kind, "min": [r[0], y0, r[1]], "max": [r[2], y1, r[3]]}
	b.update(extra)
	return b


def bridges(towers, rng, max_per=2):
	"""Rooftop bridges between neighbouring towers. Deck top = the lower roof."""
	out = []
	count = {i: 0 for i in range(len(towers))}
	pairs = []
	for i, a in enumerate(towers):
		for j in range(i + 1, len(towers)):
			b = towers[j]
			ra, rb = a["rect"], b["rect"]
			for axis in (0, 1):            # 0: gap along x, 1: gap along z
				lo, hi = (0, 2) if axis == 0 else (1, 3)
				olo, ohi = (1, 3) if axis == 0 else (0, 2)
				left, right = (ra, rb) if ra[lo] < rb[lo] else (rb, ra)
				gap = right[lo] - left[hi]
				ov0, ov1 = max(ra[olo], rb[olo]), min(ra[ohi], rb[ohi])
				if 2.5 <= gap <= 9.0 and ov1 - ov0 >= 3.0:
					pairs.append((gap, i, j, axis, left, right, ov0, ov1))
	rng.shuffle(pairs)
	pairs.sort(key=lambda p: p[0])
	for gap, i, j, axis, left, right, ov0, ov1 in pairs:
		if count[i] >= max_per or count[j] >= max_per:
			continue
		a, b = towers[i], towers[j]
		# A round tower only meets the box face at its middle line, so aim there.
		mid = (ov0 + ov1) / 2
		for t in (a, b):
			if t["look"] == "tower_round":
				c = (t["rect"][1] + t["rect"][3]) / 2 if axis == 0 else (t["rect"][0] + t["rect"][2]) / 2
				mid = c
		if mid - 1.1 < ov0 or mid + 1.1 > ov1:
			continue
		top = min(a["h"], b["h"])
		if axis == 0:
			r = (left[2], mid - 1.1, right[0], mid + 1.1)
		else:
			r = (mid - 1.1, left[3], mid + 1.1, right[1])
		# Never through a third tower.
		if any(rect_gap(r, t["rect"]) < 0.01 and t is not a and t is not b for t in towers):
			continue
		if any(rect_gap(r, o["rect"]) < 0.5 and abs(o["top"] - top) < 1.0 for o in out):
			continue
		out.append({"rect": r, "top": top, "axis": "x" if axis == 0 else "z"})
		count[i] += 1
		count[j] += 1
	return out


def build_boxes(huts, towers, spans):
	"""The generated boxes, in a stable order."""
	new = []
	huts.sort(key=lambda h: (-h["rect"][1], h["rect"][0]))
	towers.sort(key=lambda h: (h["rect"][1], h["rect"][0]))
	for i, h in enumerate(huts):
		extra = {"look": h["look"], "face": h["face"]}
		if h["look"] in ROUND:
			extra["shape"] = "round"
		new.append(box("house_w_%02d" % (i + 1), "residential_w", "solid", h["rect"], 0, h["h"], **extra))
	new.append(box("well_w", "residential_w", "cover", (-19, -62, -17, -60), 0, 1.0, look="cistern", shape="round"))
	for i, t in enumerate(towers):
		extra = {"look": t["look"], "face": t["face"]}
		if t["look"] in ROUND:
			extra["shape"] = "round"
		new.append(box("house_e_%02d" % (i + 1), "residential_e", "solid", t["rect"], 0, t["h"], **extra))
	for i, s in enumerate(spans):
		new.append(box("bridge_e_%02d" % (i + 1), "residential_e", "overhead", s["rect"], s["top"] - 0.6, s["top"],
			look="bridge", axis=s["axis"]))
	new.append(box("well_e", "residential_e", "cover", (-23, 61.5, -21, 63.5), 0, 1.0, look="cistern", shape="round"))

	# ---- barracks: a bunk tower and an upper block on the hall, bridged at the roofs.
	new.append(box("barracks_bunk", "barracks", "solid", (38, 50, 50, 64), 0, 16.0, look="tower_block", face="-z", style="garrison"))
	new.append(box("barracks_upper", "barracks", "solid", (72, 50, 88, 64), 6.0, 13.0, look="upper", face="-z", style="garrison"))
	new.append(box("barracks_bridge", "barracks", "overhead", (50, 55.5, 72, 58.5), 12.4, 13.0, look="bridge", axis="x", style="garrison"))
	return new


def main():
	check = "--check" in sys.argv
	town = json.loads(TOWN.read_text())
	pickups = json.loads(PICKUPS.read_text())
	markers = {m["id"]: m for m in town["markers"]}
	rng = random.Random(7331)

	kept = [b for b in town["boxes"] if not str(b["id"]).startswith(GENERATED)]

	# ---- residential_w: the market side. Small huts, close together.
	zw = ((-98, -73), (28, -36))
	lanes_w = [
		([(28.5, -45.5), (14, -47.5), (2, -44.5), (-12, -48.5), (-27, -46), (-41, -50.5), (-58, -48), (-72, -52.5), (-88, -50), (-97, -54)], 3.6),
		([(-4.5, -35.5), (-4.5, -58), (-2, -66), (-4, -73)], 2.6),        # through resident_w
		([(-36, -35.5), (-33, -47), (-38, -60), (-35, -73)], 2.6),
		([(-66, -35.5), (-63, -48), (-67, -62), (-64, -73)], 2.6),
		([(20, -35.5), (22, -50), (18, -73)], 2.4),
		([(-96.3, -73), (-96.3, -35)], 3.0),                              # the back-gap alley by the wall
		([(-24, -60), (-12, -60)], 2.4),                                  # little square
	]
	reserved_w = [(-18, -61, 3.6), (-4.5, -54, 1.6)]   # square with the well, resident marker
	huts = pack(rng, zw, lanes_w, HUTS, HUT_WEIGHTS, gap=1.2, reach=9.0, reserved=reserved_w, attempts=20000,
		keep_out={"x0": 3.4})
	# ---- residential_e: the barracks side. Towers and rooftop bridges.
	ze = ((-98, 36), (28, 73))
	lanes_e = [
		([(28.5, 45), (10, 47.5), (-8, 44.5), (-26, 48.5), (-44, 45.5), (-62, 49.5), (-80, 46.5), (-97, 49)], 4.6),
		([(-4.5, 35.5), (-4.5, 73)], 3.4),                                # through resident_e
		([(-40, 35.5), (-37, 58), (-41, 73)], 3.4),
		([(-75, 35.5), (-72, 60), (-76, 73)], 3.4),
		([(16, 35.5), (19, 60), (15, 73)], 3.0),
		([(-30, 62), (-16, 62)], 3.0),
	]
	reserved_e = [(0, 40, 2.6), (-4.5, 54, 1.8), (-22, 62.5, 4.0)]
	towers = pack(rng, ze, lanes_e, TOWERS, TOWER_WEIGHTS, gap=3.0, reach=7.0, reserved=reserved_e, attempts=12000,
		keep_out={"x0": 1.0})
	spans = bridges(towers, random.Random(7))
	# Looks for the hand-placed buildings.
	looks = {
		"barracks_hall": {"look": "hall", "face": "-z", "style": "garrison"},
		"watchtower": {"look": "watchtower", "face": "-x", "style": "garrison"},
		"shop_1": {"look": "shop", "face": "+z"}, "shop_2": {"look": "shop", "face": "+z"},
		"shop_3": {"look": "shop", "face": "+z"}, "shop_4": {"look": "shop", "face": "+z"},
	}
	for b in kept:
		sid = str(b["id"])
		if sid.startswith("stall_") and sid.endswith("_back"):
			b.update({"look": "stall_back"})
		elif sid.startswith("stall_"):
			# Two rows facing each other across one aisle: the door side is the aisle.
			b.update({"look": "stall", "face": "-z" if sid.startswith("stall_n") else "+z"})
	for b in kept:
		b.update(looks.get(b["id"], {}))
	town["boxes"] = kept + build_boxes(huts, towers, spans)

	# ---- walk check + hiding places
	def blockers():
		return [(b["min"][0], b["min"][2], b["max"][0], b["max"][2]) for b in town["boxes"]
			if b["kind"] in town["blocking_kinds"] and b["min"][1] < 1.8]
	errors = []
	res_w = markers["resident_w"]["pos"]
	res_e = markers["resident_e"]["pos"]
	walk_w = ((-98, -73), (28, -34))
	walk_e = ((-98, 34), (28, 73))
	# A building whose door step cannot be walked to is dropped, then check again.
	for _ in range(10):
		_, ok_w = walk_grid(walk_w, blockers(), (res_w[0], res_w[2]))
		_, ok_e = walk_grid(walk_e, blockers(), (res_e[0], res_e[2]))
		cut_w = [h for h in huts if not ok_w(*h["step"])]
		cut_e = [t for t in towers if not ok_e(*t["step"])]
		if not cut_w and not cut_e:
			break
		gone = {id(h) for h in cut_w + cut_e}
		huts = [h for h in huts if id(h) not in gone]
		towers = [t for t in towers if id(t) not in gone]
		spans = bridges(towers, random.Random(7))
		town["boxes"] = kept + build_boxes(huts, towers, spans)
		print("dropped %d building(s) with no way to their door" % len(gone))
	for h in huts:
		if not ok_w(*h["step"]):
			errors.append("door of hut at %s cannot be reached" % (h["rect"],))
	for t in towers:
		if not ok_e(*t["step"]):
			errors.append("door of tower at %s cannot be reached" % (t["rect"],))

	def tucked(x, z, rects, ok, lanes, need):
		if not ok(x, z) or lane_dist((x, z), lanes) < 1.0:
			return False
		near = sum(1 for r in rects if rect_dist(x, z, r) < 1.6)
		return near >= need
	alley = []
	for rects, ok, lanes, want, need in (([h["rect"] for h in huts], ok_w, lanes_w, 3, 2), ([t["rect"] for t in towers], ok_e, lanes_e, 2, 1)):
		cands = []
		for r in rects:
			for p in ((r[0] - 0.7, (r[1] + r[3]) / 2), (r[2] + 0.7, (r[1] + r[3]) / 2), ((r[0] + r[2]) / 2, r[1] - 0.7), ((r[0] + r[2]) / 2, r[3] + 0.7)):
				p = (round(p[0] * 4) / 4, round(p[1] * 4) / 4)
				if tucked(p[0], p[1], rects, ok, lanes, need):
					cands.append(p)
		rng.shuffle(cands)
		picked = []
		for p in cands:
			if all(math.dist(p, q) > 25 for q in picked):
				picked.append(p)
			if len(picked) == want:
				break
		alley += picked
	roofs = [h for h in huts if h["look"] in ("hut_block", "hut_long") and h["h"] <= 4.0]
	rng.shuffle(roofs)
	roof_pts = []
	for h in roofs:
		c = ((h["rect"][0] + h["rect"][2]) / 2, (h["rect"][1] + h["rect"][3]) / 2)
		if all(math.dist(c, (q[0], q[2])) > 20 for q in roof_pts):
			roof_pts.append((c[0], h["h"], c[1]))
		if len(roof_pts) == 4:
			break
	def rel(p3):
		return [round(p3[0] - res_w[0], 2), round(p3[1] - res_w[1], 2), round(p3[2] - res_w[2], 2)]
	for a in pickups["drops"]["areas"]:
		if a["id"] == "alleys":
			a["marker"] = "resident_w"
			a["spots"] = [rel((x, 0.0, z)) for x, z in alley]
		if a["id"] == "rooftops":
			a["marker"] = "resident_w"
			a["spots"] = [rel(p) for p in roof_pts]

	print("huts: %d  towers: %d  bridges: %d  alley spots: %d  roof spots: %d" % (len(huts), len(towers), len(spans), len(alley), len(roof_pts)))
	print("looks:", {k: sum(1 for h in huts + towers if h["look"] == k) for k in list(HUTS) + list(TOWERS)})
	print("boxes total:", len(town["boxes"]))
	for e in errors:
		print("WALK:", e)
	if errors:
		sys.exit(1)
	if not check:
		TOWN.write_text(json.dumps(town, indent=1, ensure_ascii=False) + "\n")
		PICKUPS.write_text(json.dumps(pickups, indent=2, ensure_ascii=False) + "\n")
		print("wrote", TOWN.relative_to(ROOT), "and", PICKUPS.relative_to(ROOT))


if __name__ == "__main__":
	main()
