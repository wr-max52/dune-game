class_name WorldGround
extends RefCounted
## What a ship can land on or fly into (M14). Pure and headless-testable: the
## terrain, the town's boxes (floors, roofs, walls, ramps) and the world's
## landmarks (mesas, spires, the outpost's buildings), all from data. The flight
## model asks it two questions every frame:
##
##   ground_at(x, z, below)  -- the highest surface under (x, z) at or below `below`
##                              (so a ship over a roof lands on the roof, a ship
##                              under the gate lintel lands on the street)
##   hit(p, r)               -- the first solid thing a sphere at p touches, or ""
##
## No physics engine involved, so the dogfight-style pure flight model can fly
## through the town in a headless trace exactly as in the game.

const FLOOR_KINDS := ["floor"]
## Box kinds that are not part of the world a ship flies through: the "ship" box
## in the town data is the parked ship itself; the "bowl" is the round pit's
## hollow shell (its square box would be a lid over the pit).
const SKIP_KINDS := ["ship", "bowl"]

var terrain: WorldTerrain
var boxes: Array = []        ## { id, kind, min: Vector3, max: Vector3, ramp_axis, ramp_sign, xf? }
var columns: Array = []      ## { id, center: Vector3 (base), radius, top, up?, h? }  (mesas, spires)
## Issue #77: on the home planet's ball, a box away from the town may lean with the
## ground: "xf" (Transform3D) is its own frame and min/max are in it. A column may
## too: "up" is its axis and "h" its height above its base. Town boxes and every
## box on a flat world have neither and are plain world-space boxes.
var world: Dictionary = {}
## Issue #93: the desert's boulders ({ center, up, radius, height }, from
## DesertLandforms). Each is a smooth hump of ground (wider than the rock: sand
## banks against it), so a speeder rides up a low one and launches off it; one
## taller than RAMP_MAX is also a wall a speeder or ship hits.
var boulders: Array = []
const RAMP_MAX := 3.0
const RAMP_SPREAD := 1.6


func add_boulders(list: Array) -> void:
	boulders.append_array(list)


## A boulder's hump: its height above its centre at `off` metres from its axis.
static func boulder_top(b: Dictionary, off: float) -> float:
	var r := float(b.radius) * RAMP_SPREAD
	if off >= r:
		return -INF
	return float(b.height) * (0.5 + 0.5 * cos(PI * off / r))


## Build from a world entry (content/core/worlds/*.json), the town it holds and
## the content (for location landmarks such as the outpost). Any part may be empty.
## `height_source` / `desert_extent`: the town's DesertTerrain.height_at and its
## extent, when the desert is on (see WorldTerrain).
func setup(world_cfg: Dictionary, town = null, content = null,
		height_source: Callable = Callable(), desert_extent: float = -1.0) -> void:
	world = world_cfg
	terrain = WorldTerrain.new(world_cfg.get("terrain", {}), height_source, desert_extent)
	boxes = []
	columns = []
	if town != null:
		for b in town.boxes():
			add_box(str(b.id), str(b.kind), _v3(b.min), _v3(b.max), str(b.get("rise_toward", "")))
	for lm in world_cfg.get("landmarks", []):
		_add_landmark(lm, content)


func add_box(id: String, kind: String, mn: Vector3, mx: Vector3, rise: String = "", visual: bool = true,
		xf = null) -> void:
	if SKIP_KINDS.has(kind):
		return
	var b := { "id": id, "kind": kind, "min": mn, "max": mx, "rise": rise, "visual": visual }
	if xf is Transform3D and xf != Transform3D.IDENTITY:
		b.xf = xf
	boxes.append(b)


## The planet's ball, or null on a flat world.
func sphere() -> PlanetSphere:
	return terrain.sphere if terrain != null else null


## "Up" at p: the ground's on the home planet's ball, straight up elsewhere.
func up_at(p: Vector3) -> Vector3:
	var sp := sphere()
	return sp.up_at(p) if sp != null else Vector3.UP


## A box's own frame (identity for a plain world-space box).
static func box_xf(b: Dictionary) -> Transform3D:
	return b.get("xf", Transform3D.IDENTITY)


