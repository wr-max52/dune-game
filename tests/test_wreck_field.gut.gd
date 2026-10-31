extends GutTest
## Wreck field: three more crashed starcruisers out east under the Remnant's
## cruiser, each a couple of km from the last and in sight of it, each barely
## different from the original; the same crew aboard each, back three minutes after
## they fall or as soon as you are 500 ft away; a supply crate with a random prize
## on every wreck's bridge platform, the original's too.
## Pure WorldGround queries on the analytic planet, plus small scenes.

const CoreScript := preload("res://src/systems/dataload/core_content.gd")
const IDS := ["starcruiser_wreck", "starcruiser_wreck_2", "starcruiser_wreck_3", "starcruiser_wreck_4"]

var _old_current: PlanetSphere
var _sp: PlanetSphere
var g: WorldGround
var _wrecks: Array = []


func before_each() -> void:
	WorldState.reset()
	_old_current = PlanetSphere.current
	_sp = PlanetSphere.new(5000.0)
	_sp.configure_site(Rect2(-200, -200, 400, 400), Rect2(-210, -210, 420, 420), [], 0.0)
	PlanetSphere.current = _sp
	var world: Dictionary = ItemKit._read_json("res://content/core/worlds/port_desert.json")
	_wrecks = world.landmarks.filter(func(lm): return str(lm.kind) == "wreck")
	g = WorldGround.new()
	g.setup({ "terrain": { "sphere_radius": 5000.0 }, "landmarks": _wrecks }, null, null)


func after_each() -> void:
	PlanetSphere.current = _old_current
	WorldState.reset()


func _lv(id: String, x: float, v: float, w: float) -> Vector3:
	return StarcruiserWreck.site_point(g, Vector3(x, v, w), "level", id)


## Same as test_crash_site's: floor under every step, nothing at the waist or head.
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


## Nothing of the ball between a and b (sampled every 20 m).
func _clear_sight(a: Vector3, b: Vector3) -> bool:
	var n := int(a.distance_to(b) / 20.0)
	for k in range(1, n):
		var p := a.lerp(b, float(k) / n)
		var dir := (p - _sp.center).normalized()
		if (p - _sp.center).length() < _sp.radius + _sp.elevation(dir):
			return false
	return true


# ---- where they lie ---------------------------------------------------------------

func test_three_more_wrecks_lie_out_east_toward_the_cruiser() -> void:
	assert_eq(_wrecks.size(), 4, "the original and three more")
	for id in IDS:
		assert_true(StarcruiserWreck.has_wreck(g, id), "%s is in the ground" % id)
	var world: Dictionary = ItemKit._read_json("res://content/core/worlds/port_desert.json")
	var cruiser: Array = world.landmarks.filter(func(lm): return str(lm.kind) == "cruiser")
	var under := _sp.surface_at(float(cruiser[0].at[0]), float(cruiser[0].at[2]))
	var first := StarcruiserWreck.frame(g, IDS[0]).origin
	for id in IDS.slice(1):
		var o := StarcruiserWreck.frame(g, id).origin
		assert_lt(o.distance_to(under), first.distance_to(under), "%s is nearer the cruiser" % id)
	var last_map := _sp.world_to_map(StarcruiserWreck.frame(g, IDS[3]).origin)
	assert_gt(last_map.length() / _sp.radius, deg_to_rad(80.0), "the last lies most of the way round to the far side")


func test_far_apart_and_each_in_sight_of_the_next() -> void:
	for i in IDS.size():
		var a := StarcruiserWreck.frame(g, IDS[i]).origin
		for j in range(i + 1, IDS.size()):
			assert_gt(a.distance_to(StarcruiserWreck.frame(g, IDS[j]).origin), 1800.0, "%s and %s far apart" % [IDS[i], IDS[j]])
	for i in IDS.size() - 1:
		# From one bridge platform the next one's stern (its radiators) shows over the sand.
		var eye := _lv(IDS[i], 0, StarcruiserWreck.BRIDGE_V + 1.7, 140)
		var stern := StarcruiserWreck.site_point(g, Vector3(0, 50, 250), "hull", IDS[i + 1])
		assert_true(_clear_sight(eye, stern), "%s is in sight from %s" % [IDS[i + 1], IDS[i]])


# ---- barely unique ----------------------------------------------------------------

func test_each_wreck_is_barely_unique() -> void:
	var sets := {}
	for id in IDS:
		var parts := {}
		for b in g.boxes:
			if str(b.id).begins_with(id + "/"):
				var local: Transform3D = (b.wreck_frame as Transform3D).affine_inverse() * WorldGround.box_xf(b)
				parts[str(b.id).trim_prefix(id + "/")] = "%s|%s" % [(b.max as Vector3).snapped(Vector3.ONE * 0.01), local.origin.snapped(Vector3.ONE * 0.05)]
		sets[id] = parts
	var yaws := {}
	for lm in _wrecks:
		yaws[float(lm.yaw_deg)] = true
	assert_eq(yaws.size(), 4, "each lies on its own heading")
	for i in IDS.size():
		for j in range(i + 1, IDS.size()):
			var a: Dictionary = sets[IDS[i]]
			var b: Dictionary = sets[IDS[j]]
			var same := 0
			for k in a:
				if b.get(k, "") == a[k]:
					same += 1
			var total := maxi(a.size(), b.size())
			assert_lt(same, total, "%s and %s differ" % [IDS[i], IDS[j]])
			assert_gt(float(same) / total, 0.9, "%s and %s are nearly the same ship" % [IDS[i], IDS[j]])


