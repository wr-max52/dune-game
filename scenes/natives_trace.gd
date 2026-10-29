extends SceneTree
## Issue #96 trace (headless, real physics, the real town scene): the first
## milestone of the desert packs. Buy food in town, carry it to the friendly pack
## and gesture it into quartz, sell the quartz back in town; hunt a sand pig and
## butcher it for food; walk up to the hostile pack and get the horn and the
## attack; survive five minutes without killing any of them and they turn
## friendly and trade; then a kill that locks a pack hostile for good.
## Writes test_results/natives_trace.txt for tests/test_natives_trace.gut.gd.
##
## Run: godot --headless --fixed-fps 60 --path . -s res://scenes/natives_trace.gd

const OUT := "res://test_results/natives_trace.txt"

var demo
var player
var nat   ## NativesDirector (untyped: its classes need the autoloads, which load after this script compiles)
var lines := PackedStringArray()


func _initialize() -> void:
	WorldState.reset()
	GameFlow.reset()
	GameFlow.change_scene = func(_p: String) -> void: pass
	_run()


func out(k: String, v) -> void:
	lines.append("%s=%s" % [k, str(v)])
	print("  ", k, "=", v)


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func place_player(p: Vector3) -> void:
	player.global_position = p
	player.velocity = Vector3.ZERO
	player.controller.velocity = Vector3.ZERO
	player.controller.body_pos = p
	if demo.terrain != null:
		demo.terrain.snap_to(p)


## Stand the player `d` metres from the leader of pack `p`, on the ground.
func beside(p: Dictionary, d: float) -> void:
	var lead = nat.leader(p)
	var up: Vector3 = nat.up_at(lead.global_position)
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	place_player(nat._on_ground(lead.global_position + side * d) + up * 0.1)


func _vendor(id: String) -> Dictionary:
	for v in demo.gear.vendors:
		if str(v.cfg.get("id", "")) == id:
			return v
	return {}


func _run() -> void:
	demo = load("res://scenes/town_demo.gd").new()
	demo.use_look = false
	demo.npc_brains = false
	get_root().add_child(demo)
	await frames(5)
	player = demo._player
	nat = demo.natives
	out("NATIVES_BUILT", nat != null)
	if nat == null:
		_write()
		return
	out("PEOPLE", str(nat.natives.get("people", {}).get("id", "")))
	out("PACKS", nat.packs.size())
	var friendly: Dictionary = nat.packs.filter(func(p): return bool(p.rec.friendly))[0]
	var hostile: Dictionary = nat.packs.filter(func(p): return not bool(p.rec.friendly))[0]
	out("FRIENDLY_SIZE", (friendly.members as Array).size())
	out("HOSTILE_SIZE", (hostile.members as Array).size())
	out("CHILDREN", (friendly.members as Array).filter(func(m): return bool(m.child)).size())
	out("CHILD_SMALLER", (friendly.members as Array).filter(func(m): return bool(m.child)).all(
		func(m): return float(m.npc.profile.get("look_scale", 1.0)) < 0.7))
	out("NO_RIFLES", (hostile.members as Array).all(func(m): return str(m.weapon.get("id", "")) != "rifle_blaster"))
	out("PIGS", nat.pigs.size())
	# ---------------------------------------------------------------- food in town
	WorldState.credits = 100
	var stall := _vendor("food_stall")
	out("FOOD_STALL", not stall.is_empty())
	for i in 3:
		demo.gear._trade(stall.cfg)
	out("FOOD_BOUGHT", WorldState.inventory.count("food"))
	out("CREDITS_AFTER_FOOD", WorldState.credits)
	# ---------------------------------------------------------------- the friendly pack
	beside(friendly, 3.0)
	await frames(90)
	out("FRIENDLY_GREETS", friendly.state == "greet")
	out("TRADE_PACK_IN_REACH", str(nat.trade_pack().get("id", "")) == str(friendly.id))
	out("TRADE", nat.trade(str(friendly.id)))
	out("QUARTZ", WorldState.inventory.count("quartz"))
	out("FRIENDLY_REP", int(friendly.rec.rep))
	# ---------------------------------------------------------------- sell the quartz
	var credits0 := WorldState.credits
	demo.gear._trade(stall.cfg)
	out("QUARTZ_SOLD_FOR", WorldState.credits - credits0)
	# ---------------------------------------------------------------- a sand pig
	var pig = nat.pigs[0]
	place_player(nat._on_ground(pig.global_position + nat.up_at(pig.global_position).cross(Vector3.RIGHT).normalized() * 2.0))
	await frames(5)
	var food0 := WorldState.inventory.count("food")
	pig.apply_damage_from(999.0, player)
	out("PIG_DEAD", pig.dead)
	out("BUTCHER_PROMPT", nat.carcass_near(6.0) == pig)
	out("PIG_FOOD", nat.butcher(pig))
	out("FOOD_FROM_PIG", WorldState.inventory.count("food") - food0)
	# ---------------------------------------------------------------- the hostile pack
	beside(hostile, 12.0)
	var hp0: int = player.health.hp
	var took := false
	for i in 60 * 12:
		await physics_frame
		if player.health.hp < hp0:
			took = true
			break
	out("HORN", nat.horns >= 1)
	out("HOSTILE_ATTACKS", hostile.state == "attack")
	out("PLAYER_HURT", took)
	# ---------------------------------------------------------------- survive 5 minutes
	var survived := 0.0
	var won := false
	for i in int(60 * (nat.survive_s + 20.0)):
		player.health.hp = player.max_health          # the trace's player cannot die
		player.is_downed = false
		await physics_frame
		survived += 1.0 / 60.0
		if bool(hostile.rec.friendly):
			won = true
			break
	out("SURVIVED_S", snappedf(survived, 0.1))
	out("WON_OVER", won)
	out("STATE_AFTER", str(hostile.state))
	out("HOSTILE_KILLS", int(hostile.rec.get("kills", 0)))
	await frames(60)
	WorldState.inventory.add("food", 1)
	beside(hostile, 3.0)
	await frames(30)
	out("TRADE_AFTER_WIN", nat.trade(str(hostile.id)))
	# ---------------------------------------------------------------- a kill locks it
	hostile.rec.friendly = false
	hostile.rec.won = false
	hostile.state = "travel"
	beside(hostile, 12.0)
	await frames(30)
	nat.start_attack(hostile)
	var victim = nat.alive(hostile)[1].npc
	victim.apply_damage_from(9999.0, player)
	await frames(10)
	out("KILLED_ONE", victim.dead)
	out("LOCKED", bool(hostile.rec.locked))
	hostile.attack_t = nat.survive_s + 1.0
	for i in 10:
		player.health.hp = player.max_health
		await physics_frame
	out("NEVER_FRIENDLY", not bool(hostile.rec.friendly))
	out("SAVED", WorldState.to_save().get("native_packs", {}).has(str(hostile.id)))
	_write()


func _write() -> void:
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_results"))
		f = FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("NATIVESTRACE wrote ", OUT, " (", lines.size(), " lines)")
	quit()
