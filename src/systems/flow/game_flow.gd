class_name GameFlow
extends RefCounted
## Scene flow between the port (on foot) and flight.
##
## The port and the dogfight are separate scenes. This class is the hand-off
## between them: a launch pad in the port calls launch(), the dogfight scene asks
## which encounter to fly, and when the fight ends it calls finish_flight(), which
## loads the port again. The port then calls take_arrival() to spawn the player
## at the pad they left from and show the outcome.
##
## State lives in static vars so it survives change_scene_to_file(). There is no
## autoload on purpose: nothing runs unless a pad starts a flight, so opening the
## dogfight scene on its own (F6, tests, review renders) behaves exactly as before.
##
## Tests swap `change_scene` for a recorder so they never tear down the GUT tree.

const PADS_PATH := "res://content/core/flow/launch_pads.json"

static var in_flight := false
static var pad_id := ""
static var encounter_id := ""
static var return_scene := ""
static var arrival: Dictionary = {}       ## { pad, encounter, outcome, payout } until taken
static var change_scene: Callable = Callable()

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(PADS_PATH, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_data = parsed
		if _data.is_empty():
			push_warning("GameFlow: could not read ", PADS_PATH)
	return _data


static func pad(id: String) -> Dictionary:
	var p: Dictionary = data().get("pads", {}).get(id, {})
	if p.is_empty():
		return {}
	var out := p.duplicate(true)
	out["id"] = id
	return out


## Every pad that belongs to a scene, by scene path.
static func pads_for_scene(scene_path: String) -> Array:
	var out: Array = []
	for id in data().get("pads", {}).keys():
		var p := pad(id)
		if str(p.get("scene", "")) == scene_path:
			out.append(p)
	return out


static func label(key: String) -> String:
	return str(data().get("labels", {}).get(key, ""))


static func setting(key: String, fallback: float) -> float:
	return float(data().get(key, fallback))


static func vec(a) -> Vector3:
	if a is Array and a.size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO


## Start a flight from a pad. Loads the flight scene.
static func launch(tree: SceneTree, from_pad: Dictionary) -> void:
	in_flight = true
	pad_id = str(from_pad.get("id", ""))
	encounter_id = str(from_pad.get("encounter", ""))
	return_scene = str(from_pad.get("scene", data().get("default_port_scene", "")))
	arrival = {}
	_go(tree, str(data().get("flight_scene", "res://scenes/flight/dogfight_demo.tscn")))


## End the flight and load the port it started from. Safe to call when no flight
## is active (does nothing), so a stand-alone dogfight never jumps scenes.
static func finish_flight(tree: SceneTree, outcome: String, payout: int = 0) -> bool:
	if not in_flight:
		return false
	in_flight = false
	arrival = { "pad": pad_id, "encounter": encounter_id, "outcome": outcome, "payout": payout }
	var target := return_scene if return_scene != "" else str(data().get("default_port_scene", ""))
	_go(tree, target)
	return true


## The port calls this once on load. Returns the arrival (and clears it) when the
## player is coming back from a flight, else {}.
static func take_arrival() -> Dictionary:
	var a := arrival
	arrival = {}
	return a


static func arrival_text(a: Dictionary) -> String:
	if a.is_empty():
		return ""
	if str(a.get("outcome", "")) == "complete":
		var t := label("arrive_complete")
		return t % int(a.get("payout", 0)) if t.contains("%d") else t
	return label("arrive_failed")


static func reset() -> void:
	in_flight = false
	pad_id = ""
	encounter_id = ""
	return_scene = ""
	arrival = {}
	change_scene = Callable()


static func _go(tree: SceneTree, path: String) -> void:
	if change_scene.is_valid():
		change_scene.call(path)
	elif tree != null:
		tree.change_scene_to_file.call_deferred(path)
