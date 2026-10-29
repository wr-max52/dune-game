extends GutTest
## Issue #51: companion droids. The roster rules (three kinds with variants, the
## cap of three, merchant prices 50/50/100 and resale 40/40/90, cargo the gate never
## sees, the range remote's five-in-a-row streak, desert wrecks far apart, fixing,
## saving), the placeholder looks, and the controller in a small scene: buying,
## selling, the "make room" choice, fixing a wreck in ten seconds, following, and
## vanishing while the player flies.

const Garrison := preload("res://src/systems/npc/garrison.gd")

var r: DroidRoster
var rng: RandomNumberGenerator


func before_each() -> void:
	WorldState.reset()
	r = WorldState.droids
	rng = RandomNumberGenerator.new()
	rng.seed = 51


# ---- data -------------------------------------------------------------------

func test_three_kinds_with_variants_and_prices() -> void:
	for k in ["floating", "cargo", "assassin"]:
		assert_false(DroidRoster.kind_cfg(k).is_empty(), k)
		assert_gt((DroidRoster.kind_cfg(k).variants as Dictionary).size(), 1, "%s has variations" % k)
	assert_eq(DroidRoster.price("floating"), 50)
	assert_eq(DroidRoster.price("cargo"), 50)
	assert_eq(DroidRoster.price("assassin"), 100)
	assert_eq(DroidRoster.resale("floating"), 40)
	assert_eq(DroidRoster.resale("cargo"), 40)
	assert_eq(DroidRoster.resale("assassin"), 90)
	assert_eq(DroidRoster.max_owned(), 3)
	var red: Dictionary = DroidRoster.variant_cfg("assassin", "remnant")
	assert_eq(Color(str(red.eye)).r > 0.9 and Color(str(red.body)).v < 0.15, true, "the Remnant's assassin is black with red eyes")


func test_player_never_gets_remnant_colours() -> void:
	for i in 40:
		assert_ne(DroidRoster.pick_variant("assassin", rng), "remnant")


func test_looks_build_for_every_variant() -> void:
	var mats := LookMaterials.new()
	for k in ["floating", "cargo", "assassin"]:
		for v in DroidRoster.kind_cfg(k).variants:
			var n := DroidKit.build(k, DroidRoster.variant_cfg(k, v), mats)
			assert_not_null(n.get_node_or_null("Model"), "%s/%s has a Model" % [k, v])
			assert_gt(DroidKit.eyes(n).size(), 0, "%s/%s has eyes" % [k, v])
			n.free()
	var a := DroidKit.build("assassin", DroidRoster.variant_cfg("assassin", "bone"), mats)
	assert_not_null(a.find_child("Muzzle", true, false), "the assassin carries a pistol")
	a.free()


# ---- owning and trade -------------------------------------------------------

func test_cap_of_three() -> void:
	assert_false(r.add("floating", "rust").is_empty())
	assert_false(r.add("cargo", "tan").is_empty())
	assert_false(r.add("assassin", "bone").is_empty())
	assert_true(r.is_full())
	assert_true(r.add("cargo", "blue").is_empty(), "no fourth droid")
	assert_eq(r.buy("cargo", "blue", 999).get("error"), "full")


func test_buy_and_sell_at_merchant_prices() -> void:
	assert_eq(r.buy("assassin", "bone", 99).get("error"), "cant_afford")
	var b := r.buy("assassin", "bone", 100)
	assert_eq(int(b.cost), 100)
	assert_eq(r.sell(int(b.droid.uid)), 90)
	assert_eq(r.owned.size(), 0)
	assert_eq(r.sell(12345), -1)


func test_cargo_is_hidden_from_the_gate() -> void:
	WorldState.inventory.add("holocrystals", 3)
	var d := r.add("cargo", "tan")
	assert_true(r.stash(int(d.uid), WorldState.inventory, "holocrystals", 3))
	assert_eq(WorldState.inventory.count("holocrystals"), 0, "out of the pockets")
	var g := Garrison.new()
	assert_eq(g.contraband().size(), 0, "the gate's search finds nothing")
	g.free()
	assert_true(WorldState.carrying_contraband(), "but Oda waits until it is sold")
	assert_eq(r.unload(int(d.uid), WorldState.inventory), 3)
	assert_eq(WorldState.inventory.count("holocrystals"), 3)


