#!/usr/bin/env python3
"""Draws the planning sketch for Nitrogen Belt City (the ring station).

    python3 docs/station/plan_nitrogen_belt.py   # writes docs/station/nitrogen_belt_plan.svg

A sketch, not data: it shows where each floor, room, bridge, tunnel and wreck
goes and roughly how big it is. The real boxes still come from content data and
the town tools when the issues are built. Same frame as the town plans: +X is
east (right), and +Z (south) is drawn downward. Floor plans share one scale and
the side section shares another.
Pure standard library; fixed seed, so the same picture every run.
"""
import math, random
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/station/nitrogen_belt_plan.svg"

# Station numbers (metres). Tunable in data later; these are the sketch's.
SHAFT_R = 12.0      # open gap in the middle of every floor
LIFT_R = 4.5        # the elevator platform riding up and down the gap
GALLERY_W = 4.0     # walkway round the gap, where the bridges land
HALL_W = 6.0        # outer hallway, glass outer wall
SPOKE_W = 4.0       # corridor from the gallery out to the hallway
BRIDGE_W = 3.0
STOREY = 14.0       # each floor is tall: floor to ceiling
GAP = 12.0          # open space between floors: the elevator crosses it in a glass tube
LEVEL = STOREY + GAP
TUBE_R = 6.0        # the elevator's glass tube between floors
# Floor radii: the top floor is the biggest, each one below smaller (levels counted from the bottom, 0 = floor 1).
MAIN_RS = {3: 70.0, 2: 60.0, 1: 50.0, 0: 42.0}    # top, homes, markets, engines
T2_RS = {3: 54.0, 2: 46.0, 1: 40.0}               # homes, outpost, markets
T2_X = 170.0        # second tower centre, east of the main tower
BAY_R = 38.0        # landing bay: the port's round pit bowl (port_round pit_bowl)
BAY_X = -175.0      # west of the main tower, off the market floor
HOMES = 25
OPEN_HOMES = 8
WRECK_L = 600.0     # the desert wreck's class (starcruiser_wreck.gd)
WRECK_H = 60.0

COL = {
	"bg": "#eef0f3", "paper": "#fbfcfd", "ink": "#22262c", "muted": "#6b7480",
	"space": "#1b1f2a", "glass": "#7fc4e8", "hall": "#d9dee5", "gallery": "#c3cad3",
	"room": "#b7c0cb", "closed": "#9aa3ae", "open": "#e9b872", "spoke": "#d9dee5",
	"lift": "#ffd34d", "bridge": "#f0a04a", "tunnel": "#8fb3c9",
	"cantina": "#6f5aa8", "barracks": "#9a4b45", "bridge_room": "#3d6f8f",
	"market": "#e9a24a", "stall": "#a2601c", "hut": "#8b929b",
	"engine": "#5c6670", "reactor": "#e26a3c", "hatch": "#c0392b",
	"outpost": "#7a3f3a", "remnant": "#c0392b", "npc": "#2d6a4f",
	"wreck": "#7d7466", "rock": "#6d7079", "gas": "#d8b48a", "gas_dark": "#9c7650",
	"ring": "#b9a58c", "home": "#c9a175", "accent": "#c0392b",
}

rng = random.Random(2026)


def pol(r, deg, c=(0.0, 0.0)):
	a = math.radians(deg)
	return (c[0] + r * math.cos(a), c[1] + r * math.sin(a))


class Svg:
	def __init__(self, w, h):
		self.w, self.h, self.parts = w, h, []

	def add(self, s):
		self.parts.append(s)

	def text(self, x, y, s, size=13, fill=COL["ink"], anchor="start", weight="normal", halo=True):
		h = ' stroke="%s" stroke-width="3" stroke-opacity="0.85" paint-order="stroke" stroke-linejoin="round"' % (
			COL["ink"] if fill in ("#fff", "#ffffff") else COL["paper"]) if halo else ""
		self.add('<text x="%.1f" y="%.1f" font-size="%s" fill="%s" text-anchor="%s" font-weight="%s"%s>%s</text>'
			% (x, y, size, fill, anchor, weight, h, s))

	def circle(self, c, r, fill, stroke="none", sw=1.0, extra=""):
		self.add('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="%s" stroke="%s" stroke-width="%.1f"%s/>'
			% (c[0], c[1], r, fill, stroke, sw, extra))

	def poly(self, pts, fill, stroke="none", sw=1.0, extra=""):
		self.add('<polygon points="%s" fill="%s" stroke="%s" stroke-width="%.1f"%s/>'
			% (" ".join("%.1f,%.1f" % p for p in pts), fill, stroke, sw, extra))

	def line(self, a, b, col, w, extra=""):
		self.add('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="%.1f"%s/>'
			% (a + b + (col, w, extra)))

	def rect(self, x, y, w, h, fill, extra=""):
		self.add('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s"%s/>' % (x, y, w, h, fill, extra))

	def done(self):
		return ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d" '
			'font-family="Helvetica, Arial, sans-serif">\n' % (self.w, self.h, self.w, self.h)
			+ "\n".join(self.parts) + "\n</svg>\n")


class View:
	"""Maps metres (x, z) into a panel of the SVG, with its own origin and scale."""
	def __init__(self, ox, oy, scale):
		self.ox, self.oy, self.s = ox, oy, scale

	def p(self, x, z):
		return (self.ox + x * self.s, self.oy + z * self.s)


