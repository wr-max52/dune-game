#!/usr/bin/env python3
"""Draws the planning sketch for issue #237 (the round port) next to today's port.

    python3 docs/town/plan_round_port.py   # writes docs/town/round_port_plan.svg

A sketch, not data: it shows where each district goes, roughly how big it is and
how it bends round the pit. The real boxes still come from content data and the
town tools when the issue is built. Today's port is drawn from
content/core/towns/port_square.json at the same scale, and the world panel
reads content/core/worlds/port_desert.json, with the moves from the issue
applied. Town frame as everywhere else: +X is the front gate side, and +Z is
drawn downward (the barracks side), matching docs/town/render_town.py.
Pure standard library; fixed seed, so the same picture every run.
"""
import json, math, random
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/town/round_port_plan.svg"

R = 140.0           # inside radius of the round wall (about 61,600 m², ~2x today)
WALL = 2.0
GATE_HALF = 6.0     # same 12 m gate as today
BACK_GATE_DEG = -166.0
PIT_R = 38.0        # bowl radius: wider than today's 56 m square pit
PORT_R = 66.0       # spaceport ring, pads sit on it
SKRUGS = (-226.0, -56.0)        # moved: ~90 m past the wall outside the back gate
NEAR_OUTPOST = (0.0, 250.0)     # moved: off to the barracks side

COL = {
	"bg": "#f4ead8", "sand": "#e8d3ad", "paper": "#fbf6ec", "ink": "#3b2f22",
	"muted": "#8a7660", "wall": "#6b5844", "street": "#d9c19a",
	"port": "#b8c4cc", "pit": "#8796a1", "pad": "#eef2f4",
	"market": "#e9a24a", "barracks": "#9a4b45", "cantina": "#6f5aa8",
	"res_w": "#c98f5e", "res_e": "#a9744b", "square": "#d4b6e0",
	"gate": "#3b2f22", "light": "#ffd34d", "accent": "#c0392b",
}

rng = random.Random(237)


def pol(r, deg, c=(0.0, 0.0)):
	a = math.radians(deg)
	return (c[0] + r * math.cos(a), c[1] + r * math.sin(a))


def smooth_path(pts, closed=True):
	"""Catmull-Rom through pts, as cubic beziers."""
	n = len(pts)
	if n < 3:
		return ""
	d = "M %.1f %.1f " % pts[0]
	rng_ = range(n) if closed else range(n - 1)
	for i in rng_:
		p0 = pts[(i - 1) % n] if closed or i > 0 else pts[0]
		p1 = pts[i]
		p2 = pts[(i + 1) % n]
		p3 = pts[(i + 2) % n] if closed or i + 2 < n else pts[-1]
		c1 = (p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6)
		c2 = (p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6)
		d += "C %.1f %.1f %.1f %.1f %.1f %.1f " % (c1 + c2 + p2)
	return d + ("Z" if closed else "")


def blob_sector(r0, r1, a0, a1, wobble=4.0, steps=14):
	"""An organic band between radii r0..r1 and angles a0..a1 (degrees)."""
	pts = []
	for i in range(steps + 1):
		a = a0 + (a1 - a0) * i / steps
		pts.append(pol(r1 + rng.uniform(-wobble, wobble * 0.3), a))
	for i in range(steps + 1):
		a = a1 - (a1 - a0) * i / steps
		pts.append(pol(r0 + rng.uniform(-wobble, wobble), a))
	return pts


def area(pts):
	s = 0.0
	for i in range(len(pts)):
		x0, y0 = pts[i]
		x1, y1 = pts[(i + 1) % len(pts)]
		s += x0 * y1 - x1 * y0
	return abs(s) / 2


class Svg:
	def __init__(self, w, h):
		self.w, self.h, self.parts = w, h, []

	def add(self, s):
		self.parts.append(s)

	def text(self, x, y, s, size=13, fill=COL["ink"], anchor="start", weight="normal", italic=False):
		st = ' font-style="italic"' if italic else ""
		halo = COL["ink"] if fill == "#fff" else COL["paper"]
		self.add('<text x="%.1f" y="%.1f" font-size="%s" fill="%s" text-anchor="%s" font-weight="%s"%s '
			'stroke="%s" stroke-width="3" stroke-opacity="0.8" paint-order="stroke" stroke-linejoin="round">%s</text>'
			% (x, y, size, fill, anchor, weight, st, halo, s))

	def done(self):
		return ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d" '
			'font-family="Helvetica, Arial, sans-serif">\n' % (self.w, self.h, self.w, self.h)
			+ "\n".join(self.parts) + "\n</svg>\n")