func test_only_cargo_droids_carry() -> void:
	WorldState.inventory.add("holocrystals", 1)
	var f := r.add("floating", "rust")
	assert_false(r.stash(int(f.uid), WorldState.inventory, "holocrystals"))
	assert_eq(WorldState.inventory.count("holocrystals"), 1)


# ---- taming -----------------------------------------------------------------

func test_five_blocks_in_a_row() -> void:
	for i in 4:
		assert_false(r.on_remote_blocked())
	r.on_remote_hit_player()
	assert_eq(r.streak, 0, "a hit resets the streak")
	for i in 4:
		r.on_remote_blocked()
	assert_true(r.on_remote_blocked(), "the fifth in a row tames it")


# ---- wrecks -----------------------------------------------------------------

func test_wrecks_one_per_kind_far_apart() -> void:
	for i in 3:
		assert_false(r.roll_wreck(rng, Vector3.ZERO, Callable(), true).is_empty())
	assert_true(r.roll_wreck(rng, Vector3.ZERO, Callable(), true).is_empty(), "max_out")
	var kinds := {}
	var sep := float(DroidRoster.config().wrecks.min_separation)
	for w in r.wrecks:
		kinds[w.kind] = true
		var p := Vector2(float(w.pos[0]), float(w.pos[2]))
		assert_gt(p.length(), float(DroidRoster.config().wrecks.min_radius) - 0.01, "out in the desert")
		for o in r.wrecks:
			if o != w:
				assert_gt(p.distance_to(Vector2(float(o.pos[0]), float(o.pos[2]))), sep - 0.01)
	assert_eq(kinds.size(), 3)


func test_ball_wrecks_cover_both_sides_and_use_surface_spacing() -> void:
	var sphere := PlanetSphere.new(5000.0)
	var surface := func(x: float, z: float) -> Vector3: return sphere.surface_at(x, z)
	for i in int(DroidRoster.config().wrecks.ball_starting_count):
		assert_false(r.roll_wreck(rng, Vector3.ZERO, Callable(), true, surface, sphere.center, sphere.radius).is_empty())
	assert_eq(r.wrecks.size(), 8, "the ball starts with a field of wrecks")
	var far_side := 0
	var sep := float(DroidRoster.config().wrecks.ball_min_separation)
	var kinds := {}
	for w in r.wrecks:
		kinds[w.kind] = true
		var p := Vector3(float(w.pos[0]), float(w.pos[1]), float(w.pos[2]))
		var dir := (p - sphere.center).normalized()
		if dir.y < 0.0:
			far_side += 1
		assert_almost_eq(sphere.height_above_ground(p), 0.0, 0.01, "wreck is seated on spherical terrain")
		for other in r.wrecks:
			if other == w:
				continue
			var q := Vector3(float(other.pos[0]), float(other.pos[1]), float(other.pos[2]))
			var arc := acos(clampf(dir.dot((q - sphere.center).normalized()), -1.0, 1.0)) * sphere.radius
			assert_gt(arc, sep - 0.01, "wrecks stay separated over the curved surface")
	assert_gt(far_side, 0, "wrecks are not confined to the town-facing hemisphere")
	assert_lt(kinds.size(), r.wrecks.size(), "the larger field allows multiple wrecks of a kind")


func test_fix_wreck_and_save_round_trip() -> void:
	var w := r.roll_wreck(rng, Vector3.ZERO, Callable(), true)
	var d := r.fix_wreck(int(w.uid))
	assert_eq(d.kind, w.kind)
	assert_eq(r.wrecks.size(), 0)
	WorldState.inventory.add("holocrystals", 2)
	var c := r.add("cargo", "olive")
	r.stash(int(c.uid), WorldState.inventory, "holocrystals", 2)
	r.roll_wreck(rng, Vector3.ZERO, Callable(), true)
	r.wrecks_seeded = true
	var saved := WorldState.to_save()
	WorldState.from_save(JSON.parse_string(JSON.stringify(saved)))
	assert_eq(WorldState.droids.owned.size(), 2)
	assert_eq(WorldState.droids.wrecks.size(), 1)
	assert_true(WorldState.droids.wrecks_seeded, "the starting field is not re-seeded after a save")
	assert_eq(WorldState.droids.all_cargo().get("holocrystals"), 2)
	assert_eq(WorldState.inventory.count("holocrystals"), 0)


