class_name TownCheck
extends RefCounted
## A town's layout checks, remembered (issue #121). TownLayout.validate()
## compares every box with every other: most of a second for the port. A planet's
## town comes from PlanetGen's cache and does not change during a session, so the
## answer for that very data is kept, and SpaceTravel asks for the next planet's
## on a worker thread (precheck) before the ship gets there. A scene switched in
## mid-flight then does not spend its first frame re-checking a town.

const TownLayout := preload("res://src/systems/world/town_layout.gd")

static var _checks := {}             ## planet id -> { data, errs }
static var _lock := Mutex.new()


## The town's validation errors ([] = fine), checked once per data.
static func errors(planet_id: String, data: Dictionary) -> Array:
	var known = _known(planet_id, data)
	if known != null:
		return known
	var t := TownLayout.new()
	t.load_from_dict(data)
	var errs := t.validate()
	_lock.lock()
	_checks[planet_id] = { "data": data, "errs": errs }
	_lock.unlock()
	return errs


## True when this data has been checked already.
static func is_known(planet_id: String, data: Dictionary) -> bool:
	return _known(planet_id, data) != null


## Starts the check for another planet's town on a worker thread (`data` is its
## PlanetGen town, fetched on the main thread; the worker only reads it).
## Returns the task id to wait on before the caller goes away, or -1 when there
## is nothing to do.
static func precheck(planet_id: String, data: Dictionary) -> int:
	if data.is_empty() or is_known(planet_id, data):
		return -1
	return WorkerThreadPool.add_task(func(): errors(planet_id, data), false, "town check")


static func clear() -> void:
	_lock.lock()
	_checks = {}
	_lock.unlock()


static func _known(planet_id: String, data: Dictionary):
	_lock.lock()
	var c: Dictionary = _checks.get(planet_id, {})
	_lock.unlock()
	if not c.is_empty() and is_same(c.data, data):
		return c.errs
	return null