func test_every_wreck_crew_route_runs_on_a_floor() -> void:
	var dc: Dictionary = DroidRoster.config().wreck
	for site in dc.sites:
		var id := str(site.landmark)
		for name in dc.routes:
			if str(name) in site.get("skip_routes", []):
				continue
			var r: Dictionary = dc.routes[name]
			var pts: Array = r.points.map(func(p): return StarcruiserWreck.site_point(g, Vector3(p[0], p[1], p[2]), str(r.frame), id))
			pts.append(pts[0])
			assert_eq(_walkable(pts), "", "%s route %s" % [id, name])


func test_the_stern_ramp_and_bridge_ramp_still_climb_to_the_pad_on_every_wreck() -> void:
	const U := StarcruiserWreck.INTERIOR_V
	const B := StarcruiserWreck.BRIDGE_V
	for lm in _wrecks:
		var id := str(lm.id)
		var w := float(lm.get("variant", {}).get("stern_ramp_w", StarcruiserWreck.STERN_RAMP_W))
		var head := StarcruiserWreck.floor_v(w)
		var hull := func(x, y, z): return StarcruiserWreck.site_point(g, Vector3(x, y, z), "hull", id)
		var route := [
			hull.call(24, -24, 150), hull.call(24, -24, 285),
			_lv(id, 28, head, w - 0.5), _lv(id, 31, head - 0.1, w - 1.0),
			_lv(id, 33, U, 232), _lv(id, 30, U, 228),
			_lv(id, 30, U, 188), _lv(id, 30, U, 182), _lv(id, 0, U, 182),
			_lv(id, 0, U, 180), _lv(id, 0, B, 150), _lv(id, 0, B, 132),
		]
		assert_eq(_walkable(route), "", "%s: hold floor -> stern ramp -> catwalk -> bridge ramp -> pad" % id)


# ---- the crew ---------------------------------------------------------------------

func _droids() -> Array:
	WorldState.droids.wrecks_seeded = true
	var root := Node3D.new()
	add_child_autofree(root)
	var p := FakePlayer.new()
	root.add_child(p)
	var ctl := DroidController.new()
	ctl.setup(null, p, null)
	ctl.ground = g
	root.add_child(ctl)
	return [ctl, p]


func test_every_wreck_has_its_crew_and_only_the_first_its_hauler() -> void:
	var s := _droids()
	await wait_physics_frames(2)
	var ctl: DroidController = s[0]
	var dc: Dictionary = DroidRoster.config().wreck
	for site in dc.sites:
		var id := str(site.landmark)
		var want: Array = (dc.units as Array).filter(func(u): return not (str(u.route) in site.get("skip_routes", [])))
		var crew: Array = ctl.remnant.filter(func(u): return str(u.spec.get("site", "")) == id)
		assert_eq(crew.size(), want.size(), "%s is manned" % id)
		assert_eq(crew.filter(func(u): return str(u.spec.route) == "pad").size(), 2, "%s: assassins on its pad" % id)
	assert_eq(str(ctl.wreck_hauler.spec.site), IDS[0], "the saber's hauler stays on the original")


func test_a_fallen_wreck_droid_is_back_after_three_minutes() -> void:
	var s := _droids()
	await wait_physics_frames(2)
	var ctl: DroidController = s[0]
	var p: FakePlayer = s[1]
	var u = ctl.remnant.filter(func(x): return str(x.spec.get("site", "")) == IDS[2])[0]
	p.global_position = u.global_position + g.up_at(u.global_position) * 30.0   # near: no walk-away
	ctl.on_unit_hit(u, 9999.0, null)
	assert_true(u.dead)
	assert_almost_eq(u.respawn_left, 180.0, 0.01, "three minutes")
	ctl._tick_remnant_respawns(179.0)
	assert_true(is_instance_valid(u) and ctl.remnant.has(u), "still down at 2:59")
	ctl._tick_remnant_respawns(1.5)
	assert_false(ctl.remnant.has(u), "gone from the list")
	var back: Array = ctl.remnant.filter(func(x): return str(x.spec.get("site", "")) == IDS[2] and not x.dead)
	assert_eq(back.size(), ctl.remnant.filter(func(x): return str(x.spec.get("site", "")) == IDS[2]).size(), "back on its route")