# ---- controller in a scene --------------------------------------------------

class FakePlayer extends CharacterBody3D:
	var piloting := false
	var locked := false


func _scene() -> Array:
	var root := Node3D.new()
	add_child_autofree(root)
	var floor_body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	col.shape = box
	col.position = Vector3(0, -0.5, 0)
	floor_body.add_child(col)
	root.add_child(floor_body)
	var p := FakePlayer.new()
	root.add_child(p)
	var ctl := DroidController.new()
	ctl.setup(null, p, null)
	root.add_child(ctl)
	return [ctl, p]


func test_controller_buy_sell_follow_and_ship() -> void:
	var s := _scene()
	var ctl: DroidController = s[0]
	var p: FakePlayer = s[1]
	WorldState.credits = 200
	assert_eq(ctl.buy("assassin"), "bought")
	assert_eq(WorldState.credits, 100)
	assert_eq(ctl.companions.size(), 1)
	assert_eq(ctl.remnant.size(), 2, "the Remnant's two patrol droids")
	p.global_position = Vector3(20, 0, 0)
	for i in 120:
		await wait_physics_frames(1)
	var u: Node3D = ctl.companions.values()[0]
	assert_lt(u.global_position.distance_to(p.global_position), 5.0, "it followed the player")
	p.piloting = true
	await wait_physics_frames(2)
	assert_eq(ctl.companions.size(), 0, "gone while flying")
	p.piloting = false
	await wait_physics_frames(2)
	assert_eq(ctl.companions.size(), 1, "back when the player climbs out")
	var uid := int(WorldState.droids.owned[0].uid)
	assert_eq(ctl.sell(uid), 90)
	assert_eq(WorldState.credits, 190)
	assert_eq(ctl.companions.size(), 0, "the sold droid de-spawns")


func test_chirp_timer_uses_droid_quirk() -> void:
	var s := _scene()
	var ctl: DroidController = s[0]
	WorldState.credits = 100
	assert_eq(ctl.buy("assassin"), "bought")
	var u = ctl.companions.values()[0]
	u.global_position = Vector3(100, 0, 0) # Keep this timer test silent.
	u.chirp_cd = 0.0

	ctl._chirps(0.016)

	var range_s: Array = DroidRoster.kind_cfg(u.kind).get("chirp_s", [9.0, 20.0])
	assert_gte(u.chirp_cd, float(range_s[0]) * 0.8, "the reset timer uses the low jitter bound")
	assert_lte(u.chirp_cd, float(range_s[1]) * 1.2, "the reset timer uses the high jitter bound")


func test_controller_make_room_then_fix_in_ten_seconds() -> void:
	var s := _scene()
	var ctl: DroidController = s[0]
	var p: FakePlayer = s[1]
	for k in ["floating", "cargo", "cargo"]:
		WorldState.droids.add(k, DroidRoster.pick_variant(k, rng))
	var wid := ctl.spawn_wreck(true)
	assert_gt(wid, 0)
	var wn: Node3D = ctl.wreck_nodes[wid]
	p.global_position = wn.global_position + Vector3(1, 0, 0)
	await wait_physics_frames(2)
	assert_eq(ctl.focus.get("kind"), "wreck")
	assert_eq(ctl.interact(), "menu", "full: asks which droid to sell")
	assert_true(ctl.menu.is_open())
	var credits := WorldState.credits
	ctl.menu.choose(str(WorldState.droids.owned[0].uid))
	assert_eq(WorldState.credits, credits + 40, "sold at merchant price")
	assert_false(ctl.fixing.is_empty(), "and the fix started")
	ctl.fixing.left = 0.05
	await wait_physics_frames(6)
	assert_eq(WorldState.droids.owned.size(), 3)
	assert_false(ctl.wreck_nodes.has(wid))
	assert_eq(WorldState.droids.wrecks.size(), 0)


