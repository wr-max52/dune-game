class_name NativesDirector
extends Node3D
## Issue #96: a planet's native people and wild animals, in play. Built by the
## town scene from the planet's "natives" (NativesData.resolve: its own config or
## its type's, the way the planet generator gives a planet everything else).
##
## Packs: 10 to 20 of one people on foot, children among them (the same bodies at
## 60%), a leader in the helmet carrying a tall pole with a rag on it so a pack is
## seen coming from far off. Every member of a pack wears the pack's colours.
## They walk their route over and over. Each NPC is an NpcBody (the guards' body,
## senses and health) walking open ground with no navmesh (free_walk); far from
## the player (pack.far_lod_m) they are slid along the ground instead, no physics,
## so a pack can cross the desert where there is no collider.
##
## How a pack treats you is its own (WorldState.native_pack), never your standing
## with the Remnant:
##   friendly  the leader comes over and gestures (they do not speak the port's
##             language: yells, and trade by hand). [E] gestures back: one food for
##             quartz (a little more from an adults-only pack), reputation up.
##   hostile   a battle horn, then they come at you on sight with clubs, spears and
##             knives, and throw sticks and light spears from further off. They
##             fight to the last; nobody flees. Survive survive_s (5 minutes)
##             without killing one of them and without being downed, and they
##             stop, offer trade and are friendly from then on. Kill one and that
##             pack is hostile for good. Downed, you wake as from any other death
##             and they go back to their route.
## Animals: each roams alone (SandPig); kill one and [E] at the carcass cuts food.
##
## Not in this milestone (the data has room for them): camps and tents, packs
## fighting each other and the Remnant, sandstorms, stealing vehicles.

signal traded(pack_id: String, quartz: int)
signal pack_won(pack_id: String)
signal pack_locked(pack_id: String)

var demo                              ## town_demo.gd
var ground: WorldGround
var gear: GearController
var player: CharacterBody3D
var natives: Dictionary = {}
var people: Dictionary = {}           ## the species data
var packs: Array = []                 ## see _make_pack
var pigs: Array = []                  ## SandPig
var survive_s := 300.0
## Members far from the player (slid along the ground) step once in this many ticks.
var far_stride := 4
var trades := 0
var butchered := 0
var _rng := RandomNumberGenerator.new()
var _hud: CanvasLayer
var _timer_label: Label
var _clock := 0.0


func setup(town_demo, n: Dictionary, world_ground: WorldGround, p_gear: GearController) -> void:
	demo = town_demo
	natives = n
	ground = world_ground
	gear = p_gear
	player = demo._player
	people = n.get("people", {}).get("data", {})
	survive_s = float(people.get("hostile", {}).get("survive_s", 300.0))
	name = "Natives"
	_rng.seed = 96


func _ready() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 5
	add_child(_hud)
	_timer_label = Label.new()
	_timer_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_timer_label.position = Vector2(-240, 110)
	_timer_label.size = Vector2(480, 30)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.add_theme_font_size_override("font_size", 22)
	_timer_label.add_theme_color_override("font_color", Color("#ffb060"))
	_timer_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_timer_label.add_theme_constant_override("outline_size", 6)
	_timer_label.visible = false
	_hud.add_child(_timer_label)
	_queue_build()
	if not staged:
		while not build_step():
			pass


# ------------------------------------------------------------------ build (issue #121)

## True: _ready only queues the bodies and build_step() makes them, one per call
## (a staged planet handoff builds the scene over several frames). Set before
## add_child. Each body is a whole procedural character, tens to hundreds of ms.
var staged := false
var _build_queue: Array = []          ## Callables, run in order: the same order (and the
                                      ## same random draws) as building everything at once


func _queue_build() -> void:
	_build_queue.clear()
	if not people.is_empty():
		var i := 0
		for p in natives.get("packs", []):
			var idx := i
			_build_queue.append(func(): _start_pack(p, idx))
			i += 1
	for f in natives.get("fauna", []):
		var state := { "f": f }
		_build_queue.append(func(): return _fauna_step(state))


## Make the next body (or start the next pack). True once everything is built.
func build_step() -> bool:
	while not _build_queue.is_empty():
		var job: Callable = _build_queue.pop_front()
		if job.call() == true:
			return _build_queue.is_empty()  # a body was made: one per call
	return true


