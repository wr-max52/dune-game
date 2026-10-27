class_name NameBook
extends RefCounted
## Every name given out in this game (issue #15). Lives in WorldState, so it is
## saved with the game and survives scene changes.
##
## Things are named by a stable key ("npc:port_town/trooper_gate_n",
## "pilot:orbital_skirmish/w0/2", "planet:port_desert"). Asking again for the same
## key gives the same name back. A new key gets a fresh name from NameEngine,
## seeded from (world seed, kind, key), checked against every name already in the
## book (and the authored ones, reserved at start), and only then written in. On a
## clash it tries the next seed, so the result is still the same every time the
## same things are named in the same order.

const NAMES_DIR := "res://content/core/names"
const MANIFEST := "res://content/core/manifest.json"
const IP_LIST := "res://content/core/llm/ip_blocklist.json"

static var _shared_engine: NameEngine

var world_seed := 0
var by_key: Dictionary = {}       ## key -> name
var owner: Dictionary = {}        ## normalized name -> key
var kinds_of: Dictionary = {}     ## key -> kind (what it was named as)
var labels: Dictionary = {}       ## key -> how it is shown, with a title ("Corporal Varo Kesh"); see NameHooks
var engine: NameEngine
var clashes := 0                  ## names thrown back because they were taken (tests read it)


func _init(eng: NameEngine = null) -> void:
	engine = eng if eng != null else shared_engine()
	world_seed = int(engine.config.get("world_seed", 1))
	for r in engine.config.get("reserved", []):
		reserve(str(r.name), str(r.key))


## The library, loaded once per run (it never changes while playing).
static func shared_engine() -> NameEngine:
	if _shared_engine == null:
		_shared_engine = load_engine()
	return _shared_engine


static func load_engine(dir: String = NAMES_DIR) -> NameEngine:
	var e := NameEngine.new()
	var banks := {}
	var m = _read(MANIFEST)
	for id in (m.get("names", []) if m is Dictionary else []):
		var b = _read("%s/%s.json" % [dir, id])
		if b is Dictionary:
			banks[str(id)] = b
		else:
			push_warning("NameBook: name bank missing: " + str(id))
	var ip = _read(IP_LIST)
	var ip_d: Dictionary = ip if ip is Dictionary else {}
	e.setup(banks, ip_d.get("terms", []), ip_d.get("name_terms", []))
	return e


# ------------------------------------------------------------------ use

## The name of the thing with this key, giving it one if it has none yet.
## `kind` picks the grammar (content/core/names/kinds.json); `ctx` fills %(key)
## slots in it. Returns "" only if the kind cannot make a free name at all.
func name_for(kind: String, key: String, ctx: Dictionary = {}) -> String:
	if by_key.has(key):
		return by_key[key]
	var max_attempts := int(engine.config.get("max_attempts", 64))
	for attempt in max_attempts:
		var seed := NameEngine.fnv("%d|%s|%s|%d" % [world_seed, kind, key, attempt])
		var n := engine.generate(kind, seed, ctx)
		if n == "":
			continue
		if is_taken(n):
			clashes += 1
			continue
		_write(n, key, kind)
		return n
	push_warning("NameBook: no free %s name for %s" % [kind, key])
	return ""


## Claim an authored name (the cantina owner's, a town written by hand) so nothing
## generated can ever take it. False if it already belongs to something else.
func reserve(name: String, key: String) -> bool:
	var n := NameEngine.normalize(name)
	if owner.has(n) and owner[n] != key:
		return false
	_write(name, key, "authored")
	return true


func has(key: String) -> bool:
	return by_key.has(key)


func is_taken(name: String) -> bool:
	return owner.has(NameEngine.normalize(name))


## Let a name go (the thing is gone for good and its name may be reused).
func release(key: String) -> void:
	if by_key.has(key):
		owner.erase(NameEngine.normalize(by_key[key]))
		by_key.erase(key)
		kinds_of.erase(key)
		labels.erase(key)


## A deterministic pick from a list for this key (a rank, a title): the same key
## always gets the same one, without spending a name.
func pick(key: String, options: Array, salt: String = "pick") -> String:
	if options.is_empty():
		return ""
	var h := NameEngine.fnv("%d|%s|%s" % [world_seed, salt, key])
	return str(options[h % options.size()])


func size() -> int:
	return by_key.size()


func _write(name: String, key: String, kind: String) -> void:
	if by_key.has(key):
		owner.erase(NameEngine.normalize(by_key[key]))
	by_key[key] = name
	owner[NameEngine.normalize(name)] = key
	kinds_of[key] = kind


# ------------------------------------------------------------------ save

func to_save() -> Dictionary:
	return { "world_seed": world_seed, "names": by_key.duplicate(), "kinds": kinds_of.duplicate(),
		"labels": labels.duplicate() }


func from_save(d: Dictionary) -> void:
	world_seed = int(d.get("world_seed", world_seed))
	var names: Dictionary = d.get("names", {})
	var kinds: Dictionary = d.get("kinds", {})
	for key in names:
		_write(str(names[key]), str(key), str(kinds.get(key, "")))
	labels = d.get("labels", {}).duplicate()


static func _read(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())
