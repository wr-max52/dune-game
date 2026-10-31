class_name TownAlarm
extends RefCounted
## The town-wide alarm (M15). Pure and headless-testable. Once it is raised, every
## Remnant trooper in town is fighting the player, wherever it was standing: the
## gate guards, the tower sentry and the barracks troopers. It keeps the one thing
## they all share, the last place anyone saw the player, so a trooper who has never
## seen you still knows where to run.
##
## Raised by: the gate checkpoint going hostile, the player hurting any trooper, or
## a trooper spotting a face it remembers (or one wanted on sight by day). Calm
## again when every trooper is down, or the player has been out of everyone's
## sight for disengage_unseen_s and is disengage_dist from the nearest trooper
## (fled), or the player is knocked out (downed). After fleeing the garrison
## remembers the player for memory_s; after being downed it forgets them.
##
## Events (drain `events`): { type: "alarm", why }, { type: "calm", why },
##   { type: "standing", delta, why, cooldown }, { type: "flag", name }

enum State { CALM, ALARM }

var cfg: Dictionary = {}
var state := State.CALM
var why := ""
var last_known := Vector3.INF     ## shared: where anyone last saw the player
var memory_left := 0.0
var unseen_s := 0.0
var raised := 0                   ## how many times this session
var events: Array = []


func _init(config: Dictionary = {}) -> void:
	cfg = config


func n(key: String, fallback: float) -> float:
	return float(cfg.get(key, fallback))


func active() -> bool:
	return state == State.ALARM


func remembers() -> bool:
	return memory_left > 0.0


func state_name() -> String:
	return State.keys()[state]


## Sound the alarm. `at` is where the trouble is (the player, if known). Returns
## true if this raised it (false if it was already up).
func raise(reason: String, at: Vector3 = Vector3.INF) -> bool:
	if at != Vector3.INF:
		last_known = at
	if state == State.ALARM:
		return false
	state = State.ALARM
	why = reason
	unseen_s = 0.0
	raised += 1
	memory_left = n("memory_s", 300.0)
	events.append({ "type": "alarm", "why": reason })
	return true


## One frame. s = { seen (any trooper sees the player), player_pos,
##   nearest_dist (player to the nearest living trooper), alive (troopers left) }
func update(dt: float, s: Dictionary) -> void:
	var seen: bool = s.get("seen", false)
	var pos: Vector3 = s.get("player_pos", Vector3.INF)
	if seen and pos != Vector3.INF:
		last_known = pos
	if state == State.CALM:
		memory_left = maxf(0.0, memory_left - dt)
		return
	if int(s.get("alive", 1)) <= 0:
		state = State.CALM
		memory_left = 0.0
		events.append({ "type": "calm", "why": "all_down" })
		return
	unseen_s = 0.0 if seen else unseen_s + dt
	if unseen_s >= n("disengage_unseen_s", 12.0) and float(s.get("nearest_dist", INF)) > n("disengage_dist", 70.0):
		state = State.CALM
		memory_left = n("memory_s", 300.0)
		events.append({ "type": "standing", "delta": int(cfg.get("fled_standing", -5)),
			"why": "Someone shot it out with the Remnant and got away.", "cooldown": "" })
		events.append({ "type": "flag", "name": "fled_gate_fight" })
		events.append({ "type": "calm", "why": "fled" })


## The player was knocked out and dragged off: the fight is over, and so is any
## memory of their face (they wake in the pit, not to a garrison shooting on sight).
func stand_down() -> void:
	memory_left = 0.0
	if state != State.ALARM:
		return
	state = State.CALM
	events.append({ "type": "calm", "why": "downed" })


func drain() -> Array:
	var e := events
	events = []
	return e