def sector(v, c, r0, r1, a0, a1, steps=None):
	steps = steps or max(4, int(abs(a1 - a0) / 4))
	pts = [v.p(*pol(r1, a0 + (a1 - a0) * i / steps, c)) for i in range(steps + 1)]
	pts += [v.p(*pol(r0, a1 - (a1 - a0) * i / steps, c)) for i in range(steps + 1)]
	return pts


def panel(svg, x, y, w, h, title, sub=""):
	svg.rect(x, y, w, h, COL["paper"], ' stroke="%s" stroke-width="1" rx="6"' % COL["hall"])
	svg.text(x + 12, y + 22, title, size=14, weight="bold")
	if sub:
		svg.text(x + 12, y + 38, sub, size=10, fill=COL["muted"])


# ------------------------------------------------------------------ floor plans

def floor_shell(svg, v, c, r_out, bridge_axis, spokes=True, rooms=True):
	"""Glass wall, hallway, room ring, gallery, open shaft, lift, two bridges."""
	s = v.s
	cc = v.p(*c)
	svg.circle(cc, r_out * s, COL["hall"], COL["glass"], 3.0)
	if rooms:
		svg.circle(cc, (r_out - HALL_W) * s, COL["room"], COL["ink"], 0.6)
	svg.circle(cc, (SHAFT_R + GALLERY_W) * s, COL["gallery"], COL["ink"], 0.6)
	svg.circle(cc, SHAFT_R * s, COL["space"])
	angles = (-90, 90) if bridge_axis == "ns" else (0, 180)
	if spokes and rooms:
		for a in angles:
			half = math.degrees(SPOKE_W / 2 / ((SHAFT_R + r_out) / 2))
			svg.poly(sector(v, c, SHAFT_R + GALLERY_W - 0.5, r_out - HALL_W + 0.5, a - half, a + half, 2), COL["spoke"])
	for a in angles:
		d = (math.cos(math.radians(a)), math.sin(math.radians(a)))
		n = (-d[1], d[0])
		p0 = (c[0] + d[0] * LIFT_R, c[1] + d[1] * LIFT_R)
		p1 = (c[0] + d[0] * SHAFT_R, c[1] + d[1] * SHAFT_R)
		hw = BRIDGE_W / 2
		svg.poly([v.p(p0[0] + n[0] * hw, p0[1] + n[1] * hw), v.p(p1[0] + n[0] * hw, p1[1] + n[1] * hw),
			v.p(p1[0] - n[0] * hw, p1[1] - n[1] * hw), v.p(p0[0] - n[0] * hw, p0[1] - n[1] * hw)], COL["bridge"])
	svg.circle(cc, LIFT_R * s, COL["lift"], COL["ink"], 1.0)
	return angles


def room(svg, v, c, r0, r1, a0, a1, fill, label="", lsize=10, lcol="#fff"):
	svg.poly(sector(v, c, r0, r1, a0, a1), fill, COL["ink"], 0.8)
	if label:
		m = v.p(*pol((r0 + r1) / 2, (a0 + a1) / 2, c))
		for i, ln in enumerate(label.split("\n")):
			svg.text(m[0], m[1] + 4 + i * (lsize + 2) - (label.count("\n") * (lsize + 2)) / 2, ln,
				size=lsize, anchor="middle", fill=lcol, weight="bold")


def npc_dots(svg, v, c, r0, r1, a0, a1, n):
	for _ in range(n):
		p = v.p(*pol(rng.uniform(r0 + 2, r1 - 2), rng.uniform(a0 + 1.5, a1 - 1.5), c))
		svg.circle(p, 2.4, COL["npc"], "#fff", 0.6)


def tunnel_stub(svg, v, c, r_out, a, label, length=14.0):
	d = (math.cos(math.radians(a)), math.sin(math.radians(a)))
	n = (-d[1], d[0])
	p0 = (c[0] + d[0] * (r_out - 1), c[1] + d[1] * (r_out - 1))
	p1 = (c[0] + d[0] * (r_out + length), c[1] + d[1] * (r_out + length))
	hw = 3.5
	svg.poly([v.p(p0[0] + n[0] * hw, p0[1] + n[1] * hw), v.p(p1[0] + n[0] * hw, p1[1] + n[1] * hw),
		v.p(p1[0] - n[0] * hw, p1[1] - n[1] * hw), v.p(p0[0] - n[0] * hw, p0[1] - n[1] * hw)],
		COL["tunnel"], COL["ink"], 0.6)
	t = v.p(*(c[0] + d[0] * (r_out + length + 3), c[1] + d[1] * (r_out + length + 3)))
	anchor = "start" if d[0] > 0.3 else ("end" if d[0] < -0.3 else "middle")
	svg.text(t[0], t[1] + (4 if abs(d[1]) < 0.5 else (12 if d[1] > 0 else -4)), label, size=9, anchor=anchor, fill=COL["muted"])


