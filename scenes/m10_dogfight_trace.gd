extends SceneTree
## M10: a headless dogfight trace. Proves "a starfighter flies, fights, and the enemy
## fighters dogfight back" WITHOUT rendering, so it runs in CI.
##
## The orbital_skirmish encounter is loaded from data and run at 60fps. The player
## ship is flown by the same fighter AI as everyone else (the M5 bot rule: the bot
## flies the real flight model and guns). Every 0.5s a row records the player's
## shield/hull, how many ships are alive on each side, and every live ship's AI
## action; every hit, kill, missile and wave is logged as an EVENT line; a RESULT
## line closes the run with totals and the worst frame cost.
##
## Output test_results/m10_dogfight_trace.txt is checked by tests/test_m10_dogfight.gut.gd.

const ENCOUNTER := "orbital_skirmish"
const SEED := 9

var Content
var Dogfight
var df

var dt := 1.0 / 60.0
var max_frames := 60 * 180   # give up after 3 simulated minutes
var frames := 0
var log := ""
var file = null
var path := "res://test_results/m10_dogfight_trace.txt"
var worst_ms := 0.0
var sum_ms := 0.0
var states_seen := {}
var player_hits_taken := 0


func _build() -> void:
	if not DirAccess.dir_exists_absolute("res://test_results"):
		DirAccess.make_dir_recursive_absolute("res://test_results")
	Content = load("res://src/systems/dataload/core_content.gd")
	Dogfight = load("res://src/systems/flight/dogfight.gd")
	var content = Content.new()
	content.load_from()
	df = Dogfight.new(content, ENCOUNTER, SEED)
	df.start()
	df.set_player_autopilot(true)
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("# M10 dogfight trace: encounter=%s seed=%d\n" % [ENCOUNTER, SEED])
	file.store_string("# t  player_shield  player_hull  allies  hostiles  wave  player_ai  actions\n")


func _process(_delta) -> bool:
	if file == null:
		_build()
	var done: bool = df.state != Dogfight.State.RUNNING or frames >= max_frames
	if done:
		_finish()
		quit(0)
		return false
	var t0 := Time.get_ticks_usec()
	var ev: Array = df.step(dt)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	worst_ms = maxf(worst_ms, ms)
	sum_ms += ms
	frames += 1
	for e in ev:
		_log_event(e)
	for s in df.ships:
		if s.alive and s.brain != null:
			states_seen[s.brain.state_label()] = true
	if frames % 30 == 0:
		_row()
	return false


func _row() -> void:
	var me: Dictionary = df.get_ship(df.player_id)
	var pai := "NONE"
	if not me.is_empty() and me.brain != null:
		pai = me.brain.state_label()
	var acts := PackedStringArray()
	for s in df.ships:
		if s.alive and s.brain != null:
			acts.append("%d:%s" % [s.id, s.brain.state_label()])
	log += "t=%.2f shield=%d hull=%d allies=%d hostiles=%d wave=%d ai=%s %s\n" % [
		df.t, int(me.defense.shield), me.defense.hull_hp(),
		df.alive_on(Dogfight.TEAM_PLAYER).size(), df.alive_on(Dogfight.TEAM_HOSTILE).size(),
		df.stats.waves, pai, " ".join(acts)]


func _log_event(e: Dictionary) -> void:
	match str(e.type):
		"wave":
			log += "EVENT t=%.2f wave index=%d count=%d\n" % [df.t, e.index, e.count]
		"kill":
			log += "EVENT t=%.2f kill victim=%d ship=%s team=%s by=%d\n" % [df.t, e.id, e.ship_id, e.team, e.by]
		"missile":
			log += "EVENT t=%.2f missile from=%d target=%d\n" % [df.t, e.id, e.target]
		"hit":
			if int(e.id) == df.player_id:
				player_hits_taken += 1
			if str(e.kind) == "missile":
				log += "EVENT t=%.2f missile_hit victim=%d by=%d\n" % [df.t, e.id, e.by]
		"complete":
			log += "EVENT t=%.2f complete payout=%d\n" % [df.t, e.payout]
		"failed":
			log += "EVENT t=%.2f failed\n" % df.t


func _finish() -> void:
	var me: Dictionary = df.get_ship(df.player_id)
	var keys := states_seen.keys()
	keys.sort()
	log += "STATES %s\n" % " ".join(PackedStringArray(keys))
	log += "RESULT state=%s t=%.2f waves=%d kills=%d player_kills=%d shots=%d hits=%d missiles=%d missile_hits=%d player_hull=%d player_hits_taken=%d worst_ms=%.3f avg_ms=%.4f frames=%d\n" % [
		df.state_label(), df.t, df.stats.waves, df.stats.kills, df.stats.player_kills,
		df.stats.shots, df.stats.hits, df.stats.missiles, df.stats.missile_hits,
		me.defense.hull_hp(), player_hits_taken,
		worst_ms, sum_ms / maxf(1.0, frames), frames]
	file.store_string(log)
	file.close()
	print("M10TRACE wrote ", path, " (", frames, " frames, ", df.state_label(), ")")