## How high p is over the highest surface beneath it (along up_at(p)): the sand,
## a roof, a mesa's top. Surfaces up to 0.5 m above p count (a step up), as in
## ground_at. Negative when p is under the ground.
func height_above(p: Vector3) -> float:
	var sp := sphere()
	if sp == null:
		return p.y - ground_at(p.x, p.z, p.y)
	var h := sp.height_above_ground(p)
	for b in boxes:
		var lp: Vector3 = box_xf(b).affine_inverse() * p
		var mn: Vector3 = b.min
		var mx: Vector3 = b.max
		if lp.x < mn.x or lp.x > mx.x or lp.z < mn.z or lp.z > mx.z:
			continue
		var top := box_top(b, lp.x, lp.z)
		if top <= lp.y + 0.5:
			h = minf(h, lp.y - top)
	for c in columns:
		var up: Vector3 = c.get("up", Vector3.UP)
		var rel: Vector3 = p - (c.center as Vector3)
		var along := rel.dot(up)
		if (rel - up * along).length() > float(c.radius):
			continue
		var top: float = c.get("h", float(c.top) - (c.center as Vector3).y)
		if top <= along + 0.5:
			h = minf(h, along - top)
	for bd in boulders:
		var bu: Vector3 = bd.up
		var rel: Vector3 = p - (bd.center as Vector3)
		if rel.length_squared() > pow(float(bd.radius) * RAMP_SPREAD + float(bd.height) + 50.0, 2.0):
			continue
		var along := rel.dot(bu)
		var bt := boulder_top(bd, (rel - bu * along).length())
		if bt > -INF and bt <= along + 0.5:
			h = minf(h, along - bt)
	return h


## The ground point under p along up_at(p).
func surface_below(p: Vector3) -> Vector3:
	return p - up_at(p) * height_above(p)


func _add_landmark(lm: Dictionary, content) -> void:
	var at := _v3(lm.get("at", [0, 0, 0]))
	if sphere() != null:
		_add_landmark_on_ball(lm, content, at)
		return
	var base := terrain.height_at(at.x, at.z)
	match str(lm.get("kind", "")):
		"mesa", "spire":
			columns.append({ "id": str(lm.get("id", "")), "kind": str(lm.kind),
				"center": Vector3(at.x, base, at.z), "radius": float(lm.get("radius", 100.0)),
				"top": base + float(lm.get("height", 100.0)) })
		"location":
			var loc: Dictionary = content.get_location(str(lm.get("location", ""))) if content != null else {}
			var yaw := deg_to_rad(float(lm.get("yaw_deg", 0.0)))
			for b in loc.get("buildings", []):
				var s := _v3(b.get("size", [4, 4, 4]))
				var p := _v3(b.get("position", [0, 0, 0])).rotated(Vector3.UP, yaw)
				var c := Vector3(at.x + p.x, base, at.z + p.z)
				# Axis-aligned footprint that covers the rotated building.
				var hx := (absf(cos(yaw)) * s.x + absf(sin(yaw)) * s.z) * 0.5
				var hz := (absf(sin(yaw)) * s.x + absf(cos(yaw)) * s.z) * 0.5
				# Issue #42: a building may be a ramp ("rise": the side its top slopes up
				# to, in the world frame; ramps are ground, not obstacles) and may skip
				# the placeholder box when something else dresses it ("visual": false).
				add_box(str(lm.get("id", "")) + "/" + str(b.get("id", "")), "solid",
					Vector3(c.x - hx, base, c.z - hz), Vector3(c.x + hx, base + s.y, c.z + hz),
					str(b.get("rise", "")), bool(b.get("visual", true)))


## Issue #77: a landmark at map (at.x, at.z) on the ball, standing along the ground's
## up there: buildings become boxes in its own frame (no footprint growth from the
## yaw), mesas and spires columns along its up.
func _add_landmark_on_ball(lm: Dictionary, content, at: Vector3) -> void:
	var sp := sphere()
	var base := sp.surface_at(at.x, at.z)
	var up := sp.up_at(base)
	var yaw := deg_to_rad(float(lm.get("yaw_deg", 0.0)))
	match str(lm.get("kind", "")):
		"mesa", "spire":
			var h := float(lm.get("height", 100.0))
			columns.append({ "id": str(lm.get("id", "")), "kind": str(lm.kind), "center": base,
				"radius": float(lm.get("radius", 100.0)), "up": up, "h": h, "top": base.y + h })
		"location":
			var loc: Dictionary = content.get_location(str(lm.get("location", ""))) if content != null else {}
			var xf := Transform3D(PlanetSphere.tilt_to(up) * Basis(Vector3.UP, yaw), base)
			for b in loc.get("buildings", []):
				var s := _v3(b.get("size", [4, 4, 4]))
				var c := _v3(b.get("position", [0, 0, 0]))
				# "rise" is in the world frame on a flat world; here the box's own frame
				# carries the yaw, so turn it back into the landmark's frame.
				add_box(str(lm.get("id", "")) + "/" + str(b.get("id", "")), "solid",
					Vector3(c.x - s.x * 0.5, 0.0, c.z - s.z * 0.5), Vector3(c.x + s.x * 0.5, s.y, c.z + s.z * 0.5),
					_rise_local(str(b.get("rise", "")), yaw), bool(b.get("visual", true)), xf)