def homes_floor(svg, v, c, r_out, axis):
	angles = floor_shell(svg, v, c, r_out, axis)
	r0, r1 = SHAFT_R + GALLERY_W, r_out - HALL_W
	spoke_half = math.degrees(SPOKE_W / 2 / ((SHAFT_R + r_out) / 2)) + 0.5
	# 25 homes round the ring, skipping the two spokes
	start = angles[0] + spoke_half
	span = 180 - 2 * spoke_half
	per_half = [13, 12]
	open_idx = {1, 4, 8, 11, 14, 17, 20, 23}
	k = 0
	for h, n in enumerate(per_half):
		a_start = start + h * 180
		w = span / n
		for i in range(n):
			a0, a1 = a_start + i * w, a_start + (i + 1) * w
			is_open = k in open_idx
			svg.poly(sector(v, c, r0, r1, a0 + 0.3, a1 - 0.3, 3), COL["open"] if is_open else COL["closed"], COL["ink"], 0.6)
			# door on the hallway side
			dm = v.p(*pol(r1, (a0 + a1) / 2, c))
			svg.circle(dm, 1.8, COL["ink"])
			if is_open:
				# bed (outer, by the window), kitchen (side), lounge (middle)
				for rr, col in ((r1 - 6, "#f6efe3"), ((r0 + r1) / 2, "#c58b4e"), (r0 + 6, "#8a5a3a")):
					svg.circle(v.p(*pol(rr, (a0 + a1) / 2, c)), 2.0, col)
				npc_dots(svg, v, c, r0 + 4, r1 - 4, a0 + 1, a1 - 1, 2 + (k % 2))
			k += 1
	# hallway walkers
	npc_dots(svg, v, c, r_out - HALL_W, r_out, 0, 360, 5)


def floor_label(svg, v, c, r_out, text, sub):
	t = v.p(c[0], c[1] - r_out - 9)
	svg.text(t[0], t[1], text, size=12, anchor="middle", weight="bold")
	if sub:
		svg.text(t[0], t[1] + 12, sub, size=9, anchor="middle", fill=COL["muted"])


def main_top(svg, v, c):
	r_out = MAIN_RS[3]
	floor_shell(svg, v, c, r_out, "ns")
	r0, r1 = SHAFT_R + GALLERY_W, r_out - HALL_W
	room(svg, v, c, r0, r1, -84, 34, COL["cantina"], "CANTINA\nbar, stage,\nbooths")
	room(svg, v, c, r0, r1, 37, 86, "#8796a1", "stores", 9)
	room(svg, v, c, r0, r1, 94, 200, COL["barracks"], "BARRACKS\nbunks, lockers")
	room(svg, v, c, r0, r1, 203, 266, COL["bridge_room"], "BRIDGE\n(cruiser\ncontrol room)", 9)
	# great window on the bridge, bar in the cantina, general
	svg.poly(sector(v, c, r1 - 1.2, r1, 208, 261, 6), COL["glass"])
	g = v.p(*pol(r1 - 4, 234, c))
	svg.circle(g, 4.0, COL["remnant"], "#fff", 1.2)
	for a in (222, 246):
		svg.circle(v.p(*pol(r1 - 14, a, c)), 2.6, COL["remnant"], "#fff", 0.6)
	for a in range(120, 190, 14):
		svg.circle(v.p(*pol(r0 + 10, a, c)), 2.4, COL["remnant"], "#fff", 0.6)
	bar = sector(v, c, r0 + 3, r0 + 6, -60, 10, 8)
	svg.poly(bar, "#3a2f58")
	owner = v.p(*pol(r0 + 8, -25, c))
	svg.circle(owner, 3.4, COL["home"], COL["ink"], 1.0)
	npc_dots(svg, v, c, r0 + 10, r1 - 2, -78, 28, 9)
	tunnel_stub(svg, v, c, r_out, 0, "to tower 2 (homes)")
	floor_label(svg, v, c, r_out, "Floor 4 (top, biggest)", "N-S bridges · general + honour guard on the bridge")


def main_homes(svg, v, c):
	homes_floor(svg, v, c, MAIN_RS[2], "ew")
	tunnel_stub(svg, v, c, MAIN_RS[2], 0, "to tower 2 (outpost)")
	floor_label(svg, v, c, MAIN_RS[2], "Floor 3: homes", "E-W bridges · 25 homes, 8 open")


def market_floor(svg, v, c, r_out, axis, bay=False, n_huts=6):
	floor_shell(svg, v, c, r_out, axis, spokes=False, rooms=False)
	r0, r1 = SHAFT_R + GALLERY_W + 2, r_out - 3
	svg.poly(sector(v, c, SHAFT_R + GALLERY_W, r_out - 0.5, 0, 360, 72), "#f3e2c4")
	# metal huts first (bigger), then stalls round them
	placed = []
	for i in range(n_huts):
		a = i * 360 / n_huts + 25 + rng.uniform(-8, 8)
		r = r1 - 6
		x, z = pol(r, a, c)
		placed.append((x, z, 7.5))
		p = v.p(x, z)
		svg.add('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s" stroke="%s" stroke-width="0.8" transform="rotate(%.1f %.1f %.1f)"/>'
			% (p[0] - 3.5 * v.s, p[1] - 3 * v.s, 7 * v.s, 6 * v.s, COL["hut"], COL["ink"], a + 90, p[0], p[1]))
	tries = 0
	n = 0
	while n < 26 and tries < 3000:
		tries += 1
		a = rng.uniform(0, 360)
		r = rng.uniform(r0 + 2, r1 - 2)
		x, z = pol(r, a, c)
		if any(math.hypot(x - q[0], z - q[1]) < q[2] for q in placed):
			continue
		if any(abs(((a - t + 180) % 360) - 180) < 9 for t in (0, 180)):
			continue      # keep the tunnel mouths clear
		placed.append((x, z, 5.0))
		p = v.p(x, z)
		svg.add('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s" transform="rotate(%.1f %.1f %.1f)"/>'
			% (p[0] - 1.8 * v.s, p[1] - 1.1 * v.s, 3.6 * v.s, 2.2 * v.s, COL["stall"], a + 90, p[0], p[1]))
		n += 1
	npc_dots(svg, v, c, r0, r1, 0, 360, 14)


