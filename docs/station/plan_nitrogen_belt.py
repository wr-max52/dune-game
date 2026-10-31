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
WALK_W = 7.0        # the inner walkway round the gap, where the bridges land; doors open off it
WALK_R = SHAFT_R + WALK_W
CORR_W = 5.0        # a corridor through the rooms ring, out to a tunnel
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
WRECK_H = 76.0      # its hull is 96 m wide and 76 m tall (HULL_RX, HULL_RY)
WRECK_STEP = 12     # each next wreck's top is this much lower: a jump + full tank peaks at ~17 m
WRECK_GAP = 4       # end-to-end gap at each joint

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

def floor_shell(svg, v, c, r_out, bridge_axis, rooms=True, corridors=()):
	"""Rooms ring with windows in the outer wall (glass rim), corridors out to tunnels,
	the inner walkway round the gap, the open gap, the lift and its two bridges."""
	s = v.s
	cc = v.p(*c)
	svg.circle(cc, r_out * s, COL["room"] if rooms else "#f3e2c4", COL["glass"], 4.0)
	for a in corridors:
		strip(svg, v, c, WALK_R - 1, r_out + 0.5, a, CORR_W, COL["hall"])
	svg.circle(cc, WALK_R * s, COL["hall"], COL["ink"] if rooms else "none", 0.6)
	svg.circle(cc, SHAFT_R * s, COL["space"])
	angles = (-90, 90) if bridge_axis == "ns" else (0, 180)
	for a in angles:
		strip(svg, v, c, LIFT_R, SHAFT_R, a, BRIDGE_W, COL["bridge"])
	svg.circle(cc, LIFT_R * s, COL["lift"], COL["ink"], 1.0)
	return angles


def strip(svg, v, c, r0, r1, a, width, fill, stroke="none"):
	d = (math.cos(math.radians(a)), math.sin(math.radians(a)))
	n = (-d[1], d[0])
	hw = width / 2
	p0 = (c[0] + d[0] * r0, c[1] + d[1] * r0)
	p1 = (c[0] + d[0] * r1, c[1] + d[1] * r1)
	svg.poly([v.p(p0[0] + n[0] * hw, p0[1] + n[1] * hw), v.p(p1[0] + n[0] * hw, p1[1] + n[1] * hw),
		v.p(p1[0] - n[0] * hw, p1[1] - n[1] * hw), v.p(p0[0] - n[0] * hw, p0[1] - n[1] * hw)], fill, stroke, 0.6)


def corridor_half_deg(r):
	"""Half the angle a corridor takes at radius r (plus a wall)."""
	return math.degrees((CORR_W / 2 + 1.0) / r)


def room(svg, v, c, r0, r1, a0, a1, fill, label="", lsize=10, lcol="#fff"):
	svg.poly(sector(v, c, r0, r1, a0, a1), fill, COL["ink"], 0.8)
	svg.poly(sector(v, c, r1 - 1.0, r1, a0 + 0.6, a1 - 0.6), COL["glass"])     # the window wall
	door = v.p(*pol(r0, (a0 + a1) / 2, c))
	svg.circle(door, 1.8, COL["ink"])
	if label:
		m = v.p(*pol((r0 + r1) / 2 + 2, (a0 + a1) / 2, c))
		for i, ln in enumerate(label.split("\n")):
			svg.text(m[0], m[1] + 4 + i * (lsize + 2) - (label.count("\n") * (lsize + 2)) / 2, ln,
				size=lsize, anchor="middle", fill=lcol, weight="bold")


def npc_dots(svg, v, c, r0, r1, a0, a1, n):
	for _ in range(n):
		p = v.p(*pol(rng.uniform(r0 + 2, r1 - 2), rng.uniform(a0 + 1.5, a1 - 1.5), c))
		svg.circle(p, 2.4, COL["npc"], "#fff", 0.6)


