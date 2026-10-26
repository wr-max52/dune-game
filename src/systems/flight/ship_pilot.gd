class_name ShipPilot
extends Node
## Your ship in the port (M14). The thin node over the pure AtmoFlight:
##   - the ship parked on the pit pad is the one you fly (it adopts the parked model
##     the decor built, so nothing on screen changes until you take off),
##   - E beside it boards; Space lifts off; W/S/A/D/Q/E and R/F fly it; Shift
##     boosts; C lands on whatever is below; E gets out once landed,
##   - a chase camera takes over the player's camera rig while seated,
##   - the sky darkens with altitude (AltitudeSky); the town's desert (DesertTerrain,
##     DesertLandforms) is the ground it flies over and lands on, plus the outpost
##     and the planet's curve beyond the sand (WorldScenery),
##   - while seated the desert's walkable collider stops following the player
##     (a ship at 300 m/s would rebuild it every frame); coming in to land it is
##     built under the ship in the background (DesertTerrain.prefetch), so getting
##     out finds ground there,
##   - crossing the edge of space hands off to the pad's space encounter
##     (GameFlow.ascend); coming back down (arrival "reentry") starts you in the sky
##     above the port, still flying,
##   - a crash tows the ship back to its pad and puts you beside it.
##
## The headless trace drives it with board(), takeoff(), land(), exit_ship() and
## set_external_command(): the same code paths the keys use.

const CoreContent := preload("res://src/systems/dataload/core_content.gd")
const ChaseCamera := preload("res://src/systems/camera/chase_camera.gd")
const TownDecor := preload("res://src/systems/world/town_decor.gd")
const SCENE_PATH := "res://scenes/town_demo.tscn"
const CRASH_TOW_TIME := 2.5

signal boarded
signal exited
signal left_atmosphere

var demo                         ## the town scene (town_demo.gd)
var content
var world: Dictionary = {}
var ground: WorldGround
var scenery: WorldScenery
var sky: AltitudeSky
var atmo: AtmoFlight
var ship_id := ""
var ship_cfg: Dictionary = {}
var pad: Dictionary = {}         ## the resolved home pad
var home := Vector3.ZERO
var home_yaw := 0.0
var visual: Node3D
var hud: FlightHud
var chase = ChaseCamera.new()
var piloting := false
var ascending := false
var crash_left := -1.0
var log_events: Array = []      ## every AtmoFlight event, for traces and tests
var flight_time := 0.0          ## seconds since liftoff (for "how long to space")
var space_time := -1.0

var _throttle := 0.0
var _stick := Vector2.ZERO
var _external: Dictionary = {}   ## a bot's command; empty = read the keys
var _pad_shape: CollisionShape3D
var _cam_near := 0.05
var _cam_far := 4000.0
var _rig_was_fp := false
var _boost := false
var _foot_prompt: Label          ## "[E] Board" while standing at the ship
var hull: StaticBody3D           ## the ship's own collision: solid while parked, off in flight
var vessel_name := ""            ## issue #15: the ship's own name (same key as in space)
var planet_name := ""


func setup(town_scene) -> void:
	demo = town_scene