def main_markets(svg, v, c):
	market_floor(svg, v, c, MAIN_RS[1], "ns")
	tunnel_stub(svg, v, c, MAIN_RS[1], 0, "to tower 2 (markets)")
	tunnel_stub(svg, v, c, MAIN_RS[1], 180, "to the landing bay", 14)
	floor_label(svg, v, c, MAIN_RS[1], "Floor 2: markets", "N-S bridges · stalls + grey metal huts, no rooms")


def main_engines(svg, v, c):
	r_out = MAIN_RS[0]
	floor_shell(svg, v, c, r_out, "ew")
	r0, r1 = SHAFT_R + GALLERY_W, r_out - HALL_W
	room(svg, v, c, r0, r1, -84, 0, COL["engine"], "ENGINE\nROOM")
	reactor = v.p(*pol(r1 - 9, -20, c))
	svg.circle(reactor, 5 * v.s, COL["reactor"], "#fff", 1.0, ' opacity="0.9"')
	room(svg, v, c, r0, r1, 0 + 4, 84, "#76808a", "pumps,\npipes")
	room(svg, v, c, r0, r1, 96, 176, "#6a5a48", "CARGO\nHOLD\ncrates, droids")
	room(svg, v, c, r0, r1, 184, 266, "#4f5964", "workshop")
	# drop hatch to the wrecks, on the hallway at the south
	h = v.p(*pol(r_out - HALL_W / 2, 90, c))
	svg.circle(h, 4.2 * v.s, COL["hatch"], "#fff", 1.2)
	svg.text(h[0], h[1] + 4.2 * v.s + 11, "drop hatch to the wrecks", size=9, anchor="middle", fill=COL["hatch"], weight="bold")
	npc_dots(svg, v, c, r0 + 3, r1 - 3, 100, 170, 3)
	npc_dots(svg, v, c, r0 + 3, r1 - 3, -80, -5, 2)
	floor_label(svg, v, c, r_out, "Floor 1 (bottom, smallest): engines", "E-W bridges · no tunnel")


def t2_homes(svg, v, c):
	homes_floor(svg, v, c, T2_RS[3], "ew")
	tunnel_stub(svg, v, c, T2_RS[3], 180, "to main (top)")
	floor_label(svg, v, c, T2_RS[3], "Floor 4: homes", "E-W bridges · 25 homes, 8 open")


def t2_outpost(svg, v, c):
	T2_R = T2_RS[2]
	floor_shell(svg, v, c, T2_R, "ns")
	r0, r1 = SHAFT_R + GALLERY_W, T2_R - HALL_W
	room(svg, v, c, r0, r1, -84, -6, COL["outpost"], "COMMAND\nROOM", 9)
	room(svg, v, c, r0, r1, 6, 84, "#8a5a50", "armoury", 9)
	room(svg, v, c, r0, r1, 96, 176, COL["barracks"], "BUNKS", 9)
	room(svg, v, c, r0, r1, 184, 266, "#7a6a60", "holding\ncells", 9)
	# barricades in the hallway either side of the tunnel mouth
	for a in (168, 192):
		svg.poly(sector(v, c, r1 + 0.5, T2_R - 0.5, a - 1.5, a + 1.5, 2), COL["ink"])
	for a in list(range(-70, -10, 15)) + list(range(110, 170, 18)) + [175, 185]:
		svg.circle(v.p(*pol((r0 + r1) / 2 if a < 170 else T2_R - 3, a, c)), 2.6, COL["remnant"], "#fff", 0.6)
	tunnel_stub(svg, v, c, T2_R, 180, "to main (homes)")
	floor_label(svg, v, c, T2_R, "Floor 3: Remnant outpost", "N-S bridges · taken / retaken")


def t2_markets(svg, v, c):
	market_floor(svg, v, c, T2_RS[1], "ew", n_huts=5)
	tunnel_stub(svg, v, c, T2_RS[1], 180, "to main (markets)")
	floor_label(svg, v, c, T2_RS[1], "Floor 2: markets", "E-W bridges · stalls + grey metal huts")


# ------------------------------------------------------------------ side section

def space_backdrop(svg, x, y, w, h, rocks=55, keep_clear=None):
	svg.rect(x + 8, y + 46, w - 16, h - 54, COL["space"], ' rx="4"')
	for _ in range(int(w * h / 3800)):
		sx, sy = rng.uniform(x + 12, x + w - 12), rng.uniform(y + 50, y + h - 10)
		svg.circle((sx, sy), rng.choice([0.6, 0.8, 1.0]), "#cfd8e6", extra=' opacity="0.7"')
	for _ in range(rocks):
		sx, sy = rng.uniform(x + 14, x + w - 14), rng.uniform(y + 54, y + h - 14)
		if keep_clear and keep_clear[0] < sx < keep_clear[2] and keep_clear[1] < sy < keep_clear[3]:
			continue
		svg.circle((sx, sy), rng.uniform(1.5, 6), COL["rock"], extra=' opacity="0.8"')


