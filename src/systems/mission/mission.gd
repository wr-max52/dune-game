extends RefCounted
## Mission state machine (M5). Pure and headless-testable.
##
## The single slice mission "Crate Retrieval" advances through a fixed sequence of
## goals. Each goal takes a typed event and returns the next goal. A goal that has
## been satisfied is not revisited. This is the spine the headless bot drives, and
## the thing the save system records.
##
## Phases:
##   IDLE          -- nothing started
##   ACCEPT        -- talk to the fixer and accept the contract
##   TRAVEL        -- go to the outpost
##   FIGHT         -- defeat the outpost's enemies
##   TAKE_CRATE    -- grab the crate objective
##   RETURN        -- come back to the fixer
##   COMPLETE      -- paid; the mission is over

enum Phase {
	IDLE,
	ACCEPT,
	TRAVEL,
	FIGHT,
	TAKE_CRATE,
	RETURN,
	COMPLETE,
}

var phase := Phase.IDLE
var started := false
var accepted := false
var at_outpost := false
var enemies_defeated := 0
var enemies_total := 0
var has_crate := false
var paid := 0
var payout := 0

# Events the world feeds in.
enum Event {
	TALK_FIXER,
	ACCEPT,
	ARRIVE_OUTPOST,
	ENEMY_KILLED,
	TOOK_CRATE,
	ARRIVED_BACK,
}


func _init(config: Dictionary) -> void:
	enemies_total = 0
	var enemies = config.get("enemies", {})
	enemies_total = int(enemies.get("troopers", 0)) + int(enemies.get("duelist", 0))
	payout = int(config.get("payout", 0))


## The next goal, by name, for the current phase; null once COMPLETE.
func current_goal() -> Variant:
	match phase:
		Phase.ACCEPT:
			return "accept_contract"
		Phase.TRAVEL:
			return "go_to_outpost"
		Phase.FIGHT:
			return "defeat_enemies"
		Phase.TAKE_CRATE:
			return "take_crate"
		Phase.RETURN:
			return "return_to_fixer"
	return null


## Feed one event. Mutates the FSM to the next valid phase. Returns the phase it
## moved TO (or the current one if the event was a no-op).
func handle(event: int) -> int:
	match phase:
		Phase.IDLE:
			if event == Event.TALK_FIXER:
				phase = Phase.ACCEPT
		Phase.ACCEPT:
			if event == Event.ACCEPT:
				accepted = true
				phase = Phase.TRAVEL
		Phase.TRAVEL:
			if event == Event.ARRIVE_OUTPOST:
				at_outpost = true
				phase = Phase.FIGHT
		Phase.FIGHT:
			if event == Event.ENEMY_KILLED:
				enemies_defeated += 1
				if enemies_defeated >= enemies_total:
					phase = Phase.TAKE_CRATE
		Phase.TAKE_CRATE:
			if event == Event.TOOK_CRATE:
				has_crate = true
				phase = Phase.RETURN
		Phase.RETURN:
			if event == Event.ARRIVED_BACK and has_crate:
				paid = payout
				phase = Phase.COMPLETE
		Phase.COMPLETE:
			return Phase.COMPLETE
	return phase


func is_complete() -> bool:
	return phase == Phase.COMPLETE


## The state the save system needs to serialise/restore.
func to_save() -> Dictionary:
	return {
		"phase": int(phase),
		"started": started,
		"accepted": accepted,
		"at_outpost": at_outpost,
		"enemies_defeated": enemies_defeated,
		"enemies_total": enemies_total,
		"has_crate": has_crate,
		"paid": paid,
		"payout": payout,
	}


func from_save(d: Dictionary) -> void:
	phase = int(d.get("phase", 0))
	started = bool(d.get("started", false))
	accepted = bool(d.get("accepted", false))
	at_outpost = bool(d.get("at_outpost", false))
	enemies_defeated = int(d.get("enemies_defeated", 0))
	enemies_total = int(d.get("enemies_total", 0))
	has_crate = bool(d.get("has_crate", false))
	paid = int(d.get("paid", 0))
	payout = int(d.get("payout", 0))