class View:
	"""Maps town metres (x, z) into a panel of the SVG."""
	def __init__(self, ox, oy, scale):
		self.ox, self.oy, self.s = ox, oy, scale

	def p(self, x, z):
		return (self.ox + x * self.s, self.oy + z * self.s)

	def pts(self, pts):
		return [self.p(*q) for q in pts]


def draw_today(svg, v):
	town = json.loads((ROOT / "content/core/towns/port_square.json").read_text())
	look = {"wall": COL["wall"], "solid": "#c9b089", "cover": "#b59a74", "floor": None,
		"overhead": COL["wall"], "ramp": COL["pit"], "ship": "#58646d", "roof": None,
		"counter": "#7d6a55", "pad": COL["pad"], "bowl": COL["pit"], "spiral": COL["cantina"], "lookout": None}
	zcol = {"market": COL["market"], "barracks": COL["barracks"], "spaceport": COL["port"],
		"cantina": COL["cantina"], "cantina_square": COL["square"], "residential_w": COL["res_w"],
		"residential_e": COL["res_e"], "main_street": COL["street"]}
	b = town["bounds"]
	x0, y0 = v.p(b["min"][0], b["min"][1])
	x1, y1 = v.p(b["max"][0], b["max"][1])
	svg.add('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s"/>' % (x0, y0, x1 - x0, y1 - y0, COL["paper"]))
	for z in town["zones"]:
		a, c = v.p(*z["min"]), v.p(*z["max"])
		svg.add('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s" opacity="0.35"/>'
			% (a[0], a[1], c[0] - a[0], c[1] - a[1], zcol.get(z["id"], "#ccc")))
	pit = v.p(-28, -28)
	svg.add('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s" opacity="0.8"/>' % (pit + (56 * v.s, 56 * v.s) + (COL["pit"],)))
	for bx in town["boxes"]:
		fill = look.get(bx["kind"], "#c9b089")
		if fill is None or bx["kind"] == "bowl":
			continue
		a, c = v.p(bx["min"][0], bx["min"][2]), v.p(bx["max"][0], bx["max"][2])
		svg.add('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s"/>'
			% (min(a[0], c[0]), min(a[1], c[1]), abs(c[0] - a[0]), abs(c[1] - a[1]), fill))
	for lbl, x, z in [("market", 65, -50), ("barracks", 70, 40), ("pit", 0, 3), ("cantina", -72, 22),
			("huts", -40, -64), ("towers", -40, 68), ("gate", 116, 3)]:
		svg.text(*v.p(x, z), lbl, size=10, anchor="middle", fill=COL["ink"], weight="bold")
	sk = v.p(-135, -60)
	svg.add('<circle cx="%.1f" cy="%.1f" r="4" fill="%s"/>' % (sk + (COL["accent"],)))
	svg.text(sk[0] - 6, sk[1] - 6, "Skrugs", size=10, anchor="end")
	return 200 * 150