def section(svg, x, y, w, h):
	"""The station from the south: both towers, the gaps between floors, the tunnels and the bay."""
	panel(svg, x, y, w, h, "Station side section, looking north",
		"Tall floors (~14 m), the top one biggest and each one below smaller. Open space (~12 m) between floors: the elevator crosses it in a glass tube. "
		"Tunnels join the towers at every level they share.")
	s = 2.05
	ox = x + 40 + (BAY_R - BAY_X) * s
	base = y + 368                # underside of floor 1 (engines)
	v = View(ox, base, s)
	def P(xm, ym):
		return v.p(xm, -ym)
	space_backdrop(svg, x, y, w, h, 40, (x + 20, y + 120, x + w - 20, y + h - 10))

	def box(x0, y0, x1, y1, fill, extra=""):
		a, b = P(x0, y0), P(x1, y1)
		svg.rect(a[0], b[1], b[0] - a[0], a[1] - b[1], fill, extra)

	def tower(cx, rs, labels, side, lift_level):
		levels = sorted(rs)
		# the glass tubes between floors
		for lv in levels[:-1]:
			y0, y1 = lv * LEVEL + STOREY, (lv + 1) * LEVEL
			box(cx - TUBE_R, y0, cx + TUBE_R, y1, "#9fd8ff", ' fill-opacity="0.18" stroke="%s" stroke-width="1.4"' % COL["glass"])
		for lv in levels:
			rr = rs[lv]
			y0 = lv * LEVEL
			box(cx - rr, y0, cx + rr, y0 + STOREY, "#aab3be", ' stroke="%s" stroke-width="2"' % COL["glass"])
			box(cx - rr + 1, y0 + 1.5, cx + rr - 1, y0 + STOREY - 1, "#8d97a3")       # the tall rooms
			box(cx - rr + 1, y0 + 4, cx + rr - 1, y0 + STOREY - 3, COL["glass"], ' fill-opacity="0.35"')  # big windows
			box(cx - SHAFT_R, y0, cx + SHAFT_R, y0 + STOREY, COL["space"])
			ns = (lv % 2 == 1) if cx == 0 else (lv % 2 == 0)
			bw = SHAFT_R if not ns else BRIDGE_W / 2
			box(cx - bw, y0 + 0.2, cx + bw, y0 + 1.4, COL["bridge"])
			lift_label = (side < 0 and lv == 1)          # clear of the bay tunnel
			t = P(cx + (rr + 3) * side, y0 + STOREY / 2 + (10 if lift_label else 0))
			svg.text(t[0], t[1] + 4, "%d: %s" % (lv + 1, labels[lv]), size=10, fill="#e6ebf2", halo=False,
				anchor="start" if side > 0 else "end")
		top = P(cx, levels[-1] * LEVEL + STOREY)
		bot = P(cx, levels[0] * LEVEL)
		svg.line(top, bot, COL["lift"], 1.4, ' stroke-dasharray="4 3"')
		# the elevator caught between floors: in the space tunnel
		ly = lift_level * LEVEL + STOREY + GAP * 0.45
		lp = P(cx, ly)
		svg.rect(lp[0] - LIFT_R * s, lp[1] - 2, 2 * LIFT_R * s, 4, COL["lift"])
		for k in range(2):
			svg.circle((lp[0] - 4 + 8 * k, lp[1] - 7), 2.8, COL["npc"], "#fff", 0.6)
		capc = P(cx, levels[-1] * LEVEL + STOREY)
		r = rs[levels[-1]]
		svg.add('<path d="M %.1f %.1f A %.1f %.1f 0 0 1 %.1f %.1f" fill="#9fd8ff" fill-opacity="0.15" stroke="%s" stroke-width="1.4"/>'
			% (capc[0] - r * 0.8 * s, capc[1], r * 0.8 * s, 8 * s, capc[0] + r * 0.8 * s, capc[1], COL["glass"]))
		t = P(cx, levels[-1] * LEVEL + STOREY + 8)
		return t

	t = tower(0, MAIN_RS, {0: "engines", 1: "markets", 2: "homes", 3: "cantina, barracks, bridge"}, -1, 1)
	svg.text(t[0], t[1] - 6, "MAIN TOWER", size=12, anchor="middle", fill="#fff", weight="bold", halo=False)
	t = tower(T2_X, T2_RS, {1: "markets", 2: "outpost", 3: "homes"}, 1, 2)
	svg.text(t[0], t[1] - 6, "SECOND TOWER", size=12, anchor="middle", fill="#fff", weight="bold", halo=False)
	lp = P(0, 1 * LEVEL + STOREY + GAP * 0.45)
	svg.text(lp[0] + 16, lp[1] + 4, "elevator in the space tunnel", size=9, fill=COL["lift"], halo=False)
	for lv in (1, 2, 3):
		box(MAIN_RS[lv], lv * LEVEL + 3, T2_X - T2_RS[lv], lv * LEVEL + 8, COL["tunnel"], ' stroke="%s" stroke-width="0.6"' % COL["ink"])
	t = P(T2_X / 2 + 8, 2 * LEVEL + STOREY + GAP / 2 - 1)
	svg.text(t[0], t[1], "tunnels at every shared level", size=10, anchor="middle", fill="#cfe3ef", halo=False)
	# landing bay: covered, as big as the port's pit, level with the main market floor, shield mouth to the west
	by = LEVEL
	box(BAY_X + BAY_R, by + 3, -MAIN_RS[1], by + 8, COL["tunnel"], ' stroke="%s" stroke-width="0.6"' % COL["ink"])
	t = P((BAY_X + BAY_R - MAIN_RS[1]) / 2, by + 10)
	svg.text(t[0], t[1], "bay tunnel", size=10, anchor="middle", fill="#cfe3ef", halo=False)
	box(BAY_X - BAY_R, by - 2, BAY_X + BAY_R, by + 24, "#5d6a75", ' stroke="%s" stroke-width="1.6"' % COL["glass"])
	box(BAY_X - BAY_R, by - 2, BAY_X + BAY_R, by, "#aab3be")
	svg.line(P(BAY_X - BAY_R, by - 2), P(BAY_X - BAY_R, by + 24), "#5ee0ff", 3.0)
	for sx_, col in ((BAY_X - 14, "#58646d"), (BAY_X + 16, "#6d7a84")):
		sp = P(sx_, by)
		svg.poly([(sp[0] - 20, sp[1]), (sp[0] + 20, sp[1]), (sp[0] + 10, sp[1] - 10), (sp[0] - 14, sp[1] - 10)], col)
	tp = P(BAY_X + 30, by)
	svg.circle((tp[0], tp[1] - 6), 3.4, "#c9cdd2", COL["ink"], 1.0)
	svg.text(tp[0], tp[1] - 13, "T-99", size=10, anchor="middle", fill="#fff", weight="bold", halo=False)
	t = P(BAY_X, by + 24)
	svg.text(t[0], t[1] - 8, "COVERED LANDING BAY", size=12, anchor="middle", fill="#fff", weight="bold", halo=False)
	t = P(BAY_X, by - 2)
	svg.text(t[0], t[1] + 15, "~76 m across, the port pit's size", size=10, anchor="middle", fill="#cfe3ef", halo=False)
	t = P(BAY_X - BAY_R - 2, by + 12)
	svg.text(t[0], t[1], "shield", size=10, anchor="end", fill="#5ee0ff", halo=False)
	# hatch down to the wrecks
	h0, h1 = P(0, 0), P(0, -12)
	svg.line(h0, h1, COL["hatch"], 2.0, ' stroke-dasharray="4 3"')
	svg.text(h1[0] + 6, h1[1] + 4, "drop hatch: ~35 m down to wreck 1 (panel below)", size=10, fill="#ff9a8a", halo=False)


