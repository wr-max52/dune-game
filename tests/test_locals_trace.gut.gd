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
	var cc := CoreContent.new()
	cc.load_from()
	var walkers := 0
	var keepers := 0
	for m in _town().markers():
		if str(m.get("role", "")) != "ambient":
			continue
		var p: Dictionary = cc.get_soldier(str(m.get("soldier", "")))
		assert_false(p.is_empty(), "%s names a soldier profile" % m.id)
		assert_eq(str(p.get("faction", "")), "locals", "%s is a local" % m.id)
		if bool(p.get("combat", {}).get("hold_ground", false)):
			keepers += 1
			assert_false(m.has("patrol"), "%s keeps a stall, it does not walk" % m.id)
		else:
			walkers += 1
			assert_gte(_town().route_points_3d(str(m.get("patrol", ""))).size(), 2, "%s walks a loop" % m.id)
	assert_eq(walkers, 5, "five locals walk the houses and the market")
	assert_eq(keepers, 4, "three merchants and the fence")


func test_every_vendor_has_a_keeper() -> void:
	var cc := CoreContent.new()
	cc.load_from()
	var t := _town()
	for v in cc.vendors_in("port_town"):
		var m: Dictionary = t.get_marker(str(v.marker))
		assert_true(m.has("soldier"), "%s's stall has someone behind it" % v.id)
	assert_eq(str(t.get_marker(str(cc.get_vendor("fence").marker)).soldier), "local_fence")


func test_stalls_face_each_other() -> void:
	# Each keeper stands between a back panel and a counter, and looks across the
	# counter into the one aisle both rows open onto.
	var t := _town()
	var aisle_z := []
	for m in t.markers():
		if not m.has("face"):
			continue
		var p := t.marker_pos(str(m.id))
		var face := Vector3(float(m.face[0]), float(m.face[1]), float(m.face[2]))
		aisle_z.append(face.z)
		var counter := false
		var back := false
		for b in t.boxes():
			if str(b.zone) != "market" or p.x < float(b.min[0]) or p.x > float(b.max[0]):
				continue
			var bz := (float(b.min[2]) + float(b.max[2])) * 0.5
			if str(b.kind) == "cover" and signf(bz - p.z) == signf(face.z - p.z) and absf(bz - p.z) < 2.5:
				counter = true
			if str(b.kind) == "solid" and signf(bz - p.z) == -signf(face.z - p.z) and absf(bz - p.z) < 2.5:
				back = true
		assert_true(counter, "%s has a counter toward the aisle" % m.id)
		assert_true(back, "%s has a back panel behind" % m.id)
	assert_eq(aisle_z.size(), 4)
	for z in aisle_z:
		assert_eq(z, aisle_z[0], "one shared aisle")
	var north := 0
	for m in t.markers():
		if m.has("face"):
			north += 1 if float(m.pos[2]) > float(m.face[2]) else 0
	assert_true(north > 0 and north < 4, "keepers on both sides of the aisle")


# ------------------------------------------------------------------ trace

func test_trace_ran_clean() -> void:
	assert_true(FileAccess.file_exists(TRACE), "trace exists (run scenes/locals_trace.gd)")
	assert_eq(_s("FAILED"), "false")
	assert_lt(_f("WORST_FRAME_MS"), 50.0, "no frame over budget")


func test_locals_go_about_their_day() -> void:
	assert_eq(int(_f("STROLL_LOCALS")), 9)
	assert_eq(int(_f("STROLL_GARRISON")), 5, "the garrison is still just the troopers")
	assert_eq(int(_f("STROLL_WALKED")), 5, "every walker walked its loop")
	assert_true(_b("STROLL_MERCHANTS_STAYED"), "merchants mind their stalls")
	assert_true(_b("STROLL_MERCHANTS_FACE_AISLE"), "merchants face the aisle")
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
