class_name Checkpoint
extends RefCounted
## The gate checkpoint's decisions, shared by every guard on it. Pure and
## headless-testable: it is told what is true this frame (standing with the
## Remnant, night or day, where the player is, whether a guard sees them, whether
## they are armed or have been shooting) and it decides what the checkpoint does:
## wave them through, ask for papers, demand a search, take a bribe, warn, or go
## hostile. It never moves a guard; it emits events the director acts on.
##
## Standing bands (product owner, 2026-10-26), each from the profile:
##   40 and up   wave        "Move along."
##   0 to 39     papers      papers, or a small bribe
##   -1 to -39   search      papers AND a search, or a bigger bribe
##   -40 down    hostile     warn once, then open fire
## A drawn weapon close by, or a shot heard recently, makes it one band worse.
## After dark bribes work one band lower: a hostile band at night is a bribe
## (night_hostile), and the search band's bribe costs the papers price.
##
## Events (drain `events` after update/answer):
##   { type: "bark", key }                    a guard says a line from the data
##   { type: "card", band, choices }          open the choice card
##   { type: "card_close" }
##   { type: "lock_player", seconds }         held still for a search
##   { type: "standing", delta, why, cooldown } a WorldState change
##   { type: "bribe", price }                 credits leave the player
##   { type: "flag", name }                   a WorldState flag
##   { type: "hostile", why }                 every guard fights
##   { type: "calm", why }                    the fight is over (fled, won, downed)

enum State { IDLE, CHALLENGE, SEARCHING, WARN, CLEARED, HOSTILE }

const BANDS := ["wave", "papers", "search", "hostile"]

var cfg: Dictionary = {}
var state := State.IDLE
var band := ""                ## the band the current challenge is in
var choices: Array = []       ## the open card's choices, or []
var card_open := false
var refused := false          ## walked away from the card: must not push through
var events: Array = []

var warn_left := 0.0
var cleared_left := 0.0
var search_left := 0.0
var memory_left := 0.0        ## how long they remember a fight with you
var fights := 0
var _warn_for := ""           ## "cross" | "hostile" | "refuse"
var _start_side := 0          ## which side of the gate line the challenge began on
var _search_from := Vector3.ZERO
var _went_on := false         ## said "go on" this visit while cleared
var _s: Dictionary = {}


func _init(config: Dictionary = {}) -> void:
	cfg = config


func n(key: String, fallback: float) -> float:
	return float(cfg.get(key, fallback))


func state_name() -> String:
	return State.keys()[state]


## The band for a standing, before night: the first band whose min it meets.
func base_band(standing: int) -> String:
	var bands: Array = cfg.get("bands", [{ "id": "wave", "min": 40 }, { "id": "papers", "min": 0 },
		{ "id": "search", "min": -39 }, { "id": "hostile", "min": -100 }])
	for b in bands:
		if standing >= int(b.min):
			return str(b.id)
	return "hostile"


## The band with the modifiers: armed close or a recent shot each make it one worse;
## at night a hostile band becomes night_hostile (they will take a bribe).
func band_for(standing: int, night: bool, armed_close: bool, recent_shot: bool) -> String:
	var i := BANDS.find(base_band(standing))
	if armed_close:
		i += 1
	if recent_shot:
		i += 1
	var id: String = BANDS[mini(i, BANDS.size() - 1)]
	if id == "hostile" and night:
		return "night_hostile"
	return id


func bribe_price(b: String, night: bool) -> int:
	var prices: Dictionary = cfg.get("bribe", { "papers": 10, "search": 25, "night_hostile": 40 })
	if b == "search" and night:
		return int(prices.get("papers", 10))
	return int(prices.get(b, 0))


