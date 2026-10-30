class_name PlanetSphere
extends RefCounted
## The home planet as a real ball (issue #77). Pure and headless-testable.
##
## The port sits on top of the ball at the world origin; the centre is straight
## below it at (0, -radius, 0). Near the port nothing changes: the town stands on
## the plane tangent to the ball there (a flat plateau), so every town box, the pit
## and the gate keep their flat coordinates. Away from the port the ground follows
## the ball, all the way round, and "up" turns with it (`up_at`).
##
## Places on the ground are given in map coordinates (x, z): the direction from the
## port and the distance along the ground (an azimuthal-equidistant map). Near the
## port map and world coordinates agree to within centimetres; the landmarks and
## landforms in the data are map coordinates.
##
## One height function (`elevation`, metres above the bare ball along a direction)
## feeds everything: the sand you see, the collider you stand on, the ship's ground
## query. That is what makes the dunes you see the dunes you walk on.

## The planet in use (set by the town scene that builds it, cleared when it goes),
## or null on a flat world. Bodies read their "up" from it.
static var current: PlanetSphere = null

var radius := 5000.0
var center := Vector3(0, -5000.0, 0)
## The tangent plateau the town stands on: flat out to `flat_radius` (map metres),
## "up" eases from straight up to the ball's over `up_blend` beyond it.
var flat_radius := 350.0
var up_blend := 450.0

## Seat: the town's footprint (same meaning as DesertTerrain.configure_site).
var site_rect := Rect2()
var under_rect := Rect2()
var sinks: Array = []                ## [{ rect: Rect2, y: float }]
var flat_sites: Array = []           ## small level pads around remote landmarks
var pad_y := 0.0
var under_y := -0.12
var pad_margin := 30.0
var blend := 260.0
var dune_offset := 12.0
var sink_ramp := 3.0
const UNDER_INSET := 1.5

var _dune := FastNoiseLite.new()
var _warp := FastNoiseLite.new()
var _swell := FastNoiseLite.new()
var _small := FastNoiseLite.new()


func _init(r: float = 5000.0) -> void:
	set_radius(r)
	_dune.seed = 3
	_dune.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_dune.fractal_type = FastNoiseLite.FRACTAL_NONE
	_dune.frequency = 1.0
	_warp.seed = 9
	_warp.frequency = 1.0
	_swell.seed = 21
	_swell.frequency = 1.0
	_swell.fractal_octaves = 3
	_small.seed = 5
	_small.frequency = 1.0
	_small.fractal_octaves = 2


func set_radius(r: float) -> void:
	radius = r
	center = Vector3(0, -r, 0)


## Seat the town: see DesertTerrain.configure_site.
func configure_site(floor_rect: Rect2, walls_rect: Rect2, sunken: Array, floor_y: float = 0.0) -> void:
	site_rect = floor_rect
	under_rect = walls_rect
	pad_y = floor_y
	under_y = floor_y - 0.12
	sinks.clear()
	for s in sunken:
		sinks.append({ "rect": s.rect, "y": float(s.y) - 1.5 })


func configure_flat_sites(sites: Array) -> void:
	flat_sites = sites.duplicate(true)


# ---------------------------------------------------------------- map <-> ball

## Unit direction from the centre for map (x, z).
func map_dir(x: float, z: float) -> Vector3:
	var d := sqrt(x * x + z * z)
	if d < 0.0001:
		return Vector3.UP
	var th := d / radius
	var s := sin(th) / d
	return Vector3(x * s, cos(th), z * s)


## Map (x, z) for a direction from the centre (the far pole maps to a circle).
func dir_map(dir: Vector3) -> Vector2:
	var h := Vector2(dir.x, dir.z)
	var hl := h.length()
	if hl < 0.0000001:
		# The port, or the point straight through the planet from it (half way round).
		return Vector2.ZERO if dir.y > 0.0 else Vector2(PI * radius, 0.0)
	var th := atan2(hl, dir.y)
	return h / hl * th * radius


## Map coordinates for a planet-wide latitude/longitude feature. Latitude is
## relative to the port's +Y pole; longitude rotates around that axis.
func map_from_lat_lon(latitude_deg: float, longitude_deg: float) -> Vector2:
	var lat := deg_to_rad(latitude_deg)
	var lon := deg_to_rad(longitude_deg)
	var dir := Vector3(cos(lat) * sin(lon), sin(lat), -cos(lat) * cos(lon))
	return dir_map(dir)


## Map (x, z) of a world point (straight down onto the ball).
func world_to_map(p: Vector3) -> Vector2:
	return dir_map((p - center).normalized())