## Whether every pack member and animal exists.
func is_built() -> bool:
	return _build_queue.is_empty()


func _line(key: String) -> String:
	return str(people.get("lines", {}).get(key, key))


func _voice(key: String) -> Array:
	return people.get("voice", {}).get(key, [])


# ------------------------------------------------------------------ ground

## A map point (metres along the ground from the port) on the ground.
func surface(m: Vector2) -> Vector3:
	var sp := ground.sphere() if ground != null else null
	if sp != null:
		return sp.surface_at(m.x, m.y)
	var h := ground.terrain.height_at(m.x, m.y) if ground != null and ground.terrain != null else 0.0
	return Vector3(m.x, h, m.y)


func up_at(p: Vector3) -> Vector3:
	return ground.up_at(p) if ground != null else Vector3.UP


func _on_ground(p: Vector3) -> Vector3:
	return ground.surface_below(p + up_at(p) * 4.0) if ground != null else p


# ------------------------------------------------------------------ packs

## A pack's record and root now, its members as the next jobs (in order). The
## pack is listed at once; one with no members yet is skipped every tick.
func _start_pack(p: Dictionary, index: int) -> bool:
	var pack := _make_pack(p, index)
	packs.append(pack)
	return false


func _make_pack(p: Dictionary, index: int) -> Dictionary:
	var id := str(p.get("id", "pack_%d" % index))
	var rec := WorldState.native_pack(id, str(p.get("attitude", "friendly")))
	var route: Array = (p.get("route", []) as Array).map(func(m): return surface(m))
	if route.is_empty():
		route = [surface(Vector2(600, 0))]
	var style := _style(str(p.get("style", "")), index)
	var size := clampi(int(p.get("size", 12)), 1, 40)
	var kids := clampi(int(p.get("children", 0)), 0, size - 1)
	var pack := {
		"id": id, "label": str(p.get("label", id)), "data": p, "rec": rec, "route": route, "route_i": 1 % route.size(),
		"members": [], "state": "travel", "attack_t": 0.0, "horned": false, "adults_only": kids == 0,
		"heading": Vector3.FORWARD, "center": route[0],
	}
	var root := Node3D.new()
	root.name = "Pack_" + id
	add_child(root)
	pack["root"] = root
	var jobs: Array = []
	for i in size:
		var slot := i
		jobs.append(func(): _add_member(pack, slot, size, kids, style); return true)
	_build_queue = jobs + _build_queue
	if bool(rec.get("friendly", false)) == false and bool(rec.get("won", false)):
		rec.friendly = true
	return pack


## Member `i` of `pack` (the leader is 0, the children last).
func _add_member(pack: Dictionary, i: int, size: int, kids: int, style: Dictionary) -> void:
	var weapons: Dictionary = people.get("weapons", {})
	var melee: Array = weapons.get("melee", [])
	var thrown: Array = weapons.get("thrown", [])
	var route: Array = pack.route
	var child := i >= size - kids
	var thrower := not child and i > 0 and not thrown.is_empty() and _rng.randf() < float(weapons.get("thrower_share", 0.4))
	var w: Dictionary = (thrown[_rng.randi() % thrown.size()] if thrower else (melee[_rng.randi() % melee.size()] if not melee.is_empty() else {}))
	var at := _on_ground(route[0] + _ring_offset(i, route[0]))
	var npc := _make_member(pack, i == 0, child, thrower, w, style, at)
	(pack.root as Node3D).add_child(npc)
	(pack.members as Array).append({ "npc": npc, "child": child, "thrower": thrower, "weapon": w, "cd": _rng.randf_range(0.0, 1.0), "slot": i })
	npc.died.connect(_on_member_died.bind(pack, npc))
	npc.hit_by.connect(_on_member_hit.bind(pack))


func _style(id: String, index: int) -> Dictionary:
	var styles: Array = people.get("styles", [])
	for s in styles:
		if str(s.get("id", "")) == id:
			return s
	return styles[index % styles.size()] if not styles.is_empty() else {}


