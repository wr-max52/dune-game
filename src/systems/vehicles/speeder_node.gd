class_name SpeederNode
extends Node3D
## A speeder in the world (issue #42): the look, the hull bolts can hit, riding it,
## and its twin lasers. HoverModel decides how it moves; this node reads the keys
## (or a bot's command), draws it and drives the camera.
##
##   E beside it   -- ride (E again to get off; you step off to the left)
##   W / S         -- throttle / brake and reverse
##   A / D         -- steer
##   Shift         -- boost
##   Space or LMB  -- both lasers at once   V -- chase / close camera
##
## `rideable = false` is the one on Skrugs's display pad: it just sits there.
## Bolts hit the hull (a StaticBody child; bolts call apply_damage on its parent):
## at 0 hull it bursts and is gone, and anyone riding is thrown clear. Nothing
## else hurts it.

const ChaseCamera := preload("res://src/systems/camera/chase_camera.gd")
const WeaponActor := preload("res://src/systems/combat/weapon_actor.gd")
const Weapon := preload("res://src/systems/combat/weapon.gd")

signal mounted
signal dismounted
signal destroyed(at: Vector3)

var demo                              ## town_demo.gd (player, rig, terrain)
var model: HoverModel
var cfg: Dictionary = {}
var rideable := true
var riding := false
var hull: StaticBody3D
var visual: Node3D
var chase = ChaseCamera.new()
var gun: WeaponActor
var shots := 0
var log_events: Array = []            ## every HoverModel event, for traces and tests

var _external: Dictionary = {}        ## a bot's command; empty = read the keys
var _hud: CanvasLayer
var _readout: Label
var _prompt: Label
var _fan: Node3D
var _glow_mat: StandardMaterial3D
var _t := 0.0


func setup(town_demo, ground: WorldGround, config: Dictionary = {}, can_ride: bool = true) -> void:
	demo = town_demo
	cfg = config if not config.is_empty() else HoverModel.load_config("speeder")
	rideable = can_ride
	model = HoverModel.new(cfg, ground)
	name = "Speeder" if can_ride else "DisplaySpeeder"


func _ready() -> void:
	_build_visual()
	_build_hull()
	if rideable:
		gun = WeaponActor.new()
		var laser: Dictionary = cfg.get("laser", {})
		gun.set_weapon(laser)
		gun.bolt_parent = demo if demo is Node3D else get_parent()
		var color := Color(str(laser.get("color", "#7fe0d0")))
		gun.configure_bolt = func(b):
			b.shooter = hull
			b.stylize = true
			b.sweep = true
			b.color = color
		chase.fit_to(float(cfg.get("look", {}).get("length", 4.6)))
		chase.chase_back = 9.0
		chase.chase_up = 3.2
		chase.look_ahead = 30.0
		_build_hud()
	_sync()


## Set it down at `at` facing `yaw` (on whatever ground is there).
func place(at: Vector3, yaw: float) -> void:
	model.place(at, yaw)
	_sync()


# ------------------------------------------------------------------ riding

func player() -> CharacterBody3D:
	return demo._player if demo != null else null


func can_mount() -> bool:
	var p := player()
	if not rideable or riding or p == null or p.locked or p.piloting or not model.alive():
		return false
	var d := Vector2(p.global_position.x - model.position.x, p.global_position.z - model.position.z).length()
	return d <= float(cfg.get("board_reach", 3.2)) and absf(p.global_position.y - (model.position.y - 1.0)) < 2.5


func mount() -> bool:
	if not can_mount():
		return false
	var p := player()
	riding = true
	p.piloting = true
	p.locked = true
	p.velocity = Vector3.ZERO
	p.visible = false
	p.process_mode = Node.PROCESS_MODE_DISABLED
	_player_collision(false)
	if demo.terrain != null:
		demo.terrain.follow(null)
	chase._primed = false
	_external = {}
	if _hud != null:
		_hud.visible = true
	mounted.emit()
	return true