func test_a_fallen_wreck_droid_is_back_once_you_walk_500_feet_away() -> void:
	var s := _droids()
	await wait_physics_frames(2)
	var ctl: DroidController = s[0]
	var p: FakePlayer = s[1]
	var u = ctl.remnant.filter(func(x): return str(x.spec.get("site", "")) == IDS[1])[0]
	var at: Vector3 = u.global_position
	var up := g.up_at(at)
	p.global_position = at + up * 10.0
	ctl.on_unit_hit(u, 9999.0, null)
	assert_true(u.dead)
	ctl._tick_remnant_respawns(1.0)
	assert_true(ctl.remnant.has(u), "you are still close: it stays down")
	p.global_position = u.global_position + up * 140.0
	ctl._tick_remnant_respawns(1.0)
	assert_true(ctl.remnant.has(u), "140 m is not 500 ft")
	p.global_position = u.global_position + up * 160.0
	ctl._tick_remnant_respawns(1.0)
	assert_false(ctl.remnant.has(u), "500 ft away: it is back on its route")


# ---- the prize crates -------------------------------------------------------------

func test_a_supply_crate_stands_on_every_bridge_platform() -> void:
	var content = CoreScript.new()
	content.load_from()
	var crates: Array = content.get_site_crates("port_town")
	var sites := {}
	for c in crates:
		sites[str(c.site)] = true
		var pt: Array = c.site_point
		assert_almost_eq(float(pt[1]), StarcruiserWreck.BRIDGE_V, 0.01, "%s is on the top deck" % c.id)
		var at := StarcruiserWreck.site_point(g, Vector3(pt[0], pt[1], pt[2]), "level", str(c.site))
		var up := g.up_at(at)
		assert_almost_eq(g.height_above(at + up), 1.0, 0.3, "%s sits on the platform" % c.id)
		assert_eq(g.hit(at + up * 1.0, 0.6), "", "%s is not inside anything" % c.id)
	for id in IDS:
		assert_true(sites.has(id), "a crate on %s, the original too" % id)
	var kinds := {}
	for e in content.get_crate_prizes("port_town"):
		kinds["credits" if e.has("credits") else str(e.item)] = e.get("credits", e.get("count", 0))
	assert_true(content.get_crate_prizes("port_town").any(func(e): return int(e.get("credits", 0)) == 300), "300 credits")
	assert_eq(int(kinds.get("food", 0)), 10, "10 food")
	assert_eq(int(kinds.get("refined_quantonium", 0)), 5, "5 refined quantonium")


func _gear() -> Array:
	var root := Node3D.new()
	add_child_autofree(root)
	var p := FakePlayer.new()
	root.add_child(p)
	var gear := GearController.new()
	gear.setup(null, null, p, null, "port_town")
	gear.ground = g
	root.add_child(gear)
	gear.set_physics_process(false)    # interact() by hand, as the trace does
	return [gear, p]


func test_opening_a_crate_gives_its_prize_once() -> void:
	var s := _gear()
	var gear: GearController = s[0]
	var p: FakePlayer = s[1]
	var crates: Array = gear.pickups.filter(func(n): return bool(n.pickup.get("crate", false)))
	assert_eq(crates.size(), 4, "one on every wreck")
	var crate = crates[2]
	var cid := str(crate.pickup.id)
	p.global_position = crate.base + g.up_at(crate.base) * 0.2 + crate.basis.x * 1.0
	gear.focus = gear._find_focus()
	assert_eq(gear.prompt_text(), gear._l("open_crate"))
	crate.pickup["prize"] = { "credits": 300 }
	var cr0 := WorldState.credits
	assert_eq(gear.interact(), "opened")
	assert_eq(WorldState.credits, cr0 + 300, "300 credits")
	assert_true(WorldState.inventory.is_taken(cid), "it stays open")
	assert_false(gear.pickups.has(crate))
	# And another: goods.
	var c2 = gear.pickups.filter(func(n): return bool(n.pickup.get("crate", false)))[0]
	c2.pickup["prize"] = { "item": "refined_quantonium", "count": 5 }
	p.global_position = c2.base + g.up_at(c2.base) * 0.2
	gear.focus = {}
	assert_eq(gear.interact(), "opened")
	assert_eq(WorldState.inventory.count("refined_quantonium"), 5, "5 refined quantonium")
	# Opened crates are not put out again.
	var again := _gear()
	var left: Array = (again[0] as GearController).pickups.filter(func(n): return bool(n.pickup.get("crate", false)))
	assert_eq(left.size(), 2)


func test_the_prize_is_rolled_from_the_table() -> void:
	var s := _gear()
	var gear: GearController = s[0]
	gear.rng.seed = 7
	var seen := {}
	for i in 200:
		var pr := gear.roll_crate_prize()
		assert_false(pr.is_empty())
		seen["credits:%d" % int(pr.credits) if pr.has("credits") else str(pr.item)] = true
	assert_gte(seen.size(), 4, "it varies")


class FakePlayer extends CharacterBody3D:
	var piloting := false
	var locked := false
	var jetpack = null