func _ring_offset(i: int, at: Vector3) -> Vector3:
	if i == 0:
		return Vector3.ZERO
	var up := up_at(at)
	var a := TAU * float(i) / 7.0
	var r := 2.0 + float(i / 7) * 2.2
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var fwd := side.cross(up)
	return side * cos(a) * r + fwd * sin(a) * r


## One member: the guards' body from the people's soldier block, in the pack's
## colours (the leader in the helmet), a child at child_scale, and what it fights
## with in its hand.
func _make_member(pack: Dictionary, leader: bool, child: bool, thrower: bool, w: Dictionary, style: Dictionary, at: Vector3) -> NpcBody:
	var body: Dictionary = people.get("body", {})
	var soldier: Dictionary = (people.get("soldier", {}) as Dictionary).duplicate(true)
	soldier["id"] = "native_" + str(natives.get("people", {}).get("id", "people"))
	soldier["archetype"] = str(body.get("archetype", "desert_nomad"))
	soldier["outfit"] = { "head": str(style.get("leader_head" if leader else "head", "")), "torso": str(style.get("torso", "")),
		"legs": str(style.get("legs", "")) }
	for k in soldier.outfit.keys():
		if soldier.outfit[k] == "":
			soldier.outfit.erase(k)
	if child:
		soldier["look_scale"] = float(body.get("child_scale", 0.6))
		soldier["hp"] = int(round(float(soldier.get("hp", 44)) * float(body.get("child_hp", 0.5))))
	# The body's weapon: a throw (slow, one at a time) for a thrower; melee
	# members carry the same unused so the body has one.
	var tw: Dictionary = w if thrower else (people.get("weapons", {}).get("thrown", [{}]) as Array)[0]
	soldier["weapon"] = { "base": "pistol_blaster", "damage": float(tw.get("damage", 7)), "bolt_speed": float(tw.get("speed", 22.0)),
		"rate": float(tw.get("cooldown_s", 3.0)), "range": float(tw.get("range", 16.0)), "mag": 1,
		"reload_time": float(tw.get("cooldown_s", 3.0)), "noise_radius": 18.0, "bolt_color": str(tw.get("color", "#8a6a3a")) }
	var npc := NpcBody.new()
	npc.post_id = "%s_%d" % [str(pack.id), (pack.members as Array).size()]
	npc.setup(soldier, at, _rng.randf() * TAU, demo._flat_mats() if demo.use_look else null)
	npc.free_walk = true
	npc.nav = null
	npc.bolt_parent = demo
	npc.target = player
	npc.target_armed = func(): return demo.player_kit != null and demo.player_kit.weapons.holder.current != ""
	npc.target_crouched = func(): return false
	if demo.use_look:
		_hand_weapon(npc, w, thrower, child)
		if leader:
			_standard(npc, body.get("standard", {}))
	return npc


## A stick, a spear or a knife in the right hand (look only).
func _hand_weapon(npc: NpcBody, w: Dictionary, thrower: bool, child: bool) -> void:
	var joint = npc.joints.get("r_wrist") if npc.joints is Dictionary else null
	if not (joint is Node3D):
		return
	var mats: LookMaterials = demo._flat_mats()
	var wood := mats.flat(Color("#6a4a2a"), 0.95)
	var bone := mats.flat(Color("#d8ccb0"), 0.8)
	var look := str(w.get("look", "spear" if thrower else "club"))
	var mi := MeshInstance3D.new()
	mi.name = "HandWeapon"
	var c := CylinderMesh.new()
	match look:
		"spear":
			c.top_radius = 0.025
			c.bottom_radius = 0.03
			c.height = 1.9
		"knife":
			c.top_radius = 0.01
			c.bottom_radius = 0.03
			c.height = 0.35
		_:
			c.top_radius = 0.07
			c.bottom_radius = 0.035
			c.height = 0.75
	mi.mesh = c
	mi.material_override = bone if look == "knife" else wood
	mi.rotation_degrees = Vector3(80, 0, 0)
	(joint as Node3D).add_child(mi)


