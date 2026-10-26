extends GutTest
## M10: the headless dogfight trace (scenes/m10_dogfight_trace.gd), the machine proof
## of "fly a starfighter and win a dogfight":
##   - the encounter runs to COMPLETE with every wave spawned and every hostile killed,
##   - the player ship (flown by the bot) scores kills with guns and seekers,
##   - the enemy fights back: the player takes hits,
##   - the AI really dogfights: pursue, attack, break and extend all appear,
##   - and no simulation frame comes near the 50ms budget.
## The playable scene is smoke-tested at the end.

const TRACE := "res://test_results/m10_dogfight_trace.txt"
const Demo := preload("res://scenes/flight/dogfight_demo.gd")


func _lines() -> PackedStringArray:
	var f := FileAccess.open(TRACE, FileAccess.READ)
	var text: String = f.get_as_text()
	f.close()
	return text.split("\n")


func _result() -> Dictionary:
	var out := {}
	for l in _lines():
		if l.begins_with("RESULT "):
			for kv in l.substr(7).split(" ", false):
				var p := kv.split("=")
				if p.size() == 2:
					out[p[0]] = p[1]
	return out


func _states() -> PackedStringArray:
	for l in _lines():
		if l.begins_with("STATES "):
			return l.substr(7).split(" ", false)
	return PackedStringArray()


func test_trace_exists_with_rows() -> void:
	assert_true(FileAccess.file_exists(TRACE), "the trace exists after the trace run")
	var rows := 0
	for l in _lines():
		if l.begins_with("t="):
			rows += 1
	assert_gt(rows, 20, "the trace records the fight over time")


func test_encounter_completes() -> void:
	var r := _result()
	assert_eq(r.get("state"), "COMPLETE", "the dogfight is won")
	assert_eq(int(r.get("waves", 0)), 2, "both waves spawned")
	assert_eq(int(r.get("kills", 0)), 7, "all seven hostiles destroyed")
	assert_gt(int(r.get("player_hull", 0)), 0, "the player survived")


func test_player_scores_with_guns_and_seekers() -> void:
	var r := _result()
	assert_gt(int(r.get("player_kills", 0)), 0, "the player ship got kills")
	assert_gt(int(r.get("hits", 0)), 20, "cannons land hits")
	assert_gt(int(r.get("missiles", 0)), 0, "seekers were launched after a lock")
	assert_gt(int(r.get("missile_hits", 0)), 0, "and some found their target")
	assert_lt(int(r.get("missile_hits", 0)), int(r.get("missiles", 0)), "and some were evaded")


func test_enemies_fight_back() -> void:
	var r := _result()
	assert_gt(int(r.get("player_hits_taken", 0)), 0, "the remnant pilots hit the player")
	assert_gt(int(r.get("shots", 0)), 0, "shots were fired")


func test_ai_uses_every_dogfight_action() -> void:
	var s := _states()
	for action in ["PURSUE", "ATTACK", "BREAK", "EXTEND"]:
		assert_true(s.has(action), "AI used %s" % action)


func test_waves_arrive_in_order() -> void:
	var idx: Array = []
	for l in _lines():
		if l.begins_with("EVENT") and l.contains(" wave "):
			idx.append(int(l.split("index=")[1].split(" ")[0]))
	assert_eq(idx, [1, 2], "wave 1 then wave 2")


func test_no_frame_over_budget() -> void:
	var r := _result()
	assert_lt(float(r.get("worst_ms", 999.0)), 50.0, "worst simulation frame under the 50ms budget")


func test_playable_scene_builds_and_runs() -> void:
	var demo = Demo.new()
	demo.autopilot = true
	add_child_autofree(demo)
	assert_not_null(demo.df, "the scene owns a dogfight director")
	assert_eq(demo.ship_nodes.size(), demo.df.ships.size(), "one ship node per ship")
	demo.warm_up(4.0)
	for i in 10:
		demo._process(1.0 / 60.0)
	assert_eq(demo.ship_nodes.size(), demo.df.ships.size(), "wave ships got nodes too")
	var me: Dictionary = demo.df.get_ship(demo.df.player_id)
	var node: Node3D = demo.ship_nodes[demo.df.player_id]
	assert_almost_eq(node.global_position.distance_to(me.flight.position), 0.0, 0.001,
		"the player's ship node tracks the flight model")
	assert_gt(demo.bolt_nodes.size() + demo.df.stats.shots, 0, "bolts are in play")
	assert_true(demo.hud_label.text.contains("SHIELD"), "the HUD shows ship status")