def draw_planned(svg, v):
	s = v.s
	cx, cy = v.p(0, 0)
	# sand outside, paper inside the wall
	svg.add('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="%s"/>' % (cx, cy, R * s, COL["paper"]))

	zones = {}
	def zone(name, pts, fill, op=0.85):
		zones[name] = area(pts)
		svg.add('<path d="%s" fill="%s" opacity="%s" stroke="%s" stroke-width="1"/>'
			% (smooth_path(v.pts(pts)), fill, op, COL["paper"]))

	# Districts round the pit, front gate at 0°, +angle = +Z (barracks side).
	zone("barracks", blob_sector(PORT_R + 10, R - 4, 13, 74, wobble=3), COL["barracks"])
	zone("market", blob_sector(PORT_R + 4, R - 4, -96, -12, wobble=3), COL["market"])
	# Neighbourhoods sprawl round the back and almost meet behind the cantina:
	# only the back lane (to the back gate) separates them.
	zone("residential_e (towers)", blob_sector(PORT_R + 6, R - 3, 78, 168, wobble=7, steps=18), COL["res_e"])
	zone("residential_w (huts)", blob_sector(PORT_R + 6, R - 3, -158, -100, wobble=7, steps=14), COL["res_w"])
	# behind the cantina the two districts curl in toward each other
	zone("residential_e (towers)+", blob_sector(117, R - 3, 168, 186, wobble=3, steps=6), COL["res_e"])
	zone("residential_w (huts)+", blob_sector(117, R - 3, -174, -158, wobble=3, steps=6), COL["res_w"])

	# cantina square + rounded cantina (same footprint as today: ~32 x 28 m)
	sq = [pol(r, a) for r, a in [(68, 160), (74, 172), (72, 188), (68, 200), (90, 198), (96, 180), (90, 162)]]
	zone("cantina_square", sq, COL["square"], 0.9)
	ccx, ccz = -92.0, 0.0
	cpts = [(ccx + 16 * math.cos(math.radians(t)) * (1 + 0.04 * math.sin(math.radians(3 * t))),
			ccz + 14 * math.sin(math.radians(t))) for t in range(0, 360, 20)]
	zones["cantina"] = area(cpts)
	svg.add('<path d="%s" fill="%s" stroke="%s" stroke-width="1.5"/>' % (smooth_path(v.pts(cpts)), COL["cantina"], COL["ink"]))
	st = v.p(ccx - 9, ccz + 9)
	svg.add('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="%s" opacity="0.35"/>' % (st + (9 * s, COL["light"])))
	svg.add('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="%s" stroke="%s"/>' % (st + (3.2 * s, COL["light"], COL["ink"])))
	door = v.p(ccx + 16, 0)
	svg.add('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s"/>' % (door[0] - 1.5, door[1] - 2 * s, 3, 4 * s, COL["paper"]))

	# streets: main street from the gate, ring road round the spaceport, back lane
	def street(pts, w, col=COL["street"], dash=None):
		ds = ' stroke-dasharray="%s"' % dash if dash else ""
		svg.add('<path d="%s" fill="none" stroke="%s" stroke-width="%.1f" stroke-linecap="round" stroke-linejoin="round"%s/>'
			% (smooth_path(v.pts(pts), closed=False), col, w * s, ds))
	street([(R + 30, 0), (R, 0), (118, 3), (98, -3), (82, 2), (PORT_R + 2, 0)], 12)
	ring = [pol(PORT_R + 3, a) for a in range(0, 361, 15)]
	street(ring, 9)
	street([pol(PORT_R + 3, 180), (-72, -2), (-76, 0)], 7)  # to the cantina door
	street([pol(PORT_R + 3, -164), pol(96, -168), pol(118, -170), pol(R, BACK_GATE_DEG), pol(R + 30, BACK_GATE_DEG)], 5)
	# winding residential lanes
	for a0, a1, r in [(84, 160, 98), (88, 164, 122), (-150, -104, 100), (-154, -106, 124)]:
		pts = [pol(r + rng.uniform(-5, 5), a0 + (a1 - a0) * i / 7) for i in range(8)]
		street(pts, 4)
	for a in (100, 128, 150, -118, -138):
		street([pol(PORT_R + 6, a + rng.uniform(-3, 3)), pol(R - 6, a + rng.uniform(-6, 6))], 3.5)

	# market aisles (curved, branching) and taller stalls along them
	aisles = [[pol(r, a) for a in range(-90, -15, 8)] for r in (84, 102, 120)]
	aisles.append([pol(80, -52), pol(100, -58), pol(124, -50)])
	aisles.append([pol(80, -30), pol(104, -24), pol(128, -32)])
	for a in aisles:
		street(a, 4.5, col="#f3d9a8")
	for r in (84, 102, 120):
		for a in range(-88, -18, 6):
			for side in (-1, 1):
				x, z = pol(r + side * 4.2, a + rng.uniform(-1, 1))
				px, pz = v.p(x, z)
				ang = a + 90
				svg.add('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="#a2601c" transform="rotate(%.1f %.1f %.1f)"/>'
					% (px - 2 * s, pz - 1 * s, 4 * s, 2 * s, ang, px, pz))

	# barracks: bigger hall, yard, drill pad
	hall = [pol(r, a) for r, a in [(104, 40), (130, 36), (132, 64), (106, 68)]]
	svg.add('<path d="%s" fill="#6e2f2b" stroke="%s"/>' % (smooth_path(v.pts(hall)), COL["ink"]))
	hall2 = [pol(r, a) for r, a in [(84, 54), (100, 52), (101, 70), (86, 72)]]
	svg.add('<path d="%s" fill="#6e2f2b" stroke="%s"/>' % (smooth_path(v.pts(hall2)), COL["ink"]))
	yard = v.p(*pol(92, 28))
	svg.add('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="none" stroke="%s" stroke-width="2" stroke-dasharray="4 3"/>' % (yard + (13 * s, COL["paper"])))

	# housing scatter: huts (west) and towers with bridges (east)
	for a0, a1, r0, r1, kind, n in [(-158, -100, PORT_R + 10, R - 6, "hut", 70), (-174, -158, 119, R - 5, "hut", 10),
			(80, 168, PORT_R + 10, R - 6, "tower", 46), (168, 186, 119, R - 5, "tower", 5)]:
		placed = []
		tries = 0
		while len(placed) < n and tries < 4000:
			tries += 1
			a = rng.uniform(a0 + 2, a1 - 2)
			r = rng.uniform(r0 + 2, r1 - 2)
			x, z = pol(r, a)
			if any(math.hypot(x - q[0], z - q[1]) < (7.5 if kind == "hut" else 10) for q in placed):
				continue
			if any(abs(r - lr) < 4 for lr in ((98, 122) if kind == "tower" else (100, 124))):
				continue
			placed.append((x, z))
		for i, (x, z) in enumerate(placed):
			px, pz = v.p(x, z)
			if kind == "hut":
				w = rng.uniform(4, 6) * s
				svg.add('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="%.1f" fill="#8f5a32" opacity="0.85"/>'
					% (px - w / 2, pz - w / 2, w, w * rng.uniform(0.7, 1.1), w * 0.35))
			else:
				w = 6.5 * s
				svg.add('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="#5e3b22" opacity="0.9"/>' % (px - w / 2, pz - w / 2, w, w))
				if i % 3 == 0 and i + 1 < len(placed):
					q = v.p(*placed[i + 1])
					if math.hypot(q[0] - px, q[1] - pz) < 22 * s:
						svg.add('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="1.5"/>' % (px, pz, q[0], q[1], COL["light"]))

	# spaceport: wider round bowl + ring of surface pads
	pr = PORT_R * s
	svg.add('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="%s"/>' % (cx, cy, pr, COL["port"]))
	svg.add('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="%s" stroke="%s" stroke-width="1.5"/>' % (cx, cy, PIT_R * s, COL["pit"], COL["ink"]))
	for a in (-28, 152):  # ramps like today's NE/SW
		p0, p1 = v.p(*pol(PIT_R - 16, a)), v.p(*pol(PIT_R + 2, a))
		svg.add('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="%.1f"/>' % (p0 + p1 + (COL["street"], 7 * s)))
	pads = [a for a in range(20, 360, 45)]
	zones["pads"] = len(pads)
	for i, a in enumerate(pads):
		px, pz = v.p(*pol(PIT_R + 15, a))
		svg.add('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="%s" stroke="%s"/>' % (px, pz, 7.5 * s, COL["pad"], COL["muted"]))
		svg.add('<text x="%.1f" y="%.1f" font-size="9" text-anchor="middle" fill="%s">H</text>' % (px, pz + 3, COL["muted"]))
	for (x, z) in [(14, 11), (-14, 11), (14, -11), (-14, -11)]:
		px, pz = v.p(x, z)
		svg.add('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s" opacity="0.6"/>' % (px - 5 * s, pz - 4 * s, 10 * s, 8 * s, COL["pad"]))

	# wall again on top (so nothing spills), with the gates cut in
	gate_deg = math.degrees(GATE_HALF / R)
	def arc(a0, a1):
		p0, p1 = v.p(*pol(R + WALL / 2, a0)), v.p(*pol(R + WALL / 2, a1))
		large = 1 if (a1 - a0) > 180 else 0
		return 'M %.1f %.1f A %.1f %.1f 0 %d 1 %.1f %.1f' % (p0 + ((R + WALL / 2) * s, (R + WALL / 2) * s, large) + p1)
	svg.add('<path d="%s" fill="none" stroke="%s" stroke-width="%.1f"/>' % (arc(gate_deg, 360 + BACK_GATE_DEG - 1.2), COL["wall"], (WALL + 1.5) * s))
	svg.add('<path d="%s" fill="none" stroke="%s" stroke-width="%.1f"/>' % (arc(BACK_GATE_DEG + 1.2, -gate_deg), COL["wall"], (WALL + 1.5) * s))
	for zt in (-12.0, 12.0):  # two gate towers
		px, pz = v.p(R - 2, zt)
		svg.add('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s"/>' % (px - 3.5 * s, pz - 3.5 * s, 7 * s, 7 * s, COL["gate"]))
		svg.add('<circle cx="%.1f" cy="%.1f" r="2.5" fill="%s"/>' % (px, pz, COL["accent"]))

	# outside: Skrugs farther out the back, near outpost off to the side
	sk = v.p(*SKRUGS)
	svg.add('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s" stroke="%s"/>' % (sk[0] - 6, sk[1] - 5, 12, 10, COL["accent"], COL["ink"]))
	svg.text(sk[0], sk[1] + 20, "Skrugs's post", size=12, anchor="middle", weight="bold")
	svg.text(sk[0], sk[1] + 34, "~90 m past the back gate", size=10, anchor="middle", fill=COL["muted"])
	old = v.p(-135, -60)
	svg.add('<circle cx="%.1f" cy="%.1f" r="4" fill="none" stroke="%s" stroke-dasharray="2 2"/>' % (old + (COL["accent"],)))
	svg.add('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-dasharray="3 3"/>' % (old + (sk[0] + 6, sk[1]) + (COL["accent"],)))
	op = v.p(*NEAR_OUTPOST)
	svg.add('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="#222" stroke="%s" stroke-width="2"/>' % (op[0] - 8, op[1] - 6, 16, 12, COL["accent"]))
	svg.text(op[0] + 14, op[1] + 4, "near outpost (0, 250)", size=12, weight="bold")
	svg.text(op[0] + 14, op[1] + 18, "off the barracks side, ~110 m past the wall", size=10, fill=COL["muted"])

	# labels
	for txt, (x, z), col in [
			("FRONT GATE", (R + 18, -24), COL["ink"]), ("two towers", (R + 18, -12), COL["muted"]),
			("MARKET  (3x, aisles)", pol(108, -54), COL["ink"]), ("BARRACKS (bigger)", pol(116, 22), "#fff"),
			("SPACEPORT", (0, -6), COL["ink"]), ("bigger bowl + 8 pads", (0, 8), COL["ink"]),
			("TOWERS", pol(104, 122), "#fff"), ("HUTS", pol(110, -130), "#fff"),
			("square", pol(76, 168), COL["ink"]), ("back gate", pol(R + 12, BACK_GATE_DEG - 6), COL["ink"]),
			]:
		px, pz = v.p(x, z)
		svg.text(px, pz, txt, size=11 if txt.isupper() else 10, anchor="middle", fill=col, weight="bold" if txt.isupper() else "normal")
	for i, (txt, target) in enumerate([
			("cantina: round body, same size as today", (ccx - 4, ccz - 6)),
			("stair tower: lit all the way up", (ccx - 9, ccz + 9)),
			("huts and towers almost meet behind it", pol(R - 8, 178))]):
		lx, lz = -R - 22, -6 + i * 15 / s * 1.0
		a, b = v.p(lx, lz), v.p(*target)
		svg.add('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="1"/>' % (a + b + (COL["ink"],)))
		svg.add('<circle cx="%.1f" cy="%.1f" r="2.5" fill="%s"/>' % (b + (COL["ink"],)))
		svg.text(a[0] - 4, a[1] + 4, txt, size=11, anchor="end")
	return zones