## The leader's pole: tall, with a rag on top, seen from far off.
func _standard(npc: NpcBody, cfg: Dictionary) -> void:
	var mats: LookMaterials = demo._flat_mats()
	var h := float(cfg.get("height", 4.2))
	var pole := MeshInstance3D.new()
	pole.name = "Standard"
	var c := CylinderMesh.new()
	c.top_radius = 0.03
	c.bottom_radius = 0.04
	c.height = h
	pole.mesh = c
	pole.material_override = mats.flat(Color("#5a3e24"), 0.95)
	pole.position = Vector3(0.45, h * 0.5, 0.1)
	npc.add_child(pole)
	var rag := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.04, 0.7, 0.9)
	rag.mesh = b
	rag.material_override = mats.cloth(Color(str(cfg.get("cloth", "#b8762e"))))
	rag.position = Vector3(0.45, h - 0.45, 0.55)
	npc.add_child(rag)


func alive(pack: Dictionary) -> Array:
	return (pack.members as Array).filter(func(m): return is_instance_valid(m.npc) and not m.npc.dead)


func pack(id: String) -> Dictionary:
	for p in packs:
		if p.id == id:
			return p
	return {}


func leader(pack: Dictionary) -> NpcBody:
	var a := alive(pack)
	return a[0].npc if not a.is_empty() else null


# ------------------------------------------------------------------ frame

func _physics_process(dt: float) -> void:
	_clock += dt
	var ppos := _player_pos()
	var timer_text := ""
	for p in packs:
		if not (p is Dictionary) or not p.has("members"):
			continue               # torn down (the scene is being freed)
		_tick_pack(p, dt, ppos)
		if p.state == "attack" and timer_text == "":
			var left := maxf(0.0, survive_s - float(p.attack_t))
			timer_text = _line("survive") % [int(left) / 60, int(left) % 60] if not bool(p.rec.locked) else ""
	_timer_label.text = timer_text
	_timer_label.visible = timer_text != ""
	_tick_prompts()


func _player_pos() -> Vector3:
	if player == null or not is_instance_valid(player) or bool(player.get("is_downed")):
		return Vector3.INF
	if bool(player.get("piloting")):
		var v = player.get("vehicle")
		if v is SpeederNode:
			return (v as SpeederNode).model.position        # they chase a speeder on foot
		return Vector3.INF
	return player.global_position


func _tick_pack(p: Dictionary, dt: float, ppos: Vector3) -> void:
	var a := alive(p)
	if a.is_empty():
		return
	var lead: NpcBody = a[0].npc
	p.center = lead.global_position
	var d := lead.global_position.distance_to(ppos) if ppos != Vector3.INF else INF
	var pk: Dictionary = people.get("pack", {})
	var rec: Dictionary = p.rec
	var noticed := false
	for m in a:
		noticed = noticed or (m.npc as NpcBody).perception.noticed
	match str(p.state):
		"travel", "greet":
			if not bool(rec.friendly):
				if ppos != Vector3.INF and (noticed or d < float(pk.get("notice_range", 45.0))):
					start_attack(p)
			elif ppos != Vector3.INF and d < float(pk.get("greet_range", 30.0)):
				p.state = "greet"
			elif p.state == "greet" and d > float(pk.get("greet_range", 30.0)) * 1.6:
				p.state = "travel"
		"attack":
			if ppos == Vector3.INF:
				_stand_down(p)               # downed (or flown off): back to their route
			elif d > float(people.get("hostile", {}).get("chase_leash_m", 160.0)):
				_stand_down(p)
			else:
				p.attack_t = float(p.attack_t) + dt
				if not bool(rec.locked) and int(rec.get("kills", 0)) == 0 and float(p.attack_t) >= survive_s:
					_win_over(p)
	for m in a:
		_tick_member(p, m, dt, ppos)


