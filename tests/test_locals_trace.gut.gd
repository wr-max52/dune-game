extends GutTest
## The port's locals with real physics (scenes/locals_trace.gd), and the data they
## stand on: who walks where, who keeps which stall, and a market whose stalls
## face each other across the aisle.

const TRACE := "res://test_results/locals_trace.txt"
const TownLayout := preload("res://src/systems/world/town_layout.gd")
const CoreContent := preload("res://src/systems/dataload/core_content.gd")

var kv := {}


func before_all() -> void:
	var f := FileAccess.open(TRACE, FileAccess.READ)
	if f == null:
		return
	for l in f.get_as_text().split("\n", false):
		var i := l.find("=")
		if i > 0 and not l.begins_with("#"):
			kv[l.substr(0, i)] = l.substr(i + 1)
	f.close()


func _f(k: String) -> float:
	return float(kv.get(k, "nan"))


func _b(k: String) -> bool:
	return str(kv.get(k, "")) == "true"


func _s(k: String) -> String:
	return str(kv.get(k, ""))


func _town() -> TownLayout:
	var t := TownLayout.new()
	t.load_town("port_town")
	return t


# ------------------------------------------------------------------ data

func test_every_local_has_a_locals_profile() -> void:
	# Issue #545: the round port's locals are of three kinds: walkers on a loop,
	# keepers behind a stall, and those who stand or sit at a spot facing
	# something (bar and club patrons, the band, dock workers).
	var cc := CoreContent.new()
	cc.load_from()
	var t := _town()
	var walkers := 0
	var keepers := 0
	var standing := 0
	for m in t.markers():
		if str(m.get("role", "")) != "ambient" or not m.has("soldier"):
			continue
		var p: Dictionary = cc.get_soldier(str(m.get("soldier", "")))
		assert_false(p.is_empty(), "%s names a soldier profile" % m.id)
		assert_eq(str(p.get("faction", "")), "locals", "%s is a local" % m.id)
		if m.has("patrol"):
			walkers += 1
			assert_gte(t.route_points_3d(str(m.patrol)).size(), 2, "%s walks a loop" % m.id)
		elif _keeper(m):
			keepers += 1
		else:
			standing += 1
			assert_true(m.has("face"), "%s stands at a spot facing something" % m.id)
	assert_eq(walkers, 15, "the houses', the market's and the club's walkers")
	assert_eq(keepers, 12, "eleven merchants and the fence")
	assert_eq(standing, 17, "patrons, the band and the dock workers")


## A stall keeper: a merchant or the fence.
func _keeper(m: Dictionary) -> bool:
	return str(m.get("soldier", "")) in ["local_merchant", "local_fence"]


func test_every_vendor_has_a_keeper() -> void:
	var cc := CoreContent.new()
	cc.load_from()
	var t := _town()
	for v in cc.vendors_in("port_town"):
		var m: Dictionary = t.get_marker(str(v.marker))
		assert_true(m.has("soldier"), "%s's stall has someone behind it" % v.id)
	assert_eq(str(t.get_marker(str(cc.get_vendor("fence").marker)).soldier), "local_fence")


func test_stalls_face_each_other() -> void:
	# Each keeper stands between a back panel and a counter and looks across the
	# counter. Issue #545: the round market's stalls face along x or z, so "in
	# front" is along each keeper's own facing.
	var t := _town()
	var keepers := 0
	for m in t.markers():
		if not (m.has("face") and _keeper(m)):
			continue
		keepers += 1
		var p := t.marker_pos(str(m.id))
		var face := Vector3(float(m.face[0]), float(m.face[1]), float(m.face[2]))
		var along_x := absf(face.x - p.x) > absf(face.z - p.z)
		var ahead := signf((face.x - p.x) if along_x else (face.z - p.z))
		var counter := false
		var back := false
		for b in t.boxes():
			if str(b.get("zone", "")) != "market":
				continue
			var lo := float(b.min[2 if along_x else 0]) - 0.5
			var hi := float(b.max[2 if along_x else 0]) + 0.5
			var side := p.z if along_x else p.x
			if side < lo or side > hi:
				continue
			var c := (float(b.min[0 if along_x else 2]) + float(b.max[0 if along_x else 2])) * 0.5
			var d := c - (p.x if along_x else p.z)
			if str(b.kind) == "cover" and signf(d) == ahead and absf(d) < 2.5:
				counter = true
			if str(b.kind) == "solid" and signf(d) == -ahead and absf(d) < 2.5:
				back = true
		assert_true(counter, "%s has a counter in front" % m.id)
		assert_true(back, "%s has a back panel behind" % m.id)
	assert_eq(keepers, 12, "every keeper checked")


# ------------------------------------------------------------------ trace

func test_trace_ran_clean() -> void:
	assert_true(FileAccess.file_exists(TRACE), "trace exists (run scenes/locals_trace.gd)")
	assert_eq(_s("FAILED"), "false")
	assert_lt(_f("WORST_FRAME_MS"), 50.0, "no frame over budget")


func test_locals_go_about_their_day() -> void:
	assert_eq(int(_f("STROLL_LOCALS")), 41)
	assert_eq(int(_f("STROLL_MERCHANTS")), 12, "eleven merchants and the fence")
	assert_eq(int(_f("STROLL_GARRISON_LOCALS")), 0, "the garrison is still just the troopers")
	assert_eq(int(_f("STROLL_WALKED")), int(_f("STROLL_PATROLLERS")), "every walker walked its loop")
	assert_gte(int(_f("STROLL_PATROLLERS")), 5)
	assert_true(_b("STROLL_MERCHANTS_STAYED"), "merchants mind their stalls")
	assert_true(_b("STROLL_MERCHANTS_FACE_COUNTERS"), "merchants face across their counters")
	assert_eq(_s("STROLL_ALARM"), "CALM", "walking through the market starts nothing")
	assert_true(_b("STROLL_TRADER_OPEN"))


func test_shoot_a_local_and_the_town_fights() -> void:
	assert_true(_b("MARKET_HIT"))
	assert_eq(_s("MARKET_ALARM"), "ALARM")
	assert_eq(_s("MARKET_ALARM_WHY"), "attacked")
	assert_true(_b("MARKET_SAID_ALARM"))
	assert_eq(_s("MARKET_GARRISON_ALARM"), "CALM", "the locals' fight is not the Remnant's")
	assert_eq(int(_f("MARKET_FIGHTING")), int(_f("MARKET_ALIVE")), "every living local fights")
	assert_false(_b("MARKET_TRADER_OPEN"), "no trade mid-fight")
	assert_gt(_f("MARKET_MERCHANT_SHOTS"), 0.0, "merchants shoot back")
	assert_true(_b("MARKET_MERCHANTS_STAYED"), "and never leave the stall")
	assert_true(_b("MARKET_PLAYER_HURT"), "and they hit")
	assert_gte(_f("MARKET_STANDING_DROP"), 10.0, "the locals remember")


func test_one_alarm_for_every_local() -> void:
	assert_true(_b("HOUSES_HIT"))
	assert_eq(_s("HOUSES_ALARM"), "ALARM")
	assert_true(_b("HOUSES_EAST_FIGHTING"), "the east houses join a west fight")
	assert_gt(_f("HOUSES_RESIDENT_SHOTS"), 0.0, "the resident shoots back")
