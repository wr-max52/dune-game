class_name GeneralPost
extends Node3D
## The Remnant general in a story save (issues #203, #204, #205, #213, #214).
##   - Where he stands: in the pit beside your wreck while the story is at the
##     "general" chapter (he meets you as you step out), then in the barracks yard
##     with one guard and an assassin droid. Gone while he is a bounty out at an
##     outpost, and for good once he is dead.
##   - An AI character on the town's ConversationHost, from his own card
##     (content/core/npcs/general_card.json). [E] beside him opens a menu, like
##     T-89's: talk, ask for work, hand over a droid.
##   - He, his guard and his droid face the front gate ("face": a town marker).
##   - The pit meeting is his to end: you cannot walk away (Esc) until he lets you
##     go (let_go) or has you searched (search). That verdict sets the Remnant
##     standing you start with. If his brain never gives one, the game does after
##     a few of his lines (search if you insulted him, else let go).
##   - Insults cost Remnant standing; too many in one talk and his guards search you
##     on the spot (the gate's rules: WorldState.search_player). In the pit meeting
##     that search is his verdict.
##   - His job (j_general_droids, issue #204): assassin droids from the desert, for
##     pay_mult times the droid merchant's resale, each raising Remnant standing.
##     Not while you are hostile. In good standing he tells you about the crashed
##     cruiser (issue #205: the quest's event, heard_of_wreck).
##   - Once the Remnant has left the moon (issue #214) he stays, in the desert armour.
##
## Config: content/core/npcs/general.json. The headless test calls talk_ended(),
## on_insult(), decide(), take_job() and hand_over() directly.

const CFG_PATH := "res://content/core/npcs/general.json"
const CARD_PATH := "res://content/core/npcs/general_card.json"

var demo                              ## town_demo.gd (or null in a test)
var player: CharacterBody3D
var gear: GearController
var cfg: Dictionary = {}
var body: Node3D                      ## MerchantNPC
var guard: Node3D
var droid: Node3D
var menu: DroidMenu
var host: ConversationHost
var spot: TalkSpot
var said := ""                        ## his last line (tests)
var searched := 0                     ## searches this session (tests)
var meeting := false                  ## the pit meeting is on and he has not given his verdict
var verdict := ""                     ## "let_go" | "search" once he has given it (tests)
var _where := ""                      ## "pit" | "barracks" | "" (away)
var _armoured := false
var _insults_seen := 0
var _talk_insults := 0
var _was_talking := false
var _was_locked := false
var _meet_lines := 0
var _free_at := 0                     ## ticks (ms): until then the pit is still his (T-89 waits)


func setup(p_demo, p_player: CharacterBody3D, p_gear: GearController) -> void:
	demo = p_demo
	player = p_player
	gear = p_gear