def wrecks(svg, x, y, w, h):
	"""Under the station: three wrecks, staggered so each one's deck shows past the one above."""
	panel(svg, x, y, w, h, "Below the station: three wrecked cruisers in the belt",
		"Smaller scale than the station panel. The desert wreck's 600 m hull, staggered so each deck shows past the one above. "
		"Each lower one also sits a hull-width north (paler = further back), so it lies beside the one above, not under it. Jetpack drops ~35–40 m (1.8 s of fuel brakes a ~45 m fall). Same droids and prize crate on each.")
	s = 1.05
	ox = x + 60 + 300 * s
	top = y + 120
	v = View(ox, top, s)
	def P(xm, ym):
		return v.p(xm, -ym)
	space_backdrop(svg, x, y, w, h, 70, (x + 40, y + 80, x + 60 + 1000 * s, y + 380))
	# the station's underside for reference
	st_a, st_b = P(-MAIN_RS[0], 4), P(MAIN_RS[0], 0)
	svg.rect(st_a[0], st_a[1], st_b[0] - st_a[0], 6, "#aab3be")
	svg.text(st_a[0], st_a[1] - 6, "engine floor underside", size=10, fill="#e6ebf2", halo=False)
	rows = [(-300.0, -35.0, 0.0, "wreck 1: level", 1.0), (-60.0, -75.0, -3.0, "wreck 2: tilted, a hull-width north", 0.75), (190.0, -115.0, 3.5, "wreck 3: tilted, a hull-width further north", 0.55)]
	rows.reverse()
	for x0, tp, tilt, lbl, op in rows:
		cxm, cym = x0 + WRECK_L / 2, tp - WRECK_H / 2
		cx_, cy_ = P(cxm, cym)
		hw, hh = WRECK_L / 2 * s, WRECK_H / 2 * s
		pts = [(-hw, -hh), (hw * 0.93, -hh), (hw, -hh * 0.3), (hw, hh), (-hw * 0.9, hh), (-hw, hh * 0.2)]
		rot = math.radians(tilt)
		pts = [(cx_ + px * math.cos(rot) - py * math.sin(rot), cy_ + px * math.sin(rot) + py * math.cos(rot)) for px, py in pts]
		svg.poly(pts, COL["wreck"], "#3a352d", 1.2, ' fill-opacity="%.2f"' % op)
		svg.text(pts[0][0] + 10, pts[0][1] + 18, lbl, size=11, fill="#fff", weight="bold")
		crate = (pts[0][0] + (pts[1][0] - pts[0][0]) * 0.62, pts[0][1] + (pts[1][1] - pts[0][1]) * 0.62)
		svg.rect(crate[0] - 4, crate[1] - 8, 8, 7, COL["lift"], ' stroke="%s" stroke-width="0.6"' % COL["ink"])
		for k in range(3):
			d = (pts[0][0] + (pts[1][0] - pts[0][0]) * (0.18 + 0.2 * k), pts[0][1] + (pts[1][1] - pts[0][1]) * (0.18 + 0.2 * k))
			svg.circle((d[0], d[1] - 4), 3.0, "#d0d4d8", COL["remnant"], 1.2)
	h0, h1 = P(0, 0), P(0, -35)
	svg.line(h0, h1, COL["hatch"], 2.0, ' stroke-dasharray="4 3"')
	svg.text(h0[0] + 6, (h0[1] + h1[1]) / 2 + 4, "hatch drop", size=10, fill="#ff9a8a", halo=False)
	sp0, sp1 = P(-330, 40), P(-200, -33)
	svg.line(sp0, sp1, "#9fd8ff", 1.6, ' stroke-dasharray="6 3"')
	svg.text(sp0[0] - 4, sp0[1] - 4, "or fly down and land on wreck 1", size=10, anchor="start", fill="#9fd8ff", halo=False)
	for (xa, ya), (xb, yb) in (((300, -35), (335, -75)), ((540, -75), (575, -115))):
		a, b = P(xa, ya), P(xb, yb)
		svg.line(a, b, "#ffd34d", 1.6, ' stroke-dasharray="3 3"')
		svg.text(b[0] + 8, (a[1] + b[1]) / 2 + 4, "jetpack down", size=10, fill="#ffd34d", halo=False)
	dz, dz2 = P(-330, -210), P(830, -210)
	svg.line(dz, dz2, COL["accent"], 1.6, ' stroke-dasharray="8 5"')
	svg.text(dz[0], dz[1] + 16, "fall past the last wreck: dead (the belt)", size=11, fill="#ff9a8a", weight="bold", halo=False)