func _ready() -> void:
	name = "ShipPilot"
	content = CoreContent.new()
	content.load_from()
	world = content.world_for_town("port_town")
	ground = WorldGround.new()
	var desert: DesertTerrain = demo.terrain
	if desert != null:
		ground.setup(world, demo.town, content, desert.height_at, desert.extent)
		# The mesas and hoodoos on screen are solid to the ship too.
		if demo.landforms != null:
			ground.add_landforms(demo.landforms.data, demo.desert_site().floor)
		scenery = WorldScenery.new()
		scenery.setup(ground)
		demo.add_child(scenery)
		if demo.use_look:
			scenery.build_visuals(demo._flat_mats(), desert.material)
	else:
		ground.setup(world, demo.town, content)
	if demo.use_look and demo.look != null:
		sky = AltitudeSky.new()
		sky.setup(demo.look, ground.atmosphere())
		demo.add_child(sky)
	var pads: Array = GameFlow.pads_for_scene(SCENE_PATH)
	pad = demo.resolve_pad(pads[0]) if not pads.is_empty() else {}
	var enc: Dictionary = content.get_encounter(str(pad.get("encounter", "")))
	ship_id = str(enc.get("player", {}).get("ship", "interceptor"))
	ship_cfg = content.get_ship(ship_id)
	atmo = AtmoFlight.new()
	atmo.setup(ship_cfg, ground)
	_find_pad_shape()
	_take_visual()
	_build_hull()
	atmo.park(home, home_yaw)
	_sync_visual()
	# The ship carries its own collision now; the pad's static box would stay
	# behind as an invisible wall when the ship leaves.
	if _pad_shape != null:
		_pad_shape.disabled = true
	hud = FlightHud.new()
	hud.space_label = GameFlow.label("space_edge")
	hud.space_altitude = atmo.space_altitude
	add_child(hud)
	var layer := CanvasLayer.new()
	layer.layer = 4
	add_child(layer)
	_foot_prompt = Label.new()
	_foot_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_foot_prompt.position = Vector2(-300, -170)
	_foot_prompt.size = Vector2(600, 28)
	_foot_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_foot_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_foot_prompt.add_theme_constant_override("outline_size", 4)
	vessel_name = NameHooks.vessel(ship_cfg, "vessel:player/" + ship_id)
	planet_name = NameHooks.planet(world)
	_foot_prompt.text = GameFlow.label("board") + ("  " + vessel_name if vessel_name != "" else "")
	hud.vessel_name = vessel_name
	_foot_prompt.visible = false
	layer.add_child(_foot_prompt)
	var look: Dictionary = ShipKit.new().looks.get(str(ship_cfg.get("look", "")), {})
	chase.fit_to(float(look.get("length", 9.0)))
	if str(demo._arrival.get("mode", "")) == "reentry":
		reenter()


## The parked model the decor built becomes the flying ship; in the greybox there
## is none, so a bare node stands in (the trace does not need to see it).
func _take_visual() -> void:
	var parked: Node3D = null
	if demo.decor != null and not demo.decor.parked_ships.is_empty():
		parked = demo.decor.parked_ships[0]
	var c: Vector3 = pad.get("center", Vector3.ZERO)
	home_yaw = deg_to_rad(float(pad.get("parked_yaw_deg", 0.0)))
	if parked != null:
		visual = parked
		home = parked.global_position
		home_yaw = parked.rotation.y
		var a := TownDecor.visual_aabb(parked)
		atmo.clearance = maxf(0.3, parked.global_position.y - a.position.y)
	else:
		visual = Node3D.new()
		visual.name = "ShipStandIn"
		demo.add_child(visual)
		home = c
	home.y = c.y if parked == null else home.y


## A box around the ship, in the ship's own frame, that travels with it: you can
## walk up to (not through) a parked ship wherever it landed. Sized from the model,
## or from the pad's box in the greybox.
func _build_hull() -> void:
	var size := Vector3(9.0, 2.5, 8.0)
	var center := Vector3.ZERO
	var acc := [null]
	TownDecor._merge_aabb(visual, Transform3D.IDENTITY, acc)
	if acc[0] != null:
		var a: AABB = acc[0]
		size = a.size
		center = a.get_center()
	else:
		var box: Dictionary = demo.town.get_box(str(pad.get("town_box", "ship")))
		if not box.is_empty():
			var w := WorldGround._v3(box.max) - WorldGround._v3(box.min)
			var c := absf(cos(home_yaw))
			var sn := absf(sin(home_yaw))
			size = Vector3(c * w.x + sn * w.z, w.y, sn * w.x + c * w.z)
			center = Vector3(0, w.y * 0.5 - atmo.clearance, 0)
	hull = StaticBody3D.new()
	hull.name = "ShipHull"
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = center
	hull.add_child(cs)
	visual.add_child(hull)


func _set_hull(solid: bool) -> void:
	if hull != null:
		for ch in hull.get_children():
			if ch is CollisionShape3D:
				ch.set_deferred("disabled", not solid)


func _find_pad_shape() -> void:
	var body: Node = demo.get_node_or_null("Town/" + str(pad.get("town_box", "ship")))
	if body == null:
		return
	for ch in body.get_children():
		if ch is CollisionShape3D:
			_pad_shape = ch


# ------------------------------------------------------------------ queries

func player() -> CharacterBody3D:
	return demo._player


