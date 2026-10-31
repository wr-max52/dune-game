extends GutTest
## Oda's asteroid run: the station's own repeated smuggling loop. The drop lands
## on the open rock outside the sealed station, and the merchant in front of the
## cantina buys it. The port's run must stay at the port.

const CoreContent := preload("res://src/systems/dataload/core_content.gd")
const TownLayout := preload("res://src/systems/world/town_layout.gd")
const JOB := "j_station_smuggle_run"

var content
var town


func before_each() -> void:
	GameFlow.reset()
	GameFlow.planet_id = "grit_station"
	WorldState.reset()
	content = CoreContent.new()
	content.load_from()
	var planet: Dictionary = PlanetGen.make(content.planets["grit_station"], content)
	town = TownLayout.new()
	town.load_from_dict(planet.get("town", {}))


func after_each() -> void:
	WorldState.reset()
	GameFlow.reset()


func _offered() -> Dictionary:
	for j in WorldState.open_jobs("stranger"):
		if str(j.id) == JOB:
			return j
	return {}


## Pick up the drop and sell everything to the station merchant, as GearController would.
func _run_once() -> Dictionary:
	assert_true(WorldState.accept_job(JOB), "the job can be taken")
	var drop := WorldState.smuggle_drop()
	assert_false(drop.is_empty(), "taking it puts a drop in the world")
	assert_true(WorldState.inventory.pick_up(drop))
	assert_true(WorldState.smuggle_drop().is_empty(), "a picked-up drop is gone")
	var fence: Dictionary = content.get_vendor("station_fence")
	var item: Dictionary = content.get_item(str(drop.item))
	for i in int(drop.count):
		var paid := WorldState.inventory.sell(str(drop.item), item, fence)
		assert_gt(paid, 0, "the station merchant buys each unit")
		WorldState.credits += paid
	WorldState.on_contraband_sold()
	return drop


func test_the_station_offers_only_its_own_run() -> void:
	var jobs := WorldState.open_jobs("stranger")
	var runs := jobs.filter(func(j): return str(j.get("kind", "")) == "smuggle")
	assert_eq(runs.size(), 1, "one smuggling run at the station")
	assert_eq(str(runs[0].get("id", "")), JOB)
	assert_eq(str(runs[0].get("location", "")), "grit_station_town")
	assert_false(jobs.map(func(j): return str(j.get("id", ""))).has("j_smuggle_run"),
		"the port's run is not offered off the home planet")
	assert_eq(str(WorldState.smuggle_offers[JOB].location), "grit_station_town")
	assert_true(WorldState.smuggle_drop().is_empty(), "nothing in the world until you take it")


func test_the_offer_names_the_rock_and_the_station_merchant() -> void:
	var j := _offered()
	assert_false(j.is_empty())
	assert_false(str(j.text).contains("%"), "the text is filled in")
	assert_true(str(j.text).contains("rock"), "it says the drop is out on the rock")
	assert_true(str(j.text).to_lower().contains("merchant"), "and who buys it")


func test_accepting_puts_it_outside_on_the_rock() -> void:
	assert_true(WorldState.accept_job(JOB))
	var drop := WorldState.smuggle_drop()
	assert_eq(str(drop.location), "grit_station_town")
	assert_eq(str(drop.marker), "gate")
	assert_true(bool(drop.ground), "it is on the ground")
	assert_true(bool(drop.surface), "exactly on the rock, not above it")
	assert_true(bool(drop.marked), "far out, so it gets a beacon")
	assert_false(town.get_marker(str(drop.marker)).is_empty(), "the marker exists")
	var p := _spot(drop)
	var st: Dictionary = town.data.station
	var c: Array = st.center
	assert_gt(Vector2(p.x - float(c[0]), p.z - float(c[2])).length(), float(st.radius) + 20.0,
		"well outside the sealed ring")
	var pit: Dictionary = st.pit
	var pc: Array = pit.center
	assert_gt(Vector2(p.x - float(pc[0]), p.z - float(pc[2])).length(), float(pit.radius) + 20.0,
		"and clear of the landing pit")