func _tick_member(p: Dictionary, m: Dictionary, dt: float, ppos: Vector3) -> void:
	var npc: NpcBody = m.npc
	var lod := float(people.get("pack", {}).get("far_lod_m", 90.0))
	var far := ppos == Vector3.INF or npc.global_position.distance_to(ppos) > lod
	if far and p.state != "attack":
		# Out of sight of the player: slid along the ground, no physics (there may
		# be no collider under them out here).
		if npc.process_mode != Node.PROCESS_MODE_DISABLED:
			npc.process_mode = Node.PROCESS_MODE_DISABLED
		# Nobody is looking: step at a fraction of the tick rate, each member on its
		# own tick (by slot), with the time of the ticks in between so the speed and
		# the route progress are the same as stepping every tick.
		var acc := float(m.get("far_acc", 0.0)) + dt
		var n := int(m.get("far_n", 0)) + 1
		m["far_acc"] = acc
		m["far_n"] = n
		if far_stride > 1 and (n + int(m.slot)) % far_stride != 0:
			return
		m["far_acc"] = 0.0
		dt = acc
		var far_goal := _goal_for(p, m, ppos)
		var speed := float(people.get("pack", {}).get("travel_speed", 1.6))
		var to := far_goal - npc.global_position
		var step := to.normalized() * minf(speed * dt, to.length()) if to.length() > 0.5 else Vector3.ZERO
		var at := _on_ground(npc.global_position + step)
		npc.global_position = at
		npc.velocity = Vector3.ZERO
		if "controller" in npc and npc.controller != null:
			npc.controller.velocity = Vector3.ZERO
			npc.controller.body_pos = at
		return
	m["far_acc"] = 0.0
	var goal := _goal_for(p, m, ppos)
	if npc.process_mode == Node.PROCESS_MODE_DISABLED:
		npc.process_mode = Node.PROCESS_MODE_INHERIT
		if demo.terrain != null and ppos != Vector3.INF:
			demo.terrain.prefetch(npc.global_position)
	match str(p.state):
		"attack":
			_fight(p, m, dt, ppos)
		"greet", "truce":
			if m.slot == 0 and ppos != Vector3.INF:
				var to_p := ppos - npc.global_position
				npc.go_to(ppos - to_p.normalized() * 2.6, false)
				npc.face_point(ppos)
			else:
				npc.stop()
				if ppos != Vector3.INF:
					npc.face_point(ppos)
		_:
			npc.go_to(goal, false)
			npc.clear_face()


## Where a member walks: the leader along the route, the rest in rows behind it.
func _goal_for(p: Dictionary, m: Dictionary, _ppos: Vector3) -> Vector3:
	var route: Array = p.route
	var lead: NpcBody = alive(p)[0].npc
	if m.npc == lead:
		var target: Vector3 = route[int(p.route_i)]
		if lead.global_position.distance_to(target) < 4.0:
			p.route_i = (int(p.route_i) + 1) % route.size()
			target = route[int(p.route_i)]
		var up := up_at(lead.global_position)
		var h := target - lead.global_position
		h -= up * h.dot(up)
		if h.length() > 0.1:
			p.heading = h.normalized()
		return target
	var up2 := up_at(lead.global_position)
	var fwd: Vector3 = p.heading
	var right := fwd.cross(up2).normalized()
	var i := int(m.slot) - 1
	var row := i / 4 + 1
	var col := float(i % 4) - 1.5
	var sp := float(people.get("pack", {}).get("spacing", 2.6))
	return lead.global_position - fwd * float(row) * sp + right * col * sp


## Hostile: run at the player; hit within reach, throw from range.
func _fight(p: Dictionary, m: Dictionary, dt: float, ppos: Vector3) -> void:
	var npc: NpcBody = m.npc
	var w: Dictionary = m.weapon
	m.cd = maxf(0.0, float(m.cd) - dt)
	var d := npc.global_position.distance_to(ppos)
	npc.face_point(ppos)
	if bool(m.thrower) and d >= float(w.get("min_range", 5.0)) and d <= float(w.get("range", 16.0)):
		npc.stop()
		var chest := ppos + up_at(ppos) * 1.2
		npc.aim_point = chest
		if m.cd <= 0.0 and npc.fire_at(chest, dt):
			m.cd = float(w.get("cooldown_s", 3.2))
		return
	npc.aim_point = Vector3.INF
	var reach := float(w.get("reach", 2.0))
	if d <= reach:
		npc.stop()
		if m.cd <= 0.0:
			m.cd = float(w.get("cooldown_s", 1.1))
			if player != null and player.has_method("apply_damage_from"):
				player.apply_damage_from(float(w.get("damage", 8)), npc)
			elif player != null and player.has_method("apply_damage"):
				player.apply_damage(float(w.get("damage", 8)))
			hits += 1
		return
	npc.go_to(ppos, true)
	if _rng.randf() < dt * 0.15:
		_yell(npc)