func is_parked_home() -> bool:
	return atmo.state == AtmoFlight.State.PARKED and Vector2(atmo.position().x - home.x, atmo.position().z - home.z).length() < 3.0


## On foot, close enough to the parked ship to climb in.
func can_board() -> bool:
	var p := player()
	if piloting or p == null or atmo.state != AtmoFlight.State.PARKED:
		return false
	var s := atmo.position()
	var reach := float(pad.get("board_reach", 9.0))
	return Vector2(p.global_position.x - s.x, p.global_position.z - s.z).length() <= reach \
		and absf(p.global_position.y - (s.y - atmo.clearance)) <= 4.0


# ------------------------------------------------------------------ actions

func board() -> bool:
	if not can_board():
		return false
	var p := player()
	piloting = true
	_foot_prompt.visible = false
	p.piloting = true
	p.locked = true
	p.velocity = Vector3.ZERO
	p.visible = false
	p.process_mode = Node.PROCESS_MODE_DISABLED
	_set_player_collision(false)
	_ground_follow(null)
	_throttle = 0.0
	_stick = Vector2.ZERO
	var rig = demo._rig
	if rig != null:
		_rig_was_fp = rig.rig.is_first_person()
		var cam: Camera3D = rig.camera()
		_cam_near = cam.near
		_cam_far = cam.far
		cam.near = 0.3
		cam.far = 160000.0
	chase._primed = false
	hud.visible = true
	boarded.emit()
	return true


func exit_ship() -> bool:
	if not piloting or atmo.state != AtmoFlight.State.PARKED:
		return false
	var p := player()
	var spot := _exit_spot()
	piloting = false
	p.piloting = false
	p.locked = false
	p.process_mode = Node.PROCESS_MODE_INHERIT
	p.visible = true
	_set_player_collision(true)
	p.global_position = spot
	p.velocity = Vector3.ZERO
	p.controller.velocity = Vector3.ZERO
	p.controller.body_pos = spot
	_ground_follow(p)
	var rig = demo._rig
	if rig != null:
		rig.clear_override()
		rig.rig.yaw = atmo.flight.basis.get_euler().y
		rig.set_first_person(_rig_was_fp)
		var cam: Camera3D = rig.camera()
		cam.near = _cam_near
		cam.far = _cam_far
	hud.visible = false
	if sky != null:
		sky.update_for(0.0, spot)
	exited.emit()
	return true


func takeoff() -> bool:
	if not piloting or not atmo.takeoff():
		return false
	_set_hull(false)
	flight_time = 0.0
	return true


func land() -> bool:
	return piloting and atmo.land()


## A bot's command for this frame and on: { pitch, yaw, roll, throttle, boost }.
## Pass {} to give control back to the keys.
func set_external_command(c: Dictionary) -> void:
	_external = c


## Back from space: start in the sky above the port, flying toward it.
func reenter() -> void:
	var p := player()
	if p != null and not piloting:
		# Seat the player without the reach check: they arrive in the cockpit.
		piloting = true
		p.piloting = true
		_ground_follow(null)
		p.locked = true
		p.visible = false
		p.process_mode = Node.PROCESS_MODE_DISABLED
		_set_player_collision(false)
		var rig = demo._rig
		if rig != null:
			_rig_was_fp = rig.rig.is_first_person()
			var cam: Camera3D = rig.camera()
			_cam_near = cam.near
			_cam_far = cam.far
			cam.near = 0.3
			cam.far = 160000.0
	var c: Vector3 = pad.get("center", Vector3.ZERO)
	var bearing := deg_to_rad(float(pad.get("reentry_bearing_deg", 200.0)))
	var dist := float(pad.get("reentry_distance", 6500.0))
	var alt := float(pad.get("reentry_altitude", 5200.0))
	var at := Vector3(c.x + sin(bearing) * dist, alt, c.z + cos(bearing) * dist)
	var to := Vector3(c.x - at.x, 0.0, c.z - at.z).normalized()
	var pitch := deg_to_rad(float(pad.get("reentry_pitch_deg", -18.0)))
	var facing := (to * cos(pitch) + Vector3(0, sin(pitch), 0)).normalized()
	atmo.place_flying(at, facing, 0.0, 0.6)
	atmo.flight.speed = atmo.flight.cruise_speed(0.6) * atmo.air_scale()
	_throttle = 0.6
	_set_hull(false)
	chase._primed = false
	hud.visible = true
	hud.toast(GameFlow.arrival_text(demo._arrival), 5.0)
	_sync_visual()