## The ground's world position at map (x, z).
func surface_at(x: float, z: float) -> Vector3:
	var dir := map_dir(x, z)
	return center + dir * (radius + elevation(dir))


## "Up" at a world point: straight up on the town's plateau, away from the centre
## out in the desert, eased in between so nothing tips over at a line.
func up_at(p: Vector3) -> Vector3:
	var radial := (p - center).normalized()
	var d := dir_map(radial).length()
	var t := smoothstep(flat_radius, flat_radius + up_blend, d)
	if t <= 0.0:
		return Vector3.UP
	if t >= 1.0:
		return radial
	return Vector3.UP.slerp(radial, t).normalized()


## The rotation that takes world up to `up_at(p)` (identity on the plateau).
func tilt_at(p: Vector3) -> Basis:
	return tilt_to(up_at(p))


static func tilt_to(up: Vector3) -> Basis:
	var axis := Vector3.UP.cross(up)
	var s := axis.length()
	if s < 0.000001:
		return Basis.IDENTITY
	return Basis(axis / s, atan2(s, Vector3.UP.dot(up)))


## A world point's height above the bare ball (what "altitude" means in flight).
func altitude(p: Vector3) -> float:
	return (p - center).length() - radius


## Height above the ground under p, measured along the ball's radius.
func height_above_ground(p: Vector3) -> float:
	var dir := (p - center).normalized()
	return (p - center).length() - radius - elevation(dir)


# ---------------------------------------------------------------- heights

## The ground's height above the bare ball along `dir` (unit). `grow` widens the
## dip under sunken floors (the collider asks for a little more than the mesh).
func elevation(dir: Vector3, grow: float = 2.0) -> float:
	var m := dir_map(dir)
	var p := dir * radius
	if not site_rect.has_area() or dir.y < 0.5:   # the town is never 60 degrees round
		return _apply_flat_sites(m.x, m.y, _dunes(p) - dune_offset)
	var d := _rect_dist(site_rect, m)
	var k := smoothstep(pad_margin, pad_margin + blend, d)
	var flat := 0.0
	if k < 1.0:
		flat = _plateau(dir) + _site_y(m.x, m.y, d, p, grow)
	if k <= 0.0:
		return _apply_flat_sites(m.x, m.y, flat)
	return _apply_flat_sites(m.x, m.y, lerpf(flat, _dunes(p) - dune_offset, k))


func _apply_flat_sites(x: float, z: float, base_height: float) -> float:
	var h := base_height
	var p := Vector2(x, z)
	for site in flat_sites:
		var rect: Rect2 = site.get("rect", Rect2())
		var distance := _rect_dist(rect, p)
		var blend_distance := maxf(0.1, float(site.get("blend", 8.0)))
		if distance >= blend_distance:
			continue
		var y := float(site.get("y", base_height))
		if site.has("plane_u"):
			# Level to the "up" bodies feel there (plane_u at plane_c), not to the
			# ball's radius: they part where up eases from the plateau's to the ball's.
			var pu: Vector3 = site.plane_u
			var du := map_dir(x, z).dot(pu)
			if du > 0.1:
				y = ((site.plane_c as Vector3) - center).dot(pu) / du - radius
		if distance <= 0.0:
			return y
		h = lerpf(y, h, smoothstep(0.0, blend_distance, distance))
	return h


## World y of the ground on the vertical line through world (x, z): what flat-world
## code (and the town's own tests) mean by "the height at x, z". Exact on the top
## half of the ball; past the rim there is no ground below and it says -INF.
func height_at(x: float, z: float, grow: float = 2.0) -> float:
	var hz := x * x + z * z
	if hz >= radius * radius:
		return -INF
	# The direction depends a little on the height: two fixed-point steps settle it.
	var y := sqrt(radius * radius - hz) - radius
	for i in 3:
		var dir := Vector3(x, y - center.y, z).normalized()
		var r := radius + elevation(dir, grow)
		if r * r <= hz:
			return -INF
		y = sqrt(r * r - hz) + center.y
	return y


## The tangent plane's height above the ball along dir (0 at the port).
func _plateau(dir: Vector3) -> float:
	return radius / maxf(dir.y, 0.05) - radius