def tunnel_stub(svg, v, c, r_out, a, label, length=14.0):
	strip(svg, v, c, r_out - 0.5, r_out + length, a, 7.0, COL["tunnel"], COL["ink"])
	d = (math.cos(math.radians(a)), math.sin(math.radians(a)))
	t = v.p(*(c[0] + d[0] * (r_out + length + 3), c[1] + d[1] * (r_out + length + 3)))
	anchor = "start" if d[0] > 0.3 else ("end" if d[0] < -0.3 else "middle")
	svg.text(t[0], t[1] + (4 if abs(d[1]) < 0.5 else (12 if d[1] > 0 else -4)), label, size=9, anchor=anchor, fill=COL["muted"])


def homes_floor(svg, v, c, r_out, axis, corridor):
	floor_shell(svg, v, c, r_out, axis, corridors=(corridor,))
	r0, r1 = WALK_R, r_out
	half = corridor_half_deg(r0)
	a_start = corridor + half
	span = 360 - 2 * half
	w = span / HOMES
	open_idx = {1, 4, 7, 10, 13, 16, 19, 22}
	for k in range(HOMES):
		a0, a1 = a_start + k * w, a_start + (k + 1) * w
		is_open = k in open_idx
		svg.poly(sector(v, c, r0, r1, a0 + 0.3, a1 - 0.3, 3), COL["open"] if is_open else COL["closed"], COL["ink"], 0.6)
		svg.poly(sector(v, c, r1 - 1.0, r1, a0 + 0.8, a1 - 0.8, 2), COL["glass"])   # its window
		svg.circle(v.p(*pol(r0, (a0 + a1) / 2, c)), 1.8, COL["ink"])                 # door on the walkway
		if is_open:
			# bed by the window, kitchen in the middle, lounge by the door
			for rr, col in ((r1 - 6, "#f6efe3"), ((r0 + r1) / 2, "#c58b4e"), (r0 + 6, "#8a5a3a")):
				svg.circle(v.p(*pol(rr, (a0 + a1) / 2, c)), 2.0, col)
			npc_dots(svg, v, c, r0 + 4, r1 - 4, a0 + 1, a1 - 1, 2 + (k % 2))
	npc_dots(svg, v, c, SHAFT_R + 1, WALK_R + 1, 0, 360, 5)      # people on the walkway


def floor_label(svg, v, c, r_out, text, sub):
	t = v.p(c[0], c[1] - r_out - 9)
	svg.text(t[0], t[1], text, size=12, anchor="middle", weight="bold")
	if sub:
		svg.text(t[0], t[1] + 12, sub, size=9, anchor="middle", fill=COL["muted"])


def main_top(svg, v, c):
	r_out = MAIN_RS[3]
	floor_shell(svg, v, c, r_out, "ns", corridors=(0,))
	r0, r1 = WALK_R, r_out
	h = corridor_half_deg(r0)
	room(svg, v, c, r0, r1, h, 118, COL["cantina"], "CANTINA\nbar, stage,\nbooths")
	room(svg, v, c, r0, r1, 120, 215, COL["barracks"], "BARRACKS\nbunks, lockers")
	room(svg, v, c, r0, r1, 217, 292, COL["bridge_room"], "BRIDGE\n(cruiser\ncontrol room)", 9)
	room(svg, v, c, r0, r1, 294, 360 - h, "#8796a1", "stores", 9)
	g = v.p(*pol(r1 - 5, 254, c))
	svg.circle(g, 4.0, COL["remnant"], "#fff", 1.2)
	for a in (238, 270):
		svg.circle(v.p(*pol(r1 - 14, a, c)), 2.6, COL["remnant"], "#fff", 0.6)
	for a in range(135, 205, 14):
		svg.circle(v.p(*pol(r0 + 14, a, c)), 2.4, COL["remnant"], "#fff", 0.6)
	svg.poly(sector(v, c, r0 + 4, r0 + 7, 25, 95, 8), "#3a2f58")       # the bar
	owner = v.p(*pol(r0 + 9, 60, c))
	svg.circle(owner, 3.4, COL["home"], COL["ink"], 1.0)
	npc_dots(svg, v, c, r0 + 12, r1 - 3, 15, 112, 9)
	tunnel_stub(svg, v, c, r_out, 0, "to tower 2 (homes)")
	floor_label(svg, v, c, r_out, "Floor 4 (top, biggest)", "N-S bridges · general + honour guard on the bridge")