# ------------------------------------------------------------------ frame

func _unhandled_input(event: InputEvent) -> void:
	if not piloting:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_stick.x = clampf(_stick.x + event.relative.x * 0.004, -1.0, 1.0)
		_stick.y = clampf(_stick.y - event.relative.y * 0.004, -1.0, 1.0)
	if InputMap.has_action("toggle_view") and event.is_action_pressed("toggle_view"):
		chase.toggle_mode()


func _physics_process(dt: float) -> void:
	if atmo == null:
		return
	if not piloting:
		_on_foot()
	else:
		_seated(dt)
	if crash_left >= 0.0:
		crash_left -= dt
		if crash_left < 0.0:
			_tow_home()


func _on_foot() -> void:
	var p := player()
	if p == null:
		return
	if sky != null:
		sky.update_for(ground.altitude(p.global_position), p.global_position)
	var near: bool = can_board() and not p.locked
	_foot_prompt.visible = near
	if near and _just("interact"):
		board()


func _seated(dt: float) -> void:
	var st := atmo.state
	if _external.is_empty():
		_read_keys(dt)
		# E just got you out: stop here, or the rest of this frame puts the chase
		# camera override back on and snaps you into the ship again.
		if not piloting:
			return
	else:
		_throttle = float(_external.get("throttle", _throttle))
		_boost = bool(_external.get("boost", false))
		atmo.set_command(float(_external.get("pitch", 0.0)), float(_external.get("yaw", 0.0)),
			float(_external.get("roll", 0.0)), _throttle, _boost)
	if st == AtmoFlight.State.LIFTOFF or st == AtmoFlight.State.FLYING or st == AtmoFlight.State.LANDING:
		flight_time += dt
	for e in atmo.step(dt):
		_on_event(e)
	_sync_visual()
	var s := atmo.position()
	player().global_position = s
	if demo.terrain != null and atmo.state != AtmoFlight.State.CRASHED \
			and (atmo.state == AtmoFlight.State.LANDING or atmo.agl() < 60.0):
		demo.terrain.prefetch(s)           # ground to step out onto, built in the background
	if sky != null:
		sky.update_for(atmo.altitude(), s)
	if demo._rig != null:
		demo._rig.set_override(chase.update(dt, atmo.transform()), 72.0)
	_update_hud()


func _read_keys(dt: float) -> void:
	var st := atmo.state
	if st == AtmoFlight.State.PARKED:
		if _just("interact"):
			exit_ship()
			return
		if _just("jump") or _axis("flight_throttle_down", "flight_throttle_up") > 0.5:
			takeoff()
		return
	if st == AtmoFlight.State.FLYING and _just("crouch_act"):
		land()
	_throttle = clampf(_throttle + _axis("flight_throttle_down", "flight_throttle_up") * dt * 0.6, 0.0, 1.0)
	var pitch := clampf(_axis("flight_pitch_down", "flight_pitch_up") + _stick.y, -1.0, 1.0)
	var yaw := clampf(_axis("flight_yaw_left", "flight_yaw_right") + _stick.x, -1.0, 1.0)
	var roll := _axis("flight_roll_left", "flight_roll_right")
	_stick = _stick.lerp(Vector2.ZERO, minf(1.0, dt * 3.0))
	_boost = _held("flight_boost")
	atmo.set_command(pitch, yaw, roll, _throttle, _boost)


func _on_event(e: Dictionary) -> void:
	e["t"] = flight_time
	log_events.append(e)
	match str(e.type):
		"airborne":
			hud.toast(GameFlow.label("airborne"), 6.0)
		"landing":
			hud.toast(GameFlow.label("landing"), 2.0)
		"landed":
			hud.toast(GameFlow.label("landed"), 4.0)
			_set_hull(true)
		"crashed":
			hud.toast(GameFlow.label("crashed"), 3.0)
			crash_left = CRASH_TOW_TIME
			if demo.terrain != null:
				demo.terrain.prefetch(home) # ground at the pad, ready before the tow
			if visual != null:
				visual.visible = false
			_crash_fx(e.at)
		"reached_space":
			space_time = flight_time
			_leave_atmosphere()


