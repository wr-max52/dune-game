class_name PlanetGen
extends RefCounted
## The planet generator (issue #45). A planet is one small file,
## content/core/planets/<id>.json (name, type, town_size, style, where it hangs in
## a neighbour's sky); this turns it into everything the town scene builds:
##
##   town      -- the layout (TownGen at its town_size, or an authored location)
##   world     -- the world dict ShipPilot, the sky and the detail tiers read
##                (an authored world, or one made from the planet's type)
##   type_cfg  -- content/core/planets/types.json for its type: ground (terrain or
##                platform), sand and rock colours, the sea / lava / gas / rock under
##                a platform, sky colours, atmosphere, how it looks from space
##   style     -- the town style (TownStyle spec: a preset or words)
##   sky       -- values laid over every time-of-day preset
##   neighbours-- other planets in its sky you can fly to: { id, at, radius, color... }
##   cantina   -- who runs the cantina { card, look }
##
## Pure and cheap: no nodes. Town scenes ask for the current planet
## (GameFlow.planet()); tests can build any planet without a scene.

const CoreContent := preload("res://src/systems/dataload/core_content.gd")
const TYPES_PATH := "res://content/core/planets/types.json"

static var _types: Dictionary = {}
static var _cache: Dictionary = {}       ## planet id -> built planet (built once per run)


static func types() -> Dictionary:
	if _types.is_empty():
		_types = TownGen._read(TYPES_PATH)
	return _types


static func home_id() -> String:
	return str(types().get("home", "port_desert"))


## Every planet id in the manifest.
static func ids(content = null) -> Array:
	var cc = content if content != null else _content()
	return cc.planets.keys()


## A planet, built (cached: the same planet is the same dictionary all run).
static func build(planet_id: String, content = null) -> Dictionary:
	if _cache.has(planet_id):
		return _cache[planet_id]
	var cc = content if content != null else _content()
	var cfg: Dictionary = cc.planets.get(planet_id, {})
	if cfg.is_empty():
		push_warning("PlanetGen: unknown planet " + planet_id)
		return {}
	var p := make(cfg, cc)
	_cache[planet_id] = p
	return p


## Build from a config dictionary (also for configs not in the manifest: tests,
## a contributor trying one out).
static func make(cfg: Dictionary, cc = null) -> Dictionary:
	if cc == null:
		cc = _content()
	var id := str(cfg.get("id", "planet"))
	var type := str(cfg.get("type", "sand"))
	var tcfg: Dictionary = types().get("types", {}).get(type, {})
	if tcfg.is_empty():
		push_warning("PlanetGen: unknown planet type %s (%s); using sand" % [type, id])
		type = "sand"
		tcfg = types().types.sand
	var size := clampi(int(cfg.get("town_size", 50)), 1, 100)
	var town_id := str(cfg.get("town", ""))
	var town: Dictionary = {}
	if town_id != "":
		town = cc.get_location(town_id)            # authored
	else:
		town_id = id + "_town"
		var opts := {}
		var co: Dictionary = cfg.get("cantina_owner", {})
		if co.has("card"):
			opts["cantina_card"] = str(co.card)
		if co.has("look"):
			opts["cantina_look"] = str(co.look)
		town = TownGen.generate(town_id, size, int(cfg.get("seed", NameEngine.fnv(id) % 100000)), opts)
	var world: Dictionary = {}
	if cfg.has("world"):
		world = cc.get_world(str(cfg.world)).duplicate(true)
	else:
		world = _world_for(id, town_id, tcfg)
	world["ground"] = str(tcfg.get("ground", "terrain"))
	world["planet"] = id
	var style := str(cfg.get("style", tcfg.get("default_style", "desert")))
	return {
		"id": id,
		"cfg": cfg,
		"type": type,
		"type_cfg": tcfg,
		"ground": str(tcfg.get("ground", "terrain")),
		"size": size,
		"town_id": town_id,
		"town": town,
		"world": world,
		"style": style,
		"sky": tcfg.get("sky", {}),
		"features": cfg.get("features", []),
		"cantina": cfg.get("cantina_owner", {}),
		"encounter": cfg.get("encounter", null),
		"name": str(cfg.get("name", "")),
		"town_name": str(cfg.get("town_name", "")),
		"neighbours": neighbours(id, cc),
	}


## A world dict for a generated planet: the same shape as content/core/worlds.
static func _world_for(id: String, town_id: String, tcfg: Dictionary) -> Dictionary:
	var platform := str(tcfg.get("ground", "terrain")) == "platform"
	var surface: Dictionary = tcfg.get("surface", {})
	return {
		"id": id,
		"label": str(tcfg.get("label", id)),
		"town": town_id,
		"naming": { "town": str(tcfg.get("town_naming", "town")), "planet": "planet" },
		"terrain": {
			"extent": 0.0 if platform else 6000.0,
			"skirt_height": -float(surface.get("depth", 160.0)) if platform else 4.0,
			"flat_height": -float(surface.get("depth", 160.0)) if platform else 0.0,
			"planet_radius": 60000.0,
			"curve_from": 6000.0,
		},
		"landmarks": [],
		"atmosphere": tcfg.get("atmosphere", {}),
		"detail": types().get("detail", {}),
	}


## The planets you can fly to from `id`: the ones that name it as "near" (where
## they hang in its sky is their "at"), and the one it is near itself (seen from
## here, back the other way: "home_at", or the mirror of its own "at").
static func neighbours(id: String, cc = null) -> Array:
	if cc == null:
		cc = _content()
	var out: Array = []
	var all: Dictionary = cc.planets
	var mine: Dictionary = all.get(id, {})
	for other in all:
		if other == id:
			continue
		var o: Dictionary = all[other]
		if str(o.get("near", "")) == id and o.has("at"):
			out.append(_neighbour(o, GameFlow.vec(o.at)))
	if str(mine.get("near", "")) != "" and all.has(str(mine.near)):
		var home: Dictionary = all[str(mine.near)]
		var at := GameFlow.vec(mine.get("at", [0, 0, -20000]))
		var back := GameFlow.vec(mine.get("home_at", [-at.x * 1.6, at.y * 0.3, -at.z * 1.6]))
		out.append(_neighbour(home, back))
	return out


static func _neighbour(o: Dictionary, at: Vector3) -> Dictionary:
	var t: Dictionary = types().get("types", {}).get(str(o.get("type", "sand")), {})
	var body: Dictionary = t.get("body", {})
	return {
		"id": str(o.get("id", "")),
		"type": str(o.get("type", "sand")),
		"at": at,
		"radius": float(o.get("body_radius", body.get("radius", 1000.0))),
		"color": Color(str(body.get("color", "#a08060"))),
		"dark": Color(str(body.get("dark", "#504030"))),
	}


## Generated names: the planet's (and its town's) own "name" in the config wins,
## reserved in the name book so nothing else gets it; otherwise the name engine.
static func reserve_names(p: Dictionary, book: NameBook = null) -> void:
	var b := book if book != null else WorldState.names
	var world: Dictionary = p.get("world", {})
	if str(p.get("name", "")) != "":
		b.reserve(str(p.name), "planet:" + str(world.get("id", p.id)))
	if str(p.get("town_name", "")) != "":
		b.reserve(str(p.town_name), "town:" + str(world.get("town", p.town_id)))


## The planet's display name (generated or reserved).
static func display_name(p: Dictionary, book: NameBook = null) -> String:
	reserve_names(p, book)
	return NameHooks.planet(p.get("world", {}), book)


static func clear_cache() -> void:
	_cache = {}
	_types = {}


static func _content():
	var cc := CoreContent.new()
	cc.load_from()
	return cc