def main_homes(svg, v, c):
	homes_floor(svg, v, c, MAIN_RS[2], "ew", 0)
	tunnel_stub(svg, v, c, MAIN_RS[2], 0, "to tower 2 (outpost)")
	floor_label(svg, v, c, MAIN_RS[2], "Floor 3: homes", "E-W bridges · 25 homes, 8 open")


def market_floor(svg, v, c, r_out, axis, n_huts=6, mouths=(0, 180)):
	floor_shell(svg, v, c, r_out, axis, rooms=False)
	r0, r1 = WALK_R + 1, r_out - 3
	placed = []
	for i in range(n_huts):
		a = i * 360 / n_huts + 25 + rng.uniform(-8, 8)
		x, z = pol(r1 - 6, a, c)
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
		if any(abs(((a - t + 180) % 360) - 180) < 9 for t in mouths):
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
	r0, r1 = WALK_R, r_out
	room(svg, v, c, r0, r1, -90, -1, COL["engine"], "ENGINE\nROOM", 9)
	svg.circle(v.p(*pol(r1 - 8, -20, c)), 4 * v.s, COL["reactor"], "#fff", 1.0, ' opacity="0.9"')
	room(svg, v, c, r0, r1, 1, 89, "#6a5a48", "CARGO\nHOLD", 9)
	room(svg, v, c, r0, r1, 91, 179, "#76808a", "pumps,\npipes", 9)
	room(svg, v, c, r0, r1, 181, 269, "#4f5964", "workshop", 9)
	# drop hatch in the cargo hold's floor, straight down to wreck 1
	h = v.p(*pol(r1 - 6, 80, c))
	svg.circle(h, 3.2 * v.s, COL["hatch"], "#fff", 1.2)
	t = v.p(*pol(r_out + 4, 70, c))
	svg.text(t[0] + 4, t[1] + 8, "drop hatch to the wrecks", size=9, anchor="start", fill=COL["hatch"], weight="bold")
	npc_dots(svg, v, c, r0 + 3, r1 - 3, 10, 50, 2)
	npc_dots(svg, v, c, r0 + 3, r1 - 3, -80, -40, 2)
	floor_label(svg, v, c, r_out, "Floor 1 (bottom, smallest): engines", "E-W bridges · no tunnel")


def t2_homes(svg, v, c):
	homes_floor(svg, v, c, T2_RS[3], "ew", 180)
	tunnel_stub(svg, v, c, T2_RS[3], 180, "to main (top)")
	floor_label(svg, v, c, T2_RS[3], "Floor 4: homes", "E-W bridges · 25 homes, 8 open")


def t2_outpost(svg, v, c):
	r_out = T2_RS[2]
	floor_shell(svg, v, c, r_out, "ns", corridors=(180,))
	r0, r1 = WALK_R, r_out
	h = corridor_half_deg(r0)
	room(svg, v, c, r0, r1, -90, -2, COL["outpost"], "COMMAND\nROOM", 9)
	room(svg, v, c, r0, r1, 2, 88, "#8a5a50", "armoury", 9)
	room(svg, v, c, r0, r1, 92, 180 - h, COL["barracks"], "BUNKS", 9)
	room(svg, v, c, r0, r1, 180 + h, 268, "#7a6a60", "holding\ncells", 9)
	# barricade across the corridor from the tunnel, troopers behind it
	strip(svg, v, c, r_out - 12, r_out - 10.5, 180, CORR_W + 1, COL["ink"])
	strip(svg, v, c, r0 + 2, r0 + 3.5, 180, CORR_W + 1, COL["ink"])
	for a, r in ((-60, 30), (-30, 34), (40, 30), (120, 30), (150, 34), (176, 26), (184, 26), (200, 17)):
		svg.circle(v.p(*pol(r, a, c)), 2.6, COL["remnant"], "#fff", 0.6)
	tunnel_stub(svg, v, c, r_out, 180, "to main (homes)")
	floor_label(svg, v, c, r_out, "Floor 3: Remnant outpost", "N-S bridges · taken / retaken")