# ------------------------------------------------------------------ space map

def space_map(svg, x, y, w, h):
	panel(svg, x, y, w, h, "Space map (schematic)",
		"Not to scale for distances. Giant ~1.2–1.4× the home planet.")
	svg.rect(x + 8, y + 46, w - 16, h - 54, COL["space"], ' rx="4"')
	cx, cy = x + w * 0.42, y + h * 0.56
	R = 70.0
	# ring belt: an annulus of rocks
	for _ in range(520):
		a = rng.uniform(0, 360)
		r = rng.uniform(R * 1.45, R * 2.25)
		px, py = cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a)) * 0.42
		svg.circle((px, py), rng.uniform(0.6, 1.8), COL["ring"], extra=' opacity="0.8"')
	# gas edge: fog shell with dense rocks, no wall
	svg.circle((cx, cy), R * 1.15, COL["gas"], extra=' opacity="0.25"')
	svg.circle((cx, cy), R, COL["gas"], COL["gas_dark"], 1.5)
	for _ in range(160):
		a = rng.uniform(0, 360)
		r = rng.uniform(R * 0.2, R * 1.12)
		svg.circle((cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a))), rng.uniform(0.8, 2.2), COL["gas_dark"])
	for i in range(4):
		svg.add('<ellipse cx="%.1f" cy="%.1f" rx="%.1f" ry="%.1f" fill="none" stroke="%s" stroke-width="2" opacity="0.5"/>'
			% (cx, cy - 30 + i * 20, R * math.sqrt(max(0.0, 1 - ((-30 + i * 20) / R) ** 2)), 3, COL["gas_dark"]))
	svg.text(cx, cy - 4, "RINGED GIANT", size=11, anchor="middle", weight="bold")
	svg.text(cx, cy + 10, "fly in: gas fog + packed rocks", size=9, anchor="middle")
	svg.text(cx, cy + 21, "no wall, you crash and die", size=9, anchor="middle")
	# station in the ring
	st = (cx + R * 1.85, cy + 18)
	svg.circle(st, 6, COL["lift"], COL["ink"], 1.2)
	svg.text(st[0] + 9, st[1] + 4, "Nitrogen Belt City", size=11, weight="bold", fill="#fff")
	svg.text(st[0] + 9, st[1] + 17, "in the ring, wrecks below", size=9, fill="#cfd8e6", halo=False)
	# home planet and approach lane round the outside
	home = (x + w - 50, y + 80)
	svg.circle(home, 16, COL["home"], "#8a6a4c", 1.2)
	svg.text(home[0], home[1] + 30, "home planet", size=10, anchor="middle", fill="#fff")
	svg.text(home[0], home[1] + 42, "(the port)", size=9, anchor="middle", fill="#cfd8e6", halo=False)
	lane = "M %.1f %.1f C %.1f %.1f %.1f %.1f %.1f %.1f" % (home[0] - 14, home[1] + 8, home[0] - 30, home[1] + 120,
		st[0] + 60, st[1] - 30, st[0] + 7, st[1] - 3)
	svg.add('<path d="%s" fill="none" stroke="#9fd8ff" stroke-width="1.6" stroke-dasharray="6 4"/>' % lane)
	svg.text(home[0] - 40, home[1] + 105, "weave through", size=9, anchor="end", fill="#9fd8ff", halo=False)
	svg.text(home[0] - 40, home[1] + 117, "belt rocks", size=9, anchor="end", fill="#9fd8ff", halo=False)
	around = "M %.1f %.1f A %.1f %.1f 0 0 0 %.1f %.1f" % (cx + R * 1.3, cy - R * 0.9, R * 1.6, R * 1.6, cx - R * 1.3, cy - R * 0.9)
	svg.add('<path d="%s" fill="none" stroke="#b8f0b0" stroke-width="1.2" stroke-dasharray="2 4"/>' % around)
	svg.text(cx, cy - R * 1.62, "going round works: clear sky", size=9, anchor="middle", fill="#b8f0b0", halo=False)