var hits := 0                         ## melee blows that landed (traces)
var horns := 0


## A hostile pack sees you: the horn (only to start an attack), yells, and in.
func start_attack(p: Dictionary) -> void:
	if p.state == "attack":
		return
	p.state = "attack"
	p.attack_t = 0.0
	var lead := leader(p)
	if lead == null:
		return
	horns += 1
	_horn(lead)
	for m in alive(p):
		(m.npc as NpcBody).perception.awareness = 1.0
		(m.npc as NpcBody).perception.noticed = true
		(m.npc as NpcBody).hostile = true
	_yell(lead)
	_toast(_line("horn") % str(p.label))


func _stand_down(p: Dictionary) -> void:
	p.state = "travel"
	p.attack_t = 0.0
	for m in alive(p):
		(m.npc as NpcBody).hostile = false
		(m.npc as NpcBody).aim_point = Vector3.INF


## Five minutes and nobody of theirs dead: they lower their weapons, and trade.
func _win_over(p: Dictionary) -> void:
	p.rec.friendly = true
	p.rec.won = true
	p.state = "truce"
	for m in alive(p):
		(m.npc as NpcBody).hostile = false
		(m.npc as NpcBody).aim_point = Vector3.INF
		(m.npc as NpcBody).stop()
	var lead := leader(p)
	var g = people.get("voice", {}).get("gesture_truce", "")
	if lead != null and str(g) != "":
		lead.say(str(g), 4.0)
	_toast(_line("won") % str(p.label))
	pack_won.emit(str(p.id))


func _on_member_hit(shooter: Node, _amount: float, p: Dictionary) -> void:
	if shooter != player:
		return
	if bool(p.rec.friendly) and not bool(p.rec.get("won", false)):
		p.rec.friendly = false            # you started it
	elif bool(p.rec.get("won", false)):
		p.rec.friendly = false
		p.rec.won = false
	start_attack(p)


func _on_member_died(p: Dictionary, npc: NpcBody) -> void:
	if npc.last_hit_by != player:
		return
	p.rec.kills = int(p.rec.get("kills", 0)) + 1
	p.rec.friendly = false
	p.rec.won = false
	if not bool(p.rec.locked):
		p.rec.locked = true
		_toast(_line("locked") % str(p.label))
		pack_locked.emit(str(p.id))
	start_attack(p)


func _horn(at: Node3D) -> void:
	var path := str(people.get("hostile", {}).get("horn", ""))
	if path == "" or not ResourceLoader.exists(path):
		return
	var a := AudioStreamPlayer3D.new()
	a.stream = load(path)
	a.unit_size = 40.0
	a.max_distance = 600.0
	a.volume_db = -2.0
	at.add_child(a)
	a.play()
	a.finished.connect(a.queue_free)


func _yell(npc: NpcBody) -> void:
	var y := _voice("yells")
	if not y.is_empty():
		npc.say(str(y[_rng.randi() % y.size()]), 1.6, true)


# ------------------------------------------------------------------ trade

## The friendly pack whose leader is within reach of the player, or {}.
func trade_pack() -> Dictionary:
	var ppos := _player_pos()
	if ppos == Vector3.INF or bool(player.get("piloting")):
		return {}
	var reach := float(people.get("pack", {}).get("trade_reach", 4.5))
	for p in packs:
		if not bool(p.rec.friendly) or not (p.state in ["greet", "truce", "travel"]):
			continue
		var lead := leader(p)
		if lead != null and lead.global_position.distance_to(ppos) <= reach:
			return p
	return {}