## A world-frame ramp side ("+x", "-z", ...) as seen from a frame turned by yaw.
static func _rise_local(rise: String, yaw: float) -> String:
	if rise == "":
		return ""
	var dir := { "+x": Vector3.RIGHT, "-x": Vector3.LEFT, "+z": Vector3.BACK, "-z": Vector3.FORWARD }[rise] as Vector3
	var l := Basis(Vector3.UP, yaw).inverse() * dir
	if absf(l.x) >= absf(l.z):
		return "+x" if l.x > 0.0 else "-x"
	return "+z" if l.z > 0.0 else "-z"


## The desert's mesas and hoodoos (content/look/desert_landforms.json, the data
## DesertLandforms builds them from), as columns a ship can hit or land on top of.
## Same skip rule as DesertLandforms: nothing within keep_out (grown by the data's
## margin), so the columns are exactly the rocks on screen. Sizes follow its meshes:
##   mesa   -- tapered cylinder r..0.8r, h tall, centred 0.42h above the ground
##   hoodoo -- column 0.55r..r, h tall, centred 0.45h up, capped by a 0.9r stone
func add_landforms(data: Dictionary, keep_out: Rect2) -> void:
	var clear := keep_out.grow(float(data.get("keep_out_margin", 25.0)))
	if sphere() != null:
		_add_landforms_on_ball(data, clear)
		return
	for m in data.get("mesas", []):
		if not clear.grow(float(m[2])).has_point(Vector2(m[0], m[1])):
			var gy := terrain.height_at(m[0], m[1])
			columns.append({ "id": "mesa_%d_%d" % [int(m[0]), int(m[1])], "kind": "mesa",
				"center": Vector3(m[0], gy, m[1]), "radius": float(m[2]) * 0.9,
				"top": gy + float(m[3]) * 0.92 })
	for hd in data.get("hoodoos", []):
		if not clear.grow(float(hd[2])).has_point(Vector2(hd[0], hd[1])):
			var gy := terrain.height_at(hd[0], hd[1])
			columns.append({ "id": "hoodoo_%d_%d" % [int(hd[0]), int(hd[1])], "kind": "hoodoo",
				"center": Vector3(hd[0], gy, hd[1]), "radius": float(hd[2]) * 0.9,
				"top": gy + float(hd[3]) * 0.95 + float(hd[2]) * 0.4 })


## Issue #77: the same columns, standing along the ball's up at their map spot
## (where DesertLandforms puts them).
func _add_landforms_on_ball(data: Dictionary, clear: Rect2) -> void:
	var sp := sphere()
	for m in data.get("mesas", []):
		if not clear.grow(float(m[2])).has_point(Vector2(m[0], m[1])):
			var base := sp.surface_at(m[0], m[1])
			var h := float(m[3]) * 0.92
			columns.append({ "id": "mesa_%d_%d" % [int(m[0]), int(m[1])], "kind": "mesa", "center": base,
				"radius": float(m[2]) * 0.9, "up": sp.up_at(base), "h": h, "top": base.y + h })
	for hd in data.get("hoodoos", []):
		if not clear.grow(float(hd[2])).has_point(Vector2(hd[0], hd[1])):
			var base := sp.surface_at(hd[0], hd[1])
			var h := float(hd[3]) * 0.95 + float(hd[2]) * 0.4
			columns.append({ "id": "hoodoo_%d_%d" % [int(hd[0]), int(hd[1])], "kind": "hoodoo", "center": base,
				"radius": float(hd[2]) * 0.9, "up": sp.up_at(base), "h": h, "top": base.y + h })


## Somewhere a ship may set down: inside the desert (beyond it there is sand to
## see but nothing to walk on).
func landable(x: float, z: float) -> bool:
	if terrain == null or terrain.in_desert(x, z):
		return true
	# Issue #45: a platform town (no desert): only on its own floors and roofs.
	for b in boxes:
		var mn: Vector3 = b.min
		var mx: Vector3 = b.max
		if x >= mn.x and x <= mx.x and z >= mn.z and z <= mx.z and str(b.kind) in ["floor", "roof", "ship"]:
			return true
	return false


## The world's atmosphere settings (where space starts, etc.).
func atmosphere() -> Dictionary:
	return world.get("atmosphere", {})


