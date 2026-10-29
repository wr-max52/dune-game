extends GutTest
## Issue #148: the crashed starcruiser is a place to ride and fight in. A speeder
## rides up the kicker plate and launches off it (and up the boarding plate into the
## hold); the hold climbs to a level interior deck; ramps and broken railings join it
## to the bridge platform and the upper gallery; every part wears the wreck's metal;
## the Remnant's droids patrol the bridge and the ship; an old cargo droid in the deep
## hold carries a red energy saber that turns your blade red.
## Pure WorldGround queries on the analytic planet, plus a small scene for the droids.

const CoreScript := preload("res://src/systems/dataload/core_content.gd")
const ID := "starcruiser_wreck"

var _old_current: PlanetSphere
var _sp: PlanetSphere
var g: WorldGround


func before_each() -> void:
	WorldState.reset()
	_old_current = PlanetSphere.current
	_sp = PlanetSphere.new(5000.0)
	_sp.configure_site(Rect2(-200, -200, 400, 400), Rect2(-210, -210, 420, 420), [], 0.0)
	PlanetSphere.current = _sp
	var world: Dictionary = ItemKit._read_json("res://content/core/worlds/port_desert.json")
	var wreck: Array = world.landmarks.filter(func(lm): return str(lm.kind) == "wreck")
	g = WorldGround.new()
	g.setup({ "terrain": { "sphere_radius": 5000.0 }, "landmarks": wreck }, null, null)


func after_each() -> void:
	PlanetSphere.current = _old_current
	WorldState.reset()


func _box(name: String) -> Dictionary:
	for b in g.boxes:
		if str(b.id) == ID + "/" + name:
			return b
	return {}


func _lv(x: float, v: float, w: float) -> Vector3:
	return StarcruiserWreck.site_point(g, Vector3(x, v, w), "level")


func _hull(x: float, y: float, z: float) -> Vector3:
	return StarcruiserWreck.site_point(g, Vector3(x, y, z), "hull")


## A speeder at `at` facing `dir` (along the ground there).
func _speeder(at: Vector3, dir: Vector3) -> HoverModel:
	var m := HoverModel.new(HoverModel.load_config("speeder"), g)
	m.place(at, 0.0)
	var up := g.up_at(m.position)
	var l := PlanetSphere.tilt_to(up).inverse() * (dir - up * dir.dot(up)).normalized()
	m.yaw = atan2(-l.x, -l.z)
	return m


## Walk the line through `points` (world, on the floor) in 0.5 m steps: the floor is
## always there within a step (0.4 m) of the line, nothing is in the way at the
## waist or the head. Returns "" or what went wrong where.
func _walkable(points: Array) -> String:
	for i in points.size() - 1:
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var n := maxi(1, int(a.distance_to(b) / 0.5))
		for k in n + 1:
			var p := a.lerp(b, float(k) / n)
			var up := g.up_at(p)
			var h := g.height_above(p + up)
			if absf(h - 1.0) > 0.4:
				return "no floor at leg %d step %d (%.2f m under the waist)" % [i, k, h]
			for lift in [1.0, 1.7]:
				var what := g.hit(p + up * lift, 0.35)
				if what != "":
					return "%s in the way at leg %d step %d" % [what, i, k]
	return ""


# ---- the speeder ------------------------------------------------------------------