def draw_world(svg, v, box):
	world = json.loads((ROOT / "content/core/worlds/port_desert.json").read_text())
	x0, y0, x1, y1 = box
	svg.add('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s"/>' % (x0, y0, x1 - x0, y1 - y0, COL["sand"]))
	svg.add('<clipPath id="wclip"><rect x="%.1f" y="%.1f" width="%.1f" height="%.1f"/></clipPath>' % (x0, y0, x1 - x0, y1 - y0))
	svg.add('<g clip-path="url(#wclip)">')
	gate = (R + WALL, 0.0)
	g = v.p(*gate)
	# what you see out of the front gate: a +-15° cone
	for half in (15,):
		a, b = v.p(*pol(1800, half, gate)), v.p(*pol(1800, -half, gate))
		svg.add('<path d="M %.1f %.1f L %.1f %.1f L %.1f %.1f Z" fill="%s" opacity="0.25"/>' % (g + a + b + (COL["light"],)))
	c = v.p(0, 0)
	svg.add('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="%s" stroke="%s" stroke-width="2"/>' % (c + (R * v.s, COL["paper"], COL["wall"])))
	moved = {"remnant_outpost_near": NEAR_OUTPOST, "skrugs_post": SKRUGS}
	for lm in world["landmarks"]:
		at = lm.get("at")
		if not at:
			continue
		x, z = moved.get(lm["id"], (at[0], at[2]))
		px, pz = v.p(x, z)
		if not (x0 - 20 < px < x1 + 20 and y0 - 20 < pz < y1 + 20):
			continue
		name = lm["id"].replace("remnant_outpost_", "outpost ").replace("starcruiser_", "").replace("_", " ")
		bearing = math.degrees(math.atan2(z - gate[1], x - gate[0]))
		in_view = abs(bearing) < 15 and x > gate[0]
		col = COL["accent"] if "outpost" in lm["id"] else COL["ink"]
		if lm["id"] == "starcruiser_wreck":
			svg.add('<ellipse cx="%.1f" cy="%.1f" rx="16" ry="6" fill="#555" transform="rotate(-8 %.1f %.1f)"/>' % (px, pz, px, pz))
			col = COL["ink"]
		else:
			svg.add('<circle cx="%.1f" cy="%.1f" r="5" fill="%s"/>' % (px, pz, col))
		label = name + (" (moved)" if lm["id"] in moved else "")
		if in_view and lm["id"] != "starcruiser_wreck":
			label += "  ← in the gate view"
		svg.text(px + 9, pz - 7, label, size=11, fill=col if in_view else COL["ink"], weight="bold" if in_view else "normal")
	svg.add('</g>')