## Near the town, in the tangent frame: the paving, the packed sand, the pit's dip.
func _site_y(x: float, z: float, d: float, p: Vector3, grow: float) -> float:
	var q := Vector2(x, z)
	var h: float
	if d <= 0.0 and under_rect.has_point(q):
		var inset := minf(minf(x - under_rect.position.x, under_rect.end.x - x),
			minf(z - under_rect.position.y, under_rect.end.y - z))
		h = lerpf(pad_y, under_y, clampf(inset / UNDER_INSET, 0.0, 1.0))
	else:
		h = pad_y + _small.get_noise_3d(p.x * 0.012, p.y * 0.012, p.z * 0.012) * 0.5 * smoothstep(4.0, pad_margin, d)
	for s in sinks:
		var r: Rect2 = s.rect.grow(grow)
		var sd := _rect_dist(r, q)
		if sd < sink_ramp:
			h = minf(h, lerpf(float(s.y), h, smoothstep(0.0, sink_ramp, sd)))
	return h


## The open dunes at a point on the ball (metres): long crested dunes, ridged
## noise stretched across the wind, on a slow swell. 3D noise, so they wrap the
## whole ball with no seam.
func _dunes(p: Vector3) -> float:
	var f := 0.0016
	var wx := p.x + _warp.get_noise_3d(p.x * f, p.y * f, p.z * f) * 140.0
	var wy := p.y + _warp.get_noise_3d(p.y * f + 40.0, p.z * f, p.x * f) * 140.0
	var wz := p.z + _warp.get_noise_3d(p.z * f, p.x * f + 40.0, p.y * f) * 140.0
	var ridge := 1.0 - absf(_dune.get_noise_3d(wx * 0.0021, wy * 0.0042, wz * 0.0042))
	var h := pow(ridge, 2.6) * 26.0
	h += _swell.get_noise_3d(p.x * 0.0006, p.y * 0.0006, p.z * 0.0006) * 24.0 + 10.0
	h += _small.get_noise_3d(p.x * 0.004, p.y * 0.004, p.z * 0.004) * 0.65
	return h


static func _rect_dist(r: Rect2, p: Vector2) -> float:
	var dx := maxf(maxf(r.position.x - p.x, p.x - r.end.x), 0.0)
	var dz := maxf(maxf(r.position.y - p.y, p.y - r.end.y), 0.0)
	return Vector2(dx, dz).length()


# ---------------------------------------------------------------- patches

## A square of ground laid on the plane tangent to the ball at map (cx, cz):
## `cells` x `cells` cells of `step` metres. Returns { xform: Transform3D (the
## plane's frame; local y = height off the plane), heights: PackedFloat32Array
## ((cells+1)^2, row-major, z rows), verts: PackedVector3Array (frame-local) }.
## Heights are what a HeightMapShape3D needs; verts are the same points for a
## mesh. Thread-safe (reads only).
func patch(cx: float, cz: float, cells: int, step: float, grow: float = 2.0) -> Dictionary:
	var p := patch_rows(cx, cz, cells, step, grow, 0, cells + 1)
	p.xform = patch_frame(cx, cz)
	return p


## Rows j0..j1-1 of patch(): { heights, verts } for just those rows, so a caller
## can build a patch a few rows at a time.
func patch_rows(cx: float, cz: float, cells: int, step: float, grow: float, j0: int, j1: int) -> Dictionary:
	var xf := patch_frame(cx, cz)
	var n := cells + 1
	var half := cells * step * 0.5
	var heights := PackedFloat32Array()
	heights.resize((j1 - j0) * n)
	var verts := PackedVector3Array()
	verts.resize((j1 - j0) * n)
	var bx := xf.basis.x
	var by := xf.basis.y
	var bz := xf.basis.z
	var o := xf.origin
	for j in range(j0, j1):
		var v := -half + j * step
		for i in n:
			var u := -half + i * step
			# The ground on the plane's own normal through (u, v), so the point sits
			# exactly on the grid (mesh and collider share it): solve
			# |q + by h| = R + elevation for h, then once more with the new direction.
			var q := o + bx * u + bz * v - center
			var h := 0.0
			for k in 2:
				var r := radius + elevation((q + by * h).normalized(), grow)
				var qb := q.dot(by)
				h = -qb + sqrt(maxf(qb * qb - q.length_squared() + r * r, 0.0))
			heights[(j - j0) * n + i] = h
			verts[(j - j0) * n + i] = Vector3(u, h, v)
	return { "heights": heights, "verts": verts }


## The frame of the plane tangent to the ball at map (cx, cz): origin on the bare
## ball, y = the ball's up there, x and z as close to the map's as the ball allows.
func patch_frame(cx: float, cz: float) -> Transform3D:
	var dir := map_dir(cx, cz)
	var b := tilt_to(dir)
	return Transform3D(b, center + dir * radius)