func test_a_speeder_rides_up_the_kicker_and_launches_off_it() -> void:
	var kicker := _box("speeder_kicker")
	assert_false(kicker.is_empty(), "a bent hull plate stands by the boarding plate")
	var xf := WorldGround.box_xf(kicker)
	var half: Vector3 = ((kicker.max as Vector3) - (kicker.min as Vector3)) * 0.5
	var foot := xf * Vector3(0, half.y, -half.z)
	var lip := xf * Vector3(0, half.y, half.z)
	var dir := (lip - foot).normalized()
	var flat := (dir - g.up_at(foot) * dir.dot(g.up_at(foot))).normalized()
	var m := _speeder(foot - flat * 60.0, flat)
	var launch := {}
	var landed := {}
	var bumps: Array = []
	for i in 60 * 8:
		m.set_command(1.0, 0.0, true)
		for e in m.step(1.0 / 60.0):
			if e.type == "bump":
				bumps.append(e.what)
			if e.type == "launch" and launch.is_empty():
				launch = e
				launch["at"] = m.position
			if e.type == "landed" and not launch.is_empty():
				landed = e
		if not landed.is_empty():
			break
	assert_eq(bumps, [], "nothing on the run-up or the plate stops it")
	assert_false(launch.is_empty(), "it leaves the ground")
	assert_lt((launch.get("at", Vector3.INF) as Vector3).distance_to(lip), 6.0, "off the kicker's lip")
	assert_gt(float(launch.get("vy", 0.0)), 5.0, "carrying the plate's climb up into the air")
	assert_false(landed.is_empty(), "and comes down")
	assert_gt(float(landed.get("air_time", 0.0)), 1.5, "after a real jump")
	assert_true(m.alive() and m.hp == m.max_hp, "unhurt")


func test_a_speeder_rides_up_the_boarding_plate_into_the_hold() -> void:
	var plate := _box("fallen_boarding_plate")
	var xf := WorldGround.box_xf(plate)
	var half: Vector3 = ((plate.max as Vector3) - (plate.min as Vector3)) * 0.5
	var foot := xf * Vector3(0, half.y, -half.z)
	var dir := xf.basis.z.normalized()
	var flat := (dir - g.up_at(foot) * dir.dot(g.up_at(foot))).normalized()
	var m := _speeder(foot - flat * 30.0, flat)
	var entry := StarcruiserWreck.site_point(g, StarcruiserWreck.ENTRY, "hull")
	var bumps: Array = []
	var best := INF
	for i in 60 * 10:
		m.set_command(0.6, 0.0)
		for e in m.step(1.0 / 60.0):
			if e.type == "bump":
				bumps.append(e.what)
		best = minf(best, m.position.distance_to(entry))
		if best < 3.0:
			break                    # on the deck; across it is the far hull
	assert_eq(bumps, [], "the plate and the breach let it through")
	assert_lt(best, 4.0, "it rides up the plate onto the hold's deck")


# ---- the interior -------------------------------------------------------------------

func test_the_interior_floors_are_level() -> void:
	for id in ["interior_deck", "gallery_landing", "bridge_platform"]:
		var b := _box(id)
		assert_false(b.is_empty(), id)
		var xf := WorldGround.box_xf(b)
		var c := xf * (((b.min as Vector3) + (b.max as Vector3)) * 0.5)
		assert_gt(xf.basis.y.normalized().dot(g.up_at(c)), cos(deg_to_rad(4.0)), "%s is level with the horizon, not the hull" % id)


func test_the_hold_climbs_to_the_interior_and_the_bridge_ramp_leads_out_to_the_platform() -> void:
	var a := deg_to_rad(34.0)
	var meet_z := (StarcruiserWreck.INTERIOR_V + 24.0 * cos(a)) / sin(a)
	var meet_w := 24.0 * sin(a) + meet_z * cos(a)
	var v := StarcruiserWreck.INTERIOR_V
	var route := [
		_hull(30, -24, 120), _hull(30, -24, meet_z - 0.5),      # up the hold's starboard side
		_lv(24, v, meet_w - 0.4), _lv(20, v, 200),              # onto the interior deck
		_lv(0, v, 183), _lv(0, v, 180),
		_lv(0, StarcruiserWreck.BRIDGE_V, 150),                 # up through the torn dorsal plates
		_lv(0, StarcruiserWreck.BRIDGE_V, 132),                 # out on the bridge platform
	]
	assert_eq(_walkable(route), "", "hold -> interior deck -> bridge ramp -> bridge platform")
	var top := _lv(0, StarcruiserWreck.BRIDGE_V, 132)
	assert_gt(_sp.height_above_ground(top), 150.0, "the bridge stands high over the dunes")