## Gesture back at pack `id`: one food for its quartz. "traded", "no_food",
## "hostile" or "none".
func trade(id: String) -> String:
	var p := pack(id)
	if p.is_empty():
		return "none"
	if not bool(p.rec.friendly):
		return "hostile"
	var inv := WorldState.inventory
	var tcfg: Dictionary = people.get("trade", {})
	var wants: Array = tcfg.get("wants", ["food"])
	var food := ""
	for w in wants:
		if inv.has(str(w)):
			food = str(w)
	var lead := leader(p)
	if food == "":
		if lead != null:
			lead.say(str(people.get("voice", {}).get("gesture_no_food", "")), 3.5)
		return "no_food"
	inv.remove(food)
	var n := int(tcfg.get("per_food", 1)) + (int(tcfg.get("adults_only_bonus", 1)) if bool(p.adults_only) else 0)
	inv.add(str(tcfg.get("gives", "quartz")), n)
	p.rec.rep = int(p.rec.get("rep", 0)) + int(tcfg.get("reputation_per_trade", 1))
	p.rec.trades = int(p.rec.get("trades", 0)) + 1
	trades += 1
	if lead != null:
		lead.say(str(people.get("voice", {}).get("gesture_thanks", "")), 3.5)
	_toast(_line("traded") % [n, str(p.label), int(p.rec.rep)])
	WorldState.log_event("Traded food for quartz with the %s." % str(p.label))
	traded.emit(id, n)
	return "traded"


func _tick_prompts() -> void:
	if gear == null or gear.hud == null or player == null or bool(player.get("locked")):
		return
	var tp := trade_pack()
	if not tp.is_empty():
		var n := WorldState.inventory.count("food")
		gear.hud.set_prompt(_line("prompt_trade") % n if n > 0 else _line("prompt_no_food"))
		if _just_interact():
			trade(str(tp.id))
		return
	var pig := carcass_near()
	if pig != null:
		gear.hud.set_prompt(_line("butcher") % str(pig.cfg.get("label", "animal")))
		if _just_interact():
			butcher(pig)


func _just_interact() -> bool:
	return InputMap.has_action("interact") and Input.is_action_just_pressed("interact")


func _toast(text: String) -> void:
	if gear != null and gear.hud != null and text != "":
		gear.hud.toast(text, 4.5)


# ------------------------------------------------------------------ animals

## One animal of fauna entry state.f (state keeps the count and tries between
## calls). True when one was placed (call again for the next), false when done.
func _fauna_step(state: Dictionary) -> bool:
	var f: Dictionary = state.f
	if not state.has("cfg"):
		state.cfg = NativesData.fauna(str(f.get("species", "")))
		state.around = f.get("around", Vector2.ZERO)
		state.r = float(f.get("radius", 900.0))
		state.site = demo.desert_site().walls.grow(60.0) if demo.has_method("desert_site") else Rect2()
		state.placed = 0
		state.tries = 0
	var cfg: Dictionary = state.cfg
	if cfg.is_empty():
		return false
	var around: Vector2 = state.around
	var r: float = state.r
	var site: Rect2 = state.site
	while int(state.placed) < int(f.get("count", 4)) and int(state.tries) < 200:
		state.tries = int(state.tries) + 1
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(r * 0.3, r)
		var m := around + Vector2(cos(a), sin(a)) * d
		if site.has_area() and site.has_point(m):
			continue
		var pig := SandPig.new()
		pig.setup(cfg, ground, surface(m), 1000 + int(state.placed), demo._flat_mats() if demo.use_look else null)
		pig.target = player
		add_child(pig)
		pig.killed.connect(func(_p): WorldState.bump("animals_killed"))
		pigs.append(pig)
		state.placed = int(state.placed) + 1
		if int(state.placed) < int(f.get("count", 4)) and int(state.tries) < 200:
			_build_queue.push_front(func(): return _fauna_step(state))
		return true
	return false


func carcass_near(reach: float = 2.8) -> SandPig:
	var ppos := _player_pos()
	if ppos == Vector3.INF or bool(player.get("piloting")):
		return null
	for pig in pigs:
		if is_instance_valid(pig) and pig.dead and not pig.butchered and pig.global_position.distance_to(ppos) <= reach:
			return pig
	return null


## Cut food from a dead animal into the player's pockets. Returns how many.
func butcher(pig: SandPig) -> int:
	var got := pig.butcher()
	if got.is_empty():
		return 0
	WorldState.inventory.add(str(got.item), int(got.count))
	butchered += 1
	_toast(_line("butchered") % [int(got.count), str(pig.cfg.get("label", "animal"))])
	return int(got.count)