func _leave_atmosphere() -> void:
	if ascending:
		return
	ascending = true
	hud.toast(GameFlow.label("leaving_planet") % planet_name if planet_name != "" else GameFlow.label("leaving_atmosphere"), 3.0)
	left_atmosphere.emit()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not is_inside_tree():
		GameFlow.ascend(null, pad)
		return
	var tw := create_tween()
	tw.tween_method(hud.set_fade, 0.0, 1.0, float(GameFlow.setting("fade_time", 0.6)))
	tw.tween_callback(func(): GameFlow.ascend(get_tree(), pad))


func _tow_home() -> void:
	if visual != null:
		visual.visible = true
	atmo.reached_space = false
	atmo.park(home, home_yaw)
	_set_hull(true)
	_sync_visual()
	if piloting:
		exit_ship()
	hud.toast(GameFlow.label("towed"), 4.0)
	if demo.pads.size() > 0:
		demo.pads[0].toast(GameFlow.label("towed"), 4.0)


func _sync_visual() -> void:
	if visual != null and is_instance_valid(visual):
		visual.global_transform = atmo.transform()


func _update_hud() -> void:
	var f = atmo.flight
	var v: Vector3 = f.velocity()
	hud.show_values({
		"speed": f.speed, "throttle": _throttle,
		"boost": f.boost_left / maxf(f.boost_time(), 0.001),
		"agl": atmo.agl(), "altitude": atmo.altitude(), "climb": v.y,
		"space_fraction": atmo.space_fraction(), "state": atmo.state_label(),
	})
	var tip := ""
	match atmo.state:
		AtmoFlight.State.PARKED:
			tip = GameFlow.label("seated")
		AtmoFlight.State.FLYING:
			tip = GameFlow.label("can_land") if atmo.can_land() else ""
		AtmoFlight.State.LANDING:
			tip = GameFlow.label("landing")
	hud.set_prompt(tip)


# ------------------------------------------------------------------ helpers

## Beside the ship (left, then right, then behind), on whatever ground is there.
func _exit_spot() -> Vector3:
	var b: Basis = atmo.flight.basis
	var s := atmo.position()
	var side := 5.5
	for off in [-b.x * side, b.x * side, b.z * (side + 3.0), -b.z * (side + 3.0)]:
		var q: Vector3 = s + Vector3(off.x, 0.0, off.z)
		var g := ground.ground_at(q.x, q.z, s.y)
		var at := Vector3(q.x, g + 0.05, q.z)
		if ground.hit(at + Vector3(0, 1.0, 0), 0.6) == "":
			return at
	return Vector3(s.x, ground.ground_at(s.x, s.z, s.y + 5.0) + 0.05, s.z)


func _set_player_collision(on: bool) -> void:
	var p := player()
	for ch in p.get_children():
		if ch is CollisionShape3D:
			ch.set_deferred("disabled", not on)


func _crash_fx(at: Vector3) -> void:
	for spec in [[9.0, 1.2, Color("#ff9a4a")], [4.5, 0.6, Color("#fff4dc")]]:
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
		demo.add_child(mi)
		mi.global_position = at
		mi.scale = Vector3.ONE * float(spec[0]) * 0.3
		var tw := mi.create_tween()
		tw.set_parallel(true)
		tw.tween_property(mi, "scale", Vector3.ONE * float(spec[0]), float(spec[1]))
		tw.tween_property(m, "albedo_color:a", 0.0, float(spec[1]))
		tw.chain().tween_callback(mi.queue_free)


func _just(action: String) -> bool:
	return InputMap.has_action(action) and Input.is_action_just_pressed(action)


func _held(action: String) -> bool:
	return InputMap.has_action(action) and Input.is_action_pressed(action)


func _axis(neg: String, pos: String) -> float:
	if not InputMap.has_action(neg) or not InputMap.has_action(pos):
		return 0.0
	return Input.get_axis(neg, pos)


## The desert's walkable collider follows whoever is on foot: null while seated,
## the player again once out (it snaps under them if a prefetch has not got there).
func _ground_follow(who: Node3D) -> void:
	if demo.terrain != null:
		demo.terrain.follow(who)