def t2_markets(svg, v, c):
	market_floor(svg, v, c, T2_RS[1], "ew", n_huts=5, mouths=(180,))
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
	svg.text(h1[0] + 6, h1[1] + 4, "drop hatch: 12 m down to wreck 1 (panel below)", size=10, fill="#ff9a8a", halo=False)


def wrecks(svg, x, y, w, h):
	"""Under the station: three wrecks end to end like stairs, each joint a jetpack hop up or down."""
	panel(svg, x, y, w, h, "Below the station: three wrecked cruisers in the belt",
		"The desert wreck's 600 m hull (about 96 m wide, 76 m tall), three of them end to end like stairs. Every joint: the next hull's top is %d m lower, "
		"across a %d m gap, so you can jetpack down AND back up (a jump plus a full tank peaks at ~17 m). Same droids and prize crate on each." % (WRECK_STEP, WRECK_GAP))
	s = 0.86
	ox = x + 40 + 300 * s
	top = y + 140                 # the engine floor's underside
	v = View(ox, top, s)
	def P(xm, ym):
		return v.p(xm, -ym)
	space_backdrop(svg, x, y, w, h, 70, (x + 30, y + 70, x + w - 30, y + 260))
	# the station's bottom floor, with the hatch
	a_, b_ = P(-MAIN_RS[0], 14), P(MAIN_RS[0], 0)
	svg.rect(a_[0], a_[1], b_[0] - a_[0], b_[1] - a_[1], "#aab3be", ' stroke="%s" stroke-width="1.2"' % COL["glass"])
	t = P(MAIN_RS[0] + 4, 7)
	svg.text(t[0], t[1] + 4, "engine floor (floor 1)", size=10, anchor="start", fill="#e6ebf2", halo=False)
	hulls = []
	x0, crown, slope = -300.0, -float(WRECK_STEP), 0.0
	for i, (lbl, sl) in enumerate((("wreck 1: level", 0.0), ("wreck 2: tilted", -0.021), ("wreck 3: tilted", 0.021))):
		if i:
			px0, pcrown, pslope = hulls[-1]
			x0 = px0 + WRECK_L + WRECK_GAP
			crown = pcrown + pslope * WRECK_L - WRECK_STEP
		hulls.append((x0, crown, sl))
		def H(u, hgt):
			return P(x0 + u, crown + sl * u + hgt)
		pts = [H(14, 0), H(WRECK_L - 6, 0), H(WRECK_L, -10), H(WRECK_L, -WRECK_H + 14), H(WRECK_L - 20, -WRECK_H),
			H(40, -WRECK_H), H(0, -WRECK_H * 0.45), H(0, -12)]
		svg.poly(pts, COL["wreck"], "#3a352d", 1.2)
		t = H(20, 0)
		svg.text(t[0], t[1] - 8, lbl, size=11, fill="#fff", weight="bold")
		c_ = H(WRECK_L * 0.62, 0)
		svg.rect(c_[0] - 4, c_[1] - 7, 8, 7, COL["lift"], ' stroke="%s" stroke-width="0.6"' % COL["ink"])
		for k in range(3):
			d = H(WRECK_L * (0.25 + 0.2 * k), 0)
			svg.circle((d[0], d[1] - 4), 3.0, "#d0d4d8", COL["remnant"], 1.2)
	# hatch hop and the joints
	h0, h1 = P(0, 0), P(0, -WRECK_STEP)
	svg.line(h0, h1, COL["hatch"], 2.0, ' stroke-dasharray="3 2"')
	t = P(-MAIN_RS[0], 30)
	svg.text(t[0], t[1], "drop hatch: %d m down to wreck 1, jetpack back up" % WRECK_STEP, size=10, fill="#ff9a8a", halo=False)
	for i in range(2):
		px0, pcrown, pslope = hulls[i]
		end = P(px0 + WRECK_L, pcrown + pslope * WRECK_L)
		svg.circle(end, 9, "none", COL["lift"], 1.4)
		svg.text(end[0], end[1] - 14, "joint %d: %d m step, %d m gap" % (i + 1, WRECK_STEP, WRECK_GAP), size=10, anchor="middle", fill=COL["lift"], halo=False)
	sp0, sp1 = P(-150, 70), P(-90, -WRECK_STEP)
	svg.line(sp0, sp1, "#9fd8ff", 1.6, ' stroke-dasharray="6 3"')
	svg.text(sp0[0] - 6, sp0[1] + 4, "or fly down and land on wreck 1", anchor="end", size=10, fill="#9fd8ff", halo=False)
	dz, dz2 = P(-300, -150), P(1510, -150)
	svg.line(dz, dz2, COL["accent"], 1.6, ' stroke-dasharray="8 5"')
	svg.text(dz[0], dz[1] + 16, "fall off any wreck into the belt: dead", size=11, fill="#ff9a8a", weight="bold", halo=False)

	# inset: one joint, close up
	ix, iy, iw, ih = x + 30, y + 288, 520, 172
	svg.rect(ix, iy, iw, ih, "#141823", ' stroke="%s" stroke-width="1" rx="4"' % COL["muted"])
	svg.text(ix + 10, iy + 18, "One joint, close up (any of the three, and the hatch)", size=11, fill="#fff", weight="bold", halo=False)
	sc = 6.0
	vi = View(ix + 250, iy + 50, sc)
	def Q(xm, ym):
		return vi.p(xm, -ym)
	# upper hull's end (left) and lower hull's start (right)
	ua, ub = Q(-30, 0), Q(0, -16)
	svg.rect(ua[0], ua[1], ub[0] - ua[0], ub[1] - ua[1], COL["wreck"], ' stroke="#3a352d"')
	la, lb = Q(WRECK_GAP, -WRECK_STEP), Q(WRECK_GAP + 30, -WRECK_STEP - 6)
	svg.rect(la[0], la[1], lb[0] - la[0], lb[1] - la[1], COL["wreck"], ' stroke="#3a352d"')
	# the hop up: jump, light the pack, rise, drift left, land
	path = "M %.1f %.1f C %.1f %.1f %.1f %.1f %.1f %.1f" % (Q(12, -WRECK_STEP) + Q(10, 6) + Q(-2, 8) + Q(-8, 0))
	svg.add('<path d="%s" fill="none" stroke="%s" stroke-width="2" stroke-dasharray="4 3"/>' % (path, COL["lift"]))
	pk = Q(2, 17 - WRECK_STEP)
	svg.line(Q(-30, 17 - WRECK_STEP), Q(WRECK_GAP + 30, 17 - WRECK_STEP), "#b8f0b0", 1.0, ' stroke-dasharray="2 3"')
	svg.text(Q(WRECK_GAP + 31, 17 - WRECK_STEP)[0], Q(0, 17 - WRECK_STEP)[1] + 4, "jetpack peak ~17 m", size=10, fill="#b8f0b0", halo=False)
	d0, d1 = Q(WRECK_GAP + 31, 0), Q(WRECK_GAP + 31, -WRECK_STEP)
	svg.line(d0, d1, "#fff", 1.2)
	svg.text(d0[0] + 6, (d0[1] + d1[1]) / 2 + 4, "%d m step (~5 m spare)" % WRECK_STEP, size=10, fill="#fff", halo=False)
	g0, g1 = Q(0, -WRECK_STEP + 3), Q(WRECK_GAP, -WRECK_STEP + 3)
	svg.line(g0, g1, "#fff", 1.6)
	t = Q(WRECK_GAP + 14, -WRECK_STEP + 3)
	svg.line(((g0[0] + g1[0]) / 2, g0[1]), (t[0] - 2, t[1] - 3), "#fff", 0.8)
	svg.text(t[0], t[1], "%d m gap" % WRECK_GAP, size=10, fill="#fff", halo=False)
	svg.text(ix + 10, iy + ih - 10, "jump 0.6 m, pack lights after 0.18 s, rises at up to 9 m/s for 1.8 s of fuel (content/core/items/jetpack.json)",
		size=9, fill="#cfd8e6", halo=False)


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
		("rect", COL["hall"], "inner walkway round the gap (doors open off it), corridors"),
		("rect", COL["glass"], "windows: the rooms' outer wall, facing space"),
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
	W, H = 1800, 1990
	svg = Svg(W, H)
	svg.rect(0, 0, W, H, COL["bg"])
	svg.text(32, 44, "Nitrogen Belt City plan", size=26, weight="bold")
	svg.text(32, 66, "Sketch, not data: floors, rooms, bridges, tunnels and wrecks, and roughly how big. "
		"+X (right) is east, north is up. Every number is tunable in content data.", size=13, fill=COL["muted"])

	space_map(svg, 24, 84, 560, 470)
	section(svg, 596, 84, 1180, 470)
	wrecks(svg, 24, 570, 1752, 470)

	# Floor plans: one scale for every floor in both towers.
	s = 1.85
	py = 1056
	panel(svg, 24, py, 1752, 400, "Main tower: 4 floors, top to bottom",
		"One scale for all floors: the top floor is the biggest, each one below smaller. Every floor: elevator in the open middle, 2 bridges to it, an inner walkway round the gap, then the rooms on the outside with big windows onto space.")
	for fn, xx in zip((main_top, main_homes, main_markets, main_engines), (254, 684, 1114, 1544)):
		fn(svg, View(xx, py + 215, s), (0.0, 0.0))

	py = 1472
	panel(svg, 24, py, 1290, 464, "Second tower: 3 floors, top to bottom",
		"Smaller than the main tower, and also shrinking downward. Its floors line up with the main tower's floors 4, 3 and 2, and a tunnel joins each pair.")
	for fn, xx in zip((t2_homes, t2_outpost, t2_markets), (254, 684, 1114)):
		fn(svg, View(xx, py + 225, s), (0.0, 0.0))

	svg.rect(1330, py, 446, 464, COL["paper"], ' stroke="%s" stroke-width="1" rx="6"' % COL["hall"])
	legend(svg, 1346, py + 28)
	sb = (1346, py + 282)
	svg.rect(sb[0], sb[1], 50 * s, 5, COL["ink"])
	svg.text(sb[0], sb[1] + 20, "50 m (floor plans)", size=10)
	svg.rect(1346, py + 312, 50 * 2.05, 5, COL["ink"])
	svg.text(1346, py + 332, "50 m (station section)", size=10)
	svg.rect(1346, py + 342, 100 * 0.86, 5, COL["ink"])
	svg.text(1346, py + 362, "100 m (wrecks)", size=10)
	for i, ln in enumerate(["Floors are counted from the bottom (1) up.",
			"Tunnels: main 4 to T2 homes, main 3 to T2 outpost,",
			"main 2 to T2 markets. The bay's tunnel leaves",
			"the main market floor to the west.",
			"",
			"Redraw: python3 docs/station/plan_nitrogen_belt.py"]):
		svg.text(1346, py + 386 + i * 13, ln, size=10, fill=COL["muted"])

	OUT.parent.mkdir(parents=True, exist_ok=True)
	OUT.write_text(svg.done())
	print("wrote", OUT.relative_to(ROOT))


if __name__ == "__main__":
	main()
