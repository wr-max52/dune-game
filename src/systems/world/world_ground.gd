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
var boxes: Array = []        ## { id, kind, min: Vector3, max: Vector3, ramp_axis, ramp_sign }
var columns: Array = []      ## { id, center: Vector3 (base), radius, top }  (mesas, spires)
var world: Dictionary = {}


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


func add_box(id: String, kind: String, mn: Vector3, mx: Vector3, rise: String = "") -> void:
	if SKIP_KINDS.has(kind):
		return
	boxes.append({ "id": id, "kind": kind, "min": mn, "max": mx, "rise": rise })


func _add_landmark(lm: Dictionary, content) -> void:
	var at := _v3(lm.get("at", [0, 0, 0]))
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
				add_box(str(lm.get("id", "")) + "/" + str(b.get("id", "")), "solid",
					Vector3(c.x - hx, base, c.z - hz), Vector3(c.x + hx, base + s.y, c.z + hz))


## The desert's mesas and hoodoos (content/look/desert_landforms.json, the data
## DesertLandforms builds them from), as columns a ship can hit or land on top of.
## Same skip rule as DesertLandforms: nothing within keep_out (grown by the data's
## margin), so the columns are exactly the rocks on screen. Sizes follow its meshes:
##   mesa   -- tapered cylinder r..0.8r, h tall, centred 0.42h above the ground
##   hoodoo -- column 0.55r..r, h tall, centred 0.45h up, capped by a 0.9r stone
func add_landforms(data: Dictionary, keep_out: Rect2) -> void:
	var clear := keep_out.grow(float(data.get("keep_out_margin", 25.0)))
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


## Somewhere a ship may set down: inside the desert (beyond it there is sand to
## see but nothing to walk on).
func landable(x: float, z: float) -> bool:
	return terrain == null or terrain.in_desert(x, z)


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
		var mn: Vector3 = b.min
		var mx: Vector3 = b.max
		if x < mn.x or x > mx.x or z < mn.z or z > mx.z:
			continue
		var top := box_top(b, x, z)
		if top <= limit and top > g:
			g = top
	for c in columns:
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
		if p.y - r * 0.5 >= mx.y:
			continue            # above it: that is landing, not hitting
		var q := Vector3(clampf(p.x, mn.x, mx.x), clampf(p.y, mn.y, mx.y), clampf(p.z, mn.z, mx.z))
		if q.distance_squared_to(p) <= r * r:
			return str(b.id)
	for c in columns:
		var cc: Vector3 = c.center
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