## Get off, beside it (left, then right, then behind).
func dismount() -> bool:
	if not riding:
		return false
	var p := player()
	riding = false
	model.set_command(0.0, 0.0)
	var spot := _exit_spot()
	p.piloting = false
	p.locked = false
	p.process_mode = Node.PROCESS_MODE_INHERIT
	p.visible = true
	_player_collision(true)
	p.global_position = spot
	p.velocity = Vector3.ZERO
	p.controller.velocity = Vector3.ZERO
	p.controller.body_pos = spot
	if demo.terrain != null:
		demo.terrain.follow(p)
	var rig = demo._rig
	if rig != null:
		rig.clear_override()
		rig.rig.yaw = model.yaw
	if _hud != null:
		_hud.visible = false
	dismounted.emit()
	return true


## A bot's command for this frame and on: { throttle, steer, boost, fire }.
## Pass {} to give control back to the keys.
func set_external_command(c: Dictionary) -> void:
	_external = c


## Bolts land here (the hull's parent). Riding or parked, the hull takes it.
func apply_damage(amount: float) -> void:
	var killed := model.apply_damage(amount)
	for e in model.events:
		log_events.append(e)
	if killed:
		_burst()


# ------------------------------------------------------------------ frame

func _physics_process(dt: float) -> void:
	if model == null or not model.alive():
		return
	_t += dt
	if riding:
		_ride(dt)
	elif rideable:
		model.set_command(0.0, 0.0)
		for e in model.step(dt):
			log_events.append(e)
		_sync()
		_show_prompt(can_mount())
		if can_mount() and _just("interact"):
			mount()


func _ride(dt: float) -> void:
	var fire := false
	if _external.is_empty():
		if _just("interact") and not model.airborne:
			dismount()
			return
		var throttle := _axis("move_back", "move_forward")
		var steer := _axis("move_left", "move_right")
		model.set_command(throttle, steer, _held("sprint_mod") or _held("flight_boost"))
		fire = _held("jump") or _held("fire") or _held("flight_fire")
	else:
		model.set_command(float(_external.get("throttle", 0.0)), float(_external.get("steer", 0.0)),
			bool(_external.get("boost", false)))
		fire = bool(_external.get("fire", false))
	for e in model.step(dt):
		log_events.append(e)
	_fire(dt, fire)
	_sync()
	var p := player()
	p.global_position = model.position
	if demo.terrain != null and model.height_over_ground() < 30.0:
		demo.terrain.prefetch(model.position)      # ground to step off onto, built in the background
	if demo._rig != null:
		demo._rig.set_override(chase.update(dt, model.transform().translated_local(Vector3(0, 0.6, 0))), 75.0)
	if demo.detail != null:
		demo.detail.update_for(model.position.y)
	_update_hud()


func _fire(dt: float, trigger: bool) -> void:
	if gun == null:
		return
	# The weapon keeps the rate and the ammo; one trigger pull fires both barrels
	# together, left and right.
	if gun.weapon.start_firing(dt, trigger) == Weapon.Result.SHOT:
		var b := model.transform().basis
		for side in [-0.55, 0.55]:
			var origin := model.position + b * Vector3(side, 0.25, -2.4)
			gun._make_bolt(model.forward(), origin, float(gun.weapon.config.get("damage", 18.0)),
				float(gun.weapon.config.get("bolt_speed", 90.0)))
			gun.shots_fired += 1
		shots += 1


func _sync() -> void:
	global_transform = model.transform()
	if visual != null:
		# Lean into turns and pitch with the climb, for the eye only.
		var lean := clampf(model.speed / 40.0, -1.0, 1.0) * (_axis("move_left", "move_right") if riding and _external.is_empty() else float(_external.get("steer", 0.0)))
		visual.rotation.z = lerpf(visual.rotation.z, -lean * 0.25, 0.15)
		visual.rotation.x = lerpf(visual.rotation.x, clampf(model.vy / 30.0, -0.35, 0.35), 0.2)
		visual.position.y = 0.04 * sin(_t * 3.0)
	if _fan != null:
		_fan.rotation.z += 0.3 + absf(model.speed) * 0.02
	if _glow_mat != null:
		_glow_mat.emission_energy_multiplier = 1.5 + absf(model.speed) / 10.0


# ------------------------------------------------------------------ helpers

func _exit_spot() -> Vector3:
	var b := model.transform().basis
	var g := model.ground
	for off in [-b.x * 2.6, b.x * 2.6, b.z * 4.0]:
		var q: Vector3 = model.position + Vector3(off.x, 0.0, off.z)
		var gy := g.ground_at(q.x, q.z, model.position.y) if g != null else 0.0
		var at := Vector3(q.x, gy + 0.05, q.z)
		if g == null or g.hit(at + Vector3(0, 1.0, 0), 0.6) == "":
			return at
	return model.position + Vector3(0, 0.5, 0)