func _ready() -> void:
	name = "GeneralPost"
	var f := FileAccess.open(CFG_PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f != null else null
	cfg = d if d is Dictionary else {}
	menu = DroidMenu.new()
	add_child(menu)
	_place()


func npc_name() -> String:
	return str(NpcBrain._read(CARD_PATH).get("name", "the general"))


func _l(key: String) -> String:
	return str(cfg.get("labels", {}).get(key, key))


func _line(key: String) -> String:
	return str(cfg.get("lines", {}).get(key, key))


# ------------------------------------------------------------------ where he is

## "pit" while he waits for you there, "barracks" after, "" while he is away (a
## bounty out at an outpost) or dead.
static func station() -> String:
	if not WorldState.story_mode() or WorldState.has_flag("general_dead") or general_hunted():
		return ""
	return "pit" if Story.chapter() in ["land", "general"] else "barracks"


## Issue #213: Oda's bounty is on him and he is out at the outpost (or dead there).
static func general_hunted() -> bool:
	return bool(WorldState.bounty.get("general", false)) and str(WorldState.bounty.get("state", "")) in ["out", "dead"]


func _place() -> void:
	var want := station()
	var armour := Story.remnant_hostile()
	if want == _where and armour == _armoured and (body != null or want == ""):
		return
	_where = want
	_armoured = armour
	for n in [body, guard, droid]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	body = null
	guard = null
	droid = null
	if want == "":
		_sync_spot()
		return
	var at := _spot(cfg.get(want, {}))
	var kit: CharacterKit = CharacterKit.new(demo._flat_mats(), 0.0) if demo != null and demo.get("use_look") else null
	body = _person(kit, cfg.get("armour_outfit" if armour else "outfit", {}), at, "General")
	if not armour:
		# The Remnant has left (issue #214): he stays on alone.
		guard = _person(kit, cfg.get("guard_outfit", {}), at + _v(cfg.get("guard_offset", [1.6, 0, -1.2])), "GeneralGuard")
		if demo != null and demo.get("use_look"):
			var look := DroidKit.build("assassin", {}, demo._flat_mats(), ShipSalesman.model_look({ "kind": "assassin" }))
			add_child(look)
			look.global_position = at + _v(cfg.get("droid_offset", [-1.8, 0, -1.0]))
			DroidKit.set_awake(look, true)
			droid = look
	_face_gate()
	_sync_spot()


## He and his escort face the front gate. People face +Z, the droid's look -Z.
func _face_gate() -> void:
	var town = demo.town if demo != null and "town" in demo else null
	var mk := str(cfg.get("face", "gate"))
	if town == null or town.get_marker(mk).is_empty():
		return
	var gate: Vector3 = town.marker_pos(mk)
	for n in [body, guard, droid]:
		if n == null:
			continue
		var to: Vector3 = gate - n.global_position
		if Vector2(to.x, to.z).length() > 0.01:
			n.rotation.y = atan2(to.x, to.z) if n != droid else atan2(-to.x, -to.z)


## His TalkSpot follows his body: on the host while he stands somewhere, off it
## while he is away.
func _sync_spot() -> void:
	if spot == null or host == null:
		return
	spot.body = body
	if body == null:
		host.spots.erase(spot)
		return
	spot.stand = body.global_position
	if not host.spots.has(spot):
		host.spots.append(spot)


func _person(kit: CharacterKit, outfit: Dictionary, at: Vector3, n: String) -> Node3D:
	var p := MerchantNPC.new(kit, "remnant_commander", outfit) if kit != null else MerchantNPC.new()
	p.name = n
	add_child(p)
	p.global_position = at
	if player != null:
		p.look_at_target = player
	return p


func _spot(where: Dictionary) -> Vector3:
	var town = demo.town if demo != null and "town" in demo else null
	var mk := str(where.get("marker", ""))
	var base := Vector3.ZERO
	if town != null and not town.get_marker(mk).is_empty():
		base = town.marker_pos(mk)
	return base + _v(where.get("offset", [0, 0, 0]))


static func _v(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


# ------------------------------------------------------------------ frame

func _physics_process(_dt: float) -> void:
	_place()
	if host != null:
		_watch_talk()
	if player == null or body == null:
		return
	if menu.is_open() or (host != null and host.is_talking()):
		return
	_meet_in_pit()
	if _was_locked:
		player.locked = false
		_was_locked = false
	var p := player.global_position
	var bp := body.global_position
	var near: bool = not bool(player.get("piloting")) and Vector2(p.x - bp.x, p.z - bp.z).length() <= float(cfg.get("reach", 3.2)) \
		and absf(p.y - bp.y) <= 2.0 and (gear == null or gear.focus.is_empty())
	if not near:
		return
	if gear != null and gear.hud != null:
		gear.hud.set_prompt(_l("talk") % npc_name())
	if not player.locked and InputMap.has_action("interact") and Input.is_action_just_pressed("interact"):
		open_menu()


## [E]: talk (his AI), ask for work, hand over droids.
func open_menu() -> void:
	var opts: Array = []
	if spot != null:
		opts.append({ "id": "chat", "text": _l("chat") })
	if not job_active():
		opts.append({ "id": "work", "text": _l("work") })
	for d in droids_to_hand_over():
		opts.append({ "id": "hand:%d" % int(d.uid), "text": _l("hand_over") % [DroidRoster.label(str(d.kind)), droid_pay()] })
	menu.open(_l("menu_title") % [npc_name(), int(WorldState.standing.get("imperial_remnant", 0))], opts, _on_menu)
	if player != null and not player.locked:
		player.locked = true
		_was_locked = true


func _on_menu(id: String) -> void:
	if id == "chat":
		_was_locked = false
		if host != null:
			host.start_talk(spot)
	elif id == "work":
		take_job()
	elif id.begins_with("hand:"):
		hand_over(int(id.substr(5)))


func _say(text: String) -> void:
	said = text
	if gear != null and gear.hud != null and text != "":
		gear.hud.toast("%s: %s" % [npc_name(), text], 5.0)


# ------------------------------------------------------------------ talk (issue #203)

## Join the town's conversation host as one of its AI characters.
func attach_host(h: ConversationHost) -> void:
	if h == null or host == h:
		return
	host = h
	var brain := NpcBrain.new(null, CARD_PATH)
	spot = TalkSpot.new(brain, body, body.global_position if body != null else Vector3.ZERO)
	spot.manual = true
	spot.radius = float(cfg.get("reach", 3.2))
	spot.face_height = 1.65
	brain.extra_brief = func(): return [_line("brief")] if meeting else []
	brain.verdict.connect(_on_verdict)
	host.add_spot(spot)
	brain.line_done.connect(_on_line)        # after the host's: his line is on screen first
	_sync_spot()


## Issue #203: you step out of your ship and he is on you: the talk opens by itself.
func _meet_in_pit() -> void:
	if _where != "pit" or Story.chapter() != "general" or host == null or spot == null or bool(player.get("piloting")):
		return
	if player.global_position.distance_to(body.global_position) <= float(cfg.get("meet_reach", 9.0)):
		_begin_meeting()
		host.start_talk(spot)


## The pit meeting: Esc can't leave, and his brain is told to end it with a verdict.
func _begin_meeting() -> void:
	meeting = true
	_meet_lines = 0
	if spot != null:
		spot.hold_line = _line("hold") % npc_name()
		spot.brain.builder.extra_actions = ["let_go", "search"]


func _meet_cfg() -> Dictionary:
	return cfg.get("meeting", {})


## True while the pit is still his: the meeting, and a moment after it (T-89 waits).
func holding() -> bool:
	return meeting or _in_talk() or Time.get_ticks_msec() < _free_at


func _on_verdict(kind: String) -> void:
	if meeting:
		decide(kind)


## His brain's line in the meeting. A verdict came with it (decide() ran already),
## or he said end_conversation (that is letting them go), or after enough lines
## with neither the game gives his verdict for him.
func _on_line(turn: Dictionary) -> void:
	if not meeting:
		return
	var applied: Array = turn.get("applied", [])
	if applied.has("end_conversation"):
		decide("let_go", false)
		return
	_meet_lines += 1
	if _meet_lines >= int(_meet_cfg().get("turns", 4)) and decide(_fallback_verdict()) and verdict == "let_go":
		_say(_line("let_go"))
		host.panel.post_notice(said)


## What he would decide if he never said: insolence gets you searched.
func _fallback_verdict() -> String:
	return "search" if _talk_insults > 0 or (spot != null and spot.brain.insults > 0) else "let_go"


## His verdict in the pit meeting: let them go, or have them searched. Sets the
## Remnant standing they start with, and the talk closes a moment later (with
## `close` false, it is closing by itself). Returns false once he has given one.
func decide(kind: String, close: bool = true) -> bool:
	if verdict != "" or not kind in ["let_go", "search"]:
		return false
	meeting = false
	verdict = kind
	if spot != null:
		spot.hold_line = ""
		spot.brain.builder.extra_actions = []
	var st: Dictionary = _meet_cfg().get("standing", {})
	WorldState.change_standing("imperial_remnant", int(st.get(kind, 0)),
		"The Remnant general let a newcomer go." if kind == "let_go" else "The Remnant general had a newcomer searched.")
	WorldState.set_flag("general_" + kind)
	if kind == "search":
		searched += 1
		var took := WorldState.search_player()
		_say(_line("meeting_search") % (_line("meeting_took") % ", ".join(PackedStringArray(took)) if not took.is_empty() else _line("meeting_clean")))
		if _in_talk():
			host.panel.post_notice(said)
	if close and _in_talk():
		var t := get_tree().create_timer(float(_meet_cfg().get("end_delay", 3.0))) if is_inside_tree() else null
		if t != null:
			t.timeout.connect(_close_talk)
		else:
			host.end_talk()
	return true


func _in_talk() -> bool:
	return host != null and host.is_talking() and host.active == spot


func _close_talk() -> void:
	if _in_talk():
		host.end_talk()


## Each line he hears: an insult costs standing; when the talk ends, the story
## moves on (the pit meeting is over).
func _watch_talk() -> void:
	var talking: bool = host.is_talking() and host.active == spot
	if talking:
		var n: int = spot.brain.insults
		while _insults_seen < n:
			_insults_seen += 1
			on_insult()
	elif _was_talking:
		talk_ended()
	_was_talking = talking


## The player mouthed off: Remnant standing drops, and once too often in one talk
## his guards search them on the spot. Returns true when they were searched.
func on_insult() -> bool:
	WorldState.change_standing("imperial_remnant", int(cfg.get("insult_standing", -5)), "Someone mouthed off at the Remnant general.")
	_talk_insults += 1
	if _talk_insults < int(cfg.get("search_after", 2)):
		return false
	_talk_insults = 0
	if meeting:
		return decide("search")
	searched += 1
	var took := WorldState.search_player()
	_say(_line("searched") % ", ".join(PackedStringArray(took)) if not took.is_empty() else _line("searched_clean"))
	return true


## The talk is over: the pit meeting ends the chapter (T-89 next, and the pointer
## goes to him), and his tip comes if he likes you enough.
func talk_ended() -> void:
	if Story.chapter() == "general":
		decide(_fallback_verdict(), false)      # the talk closed without his verdict: the game gives it
		Story.event("general_done")
		_free_at = Time.get_ticks_msec() + int(1000.0 * float(_meet_cfg().get("after", 2.5)))
	meeting = false
	_talk_insults = 0
	maybe_tip()


# ------------------------------------------------------------------ droids (issue #204)

static func job_id() -> String:
	return "j_general_droids"


func job_active() -> bool:
	return str(WorldState.jobs_taken.get(job_id(), "")) == "active"


## Ask him for work. Not while you are hostile. Returns true when you took it.
func take_job() -> bool:
	var open := WorldState.open_jobs("stranger").any(func(j): return str(j.id) == job_id())
	if not open:
		_say(_line("no_work"))
		return false
	WorldState.accept_job(job_id())
	_say(_line("job_taken") % droid_pay())
	return true


## What one droid pays: pay_mult times the droid merchant's resale.
func droid_pay() -> int:
	return int(cfg.get("pay_mult", 3)) * DroidRoster.resale(str(cfg.get("droid_kind", "assassin")))


func droids_to_hand_over() -> Array:
	if not job_active():
		return []
	var kind := str(cfg.get("droid_kind", "assassin"))
	return WorldState.droids.owned.filter(func(d): return str(d.kind) == kind)


## Hand one of your droids over: he pays, your Remnant standing goes up, and the
## job is open again for the next one. Returns the pay, or -1.
func hand_over(uid: int) -> int:
	var d := WorldState.droids.find(uid)
	if d.is_empty() or not droids_to_hand_over().has(d):
		return -1
	WorldState.droids.unload(uid, WorldState.inventory)
	WorldState.droids.remove(uid)
	if demo != null and demo.get("droids") != null:
		demo.droids._free_companion(uid)
	var pay := droid_pay()
	WorldState.credits += pay
	WorldState.change_standing("imperial_remnant", int(cfg.get("droid_standing", 5)), "Someone sold the Remnant general an assassin droid.")
	WorldState.jobs_taken.erase(job_id())       # open again
	WorldState.bump("general_droids")
	_say(_line("paid") % pay)
	maybe_tip()
	return pay


## Issue #205: in good standing he tells you about the crashed cruiser, once.
func maybe_tip() -> bool:
	if Quests.state("crashed_cruiser") != "" or int(WorldState.standing.get("imperial_remnant", 0)) < int(cfg.get("tip_standing", 15)):
		return false
	Story.event("heard_of_wreck")
	_say(_line("tip"))
	return true
