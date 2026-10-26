extends GutTest
## M10: the dogfight director and its data. Ships, pilots and encounters load by id;
## every reference between them resolves; the director spawns the encounter, runs
## its waves, applies hits, and ends in COMPLETE or FAILED. The last test builds a
## brand-new ship, gun, pilot and encounter in a throwaway content folder and flies
## it with no code change -- the data-layer promise, applied to flight.

const CoreScript := preload("res://src/systems/dataload/core_content.gd")
const Dogfight := preload("res://src/systems/flight/dogfight.gd")

var content


func before_each() -> void:
	content = CoreScript.new()
	content.load_from()


# ---- data -------------------------------------------------------------------

func test_flight_content_loads_by_id() -> void:
	for id in ["interceptor", "remnant_fighter", "remnant_heavy"]:
		assert_eq(content.get_ship(id).get("id"), id, "ship loaded: " + id)
	for id in ["rookie", "veteran", "ace"]:
		assert_eq(content.get_pilot(id).get("id"), id, "pilot loaded: " + id)
	assert_eq(content.get_encounter("orbital_skirmish").get("id"), "orbital_skirmish")


func test_every_flight_reference_resolves() -> void:
	for sid in content.ships:
		var s: Dictionary = content.get_ship(sid)
		assert_false(content.get_pilot(str(s.pilot)).is_empty(), "%s pilot resolves" % sid)
		assert_false(content.get_faction(str(s.faction)).is_empty(), "%s faction resolves" % sid)
		assert_true(s.has("flight") and s.has("hull") and s.has("hit_radius"), "%s has flight stats" % sid)
		for hp in s.hardpoints:
			assert_false(content.get_weapon(str(hp.weapon)).is_empty(), "%s weapon %s resolves" % [sid, hp.weapon])
	for eid in content.encounters:
		var e: Dictionary = content.get_encounter(eid)
		assert_false(content.get_ship(str(e.player.ship)).is_empty(), "%s player ship resolves" % eid)
		for a in e.get("allies", []):
			assert_false(content.get_ship(str(a.ship)).is_empty(), "%s ally resolves" % eid)
		for w in e.waves:
			for entry in w.ships:
				assert_false(content.get_ship(str(entry.ship)).is_empty(), "%s wave ship resolves" % eid)


func test_ship_files_match_manifest() -> void:
	for cat in ["ships", "pilots", "encounters"]:
		for id in content.manifest.get(cat, []):
			assert_true(FileAccess.file_exists("res://content/core/%s/%s.json" % [cat, id]),
				"%s file exists: %s" % [cat, id])


# ---- director -----------------------------------------------------------------

func _start(seed: int = 1):
	var df = Dogfight.new(content, "orbital_skirmish", seed)
	df.start()
	return df


func test_start_spawns_player_and_wingman() -> void:
	var df = _start()
	assert_eq(df.state, Dogfight.State.RUNNING)
	assert_gt(df.player_id, 0, "a player ship exists")
	assert_eq(df.alive_on(Dogfight.TEAM_PLAYER).size(), 2, "player plus one wingman")
	assert_eq(df.alive_on(Dogfight.TEAM_HOSTILE).size(), 0, "no hostiles before the first wave")
	var me: Dictionary = df.get_ship(df.player_id)
	assert_null(me.brain, "a human flies the player by default")


func test_first_wave_arrives_after_its_delay() -> void:
	var df = _start()
	var delay := float(content.get_encounter("orbital_skirmish").waves[0].delay)
	var saw_wave := false
	for i in int((delay + 0.5) * 60.0):
		for e in df.step(1.0 / 60.0):
			if e.type == "wave":
				saw_wave = true
	assert_true(saw_wave, "the wave event fires")
	assert_eq(df.alive_on(Dogfight.TEAM_HOSTILE).size(), 3, "three remnant fighters")


func test_player_command_flies_the_player_ship() -> void:
	var df = _start()
	df.set_player_command(1.0, 0.0, 0.0, 1.0, false, false, false)
	for i in 30:
		df.step(1.0 / 60.0)
	var me: Dictionary = df.get_ship(df.player_id)
	assert_gt(me.flight.forward().y, 0.3, "pitch input raised the player's nose")


func test_player_guns_fire_on_the_trigger() -> void:
	var df = _start()
	df.set_player_command(0, 0, 0, 0.5, false, true, false)
	df.step(1.0 / 60.0)
	assert_eq(df.stats.shots, 2, "the trigger fires both cannons")


func test_player_seekers_need_a_lock() -> void:
	var df = _start()
	df.set_player_command(0, 0, 0, 0.5, false, false, true)
	for i in 10:
		df.step(1.0 / 60.0)
	assert_eq(df.stats.missiles, 0, "no lock, no launch")