func _player_collision(on: bool) -> void:
	for ch in player().get_children():
		if ch is CollisionShape3D:
			ch.set_deferred("disabled", not on)


func _burst() -> void:
	var at := model.position
	if riding:
		dismount()
	for spec in [[7.0, 1.0, Color("#ff9a4a")], [3.5, 0.5, Color("#fff4dc")]]:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		mi.mesh = sm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = spec[2]
		mi.material_override = m
		get_parent().add_child(mi)
		mi.global_position = at
		mi.scale = Vector3.ONE * float(spec[0]) * 0.3
		var tw := mi.create_tween()
		tw.set_parallel(true)
		tw.tween_property(mi, "scale", Vector3.ONE * float(spec[0]), float(spec[1]))
		tw.tween_property(m, "albedo_color:a", 0.0, float(spec[1]))
		tw.chain().tween_callback(mi.queue_free)
	destroyed.emit(at)
	queue_free()


func _just(action: String) -> bool:
	return InputMap.has_action(action) and Input.is_action_just_pressed(action)


func _held(action: String) -> bool:
	return InputMap.has_action(action) and Input.is_action_pressed(action)


func _axis(neg: String, pos: String) -> float:
	if not InputMap.has_action(neg) or not InputMap.has_action(pos):
		return 0.0
	return Input.get_axis(neg, pos)


# ------------------------------------------------------------------ look

## An original hover sled (docs/ART_DIRECTION.md: big readable shapes, sand and
## madder red, no franchise silhouettes): a low open tub on two long outrigger
## skids, a ducted fan at the back, a teal glow under the skids.
func _build_visual() -> void:
	var look: Dictionary = cfg.get("look", {})
	# The town's materials: a new LookMaterials builds its own textures, a 60 ms
	# hitch at the moment you buy one.
	var mats: LookMaterials = demo._flat_mats() if demo != null and demo.has_method("_flat_mats") else LookMaterials.new()
	var hullm := mats.flat(Color(str(look.get("hull", "#c9a46a"))), 0.6)
	var trim := mats.flat(Color(str(look.get("trim", "#8e3a26"))), 0.7)
	var metal := mats.flat(Color(str(look.get("metal", "#4a4c52"))), 0.4, 0.6)
	var seat := mats.flat(Color(str(look.get("seat", "#3a2a20"))), 0.9)
	_glow_mat = StandardMaterial3D.new()
	var gc := Color(str(look.get("glow", "#7fe0d0")))
	_glow_mat.albedo_color = gc
	_glow_mat.emission_enabled = true
	_glow_mat.emission = gc
	_glow_mat.emission_energy_multiplier = 2.0
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	visual = Node3D.new()
	visual.name = "Look"
	add_child(visual)
	if _build_model(str(look.get("scene", "")), float(look.get("base_y", -0.65))):
		return
	# The tub: a low wedge-ended body, the rider sits in it.
	_part(_box(Vector3(1.5, 0.5, 3.0)), hullm, Vector3(0, -0.15, 0.1))
	_part(_box(Vector3(1.2, 0.35, 1.0)), hullm, Vector3(0, -0.05, -1.75), Vector3(-18, 0, 0))
	_part(_box(Vector3(1.56, 0.1, 3.06)), trim, Vector3(0, 0.12, 0.1))
	_part(_box(Vector3(0.7, 0.3, 0.8)), seat, Vector3(0, 0.15, 0.6))
	_part(_box(Vector3(0.9, 0.5, 0.12)), metal, Vector3(0, 0.3, -0.55), Vector3(-25, 0, 0))
	# Two outrigger skids on struts, with the hover glow under them.
	for side in [-1.0, 1.0]:
		_part(_cyl(0.16, 0.16, 4.4), trim, Vector3(side * 1.25, -0.45, -0.1), Vector3(90, 0, 0))
		_part(_cyl(0.05, 0.05, 0.6), metal, Vector3(side * 1.0, -0.3, -1.0), Vector3(0, 0, side * 50))
		_part(_cyl(0.05, 0.05, 0.6), metal, Vector3(side * 1.0, -0.3, 0.9), Vector3(0, 0, side * 50))
		_part(_box(Vector3(0.24, 0.04, 3.8)), _glow_mat, Vector3(side * 1.25, -0.63, -0.1))
		# Twin lasers along the skids' noses.
		_part(_cyl(0.05, 0.05, 0.9), metal, Vector3(side * 0.55, 0.15, -2.15), Vector3(90, 0, 0))
	# The rear ducted fan.
	var duct := _part(_cyl(0.6, 0.6, 0.35), metal, Vector3(0, 0.15, 1.85), Vector3(90, 0, 0))
	duct.name = "Duct"
	_fan = Node3D.new()
	_fan.position = Vector3(0, 0.15, 1.85)
	visual.add_child(_fan)
	for k in 3:
		var blade := MeshInstance3D.new()
		blade.mesh = _box(Vector3(0.12, 1.0, 0.04))
		blade.material_override = trim
		blade.rotation.z = k * PI / 3.0
		_fan.add_child(blade)