def main():
	W, H = 1720, 1000
	svg = Svg(W, H)
	svg.add('<rect width="%d" height="%d" fill="%s"/>' % (W, H, COL["bg"]))
	svg.text(32, 46, "Round port plan (issue #237)", size=26, weight="bold")
	svg.text(32, 70, "Sketch, not data: districts, sizes and where things move. Same metres-to-pixels scale for today and the plan. +X (right) is the front gate.", size=13, fill=COL["muted"])

	# Today, same scale as the plan
	scale = 1.95
	svg.text(32, 112, "Today: port_square (size 50, 200 × 150 m, ~30,000 m²)", size=15, weight="bold")
	today_area = draw_today(svg, View(60 + 140 * scale * 0.95, 130 + 82 * scale, scale))

	# Plan
	vx, vy, pscale = 1150, 470, 1.75
	svg.text(700, 112, "Planned: port_round (~size 67, 280 m across, ~61,600 m²)", size=15, weight="bold")
	zones = draw_planned(svg, View(vx, vy, pscale))

	# World around the town
	box = (32, 560, 640, 975)
	svg.text(32, 548, "Around the town: out of the front gate you see only the wreck", size=15, weight="bold")
	draw_world(svg, View(32 + 330 * 0.26, 765, 0.26), box)

	# zone table
	tx, ty = 32, 512
	tot = math.pi * R * R
	rows = [
		"Rough areas in the sketch (m²):  inside the wall %d (today 30,000)" % tot,
		"market %d (today ~3,500)  ·  barracks %d (today ~3,500)" % (zones["market"], zones["barracks"]),
		"spaceport ring %d with %d pads (today a 56 m square pit)  ·  cantina %d (kept)" % (math.pi * PORT_R ** 2, zones["pads"], zones["cantina"]),
		"huts %d (today ~4,650)  ·  towers %d (today ~4,650)" % (zones["residential_w (huts)"] + zones["residential_w (huts)+"],
			zones["residential_e (towers)"] + zones["residential_e (towers)+"]),
	]
	for i, row in enumerate(rows):
		svg.text(tx, ty - 50 + i * 16, row, size=11, fill=COL["muted"])
	OUT.write_text(svg.done())
	print("wrote", OUT.relative_to(ROOT), "today %d m², plan %d m²" % (today_area, tot))
	for k, a in zones.items():
		print("  %-26s %8.0f" % (k, a))


if __name__ == "__main__":
	main()
