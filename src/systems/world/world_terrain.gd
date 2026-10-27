class_name WorldTerrain
extends RefCounted
## The ground under a flying ship (M14). Pure: a height in metres for any world
## (x, z). It does not shape the desert itself: inside the desert's extent it asks
## the town's DesertTerrain (the same height_at the sand mesh and the walkable
## collider use, so what you see is what you land on). Beyond that edge it is the
## planet: a level `skirt_height` that falls away on a sphere of `planet_radius`,
## so a high ship sees the horizon curve down. Settings: the "terrain" block of
## content/core/worlds/<id>.json.
##
## With no desert (the old town in the void, unit tests) the ground is flat at 0
## out to the edge.

var cfg: Dictionary = {}
var source: Callable             ## (x, z) -> height: DesertTerrain.height_at, or none
var extent := 6000.0             ## half-size of the desert; the planet beyond
var skirt_height := 0.0          ## the level the planet starts from at the edge
var planet_radius := 120000.0
var curve_from := 6000.0


func _init(terrain_cfg: Dictionary = {}, height_source: Callable = Callable(), desert_extent: float = -1.0) -> void:
	cfg = terrain_cfg
	source = height_source
	extent = desert_extent if desert_extent > 0.0 else float(terrain_cfg.get("extent", extent))
	skirt_height = float(terrain_cfg.get("skirt_height", skirt_height))
	planet_radius = float(terrain_cfg.get("planet_radius", planet_radius))
	curve_from = float(terrain_cfg.get("curve_from", extent))


## True inside the desert's square (where the sand mesh and collider exist).
func in_desert(x: float, z: float) -> bool:
	return absf(x) <= extent and absf(z) <= extent


## How far the curved surface has fallen below flat at horizontal distance d from
## the port.
func drop(d: float) -> float:
	if d <= curve_from:
		return 0.0
	var k := d - curve_from
	return k * k / (2.0 * planet_radius)


## The ground's height at (x, z), in world metres.
func height_at(x: float, z: float) -> float:
	return local_height(x, z) - drop(Vector2(x, z).length())


## Height before the planet's curve: the desert inside its extent, the skirt beyond.
func local_height(x: float, z: float) -> float:
	if not in_desert(x, z):
		return skirt_height
	return float(source.call(x, z)) if source.is_valid() else float(cfg.get("flat_height", 0.0))


## A world position's altitude above the curved sea level (what "space at 8 km"
## measures). Near the port this is just y.
func altitude(p: Vector3) -> float:
	return p.y + drop(Vector2(p.x, p.z).length())