## Issue #43: the Hyper3D speeder (the look's "scene", prepped by
## tools/look/prep_vehicle.gd: facing -Z, metres, centred). Its underside sits at
## `base_y` (where the stand-in's skids are), with the hover glow under it. False
## when there is no model, so the stand-in is built instead.
func _build_model(path: String, base_y: float) -> bool:
	if path == "" or not ResourceLoader.exists(path):
		return false
	var res = load(path)
	var inst = (res as PackedScene).instantiate() if res is PackedScene else null
	if not (inst is Node3D):
		if inst != null:
			inst.free()
		return false
	var m := inst as Node3D
	m.name = "Model"
	visual.add_child(m)
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = _local_xf(mi, m) * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	m.position = Vector3(-box.get_center().x, base_y - box.position.y, -box.get_center().z)
	for side in [-1.0, 1.0]:
		_part(_box(Vector3(0.24, 0.04, box.size.z * 0.75)), _glow_mat, Vector3(side * box.size.x * 0.32, base_y - 0.02, 0))
	return true


static func _local_xf(n: Node3D, top: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var p: Node = n
	while p != null and p != top:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return top.transform * xf


func _part(mesh: Mesh, mat: Material, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	visual.add_child(mi)
	return mi


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _cyl(top: float, bottom: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = 12
	return c


## The hull: what bolts hit (and what you bump into on foot). Its parent (this
## node) takes the damage.
func _build_hull() -> void:
	hull = StaticBody3D.new()
	hull.name = "Hull"
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.0, 1.0, 4.6)
	cs.shape = shape
	cs.position = Vector3(0, -0.2, 0)
	hull.add_child(cs)
	add_child(hull)


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 5
	_hud.visible = false
	add_child(_hud)
	_readout = Label.new()
	_readout.position = Vector2(18, 54)
	_readout.add_theme_font_size_override("font_size", 18)
	_readout.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_readout.add_theme_constant_override("outline_size", 4)
	_hud.add_child(_readout)
	var help := Label.new()
	help.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	help.position = Vector2(-420, -100)
	help.size = Vector2(840, 28)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.text = "[W/S] Throttle   [A/D] Steer   [Shift] Boost   [Space / LMB] Lasers   [E] Get off"
	help.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	help.add_theme_constant_override("outline_size", 4)
	_hud.add_child(help)
	var layer := CanvasLayer.new()
	layer.layer = 4
	add_child(layer)
	_prompt = Label.new()
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.position = Vector2(-300, -170)
	_prompt.size = Vector2(600, 28)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.text = "[E]  Ride speeder"
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_prompt.add_theme_constant_override("outline_size", 4)
	_prompt.visible = false
	RetroUI.prompt(_prompt)
	layer.add_child(_prompt)


func _show_prompt(on: bool) -> void:
	if _prompt != null:
		_prompt.visible = on


func _update_hud() -> void:
	if _readout == null:
		return
	_readout.text = "SPEEDER\nSPEED  %3d m/s   %3d km/h\nHULL   %3d / %d\nBOOST  %3d%%%s" % [
		int(absf(model.speed)), int(absf(model.speed) * 3.6), model.hp, model.max_hp,
		int(model.boost_left / maxf(model.p("boost_time", 3.5), 0.001) * 100.0),
		"\nAIRBORNE" if model.airborne else ""]