func test_a_ramp_joins_the_interior_to_the_upper_gallery() -> void:
	var a := deg_to_rad(34.0)
	var v := StarcruiserWreck.INTERIOR_V
	var g_end := Vector3(-20, -3.3, 235)
	var route := [
		_lv(20, v, 200), _lv(-8, v, 223), _lv(-20, v, 223),    # across the deck to the landing
		_lv(-20, v, 219),
		_lv(-20, g_end.y * cos(a) + g_end.z * sin(a), -g_end.y * sin(a) + g_end.z * cos(a)),
		_hull(-20, -3.3, 200),                                  # and down the gallery
	]
	assert_eq(_walkable(route), "", "interior deck -> landing -> ramp -> upper gallery")


func test_broken_railings_line_the_open_edges() -> void:
	for run in ["deck_bow_rail", "deck_starboard_rail", "bridge_port_rail", "bridge_starboard_rail"]:
		var panels := g.boxes.filter(func(b): return str(b.id).begins_with(ID + "/" + run + "_") and not str(b.id).contains("_post_"))
		assert_gt(panels.size(), 1, "%s stands" % run)
	assert_false(_box("deck_bow_rail_0").is_empty())
	assert_true(_box("deck_bow_rail_2").is_empty(), "with panels knocked out")
	var sagging := _box("deck_starboard_rail_2")
	assert_false(sagging.is_empty())
	var up := g.up_at(WorldGround.box_xf(sagging).origin)
	assert_lt(WorldGround.box_xf(sagging).basis.y.normalized().dot(up), cos(deg_to_rad(10.0)), "and some sagging")
	# A rail stops you walking off the deck's bow edge.
	assert_ne(g.hit(_lv(0, StarcruiserWreck.INTERIOR_V + 1.0, 172), 0.35), "", "the bow rail is solid")


func test_the_hatch_is_torn_and_the_old_solid_bridge_is_gone() -> void:
	assert_true(_box("plate_%d_1" % StarcruiserWreck.HATCH_SECTION).is_empty())
	assert_true(_box("plate_%d_2" % StarcruiserWreck.HATCH_SECTION).is_empty())
	assert_false(_box("plate_%d_3" % StarcruiserWreck.HATCH_SECTION).is_empty(), "only the dorsal plates")
	assert_false(_box("bridge").is_empty(), "the bridge house stands on the platform")
	assert_false(_box("bridge_strut_-11").is_empty())


func test_every_surface_wears_the_wreck_metal() -> void:
	var mine := g.boxes.filter(func(b): return str(b.id).begins_with(ID + "/"))
	assert_gt(mine.size(), 300)
	for b in mine:
		assert_true(b.has("wreck_finish") and b.has("wreck_frame") and b.has("wreck_level"), str(b.id))
	var scenery := WorldScenery.new()
	scenery.setup(g)
	add_child_autofree(scenery)
	scenery.build_visuals()
	for id in ["interior_deck", "bridge_platform", "bridge_ramp", "gallery_ramp", "speeder_kicker", "deck_bow_rail_0"]:
		var mi := scenery.find_child(ID + "_" + id, true, false) as MeshInstance3D
		assert_not_null(mi, id)
		if mi != null:
			assert_eq((mi.material_override as ShaderMaterial).shader, WorldScenery.WRECK_SHADER, "%s is the ship's metal" % id)


# ---- the droids ----------------------------------------------------------------------

func test_every_wreck_route_runs_on_a_floor() -> void:
	var wc: Dictionary = DroidRoster.config().wreck
	for name in wc.routes:
		var r: Dictionary = wc.routes[name]
		var pts: Array = r.points.map(func(p): return StarcruiserWreck.site_point(g, Vector3(p[0], p[1], p[2]), str(r.frame)))
		pts.append(pts[0])
		assert_eq(_walkable(pts), "", "route %s" % name)
	for u in wc.units:
		assert_true(wc.routes.has(str(u.route)), "unit route %s exists" % u.route)
	assert_true(wc.routes.has(str(wc.hauler.route)))
	var bridge_units: Array = wc.units.filter(func(u): return str(u.route) == "bridge")
	var ship_units: Array = wc.units.filter(func(u): return str(u.route) != "bridge")
	assert_gt(bridge_units.size(), 0, "a droid walks the bridge")
	assert_gt(ship_units.size(), 1, "and others the ship")