func choices_for(b: String, night: bool, credits: int) -> Array:
	var price := bribe_price(b, night)
	var bribe := { "id": "bribe", "label": "Bribe %d cr" % price, "price": price, "enabled": credits >= price }
	var out: Array = []
	match b:
		"papers":
			out = [{ "id": "papers", "label": "Show papers", "enabled": true }, bribe]
		"search":
			out = [{ "id": "search", "label": "Submit to a search", "enabled": true }, bribe]
		"night_hostile":
			out = [bribe]
	out.append({ "id": "mouth_off", "label": "Mouth off", "enabled": true })
	out.append({ "id": "walk_away", "label": "Walk away", "enabled": true })
	return out


## One frame. s = { standing, night, credits, player_pos, gate_pos, gate_x,
##   noticed (any guard), unseen_s (since any guard saw the player), armed,
##   recent_shot, attacked (the player hurt a guard), guards_alive }
func update(dt: float, s: Dictionary) -> void:
	_s = s
	memory_left = maxf(0.0, memory_left - dt)
	var alive := int(s.get("guards_alive", 1))
	if alive <= 0:
		if state != State.IDLE:
			_close_card()
			if state == State.HOSTILE:
				_emit({ "type": "calm", "why": "all_down" })
			state = State.IDLE
		return
	if bool(s.get("attacked", false)) and state != State.HOSTILE:
		_go_hostile("attacked")
		return

	var pos: Vector3 = s.get("player_pos", Vector3.INF)
	var gate: Vector3 = s.get("gate_pos", Vector3.ZERO)
	var dist := Vector2(pos.x - gate.x, pos.z - gate.z).length() if pos != Vector3.INF else INF
	var side := _side(pos)
	var noticed: bool = s.get("noticed", false)
	var zone := n("zone_radius", 11.0)

	match state:
		State.IDLE:
			if not noticed:
				return
			if memory_left > 0.0 and dist <= n("hostile_radius", 26.0):
				_bark("contact")
				_go_hostile("remembered")
				return
			var armed_close: bool = bool(s.get("armed", false)) and dist <= n("armed_escalate_radius", 10.0) + zone
			var b := band_for(int(s.get("standing", 0)), bool(s.get("night", false)), armed_close, bool(s.get("recent_shot", false)))
			if b == "hostile":
				if dist <= n("hostile_radius", 26.0):
					band = b
					_bark("halt_hostile")
					_warn("hostile")
				return
			if dist > zone:
				return
			band = b
			_start_side = side
			refused = false
			if b == "wave":
				_bark("wave")
				_clear()
				return
			_bark(b)
			_open_card()
			state = State.CHALLENGE
		State.CHALLENGE:
			if dist > zone + 3.0:
				_close_card()
				if refused or band == "search" or band == "night_hostile":
					_bark("stay_out")
				state = State.IDLE
			elif side != _start_side and side != 0:
				_close_card()
				_bark("warn")
				_warn("cross")
		State.SEARCHING:
			search_left -= dt
			if pos != Vector3.INF and Vector2(pos.x - _search_from.x, pos.z - _search_from.z).length() > 2.5:
				_bark("warn")
				_warn("refuse")
			elif search_left <= 0.0:
				_bark("cleared_search")
				_clear()
		State.WARN:
			warn_left -= dt
			match _warn_for:
				"hostile":
					if dist > n("hostile_radius", 26.0) + 4.0:
						_bark("stay_out")
						state = State.IDLE
					elif warn_left <= 0.0:
						_go_hostile("ignored_warning")
				"cross", "refuse":
					if _warn_for == "cross" and side == _start_side:
						# Came back: the question stands.
						_open_card()
						state = State.CHALLENGE
					elif warn_left <= 0.0:
						_go_hostile("pushed_through" if _warn_for == "cross" else "refused_search")
		State.CLEARED:
			cleared_left -= dt
			if noticed and dist <= zone and not _went_on and cleared_left < n("cleared_s", 180.0) - 20.0:
				_went_on = true
				_bark("go_on")
			if dist > zone + 10.0:
				_went_on = false
			if cleared_left <= 0.0:
				state = State.IDLE
		State.HOSTILE:
			var far := dist > n("disengage_dist", 70.0)
			if float(s.get("unseen_s", 0.0)) >= n("disengage_unseen_s", 12.0) and far:
				memory_left = n("memory_s", 300.0)
				state = State.IDLE
				_emit({ "type": "standing", "delta": int(cfg.get("standing", {}).get("fled", -5)), "why": "Someone shot up the east gate and got away." })
				_emit({ "type": "flag", "name": "fled_gate_fight" })
				_emit({ "type": "calm", "why": "fled" })