# ------------------------------------------------------------------ legend

def legend(svg, x, y):
	items = [
		("circle", COL["lift"], "elevator platform (NPCs + player ride it)"),
		("rect", COL["bridge"], "bridge to the elevator (2 per floor, alternating N-S / E-W)"),
		("rect", COL["space"], "open gap in the middle"),
		("rect", COL["hall"], "outer hallway, glass outer wall (blue rim)"),
		("rect", COL["open"], "open home: bed, kitchen, lounge, 2–3 people"),
		("rect", COL["closed"], "closed home (door only)"),
		("rect", COL["stall"], "market stall"),
		("rect", COL["hut"], "small home hut, grey metal"),
		("rect", COL["tunnel"], "tunnel (between towers / to the bay)"),
		("circle", COL["npc"], "local (crowd ~80 on the station)"),
		("circle", COL["remnant"], "Remnant trooper / general"),
		("circle", COL["home"], "cantina owner (a desert local)"),
	]
	svg.text(x, y, "Key", size=12, weight="bold")
	for i, (kind, col, txt) in enumerate(items):
		yy = y + 18 + i * 17
		if kind == "circle":
			svg.circle((x + 7, yy - 4), 5, col, COL["ink"], 0.6)
		else:
			svg.rect(x + 1, yy - 10, 12, 11, col, ' stroke="%s" stroke-width="0.5"' % COL["ink"])
		svg.text(x + 20, yy, txt, size=10)


def main():
	W, H = 1800, 1900
	svg = Svg(W, H)
	svg.rect(0, 0, W, H, COL["bg"])
	svg.text(32, 44, "Nitrogen Belt City plan", size=26, weight="bold")
	svg.text(32, 66, "Sketch, not data: floors, rooms, bridges, tunnels and wrecks, and roughly how big. "
		"+X (right) is east, north is up. Every number is tunable in content data.", size=13, fill=COL["muted"])

	space_map(svg, 24, 84, 560, 470)
	section(svg, 596, 84, 1180, 470)
	wrecks(svg, 24, 570, 1752, 400)

	# Floor plans: one scale for every floor in both towers.
	s = 1.85
	py = 986
	panel(svg, 24, py, 1752, 400, "Main tower: 4 floors, top to bottom",
		"One scale for all floors: the top floor is the biggest, each one below smaller. Every floor: elevator in the open middle, 2 bridges to it, a gallery round the gap, rooms, then the outer hallway behind a glass wall.")
	for fn, xx in zip((main_top, main_homes, main_markets, main_engines), (254, 684, 1114, 1544)):
		fn(svg, View(xx, py + 215, s), (0.0, 0.0))

	py = 1402
	panel(svg, 24, py, 1290, 444, "Second tower: 3 floors, top to bottom",
		"Smaller than the main tower, and also shrinking downward. Its floors line up with the main tower's floors 4, 3 and 2, and a tunnel joins each pair.")
	for fn, xx in zip((t2_homes, t2_outpost, t2_markets), (254, 684, 1114)):
		fn(svg, View(xx, py + 225, s), (0.0, 0.0))

	svg.rect(1330, py, 446, 444, COL["paper"], ' stroke="%s" stroke-width="1" rx="6"' % COL["hall"])
	legend(svg, 1346, py + 28)
	sb = (1346, py + 252)
	svg.rect(sb[0], sb[1], 50 * s, 5, COL["ink"])
	svg.text(sb[0], sb[1] + 20, "50 m (floor plans)", size=10)
	svg.rect(1346, py + 284, 50 * 2.05, 5, COL["ink"])
	svg.text(1346, py + 304, "50 m (station section)", size=10)
	svg.rect(1346, py + 316, 100 * 1.05, 5, COL["ink"])
	svg.text(1346, py + 336, "100 m (wrecks)", size=10)
	for i, ln in enumerate(["Floors are counted from the bottom (1) up.",
			"Tunnels: main 4 to T2 homes, main 3 to T2 outpost,",
			"main 2 to T2 markets. The bay's tunnel leaves",
			"the main market floor to the west.",
			"",
			"Redraw: python3 docs/station/plan_nitrogen_belt.py"]):
		svg.text(1346, py + 358 + i * 14, ln, size=10, fill=COL["muted"])

	OUT.parent.mkdir(parents=True, exist_ok=True)
	OUT.write_text(svg.done())
	print("wrote", OUT.relative_to(ROOT))


if __name__ == "__main__":
	main()