func space_altitude() -> float:
	return float(atmosphere().get("space_altitude", 8000.0))


func altitude(p: Vector3) -> float:
	return terrain.altitude(p) if terrain != null else p.y


## Top of a box at (x, z) (ramps slope along their rise axis).
static func box_top(b: Dictionary, x: float, z: float) -> float:
	var mn: Vector3 = b.min
	var mx: Vector3 = b.max
	match str(b.get("rise", "")):
		"+x":
			return lerpf(mn.y, mx.y, clampf((x - mn.x) / maxf(mx.x - mn.x, 0.001), 0.0, 1.0))
		"-x":
			return lerpf(mx.y, mn.y, clampf((x - mn.x) / maxf(mx.x - mn.x, 0.001), 0.0, 1.0))
		"+z":
			return lerpf(mn.y, mx.y, clampf((z - mn.z) / maxf(mx.z - mn.z, 0.001), 0.0, 1.0))
		"-z":
			return lerpf(mx.y, mn.y, clampf((z - mn.z) / maxf(mx.z - mn.z, 0.001), 0.0, 1.0))
	return mx.y


## The highest surface under (x, z) whose top is at or below `below` (+0.5 m of
## step-up). Terrain, box tops and column tops all count.
func ground_at(x: float, z: float, below: float = INF) -> float:
	var g := terrain.height_at(x, z) if terrain != null else 0.0
	var limit := below + 0.5
	for b in boxes:
		if b.has("xf"):
			continue            # leans with the ball: height_above() asks it
		var mn: Vector3 = b.min
		var mx: Vector3 = b.max
		if x < mn.x or x > mx.x or z < mn.z or z > mx.z:
			continue
		var top := box_top(b, x, z)
		if top <= limit and top > g:
			g = top
	for bd in boulders:
		var bc: Vector3 = bd.center
		if (bd.up as Vector3) != Vector3.UP or absf(x - bc.x) > float(bd.radius) * RAMP_SPREAD \
				or absf(z - bc.z) > float(bd.radius) * RAMP_SPREAD:
			continue
		var bt := bc.y + boulder_top(bd, Vector2(x - bc.x, z - bc.z).length())
		if bt <= limit and bt > g:
			g = bt
	for c in columns:
		if c.has("up"):
			continue
		var cc: Vector3 = c.center
		if Vector2(x - cc.x, z - cc.z).length() <= float(c.radius):
			var top: float = c.top
			if top <= limit and top > g:
				g = top
	return g


## The first box or column a sphere touches, or "" when clear. Floors and ramps are
## ground, not obstacles (ground_at handles them), and so are surfaces the sphere's
## bottom is resting on from above.
func hit(p: Vector3, r: float) -> String:
	for b in boxes:
		if FLOOR_KINDS.has(b.kind) or str(b.get("rise", "")) != "":
			continue
		var mn: Vector3 = b.min
		var mx: Vector3 = b.max
		var lp: Vector3 = box_xf(b).affine_inverse() * p if b.has("xf") else p
		if lp.y - r * 0.5 >= mx.y:
			continue            # above it: that is landing, not hitting
		var q := Vector3(clampf(lp.x, mn.x, mx.x), clampf(lp.y, mn.y, mx.y), clampf(lp.z, mn.z, mx.z))
		if q.distance_squared_to(lp) <= r * r:
			return str(b.id)
	for bd in boulders:
		if float(bd.height) <= RAMP_MAX:
			continue                # low: a ramp, ridden over, not hit
		var bu: Vector3 = bd.up
		var rel: Vector3 = p - (bd.center as Vector3)
		var along := rel.dot(bu)
		if along - r * 0.5 >= float(bd.height) * 0.85 or along + r < 0.0:
			continue
		if (rel - bu * along).length() <= float(bd.radius) * 0.8 + r:
			return "boulder"
	for c in columns:
		var cc: Vector3 = c.center
		if c.has("up"):
			var up: Vector3 = c.up
			var rel := p - cc
			var along := rel.dot(up)
			if along - r * 0.5 >= float(c.h) or along + r < 0.0:
				continue
			if (rel - up * along).length() <= float(c.radius) + r:
				return str(c.id)
			continue
		if p.y - r * 0.5 >= float(c.top) or p.y + r < cc.y:
			continue
		if Vector2(p.x - cc.x, p.z - cc.z).length() <= float(c.radius) + r:
			return str(c.id)
	return ""


static func _v3(a) -> Vector3:
	if a is Vector3:
		return a
	if a is Array and a.size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO
