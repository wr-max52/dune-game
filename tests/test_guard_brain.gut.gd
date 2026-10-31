extends GutTest
## One guard's brain (guard_brain.gd, pure): it walks its loop and looks around,
## turns to a noise, attends a challenge, opens fire then runs for cover, hides,
## winds up and fires a burst only with the target in sight, fights in the open
## when there is no cover, searches on a leash, and goes home. Plus the cover
## picker and the player's health.

const CoreScript := preload("res://src/systems/dataload/core_content.gd")
const DT := 1.0 / 60.0

var prof: Dictionary


func before_each() -> void:
	var cc = CoreScript.new()
	cc.load_from()
	prof = cc.get_soldier("gate_guard")


func _brain() -> GuardBrain:
	var b := GuardBrain.new(prof, 3)
	b.patrol_points = [Vector3(95, 0, 9), Vector3(88, 0, 9), Vector3(88, 0, 11.5)]
	b.pos = Vector3(95, 0, 9)
	return b


## Run the brain, moving `pos` toward go_to at walking pace like a body would.
func _run(b: GuardBrain, seconds: float, speed: float = 3.2) -> void:
	for i in int(seconds * 60.0):
		b.update(DT)
		if b.go_to != Vector3.INF:
			var to := Vector3(b.go_to.x - b.pos.x, 0, b.go_to.z - b.pos.z)
			var step := minf(to.length(), (6.2 if b.sprint else speed) * DT)
			if to.length() > 0.001:
				b.pos += to.normalized() * step
		b.arrived = b.go_to == Vector3.INF or b.pos.distance_to(b.go_to) < 0.6
		if b.fire:
			b.on_shot()


func test_walks_the_loop_and_looks_around() -> void:
	var b := _brain()
	var visited := {}
	var faced := 0
	for i in 60 * 40:
		_run(b, DT)
		for j in b.patrol_points.size():
			if b.pos.distance_to(b.patrol_points[j]) < 1.0:
				visited[j] = true
		if b.go_to == Vector3.INF and b.face != Vector3.INF:
			faced += 1
	assert_eq(visited.size(), 3, "every point on the loop")
	assert_gt(faced, 60, "looks around while paused")
	assert_eq(b.state, GuardBrain.State.PATROL)


func test_turns_to_a_noise() -> void:
	var b := _brain()
	b.investigate(Vector3(100, 0, 20))
	_run(b, 0.5)
	assert_eq(b.face, Vector3(100, 0, 20))
	assert_eq(b.go_to, Vector3.INF, "stops to look")


func test_attends_a_challenge() -> void:
	var b := _brain()
	b.target_pos = Vector3(93, 0, 0)
	b.attend()
	_run(b, 0.2)
	assert_eq(b.state, GuardBrain.State.ATTEND)
	assert_eq(b.face, Vector3(93, 0, 0))
	assert_false(b.fire)
	b.patrol()
	_run(b, 0.2)
	assert_ne(b.state, GuardBrain.State.ATTEND)


func test_lead_walks_up_to_ask() -> void:
	var b := _brain()
	b.target_pos = Vector3(93, 0, 0)
	b.attend()
	b.walk_up = 2.2
	_run(b, 5.0)
	var d := Vector2(b.pos.x - 93.0, b.pos.z).length()
	assert_between(d, 1.5, 2.3, "stops a couple of metres off, not on top of you")
	assert_eq(b.go_to, Vector3.INF)
	assert_eq(b.face, Vector3(93, 0, 0))
	# A half step back: it stays put.
	b.target_pos = Vector3(93, 0, -0.5)
	_run(b, 0.5)
	assert_eq(b.go_to, Vector3.INF)


func test_opens_fire_then_runs_for_cover() -> void:
	var b := _brain()
	b.visible = true
	b.target_pos = Vector3(104, 0, 1)
	b.engage()
	var fired_first := false
	var asked := false
	for i in 60 * 3:
		_run(b, DT)
		if b.fire and not asked:
			fired_first = true
		if b.want_cover:
			asked = true
			b.want_cover = false
			b.cover = Vector3(88.5, 0, 4.8)
	assert_true(fired_first, "the opening burst comes before cover")
	assert_true(asked, "then asks for cover")
	assert_lt(b.pos.distance_to(Vector3(88.5, 0, 4.8)), 1.0, "and gets there")
	assert_true(b.fight == GuardBrain.Fight.HIDE or b.fight == GuardBrain.Fight.WINDUP or b.fight == GuardBrain.Fight.BURST)


func test_hides_low_and_only_fires_with_sight() -> void:
	var b := _brain()
	b.visible = false
	b.target_pos = Vector3(104, 0, 1)
	b.last_seen = Vector3(104, 0, 1)
	b.engage()
	b.want_cover = false
	b.cover = b.pos
	var crouched := false
	var fired := false
	for i in 60 * 4:
		_run(b, DT)
		crouched = crouched or b.crouch
		fired = fired or b.fire
	assert_true(crouched, "ducks behind cover")
	assert_false(fired, "never fires at what it cannot see")
	b.visible = true
	var shots := 0
	for i in 60 * 6:
		_run(b, DT)
		if b.fire:
			shots += 1
	assert_gt(shots, 0, "fires once the target shows")


func test_aim_misses_more_at_range_and_on_the_move() -> void:
	var b := _brain()
	b.pos = Vector3.ZERO
	var spread := func(at: Vector3, vel: Vector3) -> float:
		b.target_vel = vel
		var total := 0.0
		for i in 200:
			var a: Vector3 = b._aim_at(at)
			total += a.distance_to(at + Vector3(0, b.target_chest, 0))
		return total / 200.0
	var near: float = spread.call(Vector3(0, 0, 8), Vector3.ZERO)
	var far: float = spread.call(Vector3(0, 0, 30), Vector3.ZERO)
	var moving: float = spread.call(Vector3(0, 0, 30), Vector3(5, 0, 0))
	assert_gt(far, near, "worse at range")
	assert_gt(moving, far, "worse at a moving target")


func test_no_cover_fights_in_the_open() -> void:
	var b := _brain()
	b.visible = false
	b.target_pos = Vector3(104, 0, 1)
	b.last_seen = Vector3(104, 0, 1)
	b.engage()
	b.want_cover = false
	b.cover = Vector3.INF
	_run(b, 0.2)
	assert_eq(b.fight, GuardBrain.Fight.OPEN)
	b.visible = true
	var fired := false
	for i in 60 * 3:
		_run(b, DT)
		fired = fired or b.fire
	assert_true(fired)


func test_fight_with_nothing_to_go_on_stands_ready() -> void:
	var b := _brain()
	b.engage()
	_run(b, 1.0)
	assert_eq(b.go_to, Vector3.INF)
	assert_false(b.fire)


func test_searches_on_a_leash_then_goes_home() -> void:
	var b := _brain()
	b.target_pos = Vector3(104, 0, 1)
	b.engage()
	b.last_seen = Vector3(200, 0, 0)
	b.calm()
	assert_eq(b.state, GuardBrain.State.SEARCH)
	var farthest := 0.0
	for i in 60 * 30:
		_run(b, DT)
		farthest = maxf(farthest, b.pos.distance_to(b.patrol_points[0]))
	assert_lte(farthest, b.c("search_leash", 22.0) + 1.0, "does not chase into the desert")
	assert_eq(b.state, GuardBrain.State.PATROL, "back on the loop")


func test_barks_from_orders_are_not_lost() -> void:
	var b := _brain()
	b.visible = true
	b.engage()
	b.update(DT)
	assert_eq(b.bark, "contact", "the line asked for by engage() comes out on the next update")
	b.update(DT)
	assert_eq(b.bark, "", "once")


# ------------------------------------------------------------------ cover picker

func test_cover_spots_hide_from_the_threat() -> void:
	var boxes := [
		{ "id": "crate", "kind": "cover", "min": [0, 0, 0], "max": [2, 1.1, 2] },
		{ "id": "low", "kind": "cover", "min": [10, 0, 0], "max": [12, 0.5, 2] },
	]
	var spots := CoverPicker.candidates(boxes, Vector3(1, 0, 1), 20.0)
	assert_gt(spots.size(), 4)
	for s in spots:
		assert_eq(s.box, "crate", "a 0.5 m box hides nobody")
	var threat := Vector3(20, 0, 1)
	var i := CoverPicker.pick(Vector3(-5, 0, 1), threat, spots, [], 2.0, 40.0)
	assert_gte(i, 0)
	var p: Vector3 = spots[i].pos
	assert_lt(p.x, 0.0, "the spot is on the far side of the crate from the threat")
	assert_true(CoverPicker.covers(spots[i], threat))
	var j := CoverPicker.pick(Vector3(-5, 0, 1), threat, spots, [p], 2.0, 40.0)
	assert_true(j < 0 or (spots[j].pos as Vector3).distance_to(p) >= 1.2, "a claimed spot is not handed out twice")


func test_segment_rect() -> void:
	var r := [0.0, 0.0, 2.0, 2.0]
	assert_true(CoverPicker.segment_hits_rect(Vector2(-1, 1), Vector2(3, 1), r))
	assert_false(CoverPicker.segment_hits_rect(Vector2(-1, 3), Vector2(3, 3), r))
	assert_true(CoverPicker.segment_hits_rect(Vector2(-1, -1), Vector2(3, 3), r))
	assert_false(CoverPicker.segment_hits_rect(Vector2(-3, 0), Vector2(-1, 0), r))


func test_town_has_cover_at_the_gate() -> void:
	# Issue #237: in both ports, measured from the gate.
	for layout in ["port_square", "port_round"]:
		var t = preload("res://src/systems/world/town_layout.gd").new()
		t.load_town("port_town", layout)
		var gate: Vector3 = t.marker_pos("gate")
		var spots := CoverPicker.candidates(t.boxes(), gate, 28.0)
		var outside := gate + Vector3(11, 0, 0)
		var hiding := 0
		for s in spots:
			if (s.pos as Vector3).x < gate.x - 1.0 and CoverPicker.covers(s, outside):
				hiding += 1
		assert_gte(hiding, 4, "%s: the barricades and walls give the guards somewhere to hide from the desert side" % layout)


# ------------------------------------------------------------------ player health

func test_player_health_regens_and_downs() -> void:
	var body = preload("res://src/systems/player/character_body.gd").new()
	add_child_autofree(body)
	var downs := [0]
	body.downed.connect(func(): downs[0] += 1)
	body.apply_damage(30.0)
	assert_eq(body.health.hp, 70)
	for i in int(60 * 2):
		body._tick_health(DT)
	assert_eq(body.health.hp, 70, "no regen right after a hit")
	for i in int(60 * 6):
		body._tick_health(DT)
	assert_gt(body.health.hp, 90, "comes back after a few quiet seconds")
	body.apply_damage(200.0)
	assert_true(body.is_downed)
	assert_eq(downs[0], 1)
	body.apply_damage(10.0)
	assert_eq(downs[0], 1, "downed once")
	body.revive(2.0)
	assert_false(body.is_downed)
	assert_eq(body.health.hp, body.max_health)
	body.apply_damage(50.0)
	assert_eq(body.health.hp, body.max_health, "a grace period after waking up")