func test_the_remnant_patrols_the_wreck_and_a_cargo_droid_carries_the_saber() -> void:
	WorldState.droids.wrecks_seeded = true
	var root := Node3D.new()
	add_child_autofree(root)
	var scenery := WorldScenery.new()
	scenery.setup(g)
	root.add_child(scenery)
	var p := FakePlayer.new()
	root.add_child(p)
	var ctl := DroidController.new()
	ctl.setup(null, p, null)
	ctl.ground = g
	root.add_child(ctl)
	await wait_physics_frames(2)
	var mine: Array = ctl.remnant.filter(func(u): return u.spec.has("site"))
	assert_eq(mine.size(), (DroidRoster.config().wreck.units as Array).size(), "every wreck unit is out")
	for u in mine:
		assert_eq(u.faction, "imperial_remnant")
		assert_true(ctl.remnant_hostile(u), "they shoot on sight")
		assert_null(ctl._garrison(u), "and call no garrison")
		assert_lt(absf(g.height_above(u.global_position + g.up_at(u.global_position)) - 1.0), 0.3, "standing on a floor")
	var bridge: Array = mine.filter(func(u): return str(u.spec.route) == "bridge")
	var start: Vector3 = bridge[0].global_position
	for i in 90:
		await wait_physics_frames(1)
	assert_gt(bridge[0].global_position.distance_to(start), 1.5, "the bridge droid walks its round")
	assert_lt(absf(g.height_above(bridge[0].global_position + g.up_at(start)) - 1.0), 0.3, "on the platform")
	assert_not_null(ctl.wreck_hauler, "an old cargo droid in the deep hold")
	assert_eq(ctl.wreck_hauler.kind, "cargo")
	assert_eq(ctl.wreck_hauler.faction, "", "nobody's")
	assert_eq(str(DroidRoster.config().wreck.hauler.carries), "wreck_red_saber")
	ctl.withdraw_town_remnant()
	assert_eq(ctl.remnant.filter(func(u): return u.spec.has("site")).size(), mine.size(), "they stay after the fleet falls")


# ---- the red saber -------------------------------------------------------------------

func test_the_red_saber_is_a_carried_pickup_that_turns_the_blade_red() -> void:
	var content = CoreScript.new()
	content.load_from()
	var item: Dictionary = content.get_item("red_energy_saber")
	assert_false(item.is_empty())
	var red := Color(str(item.blade_color))
	assert_true(red.r > 0.9 and red.g < 0.3 and red.b < 0.3, "it is red")
	var entry: Array = content.get_pickups("port_town").filter(func(e): return str(e.id) == "wreck_red_saber")
	assert_eq(entry.size(), 1)
	assert_eq(str(entry[0].item), "red_energy_saber")
	assert_true(bool(entry[0].carried), "it rides on its droid, hidden until then")
	var look := ItemKit.new().build("red_saber")
	assert_not_null(look.find_child("Blade", true, false), "it looks like a saber")
	look.free()
	var gear := GearController.new()
	gear.content = content
	assert_eq(gear.blade_color().a, 0.0, "the default blade until you own it")
	WorldState.inventory.pick_up(entry[0])
	assert_eq(gear.blade_color(), red, "owning it turns the blade red")
	gear.free()
	var kit := CharacterKit.new(LookMaterials.new())
	var sword := kit.make_energy_sword()
	CharacterKit.recolor_energy_sword(sword, red)
	assert_eq(sword.get_meta("color"), red)
	assert_eq((sword.get_node("Blade/BladeLight") as OmniLight3D).light_color, red)
	assert_eq(((sword.get_node("Blade/Glow") as MeshInstance3D).material_override as ShaderMaterial).get_shader_parameter("color"), red)
	sword.free()


class FakePlayer extends CharacterBody3D:
	var piloting := false
	var locked := false
