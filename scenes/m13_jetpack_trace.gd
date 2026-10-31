extends SceneTree
## M13 trace (headless): the jetpack, end to end, with real physics in the town.
## Writes test_results/m13_jetpack_trace.txt (KEY=value lines) for
## tests/test_m13_jetpack.gut.gd.
##
## The bot walks out of the pit and up the ramp to the jetpack, picks it up (it
## attaches), flies, lets the fuel recharge, takes it off and puts it back on,
## flies out over the north wall (and lands on the sand outside), sells it at the market, buys it
## back, and reloads the town from a save to show the pickup stays taken. The bot
## uses the same calls the keys do (set_command with jump held, interact(),
## toggle_gear()).
##
## Run: godot --headless --fixed-fps 60 --path . -s res://scenes/m13_jetpack_trace.gd

const OUT := "res://test_results/m13_jetpack_trace.txt"
const OPEN_SKY := Vector3(40, 0, 10)       # street, nothing overhead
const NORTH_STRIP := Vector3(-84, 0, 71)   # just inside the north wall, clear around
const TRADER_APPROACH := Vector3(58, 0, -38)   # the market aisle, in front of the trader's stall

var demo
var gear: GearController
var player
var lines := PackedStringArray()
var worst_ms := 0.0
var _last := 0
var _frames := 0
var jet_starts := 0


func _initialize() -> void:
	WorldState.reset()
	demo = load("res://scenes/town_demo.gd").new()
	demo.npc_brains = false   # M15: guards hold their posts; this trace is about something else
	demo.use_look = false              # greybox: fast, same collision
	get_root().add_child(demo)
	_run()


func _process(_d: float) -> bool:
	var now := Time.get_ticks_usec()
	if _last > 0 and _frames > 30:
		worst_ms = maxf(worst_ms, (now - _last) / 1000.0)
	_last = now
	_frames += 1
	return false


func out(k: String, v) -> void:
	lines.append("%s=%s" % [k, str(v)])


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func place(p: Vector3) -> void:
	player.global_position = p + Vector3(0, 0.05, 0)
	player.velocity = Vector3.ZERO
	player.controller.velocity = Vector3.ZERO
	player.controller.body_pos = player.global_position
	player.rotation.y = 0.0            # yaw 0: command x -> world x, y -> world z


## Walk (2D steering, like the town walk trace) until within `reach` of `to`.
## Returns the frames it took, or -1 on timeout.
func walk_to(to: Vector3, reach: float = 0.6, max_frames: int = 1200) -> int:
	for i in max_frames:
		var p: Vector3 = player.global_position
		var d := Vector2(to.x - p.x, to.z - p.z)
		if d.length() <= reach:
			player.set_command(Vector2.ZERO, false, false, false)
			await frames(2)
			return i
		player.rotation.y = 0.0
		player.set_command(d.normalized(), true, false, false)
		await physics_frame
	player.set_command(Vector2.ZERO, false, false, false)
	return -1


## Jump and hold for `hold_frames` (0 = a tap). Returns { apex, frames_air }
## measured from the start height, after landing again.
func jump(hold_frames: int, dir: Vector2 = Vector2.ZERO) -> Dictionary:
	var y0: float = player.global_position.y
	var apex := y0
	player.set_command(dir, false, false, true, true)
	await physics_frame
	var air := 0
	var held := 1
	for i in 60 * 30:
		var hold := held < hold_frames
		player.set_command(dir, false, false, false, hold)
		await physics_frame
		held += 1
		air += 1
		apex = maxf(apex, player.global_position.y)
		if player.is_on_floor() and air > 5:
			break
	player.set_command(Vector2.ZERO, false, false, false)
	await frames(2)
	return { "apex": apex - y0, "air": air }