# ---- issue #64 ----------------------------------------------------------------

func test_two_of_a_kind_do_not_stack() -> void:
	var s := _scene()
	var ctl: DroidController = s[0]
	var p: FakePlayer = s[1]
	WorldState.credits = 500
	assert_eq(ctl.buy("floating"), "bought")
	assert_eq(ctl.buy("floating"), "bought")
	for spot in [Vector3(20, 0, 0), Vector3(20, 0, 25)]:
		p.global_position = spot
		for i in 240:
			await wait_physics_frames(1)
	var us: Array = ctl.companions.values()
	assert_eq(us.size(), 2)
	var gap := Vector2(us[0].global_position.x - us[1].global_position.x, us[0].global_position.z - us[1].global_position.z).length()
	assert_gt(gap, 1.0, "two floating droids keep apart instead of sharing a slot")
	assert_ne(us[0].look_lift, us[1].look_lift, "and hover at their own heights")
	assert_ne(us[0].quirk(), us[1].quirk(), "each has its own pace")


func test_cargo_droid_is_bigger() -> void:
	var s := _scene()
	var ctl: DroidController = s[0]
	var u = ctl._make_unit("cargo", "tan")
	assert_gt(u.size_scale, 1.0)
	assert_almost_eq(u.look.scale.x, float(DroidRoster.kind_cfg("cargo").scale), 0.001)
	assert_gt((u.shape.shape as BoxShape3D).size.y, 0.7, "its body grew with it")
	u.free()


func test_pit_hauler_roams_the_pit() -> void:
	var s := _scene()
	var ctl: DroidController = s[0]
	assert_not_null(ctl.hauler, "the old cargo droid is in the pit")
	assert_eq(ctl.hauler.kind, "cargo")
	assert_eq(ctl.hauler.faction, "", "nobody's: not the Remnant's")
	assert_false(ctl.companions.values().has(ctl.hauler), "and not yours")
	var start: Vector3 = ctl.hauler.global_position
	for i in 120:
		await wait_physics_frames(1)
	assert_gt(Vector2(ctl.hauler.global_position.x - start.x, ctl.hauler.global_position.z - start.z).length(), 1.0, "it walks its round")
	var cfg: Dictionary = DroidRoster.config().pit_hauler
	assert_eq(str(cfg.carries), "pit_jetpack", "carrying the jetpack")
	var rumor: Array = WorldState.all_rumors().filter(func(r): return str(r.id) == "r_pit_hauler")
	assert_eq(rumor.size(), 1, "Oda knows about it")
	assert_true(str(rumor[0].text).to_lower().contains("jetpack"))
	assert_false(WorldState.rumors("stranger", [], 99).filter(func(r): return str(r.id) == "r_pit_hauler").is_empty(), "and tells strangers")
	WorldState.set_flag("pit_jetpack_taken")
	assert_true(WorldState.rumors("stranger", [], 99).filter(func(r): return str(r.id) == "r_pit_hauler").is_empty(), "until it is taken")


func test_assassin_holds_still_in_a_fight() -> void:
	var look := DroidKit.build("assassin", DroidRoster.variant_cfg("assassin", "bone"), LookMaterials.new(),
		DroidRoster.kind_cfg("assassin").look)
	add_child_autofree(look)
	if not DroidKit.play_anim(look, "idle"):
		pass_test("no rigged model in this build")
		return
	var ap: AnimationPlayer = look.find_child("AnimationPlayer", true, false)
	assert_eq(ap.speed_scale, 1.0, "standing about: the idle plays (its little dance)")
	assert_true(DroidKit.hold_pose(look, "aim", 0.0))
	assert_eq(ap.speed_scale, 0.0, "in a fight: one still ready stance")
	DroidKit.play_anim(look, "idle")
	assert_eq(ap.speed_scale, 1.0, "and back to the idle when it is over")