func test_every_rock_spot_is_outside_the_station() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://content/core/pickups/grit_station_town.json"))
	var areas: Array = d.drops.areas
	assert_gte(areas.size(), 3, "rock past the pit, behind the cantina, beside the dome")
	for a in areas:
		assert_false(town.get_marker(str(a.marker)).is_empty(), "%s marker exists" % a.id)
		assert_true(bool(a.get("ground", false)), "%s sits on the ground" % a.id)
		assert_true(bool(a.get("surface", false)), "%s sits exactly on the rock" % a.id)
		assert_true(bool(a.get("marked", false)), "%s has a beacon" % a.id)
		assert_gte((a.spots as Array).size(), 3, "%s has several spots" % a.id)
		var hint := str(a.get("hint", "")).to_lower()
		for word in ["north", "south", "east", "west"]:
			assert_false(hint.contains(word), "%s uses a landmark, not a compass" % a.id)
		for s in a.spots:
			var p: Vector3 = town.marker_pos(str(a.marker)) + Vector3(float(s[0]), float(s[1]), float(s[2]))
			var st: Dictionary = town.data.station
			var c: Array = st.center
			assert_gt(Vector2(p.x - float(c[0]), p.z - float(c[2])).length(), float(st.radius) + 20.0,
				"%s spot %s is outside the ring" % [a.id, p])
			var pit: Dictionary = st.pit
			var pc: Array = pit.center
			assert_gt(Vector2(p.x - float(pc[0]), p.z - float(pc[2])).length(), float(pit.radius) + 20.0,
				"%s spot %s is clear of the pit" % [a.id, p])
			for b in town.boxes():
				if str(b.kind) != "floor":
					continue
				var inside: bool = p.x > float(b.min[0]) and p.x < float(b.max[0]) \
					and p.z > float(b.min[2]) and p.z < float(b.max[2])
				assert_false(inside, "%s spot %s is not on the station floor" % [a.id, p])


func test_the_station_merchant_buys_the_goods() -> void:
	var fence: Dictionary = content.get_vendor("station_fence")
	assert_eq(str(fence.location), "grit_station_town")
	assert_eq(str(fence.marker), "vendor_1", "the merchant in front of the cantina")
	assert_false(town.get_marker(str(fence.marker)).is_empty())
	assert_false(bool(fence.get("bounties", true)), "the port's fence still handles bounties")
	var job: Dictionary = WorldState.board().filter(func(j): return str(j.id) == JOB)[0]
	for g in job.goods:
		var it: Dictionary = content.get_item(str(g.item))
		assert_true(bool(it.get("contraband", false)), "%s is contraband" % g.item)
		assert_gt(Inventory.sell_price(it, fence), 0, "the station merchant buys %s" % g.item)


func test_the_loop_repeats_and_moves_the_drop() -> void:
	var areas := []
	var c0 := WorldState.credits
	for run in 8:
		assert_false(_offered().is_empty(), "offered again on run %d" % run)
		areas.append(str(WorldState.smuggle_offers[JOB].area))
		_run_once()
		assert_false(WorldState.carrying_contraband())
	for i in range(1, areas.size()):
		assert_ne(areas[i], areas[i - 1], "never the same area twice running")
	assert_eq(WorldState.count("smuggle_runs"), 8)
	assert_gt(WorldState.credits, c0, "the station merchant paid")


func test_not_offered_while_a_drop_is_out_or_carried() -> void:
	assert_true(WorldState.accept_job(JOB))
	assert_true(_offered().is_empty(), "one drop at a time")
	assert_false(WorldState.accept_job(JOB))
	WorldState.inventory.pick_up(WorldState.smuggle_drop())
	assert_true(_offered().is_empty(), "not while you carry it")
	WorldState.inventory.remove(str(WorldState.smuggle.item), int(WorldState.smuggle.count))
	assert_false(_offered().is_empty(), "sold or lost: she has another")


func test_a_station_run_does_not_advance_the_port_story() -> void:
	Story.skip_to("smuggle_1")
	assert_eq(Story.chapter(), "smuggle_1")
	_run_once()
	assert_false(bool(WorldState.story.get("took_run", true)), "this was not the port's chapter run")
	assert_eq(Story.chapter(), "smuggle_1", "the port's story stays where it was")


func test_drop_survives_a_save() -> void:
	assert_true(WorldState.accept_job(JOB))
	var drop := WorldState.smuggle_drop()
	WorldState.from_save(JSON.parse_string(JSON.stringify(WorldState.to_save())))
	var saved := WorldState.smuggle_drop()
	assert_eq(str(saved.get("id", "")), str(drop.id))
	assert_eq(str(saved.get("location", "")), "grit_station_town")
	assert_true(bool(saved.get("surface", false)))
	WorldState.inventory.pick_up(WorldState.smuggle_drop())
	WorldState.from_save(JSON.parse_string(JSON.stringify(WorldState.to_save())))
	assert_true(WorldState.smuggle_drop().is_empty(), "and stays taken")


func test_a_surface_drop_sits_exactly_on_the_rock() -> void:
	var gear := GearController.new()
	gear.town = town
	gear.ground_at = func(_x, _z): return -7.25
	var entry := { "marker": "gate", "offset": [150, 0, 8], "ground": true, "surface": true }
	assert_almost_eq(gear._place(entry).y, -7.25, 0.001, "surface wins over the marker's height")
	entry.erase("surface")
	assert_almost_eq(gear._place(entry).y, 0.0, 0.001, "ordinary ground drops keep the marker height when the rock is lower")
	gear.free()


func _spot(drop: Dictionary) -> Vector3:
	var off: Array = drop.offset
	return town.marker_pos(str(drop.marker)) + Vector3(float(off[0]), float(off[1]), float(off[2]))
