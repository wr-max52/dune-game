extends GutTest
## Oda's smuggling run: a job that repeats forever. She lines up a drop of
## contraband in one of the hiding places, taking the job puts it in the world,
## the player picks it up and sells it to the fence, and she lines up the next.
## Also checks every hiding place is somewhere a player can stand.

const CoreContent := preload("res://src/systems/dataload/core_content.gd")
const TownLayout := preload("res://src/systems/world/town_layout.gd")
const JOB := "j_smuggle_run"

var content


func before_each() -> void:
	WorldState.reset()
	Story.skip_to("smuggle_1")                 # issue #64: the story opens the run
	content = CoreContent.new()
	content.load_from()


func after_all() -> void:
	WorldState.reset()


func _offered() -> Dictionary:
	for j in WorldState.open_jobs("stranger"):
		if str(j.id) == JOB:
			return j
	return {}


## Pick up the drop and sell everything to the fence, as GearController would.
func _run_once() -> Dictionary:
	assert_true(WorldState.accept_job(JOB), "the job can be taken")
	var drop := WorldState.smuggle_drop()
	assert_false(drop.is_empty(), "taking it puts a drop in the world")
	assert_true(WorldState.inventory.pick_up(drop))
	assert_true(WorldState.smuggle_drop().is_empty(), "a picked-up drop is gone")
	var fence: Dictionary = content.get_vendor("fence")
	var item: Dictionary = content.get_item(str(drop.item))
	for i in int(drop.count):
		WorldState.credits += WorldState.inventory.sell(str(drop.item), item, fence)
	return drop


func test_goods_are_contraband_the_fence_buys() -> void:
	var fence: Dictionary = content.get_vendor("fence")
	for g in WorldState.board().filter(func(j): return j.id == JOB)[0].goods:
		var it: Dictionary = content.get_item(str(g.item))
		assert_false(it.is_empty(), "%s is an item" % g.item)
		assert_true(bool(it.get("contraband", false)), "%s is contraband" % g.item)
		assert_gt(Inventory.sell_price(it, fence), 0, "the fence buys %s" % g.item)
		assert_true(ItemKit.new().has_look(str(it.look)), "%s has a look" % g.item)


func test_offer_names_the_goods_and_the_area() -> void:
	var j := _offered()
	assert_false(j.is_empty(), "Oda offers the run once the story reaches it")
	assert_false(str(j.text).contains("%"), "the text is filled in")
	assert_true(str(j.text).contains(str(WorldState.smuggle.hint)), "she says where")
	var value := int(content.get_item(str(WorldState.smuggle.item)).value)
	assert_eq(int(j.pays), int(WorldState.smuggle.count) * value, "pays what the fence gives")
	assert_true(WorldState.smuggle_drop().is_empty(), "nothing in the world until you take it")


func test_loop_repeats_and_moves_the_drop() -> void:
	var areas := []
	var c0 := WorldState.credits
	for run in 8:
		var j := _offered()
		assert_false(j.is_empty(), "offered again on run %d" % run)
		areas.append(str(WorldState.smuggle.area))
		_run_once()
		assert_false(WorldState.carrying_contraband())
	for i in range(1, areas.size()):
		assert_ne(areas[i], areas[i - 1], "never the same area twice running")
	assert_eq(WorldState.count("smuggle_runs"), 8)
	assert_gt(WorldState.credits, c0, "the fence paid")


func test_not_offered_while_a_drop_is_out_or_carried() -> void:
	assert_true(WorldState.accept_job(JOB))
	assert_true(_offered().is_empty(), "one drop at a time")
	assert_false(WorldState.accept_job(JOB))
	WorldState.inventory.pick_up(WorldState.smuggle_drop())
	assert_true(_offered().is_empty(), "not while you carry it")
	# The gate takes it off you: the run is over, she lines up the next.
	WorldState.inventory.remove(str(WorldState.smuggle.item), int(WorldState.smuggle.count))
	assert_false(_offered().is_empty(), "lost at the gate: she has another")


func test_any_contraband_blocks_the_next_drop() -> void:
	WorldState.inventory.add("unmarked_cells")
	assert_true(_offered().is_empty(), "sell the cells first")
	WorldState.inventory.remove("unmarked_cells")
	assert_false(_offered().is_empty())


func test_drop_survives_a_save() -> void:
	WorldState.accept_job(JOB)
	var drop := WorldState.smuggle_drop()
	WorldState.from_save(JSON.parse_string(JSON.stringify(WorldState.to_save())))
	assert_eq(str(WorldState.smuggle_drop().get("id", "")), str(drop.id), "the drop is still out there")
	WorldState.inventory.pick_up(WorldState.smuggle_drop())
	WorldState.from_save(JSON.parse_string(JSON.stringify(WorldState.to_save())))
	assert_true(WorldState.smuggle_drop().is_empty(), "and stays taken")


## Every hiding place is on open ground (not inside a house or wall) or on top
## of a house roof, and its marker exists.
func test_hiding_places_are_reachable() -> void:
	var town := TownLayout.new()
	assert_true(town.load_town("port_town"))
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://content/core/pickups/port_town.json"))
	var areas: Array = d.drops.areas
	assert_gte(areas.size(), 4, "east desert, back desert, alleys, rooftops")
	for a in areas:
		assert_false(town.get_marker(str(a.marker)).is_empty(), "%s marker exists" % a.id)
		assert_gte((a.spots as Array).size(), 3, "%s has several spots" % a.id)
		for s in a.spots:
			var p := town.marker_pos(str(a.marker)) + Vector3(float(s[0]), float(s[1]), float(s[2]))
			var on_roof := false
			for b in town.boxes():
				if not (str(b.kind) in ["solid", "wall"]):
					continue
				var inside: bool = p.x > float(b.min[0]) and p.x < float(b.max[0]) and p.z > float(b.min[2]) and p.z < float(b.max[2])
				if not inside:
					continue
				if is_equal_approx(p.y, float(b.max[1])):
					on_roof = true
				else:
					assert_true(p.y > float(b.max[1]), "%s spot %s is inside %s" % [a.id, p, b.id])
			if p.y > 0.5:
				assert_true(on_roof, "%s spot %s sits on a roof" % [a.id, p])