func test_hits_damage_and_kills_are_reported() -> void:
	var df = _start()
	var foe: int = df.spawn_ship("remnant_fighter", Dogfight.TEAM_HOSTILE, Vector3(0, 0, -150),
		Vector3(0, 0, 1))
	df.set_player_command(0, 0, 0, 0.0, false, true, false)
	var kinds := {}
	for i in 180:
		for e in df.step(1.0 / 60.0):
			kinds[e.type] = true
	assert_true(kinds.has("hit"), "bolts hit the fighter ahead")
	assert_true(kinds.has("kill"), "enough hits destroy it")
	assert_false(df.get_ship(foe).alive, "the fighter is dead")
	assert_gte(df.stats.player_kills, 1, "the kill is credited to the player")


func test_player_death_fails_the_encounter() -> void:
	var df = _start()
	df.get_ship(df.player_id).defense.apply_damage(10000.0)
	df.get_ship(df.player_id).alive = false
	df.step(1.0 / 60.0)
	assert_eq(df.state, Dogfight.State.FAILED)


func test_clearing_every_wave_completes_with_payout() -> void:
	var df = _start()
	var payout := -1
	for i in 60 * 60:
		for e in df.step(1.0 / 60.0):
			if e.type == "complete":
				payout = e.payout
		# Remove hostiles as soon as they spawn: this test is about the wave logic.
		for s in df.alive_on(Dogfight.TEAM_HOSTILE):
			s.alive = false
		if df.state != Dogfight.State.RUNNING:
			break
	assert_eq(df.state, Dogfight.State.COMPLETE, "all waves cleared")
	assert_eq(df.stats.waves, 2, "both waves spawned")
	assert_eq(payout, int(content.get_encounter("orbital_skirmish").payout), "payout comes from data")


func test_cycle_target_walks_the_hostiles() -> void:
	var df = _start()
	var a: int = df.spawn_ship("remnant_fighter", Dogfight.TEAM_HOSTILE, Vector3(0, 0, -500), Vector3.BACK)
	var b: int = df.spawn_ship("remnant_fighter", Dogfight.TEAM_HOSTILE, Vector3(50, 0, -500), Vector3.BACK)
	df.cycle_player_target()
	var first: int = df.player_target_id
	df.cycle_player_target()
	assert_ne(df.player_target_id, first, "the next target is a different ship")
	assert_true(df.player_target_id in [a, b])


func test_unknown_ids_warn_instead_of_crashing() -> void:
	var df = _start()
	assert_eq(df.spawn_ship("no_such_ship", Dogfight.TEAM_HOSTILE, Vector3.ZERO, Vector3.FORWARD), -1)
	var empty = Dogfight.new(content, "no_such_encounter", 1)
	empty.start()
	assert_eq(empty.player_id, -1, "an unknown encounter spawns nothing")


# ---- extensibility --------------------------------------------------------------

func _write(path: String, data) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()


func test_a_new_ship_and_fight_need_only_data() -> void:
	var root := "user://m10_new_content"
	_write(root + "/manifest.json", { "weapons": ["test_lance"], "ships": ["test_corvette", "test_drone"],
		"pilots": ["test_pilot"], "encounters": ["test_brawl"] })
	_write(root + "/weapons/test_lance.json", { "id": "test_lance", "class": "ship_cannon",
		"fire_group": "primary", "damage": 40, "bolt_speed": 400.0, "rate": 0.3, "range": 800.0,
		"mag": 10, "reload_time": 1.0 })
	_write(root + "/pilots/test_pilot.json", { "id": "test_pilot", "aim_cone_deg": 10.0, "engage_range": 900.0 })
	_write(root + "/ships/test_corvette.json", { "id": "test_corvette", "look": "test_corvette",
		"pilot": "test_pilot", "hull": 300, "hit_radius": 6.0, "flight": { "max_speed": 30.0 },
		"hardpoints": [ { "weapon": "test_lance", "mount": [0, 0, -4] } ] })
	_write(root + "/ships/test_drone.json", { "id": "test_drone", "look": "test_drone",
		"pilot": "test_pilot", "hull": 20, "hit_radius": 1.5, "flight": { "max_speed": 60.0 },
		"hardpoints": [ { "weapon": "test_lance", "mount": [0, 0, -1] } ] })
	_write(root + "/encounters/test_brawl.json", { "id": "test_brawl", "payout": 5,
		"player": { "ship": "test_corvette", "spawn": [0, 0, 0], "facing": [0, 0, -1] },
		"waves": [ { "delay": 0.5, "spawn_distance": 500.0, "ships": [ { "ship": "test_drone", "count": 2 } ] } ] })

	var c = CoreScript.new()
	assert_true(c.load_from(root), "the new content folder loads")
	var df = Dogfight.new(c, "test_brawl", 2)
	df.start()
	df.set_player_autopilot(true)
	for i in 60 * 120:
		df.step(1.0 / 60.0)
		if df.state != Dogfight.State.RUNNING:
			break
	assert_eq(df.get_ship(df.player_id).ship_id, "test_corvette", "the player flies the new ship")
	assert_eq(df.stats.waves, 1, "the new encounter's wave spawned")
	assert_gt(df.stats.shots, 0, "the new gun fired")
	assert_ne(df.state, Dogfight.State.RUNNING, "the new fight reached an outcome")