## The player picked a card choice. Returns true if it was taken.
func answer(choice_id: String) -> bool:
	if not card_open:
		return false
	var night := bool(_s.get("night", false))
	var credits := int(_s.get("credits", 0))
	var deltas: Dictionary = cfg.get("standing", {})
	match choice_id:
		"papers":
			if band != "papers":
				return false
			_close_card()
			_bark("cleared_papers")
			_emit({ "type": "standing", "delta": int(deltas.get("papers", 1)), "why": "", "cooldown": "gate_papers" })
			_clear()
		"search":
			if band != "search":
				return false
			_close_card()
			_bark("searching")
			search_left = n("search_s", 3.0)
			_search_from = _s.get("player_pos", Vector3.ZERO)
			_emit({ "type": "lock_player", "seconds": search_left })
			state = State.SEARCHING
		"bribe":
			var price := bribe_price(band, night)
			if credits < price:
				_bark("no_credits")
				return false
			_close_card()
			_bark("bribe_taken")
			_emit({ "type": "bribe", "price": price })
			_emit({ "type": "flag", "name": "bribed_gate" })
			_clear()
		"mouth_off":
			_bark("mouth_off")
			_emit({ "type": "standing", "delta": int(deltas.get("mouth_off", -2)), "why": "", "cooldown": "gate_mouth" })
			match band:
				"papers":
					band = "search"
					_open_card()
				_:
					_close_card()
					_warn("hostile")
		"walk_away":
			_close_card()
			_bark("walk_away")
			refused = true
		_:
			return false
	return true


## The player was knocked out and dragged off: the checkpoint stands down but
## remembers the fight.
func on_player_downed() -> void:
	_close_card()
	if state == State.HOSTILE:
		memory_left = n("memory_s", 300.0)
		_emit({ "type": "calm", "why": "downed" })
	state = State.IDLE


func drain() -> Array:
	var e := events
	events = []
	return e


# ------------------------------------------------------------------ internals

func _side(pos: Vector3) -> int:
	if pos == Vector3.INF:
		return 0
	var gx := float(_s.get("gate_x", 99.0))
	if pos.x > gx + 1.2:
		return 1
	if pos.x < gx - 1.2:
		return -1
	return 0


func _open_card() -> void:
	choices = choices_for(band, bool(_s.get("night", false)), int(_s.get("credits", 0)))
	card_open = true
	_emit({ "type": "card", "band": band, "choices": choices })


func _close_card() -> void:
	if card_open:
		card_open = false
		choices = []
		_emit({ "type": "card_close" })


func _clear() -> void:
	state = State.CLEARED
	cleared_left = n("cleared_s", 180.0)
	_went_on = false


func _warn(why: String) -> void:
	state = State.WARN
	_warn_for = why
	warn_left = n("warn_s", 3.0)


func _go_hostile(why: String) -> void:
	_close_card()
	state = State.HOSTILE
	fights += 1
	memory_left = n("memory_s", 300.0)
	_emit({ "type": "hostile", "why": why })
	_emit({ "type": "flag", "name": "gate_fight" })
	_emit({ "type": "standing", "delta": int(cfg.get("standing", {}).get("fight", -10)),
		"why": "A firefight broke out at the east gate.", "cooldown": "gate_fight" })


func _bark(key: String) -> void:
	_emit({ "type": "bark", "key": key })


func _emit(e: Dictionary) -> void:
	events.append(e)