func _run() -> void:
	await frames(5)
	demo._attach_body()                # the worn pack needs a body to sit on
	gear = demo.gear
	player = demo._player
	player.jet_started.connect(func(): jet_starts += 1)
	await frames(5)
	out("GEAR_BUILT", gear != null)
	out("PICKUPS_PLACED", gear.pickups.size())
	out("JETPACK_PICKUP_PLACED", gear.pickup_node("pit_jetpack") != null)
	out("VENDORS_PLACED", gear.vendors.size())
	out("START_CREDITS", WorldState.credits)

	# ---- without a jetpack: tap and hold are the same plain jump
	place(OPEN_SKY)
	await frames(10)
	var tap0: Dictionary = await jump(0)
	var hold0: Dictionary = await jump(120)
	out("NO_PACK_TAP_APEX", snappedf(tap0.apex, 0.01))
	out("NO_PACK_HOLD_APEX", snappedf(hold0.apex, 0.01))
	out("NO_PACK_TOGGLE", gear.toggle_gear())

	# ---- walk out of the pit and up the ramp to the jetpack
	place(demo.town.spawn_pos())
	await frames(10)
	var pk: Node3D = gear.pickup_node("pit_jetpack")
	var spot: Vector3 = pk.base if pk != null else Vector3.ZERO
	var f1 := await walk_to(Vector3(2, 0, 18.5), 0.75)
	var f2 := await walk_to(Vector3(22, 0, 18.5), 0.75)
	var f3 := await walk_to(spot, 1.2)
	out("WALKED_TO_PICKUP", f1 >= 0 and f2 >= 0 and f3 >= 0)
	out("PICKUP_HEIGHT_OK", absf(player.global_position.y - spot.y) < 0.3)
	await frames(2)
	out("PICKUP_PROMPT", gear.prompt_text())
	out("PICKUP_RESULT", gear.interact())
	await frames(3)
	out("OWNS_JETPACK", WorldState.inventory.has("jetpack"))
	out("ATTACHED", WorldState.inventory.in_slot("back"))
	out("PLAYER_HAS_JET", player.jetpack != null)
	out("PICKUP_GONE", gear.pickup_node("pit_jetpack") == null)
	out("PICKUP_TAKEN", WorldState.inventory.is_taken("pit_jetpack"))
	out("SECOND_INTERACT", gear.interact())
	var chest = player.get_node("Avatar").joints.chest
	out("WORN_ON_CHEST", gear.worn != null and gear.worn.get_parent() == chest)
	var back_z: float = (chest.global_transform.affine_inverse() * gear.worn.global_position).z if gear.worn != null else 0.0
	out("WORN_BEHIND", back_z < -0.05)

	# ---- fly: a tap is still a plain jump; a hold is a jetpack climb
	place(OPEN_SKY)
	await frames(30)
	var jet = player.jetpack
	jet.refill()
	var tap1: Dictionary = await jump(4)
	out("PACK_TAP_APEX", snappedf(tap1.apex, 0.01))
	out("PACK_TAP_FUEL_USED", snappedf(jet.fuel_max() - jet.fuel, 0.001))
	jet.refill()
	var burned0: float = jet.burned
	var starts0 := jet_starts
	var flames_seen := false
	var min_fuel: float = jet.fuel
	var y0: float = player.global_position.y
	var apex := y0
	player.set_command(Vector2.ZERO, false, false, true, true)
	await physics_frame
	var air := 0
	for i in 60 * 30:
		player.set_command(Vector2.ZERO, false, false, false, true)    # keep holding
		await physics_frame
		air += 1
		apex = maxf(apex, player.global_position.y)
		min_fuel = minf(min_fuel, jet.fuel)
		if jet.thrusting and gear.worn != null and gear.worn.get_node("Flames").visible:
			flames_seen = true
		if player.is_on_floor() and air > 5:
			break
	player.set_command(Vector2.ZERO, false, false, false)
	await frames(2)
	out("PACK_HOLD_APEX", snappedf(apex - y0, 0.01))
	out("PACK_HOLD_AIR_FRAMES", air)
	out("PACK_BURN_SECONDS", snappedf(jet.burned - burned0, 0.01))
	out("PACK_MIN_FUEL", snappedf(min_fuel, 0.001))
	out("PACK_LIT", jet_starts - starts0)
	out("FLAMES_WHILE_THRUSTING", flames_seen)
	out("FLAMES_AFTER_LANDING", gear.worn.get_node("Flames").visible if gear.worn != null else true)
	out("FUEL_ON_LANDING", snappedf(jet.fuel, 0.001))
	await frames(30)
	out("FUEL_HALF_SECOND_LATER", snappedf(jet.fuel, 0.001))
	await frames(int(60 * (jet.recharge_delay() + jet.fuel_max() / jet.recharge_ground() + 0.5)))
	out("FUEL_RECHARGED", snappedf(jet.fuel, 0.001))

	# ---- take it off, jump, put it back on
	out("DETACH", gear.toggle_gear())
	await frames(2)
	out("DETACHED_PLAYER_HAS_JET", player.jetpack != null)
	out("DETACHED_WORN", gear.worn != null)
	out("DETACHED_STILL_OWNED", WorldState.inventory.has("jetpack"))
	var hold2: Dictionary = await jump(120)
	out("DETACHED_HOLD_APEX", snappedf(hold2.apex, 0.01))
	out("REATTACH", gear.toggle_gear())
	await frames(2)
	out("REATTACHED_PLAYER_HAS_JET", player.jetpack != null)

	# ---- fly out over the north wall: the town sits on the desert now, so the
	# pack sets you down on the sand outside (no rescue needed)
	place(NORTH_STRIP)
	await frames(20)
	player.jetpack.refill()
	var rec0 := gear.recoveries
	var max_z := -INF
	var top := -INF
	var landed := false
	player.set_command(Vector2(0, 1), false, false, true, true)
	await physics_frame
	for i in 60 * 12:
		player.rotation.y = 0.0
		var climbing := top < 9.0
		player.set_command(Vector2(0, 1), false, false, false, climbing)
		await physics_frame
		max_z = maxf(max_z, player.global_position.z)
		top = maxf(top, player.global_position.y)
		if gear.recoveries > rec0:
			break
		if player.is_on_floor() and player.global_position.z > 76.0 and top > 6.5:
			landed = true
			break
	player.set_command(Vector2.ZERO, false, false, false)
	await frames(30)
	out("WALL_CLEARED", top > 6.5 and max_z > 75.0)
	out("FLEW_OUT_MAX_Z", snappedf(max_z, 0.1))
	out("RECOVERED", gear.recoveries - rec0)
	var outside: Vector3 = player.global_position
	out("LANDED_OUTSIDE", landed and outside.z > 75.0 and player.is_on_floor())
	out("LANDED_Y", snappedf(outside.y, 0.01))

	# ---- sell at the market, then buy it back
	place(TRADER_APPROACH)
	await frames(10)
	var trader: Dictionary = demo.gear.content.get_vendor("gear_trader")
	var stall: Vector3 = demo.town.marker_pos(str(trader.marker))
	var fv := await walk_to(Vector3(stall.x, 0, -35.2), 0.3, 400)   # up to the counter
	out("REACHED_TRADER", fv >= 0 or Vector2(player.global_position.x - stall.x, player.global_position.z - stall.z).length() <= float(trader.reach))
	await frames(2)
	out("SELL_PROMPT", gear.prompt_text())
	var c0: int = WorldState.credits
	out("TRADE_MENU", gear.interact())
	out("SELL_ROW", _row(gear, "sell:jetpack"))
	gear.menu.choose("sell:jetpack")
	out("SELL_RESULT", gear.last_trade)
	out("MENU_STAYS_OPEN", gear.menu.is_open())
	await frames(2)
	out("SOLD_FOR", WorldState.credits - c0)
	out("AFTER_SALE_OWNS", WorldState.inventory.has("jetpack"))
	out("AFTER_SALE_ATTACHED", WorldState.inventory.in_slot("back"))
	out("AFTER_SALE_PLAYER_HAS_JET", player.jetpack != null)
	out("AFTER_SALE_WORN", gear.worn != null)
	out("TRADER_STOCK", ",".join(PackedStringArray(WorldState.inventory.vendor_stock(trader))))
	out("EVENT_LOGGED", str(WorldState.events[-1].text) if not WorldState.events.is_empty() else "")
	out("BUY_ROW", _row(gear, "buy:jetpack"))
	var c1: int = WorldState.credits
	gear.menu.choose("buy:jetpack")
	out("BUY_RESULT", gear.last_trade)
	await frames(2)
	out("BOUGHT_FOR", c1 - WorldState.credits)
	out("BOUGHT_ATTACHED", WorldState.inventory.in_slot("back"))
	out("BOUGHT_PLAYER_HAS_JET", player.jetpack != null)
	gear.menu.choose("sell:jetpack")
	out("RESELL_RESULT", gear.last_trade)
	await frames(2)
	out("POOR_ROW", _row(gear, "buy:jetpack"))
	gear.menu.choose("buy:jetpack")
	out("POOR_RESULT", gear.last_trade)
	gear.menu.choose("")        # walk away
	out("END_CREDITS", WorldState.credits)

	# Frame cost of the gameplay above (the reload below rebuilds the whole town,
	# which is a load, not a frame).
	out("WORST_MS", snappedf(worst_ms, 0.01))

	# ---- save, reload the town: the jetpack does not reappear in the street
	WorldState.inventory.buy("jetpack", demo.gear.content.get_item("jetpack"), trader, 999)   # test: own it again
	WorldState.inventory.attach("jetpack", demo.gear.content.get_item("jetpack"))
	var saved := JSON.stringify(WorldState.to_save())
	WorldState.reset()
	WorldState.from_save(JSON.parse_string(saved))
	demo.queue_free()
	await frames(3)
	demo = load("res://scenes/town_demo.gd").new()
	demo.npc_brains = false   # M15: guards hold their posts; this trace is about something else
	demo.use_look = false
	get_root().add_child(demo)
	await frames(5)
	out("RELOAD_PICKUPS_PLACED", demo.gear.pickups.size())
	out("RELOAD_JETPACK_PLACED", demo.gear.pickup_node("pit_jetpack") != null)
	out("RELOAD_ATTACHED", WorldState.inventory.in_slot("back"))
	out("RELOAD_PLAYER_HAS_JET", demo._player.jetpack != null)
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_results"))
		f = FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("M13TRACE wrote ", OUT, " (", lines.size(), " lines)")
	quit()


## The trade menu's row for option `id` ("" when it is not there).
func _row(gear, id: String) -> String:
	for o in gear.menu.options:
		if str(o.id) == id:
			return str(o.text)
	return ""
