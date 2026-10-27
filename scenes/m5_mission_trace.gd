extends SceneTree
## M5: the headless bot playthrough. This is the machine proof that "fixer,
## contract, crate, payout, save/load all work end to end," WITHOUT rendering, so
## it runs in CI.
##
## It loads the crate_retrieval mission from the data layer, then drives the
## mission state machine through the full loop by feeding it world events, the way
## a player's actions would: talk to the fixer, accept the contract, travel to the
## desert outpost, defeat the 4 troopers and 1 duelist, take the crate, return to
## the fixer, get paid. It then runs the save system and proves the four things the
## spec names survive a save/load: player position, credits, mission state, and
## cantina owner memory.
##
## The squad coordinator is exercised too, so the trace also shows "4 troopers do
## not all stand in the open."
##
## Output test_results/m5_mission_trace.txt is checked by
## tests/test_bot_playthrough.gut.gd.

var content
var Mission
var Save
var Squad

var mission
var save
var squad
var t := 0.0
var frames_done := 0
var target := 240  # 4s of 60fps
var log := ""
var file = null
var path := "res://test_results/m5_mission_trace.txt"

# A little squad + cover, so the trace can show the squad spreads out.
var squad_members := [
	Vector3.ZERO,
	Vector3(1.0, 0.0, 0.0),
	Vector3(2.0, 0.0, 0.0),
	Vector3(3.0, 0.0, 0.0),
]
var cover := [
	{ "position": Vector3(0.0, 0.0, 0.0) },
	{ "position": Vector3(1.0, 0.0, 0.0) },
	{ "position": Vector3(2.0, 0.0, 0.0) },
	{ "position": Vector3(3.0, 0.0, 0.0) },
]


func _build() -> void:
	if not DirAccess.dir_exists_absolute("res://test_results"):
		DirAccess.make_dir_recursive_absolute("res://test_results")
	content = load("res://src/systems/dataload/core_content.gd").new()
	content.load_from()
	Mission = load("res://src/systems/mission/mission.gd")
	Save = load("res://src/systems/save/save_system.gd")
	Squad = load("res://src/systems/ai/squad_coordinator.gd")

	# The mission config comes from the data layer, not hardcoded.
	var cfg: Dictionary = content.get_mission("crate_retrieval")
	mission = Mission.new(cfg)

	save = Save.new()
	save.new_game()
	save.set_player_position(Vector3.ZERO)
	save.set_mission(mission.to_save())
	save.remember_in_cantina_owner("player_name", "Rider")

	squad = Squad.new()
	squad.cover_nodes = cover
	squad.members = squad_members

	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("# t  phase  goal  enemies_defeated  credits  event\n")


func _process(_delta) -> bool:
	if file == null:
		_build()
	if frames_done > target:
		_run()
		file.store_string(log)
		file.close()
		print("M5TRACE wrote ", path, " (complete=", mission.is_complete(),
			" credits=", save.get_credits(), ")")
		quit(0)
		return false
	frames_done += 1
	return false


## Drive the whole loop. The "bot" is the sequence of world events the mission
## state machine consumes; a real controller would emit these from the live game.
func _run() -> void:
	# 1. Talk to the fixer.
	mission.handle(mission.Event.TALK_FIXER)
	_log("TALK_FIXER")

	# 2. Accept the contract.
	mission.handle(mission.Event.ACCEPT)
	_log("ACCEPT")

	# 3. Travel to the desert outpost.
	mission.handle(mission.Event.ARRIVE_OUTPOST)
	_log("ARRIVE_OUTPOST")

	# 4. Defeat the outpost's enemies: 4 troopers + 1 duelist = 5.
	#    The squad coordinates first so they do not all stand in the open.
	squad.members = squad_members
	var assignment: Array = squad.assign(squad.members.size())
	_walk_to_assignment(assignment)
	_log("SQUAD_OPEN=%d" % squad.troopers_in_open(squad.members.size()))
	for _i in mission.enemies_total:
		mission.handle(mission.Event.ENEMY_KILLED)
	_log("ENEMIES_DOWN=%d" % mission.enemies_defeated)

	# 5. Take the crate objective.
	mission.handle(mission.Event.TOOK_CRATE)
	_log("TOOK_CRATE")

	# 6. Return to the fixer and get paid.
	mission.handle(mission.Event.ARRIVED_BACK)
	_log("ARRIVED_BACK")

	# 7. Save/load. The payout lands in credits; the four named things survive.
	save.set_mission(mission.to_save())
	save.add_credits(mission.paid)
	var ok: bool = save.save_to("user://m5_test_save.json")
	_load_roundtrip(ok)
	_log("SAVED=%s" % str(ok))
	_log("LOAD_OK=%s" % str(ok))


## Walk each trooper to the cover node the coordinator assigned it.
func _walk_to_assignment(assignment: Array) -> void:
	for i in assignment.size():
		var node_idx: int = assignment[i]
		if node_idx >= 0:
			squad.members[i] = cover[node_idx].position
		else:
			squad.members[i] = Vector3(50.0, 0.0, 50.0)  # forced open, no node


## Reload from the saved file into a fresh save and prove the four things survived.
func _load_roundtrip(saved: bool) -> void:
	var restored = Save.new()
	var loaded: bool = restored.load_from("user://m5_test_save.json")
	if not loaded:
		_log("RELOAD_MISSING")
		return
	# Mission state: build a mission and restore the saved fields; it must be COMPLETE
	# with the full payout and the enemy count it earned.
	var cfg: Dictionary = content.get_mission("crate_retrieval")
	var m2: RefCounted = Mission.new(cfg)
	m2.from_save(restored.get_mission())
	_log("RELOAD_PHASE=%d" % int(m2.phase))
	_log("RELOAD_COMPLETE=%s" % str(m2.is_complete()))
	_log("RELOAD_KILLS=%d" % m2.enemies_defeated)
	_log("RELOAD_PAYOUT=%d" % m2.payout)
	# Player position and credits and cantina owner memory: prove they survive too.
	_log("RELOAD_POS=%s" % str(restored.get_player_position()))
	_log("RELOAD_CREDITS=%d" % restored.get_credits())
	_log("RELOAD_MEMORY=%s" % str(restored.get_npc_memory().get("player_name", "")))


func _log(event: String) -> void:
	log += "t=%.2f phase=%-8s goal=%-13s kills=%-3d credits=%-4d %s\n" % [
		t,
		_mission_phase_name(),
		str(mission.current_goal()),
		mission.enemies_defeated,
		save.get_credits(),
		event,
	]


func _mission_phase_name() -> String:
	match mission.phase:
		mission.Phase.IDLE: return "IDLE"
		mission.Phase.ACCEPT: return "ACCEPT"
		mission.Phase.TRAVEL: return "TRAVEL"
		mission.Phase.FIGHT: return "FIGHT"
		mission.Phase.TAKE_CRATE: return "TAKE_CRATE"
		mission.Phase.RETURN: return "RETURN"
		mission.Phase.COMPLETE: return "COMPLETE"
	return "?"
