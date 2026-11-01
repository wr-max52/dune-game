extends GutTest
## Handing over a job's goods at a menu (the fence, a droid merchant's post):
## while the job is open and you carry what closes it, those rows go first, are
## marked "job" (green in the menu) and a fresh menu opens with the cursor on them.

const CoreContent := preload("res://src/systems/dataload/core_content.gd")

var content


func before_each() -> void:
	GameFlow.reset()
	WorldState.reset()
	content = CoreContent.new()
	content.load_from()


func after_all() -> void:
	WorldState.reset()


func _gear() -> GearController:
	var gear := GearController.new()
	gear.content = content
	gear.labels = CharacterKit._read_json("res://content/core/flow/gear.json").labels
	gear.vendor_talk = { "fence": Callable() }     # he has a brain: "Talk" is on his menu
	autofree(gear)
	return gear


## Take Oda's run and pick its drop up; also carry something else contraband
## and something plain.
func _carry_the_drop() -> Dictionary:
	Story.skip_to("smuggle_1")
	assert_true(WorldState.accept_job("j_smuggle_run"))
	var drop := WorldState.smuggle_drop()
	assert_true(WorldState.inventory.pick_up(drop))
	var other := "unmarked_cells" if str(drop.item) != "unmarked_cells" else "holocrystals"
	WorldState.inventory.add(other, 1)
	WorldState.inventory.add("food", 1)
	return { "item": str(drop.item), "other": other }


func test_the_fence_puts_the_drop_first_and_marks_it() -> void:
	var c := _carry_the_drop()
	var fence: Dictionary = content.get_vendor("fence")
	assert_true(WorldState.fence_run_open("port_town"))
	var rows := _gear().trade_options(fence)
	assert_eq(str(rows[0].id), "sell:" + c.item, "the drop's goods top the list, above Talk")
	assert_eq(str(rows[1].id), "sell:" + c.other, "then the rest of the contraband")
	assert_true(bool(rows[0].get("job", false)) and bool(rows[1].get("job", false)))
	for r in rows.slice(2):
		assert_false(bool(r.get("job", false)), "%s is not the job's" % r.id)
	assert_eq(str(rows[2].id), "talk")


func test_no_job_rows_without_an_open_run() -> void:
	WorldState.inventory.add("holocrystals", 1)
	var rows := _gear().trade_options(content.get_vendor("fence"))
	assert_false(WorldState.fence_run_open("port_town"), "no run taken")
	assert_eq(str(rows[0].id), "talk")
	assert_true(rows.all(func(r): return not bool(r.get("job", false))))


func test_another_towns_fence_does_not_close_it() -> void:
	_carry_the_drop()
	assert_false(WorldState.fence_run_open("grit_station_town"))
	var station: Dictionary = content.get_vendor("station_fence")
	assert_true(_gear().trade_options(station).all(func(r): return not bool(r.get("job", false))))


func test_the_menu_opens_on_the_job_row_in_green() -> void:
	var menu := DroidMenu.new()
	add_child_autofree(menu)
	var opts := [{ "id": "talk", "text": "Talk" }, { "id": "sell:a", "text": "Sell a", "job": true }, { "id": "sell:b", "text": "Sell b" }]
	menu.open("Fence", opts, func(_id): pass)
	assert_eq(menu.selected, 1, "the cursor starts on the job's row")
	assert_eq(menu._rows[1].text.get_theme_color("font_color"), DroidMenu.JOB_GREEN)
	assert_ne(menu._rows[2].text.get_theme_color("font_color"), DroidMenu.JOB_GREEN)
	menu.move(1)
	menu.open("Fence", opts, func(_id): pass, "", true)
	assert_eq(menu.selected, 2, "after a sale the cursor stays where it was")
	menu.open("Fence", [{ "id": "talk", "text": "Talk" }], func(_id): pass)
	assert_eq(menu.selected, 0, "no job row: the top")


func test_a_droid_post_puts_the_wanted_droids_first() -> void:
	Story.skip_to("droid_merchant")
	var want := Story.droid_wanted_kind()
	assert_ne(want, "")
	var rng := RandomNumberGenerator.new()
	WorldState.droids.add(want, DroidRoster.pick_variant(want, rng))
	var dc := DroidController.new()
	autofree(dc)
	dc.cfg = DroidRoster.config()
	dc.labels = dc.cfg.get("labels", {})
	dc.vendor_sites = [{ "id": "droid_post_test", "pos": Vector3(5, 0, 5), "face": Vector3.FORWARD }]
	dc.vendor_pos = Vector3(5, 0, 5)
	var rows := dc.trade_options()
	assert_true(str(rows[0].id).begins_with("deliver:"), "the handover tops the list")
	assert_true(bool(rows[0].get("job", false)))
	assert_true(rows.slice(1).all(func(r): return not bool(r.get("job", false))))
	dc.vendor_pos = Vector3.INF     # the port's market stall: no handover there
	assert_true(dc.trade_options().all(func(r): return not str(r.id).begins_with("deliver:")))
