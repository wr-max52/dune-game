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
##   - issue #46: crossing the edge of space keeps you in this scene, over the same
##     ground. With GameFlow.space_dogfight() on, the pad's encounter starts right
##     there (SpaceFight) and flies your ship until it is won, lost, or you dive
##     `space_exit_margin` back below the edge; then normal flight takes over where
##     the fight left you. A lost fighter is towed home like a crash. Climbing out
##     again starts another sortie.
##   - (an arrival "reentry" from the stand-alone flight scene still starts you in
##     the sky above the port, still flying),
##   - a crash tows the ship back to its pad and puts you beside it,
##   - issue #55: the ship's guns fire from the moment you sit down (LMB / Space),
##     in the air as in space; the hull (and shield) from its data takes bolts
##     wherever it is, and the garrison shoots it once it lifts off inside town.
##     A hull shot to nothing goes down like a crash and is towed home.
##   - issue #43: every ship parked in the pit is flyable. Each is a berth (its ship
##     data, model, hull and home bay); E beside any parked one boards it, and that
##     ship's own stats, guns and Shift ability fly from then on. The one you left
##     stays where you landed it.
##
## The headless trace drives it with board(), takeoff(), land(), exit_ship() and
## set_external_command(): the same code paths the keys use.

const CoreContent := preload("res://src/systems/dataload/core_content.gd")
const ChaseCamera := preload("res://src/systems/camera/chase_camera.gd")
const ShipDefense := preload("res://src/systems/flight/ship_defense.gd")
const ShipLoadout := preload("res://src/systems/flight/ship_loadout.gd")
const BoltScene := preload("res://scenes/entities/bolt.tscn")
const TownDecor := preload("res://src/systems/world/town_decor.gd")
const SCENE_PATH := "res://scenes/town_demo.tscn"
const CRASH_TOW_TIME := 2.5

signal boarded
signal exited
signal left_atmosphere
signal fight_started
signal fight_ended(outcome: String)

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
var berths: Array = []           ## issue #43: { ship_id, cfg, visual, hull, home, home_yaw, clearance } per parked ship
var berth := 0                   ## the berth you fly (or last flew)
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
var _cam_near := 0.05
var _cam_far := 4000.0
var _rig_was_fp := false
var _boost := false
var _motion_basis := Basis.IDENTITY
var _motion_basis_valid := false
var _foot_prompt: Label          ## "[E] Board" while standing at the ship
var jolt := BoardJolt.new(1.6, 1.4)   ## issue #87: the ship settles and lifts on its gear as you board
var _jolt_xf := Transform3D.IDENTITY
var hull: ShipHull               ## the ship's own collision: solid parked and flying (bolts hit it)
var defense                      ## issue #55: ShipDefense, the flown ship's shield and hull
var guns                         ## issue #55: ShipLoadout, its guns in the air
var shots := 0                   ## bolts the guns fired in the air (traces, tests)
var vessel_name := ""            ## issue #15: the ship's own name (same key as in space)
var planet_name := ""
var fight: SpaceFight            ## issue #46: the space encounter in progress, or null
var kit: ShipKit                 ## built once at load (on the town's materials) for every fight
var fight_log: Array = []        ## { outcome, payout, at } per sortie, for traces and tests
var space_exit_margin := 250.0   ## metres below the edge that break off a running fight
var travel: SpaceTravel          ## issue #45: the other planets in this sky, and flying to them
var _engine: AudioStreamPlayer   ## issue #16: the engine drone while the ship flies
var bay_landing := false          ## issue #75: Z near the bay: she is flying herself in
var bay_landings := 0             ## times that brought her down (traces, tests)


func setup(town_scene) -> void:
	demo = town_scene


func _ready() -> void:
	name = "ShipPilot"
	_engine = Sound.loop("ship_engine", self)
	content = CoreContent.new()
	content.load_from()
	world = demo.world if "world" in demo and not demo.world.is_empty() else content.world_for_town("port_town")
	ground = WorldGround.new()
	var desert: DesertTerrain = demo.terrain
	if desert != null:
		ground.setup(world, demo.town, content, desert.height_at, desert.extent)
		# The mesas and hoodoos on screen are solid to the ship too.
		if demo.landforms != null:
			ground.add_landforms(demo.landforms.data, demo.desert_site().floor)
			ground.add_boulders(demo.landforms.boulders)      # issue #93: solid rocks, speeder ramps
		scenery = WorldScenery.new()
		scenery.setup(ground)
		demo.add_child(scenery)
		if demo.use_look:
			scenery.build_visuals(demo._flat_mats(), desert.material)
	else:
		ground.setup(world, demo.town, content)
	# Issue #45: a platform town's glass (and an asteroid's rock) are solid to ships.
	if "platform" in demo and demo.platform != null:
		demo.platform.add_to_ground(ground)
	if demo.use_look and demo.look != null:
		sky = AltitudeSky.new()
		sky.setup(demo.look, ground.atmosphere())
		demo.add_child(sky)
	var pads: Array = GameFlow.pads_for_scene(SCENE_PATH)
	pad = demo.resolve_pad(pads[0]) if not pads.is_empty() else {}
	var enc: Dictionary = content.get_encounter(str(pad.get("encounter", "")))
	ship_id = str(enc.get("player", {}).get("ship", "interceptor"))
	if GameFlow.flown_ship != "" and content.ships.has(GameFlow.flown_ship):
		ship_id = GameFlow.flown_ship         # issue #45: the ship you flew in on is on the pad
	ship_cfg = content.get_ship(ship_id)
	atmo = AtmoFlight.new()
	atmo.setup(ship_cfg, ground)
	space_exit_margin = GameFlow.setting("space_exit_margin", space_exit_margin)
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
	planet_name = NameHooks.planet(world)
	_foot_prompt.visible = false
	RetroUI.prompt(_foot_prompt)
	layer.add_child(_foot_prompt)
	kit = ShipKit.new(demo._flat_mats())
	_gather_berths()
	_use_berth(0)
	if "planet" in demo and not demo.planet.is_empty():
		travel = SpaceTravel.new()
		travel.setup(self, demo.planet.get("neighbours", []), demo.use_look)
		demo.add_child(travel)
	if str(demo._arrival.get("mode", "")) == "reentry":
		reenter()
	elif str(demo._arrival.get("mode", "")) == "travel":
		arrive_from_space(demo._arrival)
	elif str(demo._arrival.get("mode", "")) == "handoff":
		arrive_handoff(demo._arrival)


## Every parked ship the decor built becomes a berth: the pit pad's own ship first
## (berth 0, the pad's encounter ship), then each bay's. In the greybox there are no
## models, so a bare node stands in for the pit ship (the trace does not need to see
## it). Each berth's greybox box stops being solid: the ship carries its own hull, and
## the static box would stay behind as an invisible wall when the ship leaves.
func _gather_berths() -> void:
	var parked: Array = demo.decor.parked_ships if demo.decor != null else []
	var c: Vector3 = pad.get("center", Vector3.ZERO)
	if parked.is_empty():
		var v := Node3D.new()
		v.name = "ShipStandIn"
		demo.add_child(v)
		v.position = c
		v.rotation.y = deg_to_rad(float(pad.get("parked_yaw_deg", 0.0)))
		parked = [v]
	for i in parked.size():
		var v: Node3D = parked[i]
		var id := ship_id if i == 0 else str(v.get_meta("ship_id", ship_id))
		var box_id := str(pad.get("town_box", "ship")) if i == 0 else str(v.get_meta("box_id", ""))
		add_berth(v, id, box_id)


## A parked ship becomes one you can board: its data, model, hull and home bay.
## Issue #58: also how a ship bought from T-89 joins once it is on the spare pad.
## Returns its berth index.
func add_berth(v: Node3D, id: String, box_id: String) -> int:
	var i := berths.size()
	var b := {
		"ship_id": id, "cfg": ship_cfg if i == 0 else content.get_ship(id), "visual": v,
		"home": v.global_position, "home_yaw": v.rotation.y, "clearance": atmo.clearance,
	}
	var acc := [null]
	TownDecor._merge_aabb(v, Transform3D.IDENTITY, acc)
	if acc[0] != null:
		b.clearance = maxf(0.3, -(acc[0] as AABB).position.y)
	_disable_box(box_id)
	b.hull = _build_hull(v, acc[0], box_id, b.clearance)
	b.hull.on_damage = _on_hull_hit.bind(i)
	b.box_id = box_id
	b.destroyed = false
	berths.append(b)
	if WorldState.ships_destroyed.has(box_id):
		_wreck_berth(i, false)          # issue #64: shot to pieces in an earlier session
	return i


## Issue #58: the last berth leaves (sold back to T-89): its model goes, and you
## fly the pit pad's ship again if it was the one you last flew. Not while you sit
## in it. Returns true when it went.
func remove_last_berth() -> bool:
	var i := berths.size() - 1
	if i <= 0 or (piloting and berth == i):
		return false
	if berth == i:
		_use_berth(0)
	var v: Node3D = berths[i].visual
	berths.remove_at(i)
	if demo.decor != null:
		demo.decor.parked_ships.erase(v)
	v.queue_free()
	return true


## Fly berth `i` from now on: its data, model, hull and home bay. It is parked
## wherever its model stands.
func _use_berth(i: int) -> void:
	var b: Dictionary = berths[i]
	berth = i
	ship_id = b.ship_id
	ship_cfg = b.cfg
	visual = b.visual
	hull = b.hull
	home = b.home
	home_yaw = b.home_yaw
	atmo.setup(ship_cfg, ground)
	atmo.clearance = b.clearance
	atmo.park(visual.global_position, visual.rotation.y)
	_sync_visual()
	defense = ShipDefense.new(ship_cfg)
	guns = ShipLoadout.new(ship_cfg, content)
	vessel_name = NameHooks.vessel(ship_cfg, "vessel:player/" + ship_id)
	hud.vessel_name = vessel_name
	var look: Dictionary = kit.looks.get(str(ship_cfg.get("look", "")), {})
	chase.fit_to(float(look.get("length", 9.0)))


## A box around the ship, in the ship's own frame, that travels with it: you can
## walk up to (not through) a parked ship wherever it landed. Sized from the model,
## or from the pad's box in the greybox.
func _build_hull(v: Node3D, model_box, box_id: String, clear: float) -> ShipHull:
	var size := Vector3(9.0, 2.5, 8.0)
	var center := Vector3.ZERO
	if model_box != null:
		size = (model_box as AABB).size
		center = (model_box as AABB).get_center()
	else:
		var box: Dictionary = demo.town.get_box(box_id)
		if not box.is_empty():
			var w := WorldGround._v3(box.max) - WorldGround._v3(box.min)
			var c := absf(cos(v.rotation.y))
			var sn := absf(sin(v.rotation.y))
			size = Vector3(c * w.x + sn * w.z, w.y, sn * w.x + c * w.z)
			center = Vector3(0, w.y * 0.5 - clear, 0)
	var body := ShipHull.new()
	body.name = "ShipHull"
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = center
	body.add_child(cs)
	v.add_child(body)
	return body


func _set_hull(solid: bool) -> void:
	if hull != null:
		for ch in hull.get_children():
			if ch is CollisionShape3D:
				ch.set_deferred("disabled", not solid)


func _disable_box(box_id: String) -> void:
	var body: Node = demo.get_node_or_null("Town/" + box_id)
	if body == null:
		return
	for ch in body.get_children():
		if ch is CollisionShape3D:
			ch.disabled = true


# ------------------------------------------------------------------ queries

func player() -> CharacterBody3D:
	return demo._player


func is_parked_home() -> bool:
	return atmo.state == AtmoFlight.State.PARKED and Vector2(atmo.position().x - home.x, atmo.position().z - home.z).length() < 3.0


## On foot, close enough to a parked ship to climb in.
func can_board() -> bool:
	return nearest_berth() >= 0


## The berth you are close enough to board (the nearest), or -1. Every ship but the
## one you fly is always parked; that one only while it is on the ground.
func nearest_berth() -> int:
	var p := player()
	if piloting or p == null:
		return -1
	var reach := float(pad.get("board_reach", 9.0))
	var best := -1
	var best_d := INF
	for i in berths.size():
		if i == berth and atmo.state != AtmoFlight.State.PARKED:
			continue
		if bool(berths[i].get("destroyed", false)):
			continue
		var v: Node3D = berths[i].visual
		var s := v.global_position
		var d := Vector2(p.global_position.x - s.x, p.global_position.z - s.z).length()
		if d <= reach and d < best_d and absf(p.global_position.y - (s.y - float(berths[i].clearance))) <= 4.0:
			best = i
			best_d = d
	return best


# ------------------------------------------------------------------ actions

func board() -> bool:
	var i := nearest_berth()
	if i < 0 or not Story.ships_unlocked():
		return false
	if i != berth:
		_use_berth(i)
	var p := player()
	piloting = true
	_motion_basis = atmo.flight.basis
	_motion_basis_valid = true
	_foot_prompt.visible = false
	p.piloting = true
	p.vehicle = self
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
	if atmo.state == AtmoFlight.State.PARKED:
		jolt.start()
	boarded.emit()
	return true


func exit_ship() -> bool:
	if not piloting or atmo.state != AtmoFlight.State.PARKED:
		return false
	var p := player()
	var spot := _exit_spot()
	piloting = false
	_motion_basis_valid = false
	if demo.detail != null:
		demo.detail.update_motion(0.0, atmo.altitude(), 0.0, 0.0, false)
	p.piloting = false
	p.vehicle = null
	p.locked = false
	p.process_mode = Node.PROCESS_MODE_INHERIT
	p.visible = true
	_set_player_collision(true)
	p.global_position = spot
	var rig = demo._rig
	if rig != null:
		rig.clear_override()
		# The ship's heading, read in the ground's own frame (issue #77: on the ball).
		rig.rig.yaw = (PlanetSphere.tilt_to(atmo.up()).inverse() * atmo.flight.basis).get_euler().y
		p.rotation.y = rig.rig.yaw
		if "player_kit" in demo and demo.player_kit != null and demo.player_kit.avatar != null:
			demo.player_kit.avatar.facing_yaw = rig.rig.yaw
		rig.set_first_person(_rig_was_fp)
		var cam: Camera3D = rig.camera()
		cam.near = _cam_near
		cam.far = _cam_far
	if p.has_method("align_to_ground"):
		p.call("align_to_ground", true)
	else:
		p.velocity = Vector3.ZERO
		p.controller.velocity = Vector3.ZERO
		p.controller.body_pos = spot
	_ground_follow(p)
	hud.visible = false
	if sky != null:
		sky.update_for(0.0, spot)
	exited.emit()
	return true


func takeoff() -> bool:
	if not piloting or not atmo.takeoff():
		return false
	flight_time = 0.0
	return true


func land() -> bool:
	return piloting and atmo.land()


# ------------------------------------------------------------------ Z: land in the bay (issue #75)

## Close enough to your bay (across the ground, below space) for Z to bring you in.
func near_bay() -> bool:
	if not piloting or fight != null or atmo.state != AtmoFlight.State.FLYING:
		return false
	var p := atmo.position()
	return Vector2(p.x - home.x, p.z - home.z).length() <= GameFlow.setting("bay_land_radius", 4000.0) \
		and atmo.altitude() < atmo.space_altitude


## Z: fly her over the bay and set her down on her own pad, on any planet. False
## when not near enough (or not flying).
func bay_land() -> bool:
	if bay_landing or not near_bay():
		return false
	bay_landing = true
	_throttle = 0.0
	hud.toast(GameFlow.label("bay_landing"), 3.0)
	return true


## One frame of the autopilot: across to a point high over the pad (higher than
## anything in the town), turning to the pad's heading on the way in, then
## straight down with the normal landing.
func _bay_step(dt: float) -> void:
	var f = atmo.flight
	var pos: Vector3 = f.position
	var flat := Vector2(home.x - pos.x, home.z - pos.z)
	var d := flat.length()
	var hold := home.y + atmo.clearance + 60.0
	if d < 0.5:
		f.position = Vector3(home.x, pos.y, home.z)
		f.speed = 0.0
		f.basis = Basis(Vector3.UP, home_yaw)
		if pos.y > hold + 2.0:
			f.position.y = move_toward(pos.y, hold, maxf(10.0, (pos.y - hold) * 0.9) * dt)
			return
		bay_landing = false
		if atmo.land():
			bay_landings += 1
		return
	var v := clampf(d * 0.7, 3.0, 90.0)
	var step := flat.normalized() * minf(v * dt, d)
	var ty := hold if d < 250.0 else maxf(pos.y, hold)
	f.position = Vector3(pos.x + step.x, move_toward(pos.y, ty, maxf(8.0, absf(pos.y - ty) * 0.8) * dt), pos.z + step.y)
	var yaw := atan2(-flat.x, -flat.y) if d > 30.0 else home_yaw
	f.basis = f.basis.slerp(Basis(Vector3.UP, yaw), minf(1.0, dt * 2.0)).orthonormalized()
	f.speed = v


## A bot's command for this frame and on: { pitch, yaw, roll, throttle, boost }.
## Pass {} to give control back to the keys.
func set_external_command(c: Dictionary) -> void:
	_external = c


## Back from space: start in the sky above the port, flying toward it.
## The space encounter over this planet: the planet's own ("" = quiet sky), else
## the pad's (issue #45).
func encounter_id() -> String:
	var e = demo.planet.get("encounter", null) if "planet" in demo else null
	return str(e) if e != null else str(pad.get("encounter", ""))


## Issue #45: in from another planet. Seated in the ship you flew (it is parked on
## this bay's pad, berth 0), flying, high over the bay on the side you came from,
## nose down at the town.
func arrive_from_space(a: Dictionary) -> void:
	var tcfg: Dictionary = demo.planet.get("type_cfg", {})
	var arr: Dictionary = tcfg.get("arrival", {})
	var c: Vector3 = pad.get("center", Vector3.ZERO)
	var from := Vector2(0, 1)
	for n in demo.planet.get("neighbours", []):
		if str(n.id) == str(a.get("from", "")):
			var at: Vector3 = n.at
			from = Vector2(at.x - c.x, at.z - c.z).normalized()
	var dist := float(arr.get("distance", pad.get("reentry_distance", 3250.0)))
	var alt := float(arr.get("altitude", pad.get("reentry_altitude", 2600.0)))
	_seat_arriving()
	var at := Vector3(c.x + from.x * dist, alt, c.z + from.y * dist)
	var to := Vector3(c.x - at.x, 0.0, c.z - at.z).normalized()
	var pitch := deg_to_rad(float(pad.get("reentry_pitch_deg", -18.0)))
	var facing := (to * cos(pitch) + Vector3(0, sin(pitch), 0)).normalized()
	atmo.place_flying(at, facing, 0.0, 0.6)
	atmo.flight.speed = atmo.flight.cruise_speed(0.6) * atmo.air_scale()
	_throttle = 0.6
	_set_hull(true)
	chase._primed = false
	hud.visible = true
	hud.toast(GameFlow.arrival_text(a), 5.0)
	_sync_visual()


## Issue #99: in from another planet with no fade. The ship carries on exactly
## where it was (the travel worked out where that is in this planet's own
## coordinates), same heading, speed and throttle, still flying.
func arrive_handoff(a: Dictionary) -> void:
	var h: Dictionary = a.get("handoff", {})
	_seat_arriving()
	var at: Vector3 = h.get("position", Vector3(0, 3000, 0))
	var b: Basis = h.get("basis", Basis.IDENTITY)
	var thr := float(h.get("throttle", 0.6))
	atmo.place_flying(at, -b.z, float(h.get("speed", 0.0)), thr)
	atmo.flight.basis = b
	_throttle = thr
	_set_hull(true)
	chase._primed = false
	hud.visible = true
	_sync_visual()
	if demo.terrain != null:
		demo.terrain.prefetch(at)
	if sky != null:
		sky.update_for(atmo.altitude(), at)


## Put the player in the cockpit without the walk up to the ship.
func _seat_arriving() -> void:
	var p := player()
	if p == null or piloting:
		return
	piloting = true
	p.piloting = true
	p.vehicle = self
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


func reenter() -> void:
	var p := player()
	if p != null and not piloting:
		# Seat the player without the reach check: they arrive in the cockpit.
		piloting = true
		p.piloting = true
		p.vehicle = self
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
	if fight != null and InputMap.has_action("flight_next_target") and event.is_action_pressed("flight_next_target"):
		fight.next_target()


func _physics_process(dt: float) -> void:
	if atmo == null:
		return
	if not piloting:
		_on_foot()
	else:
		_seated(dt)
	_engine_step()
	if crash_left >= 0.0:
		crash_left -= dt
		if crash_left < 0.0:
			_tow_home()


func _exit_tree() -> void:
	if demo != null and is_instance_valid(demo) and demo.detail != null and atmo != null:
		demo.detail.update_motion(0.0, atmo.altitude(), 0.0, 0.0, false)
	_motion_basis_valid = false
	Sound.set_space(false)


## Issue #16: the engine drones while the ship is in the air; pitch follows the throttle.
func _engine_step() -> void:
	if _engine == null:
		return
	var st := atmo.state
	var on := piloting and (st == AtmoFlight.State.LIFTOFF or st == AtmoFlight.State.FLYING \
		or st == AtmoFlight.State.LANDING)
	if on != _engine.playing:
		if on:
			_engine.play()
		else:
			_engine.stop()
	if on:
		_engine.pitch_scale = 0.75 + _throttle * 0.5 + (0.15 if _boost else 0.0)


func _on_foot() -> void:
	var p := player()
	if p == null:
		return
	if sky != null:
		sky.update_for(ground.altitude(p.global_position), p.global_position)
	if demo.detail != null:
		demo.detail.update_for(ground.altitude(p.global_position))
	var i := nearest_berth() if not p.locked else -1
	var near := i >= 0
	if near:
		var cfg: Dictionary = berths[i].cfg
		var vname := NameHooks.vessel(cfg, "vessel:player/" + str(berths[i].ship_id))
		_foot_prompt.text = "%s  %s" % [GameFlow.label("board"), "  ·  ".join(
			[vname, str(cfg.get("label", ""))].filter(func(x): return x != ""))]
		if not Story.ships_unlocked():
			# Issue #64: the port's ships fly once Oda tells you about the fleet.
			_foot_prompt.text = "%s  ·  %s" % [vname, Story.line("ship_locked")]
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
	_jolt_xf = jolt.step(dt)
	if fight != null:
		_fight_step(dt)
	elif bay_landing:
		_bay_step(dt)
	else:
		for e in atmo.step(dt):
			_on_event(e)
		_rearm_space()
		_fire_guns(dt, _held("flight_fire") if _external.is_empty() else bool(_external.get("fire", false)))
		defense.step(dt)
	_sync_visual()
	var s := atmo.position()
	var agl_now := atmo.agl()
	player().global_position = s
	if demo.terrain != null and atmo.state != AtmoFlight.State.CRASHED \
			and (atmo.state == AtmoFlight.State.LANDING or agl_now < 60.0):
		demo.terrain.prefetch(s)           # ground to step out onto, built in the background
	if sky != null:
		sky.update_for(atmo.altitude(), s)
	if demo.detail != null:
		var turn_rate := 0.0
		var basis_now: Basis = atmo.flight.basis
		if _motion_basis_valid and dt > 0.0:
			var turn_radians := _motion_basis.get_rotation_quaternion().angle_to(basis_now.get_rotation_quaternion())
			turn_rate = rad_to_deg(turn_radians / dt)
		_motion_basis = basis_now
		_motion_basis_valid = true
		var in_flight := atmo.state in [AtmoFlight.State.LIFTOFF, AtmoFlight.State.FLYING, AtmoFlight.State.LANDING]
		demo.detail.update_motion(dt, atmo.altitude(), atmo.speed(), turn_rate, in_flight)
	if demo._rig != null:
		demo._rig.set_override(chase.update(dt, atmo.transform()), 72.0)
	_update_hud(agl_now)


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
		bay_landing = false
		land()
	if st == AtmoFlight.State.FLYING and _just("bay_land"):
		if bay_landing:
			bay_landing = false          # Z again: take her back
		else:
			bay_land()
	if bay_landing:
		return
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
			if space_time < 0.0:
				space_time = flight_time
			Sound.set_space(true)
			_leave_atmosphere()


## Issue #46: out of the atmosphere, still in this scene, over the same ground.
## No fade and no scene change: the sky is already black up here.
func _leave_atmosphere() -> void:
	ascending = true
	left_atmosphere.emit()
	if GameFlow.space_dogfight() and start_fight():
		hud.toast(GameFlow.label("contact"), 6.0)
	else:
		hud.toast(GameFlow.label("in_orbit"), 5.0)


## Start the pad's encounter around the ship as it flies now. False if there is
## none (or one is already running).
func start_fight() -> bool:
	if fight != null:
		return false
	var f := SpaceFight.new()
	demo.add_child(f)
	if not f.begin(content, encounter_id(), atmo.transform(), atmo.speed(), 1, kit, ship_id):
		f.queue_free()
		return false
	fight = f
	fight_started.emit()
	return true


## One frame of the fight: the director flies the player's ship from the same
## command the keys (or a bot) give normal flight, and the town ship follows it.
func _fight_step(dt: float) -> void:
	var cmd: Dictionary = atmo._command.duplicate()
	if _external.is_empty():
		cmd["fire"] = _held("flight_fire")
		cmd["missile"] = _held("flight_missile")
	else:
		cmd["fire"] = bool(_external.get("fire", false))
		cmd["missile"] = bool(_external.get("missile", false))
	var events: Array = fight.step(dt, cmd)
	var f = fight.player_flight()
	if f != null:
		atmo.flight.position = f.position
		atmo.flight.basis = f.basis
		atmo.flight.speed = f.speed
	for e in events:
		match str(e.type):
			"wave":
				hud.toast("Wave %d" % int(e.index), 2.5)
			"kill":
				if fight != null and e.by == fight.df.player_id:
					hud.toast("Kill  ·  " + str(e.who) if str(e.get("who", "")) != "" else "Kill", 2.0)
			"complete":
				end_fight("complete")
				return
			"failed":
				end_fight("failed")
				return
	if atmo.altitude() < atmo.space_altitude - space_exit_margin:
		end_fight("left")


## Finish the sortie. "complete" pays out, "failed" tows the ship home (as a crash
## does), "left" (dived out early) just ends it. Normal flight picks up where the
## fight left the ship.
func end_fight(outcome: String) -> void:
	if fight == null:
		return
	var pay := fight.payout() if outcome == "complete" else 0
	var at := atmo.position()
	fight.queue_free()
	fight = null
	fight_log.append({ "outcome": outcome, "payout": pay, "at": at })
	if outcome != "left":
		WorldState.on_flight_returned({ "pad": str(pad.get("id", "")), "encounter": str(pad.get("encounter", "")),
			"outcome": outcome, "payout": pay, "mode": "orbit" })
	match outcome:
		"complete":
			var t := GameFlow.label("orbit_complete")
			hud.toast(t % pay if t.contains("%d") else t, 6.0)
		"left":
			hud.toast(GameFlow.label("orbit_broke_off"), 3.0)
	if outcome == "failed":
		atmo._crash(at, "space")
		_on_event({ "type": "crashed", "at": at, "what": "space" })
		hud.toast(GameFlow.label("orbit_failed"), 4.0)
	else:
		var throttle := clampf(float(atmo._command.get("throttle", 0.6)), 0.0, 1.0)
		atmo.place_flying(at, atmo.flight.forward(), atmo.flight.speed, throttle)
	fight_ended.emit(outcome)


## Back under the edge of space (and no fight running): the next climb out is a
## new sortie.
func _rearm_space() -> void:
	if atmo.reached_space and atmo.altitude() < atmo.space_altitude - space_exit_margin:
		atmo.reached_space = false
		ascending = false
		Sound.set_space(false)


func _tow_home() -> void:
	if visual != null:
		visual.visible = true
	atmo.reached_space = false
	ascending = false
	Sound.set_space(false)
	atmo.park(home, home_yaw)
	_set_hull(true)
	_sync_visual()
	defense = ShipDefense.new(ship_cfg)       # patched up at the pad
	if piloting:
		exit_ship()
	hud.toast(GameFlow.label("towed"), 4.0)
	if demo.pads.size() > 0:
		demo.pads[0].toast(GameFlow.label("towed"), 4.0)


func _sync_visual() -> void:
	if visual != null and is_instance_valid(visual):
		visual.global_transform = atmo.transform() * _jolt_xf


func _update_hud(agl_now: float) -> void:
	var f = atmo.flight
	var v: Vector3 = f.velocity()
	hud.show_values({
		"speed": f.speed, "throttle": _throttle,
		"boost": f.boost_left / maxf(f.boost_time(), 0.001),
		"agl": agl_now, "altitude": atmo.altitude(), "climb": v.y,
		"space_fraction": atmo.space_fraction(), "state": atmo.state_label(),
		"hull": defense.hull_hp(), "hull_max": defense.hull_max(), "shield": int(defense.shield),
	})
	var tip := ""
	match atmo.state:
		AtmoFlight.State.PARKED:
			tip = GameFlow.label("seated")
		AtmoFlight.State.FLYING:
			tip = GameFlow.label("can_land") if atmo.can_land(agl_now) else ""
			if bay_landing:
				tip = GameFlow.label("bay_landing")
			elif near_bay():
				tip = (tip + "    " if tip != "" else "") + GameFlow.label("bay_land")
		AtmoFlight.State.LANDING:
			tip = GameFlow.label("landing")
	hud.set_prompt(tip)


# ------------------------------------------------------------------ guns and hull (issue #55)

## Issue #55: in town the garrison treats your ship as hostile from the moment it
## lifts off until it is back on the ground (or gone to space).
func hostile_in_town() -> bool:
	return piloting and fight == null and atmo.state != AtmoFlight.State.PARKED \
		and atmo.state != AtmoFlight.State.CRASHED and TownNav.in_town(demo.town, atmo.position())


## What the troopers' eyes and bolts hit while you fly.
func hull_body() -> CollisionObject3D:
	return hull


func threat_velocity() -> Vector3:
	return atmo.flight.velocity()


## The guns, in the air or still on the pad: the primary group (cannons) as real
## bolts, the same ones the troopers and the speeder fire. Seekers stay a space
## weapon (nothing down here to lock).
func _fire_guns(dt: float, trigger: bool) -> void:
	if guns == null or atmo.state == AtmoFlight.State.CRASHED:
		return
	var v: Vector3 = atmo.flight.velocity() if atmo.state != AtmoFlight.State.PARKED else Vector3.ZERO
	var volley := false
	for s in guns.fire(dt, atmo.transform(), v, trigger, false):
		if str(s.kind) != "bolt":
			continue
		var b = BoltScene.instantiate()
		var vel: Vector3 = s.velocity
		b.direction = vel.normalized()
		b.speed = vel.length()
		b.damage = float(s.damage)
		b.range_m = float(s.range)
		b.shooter = hull
		b.sweep = true
		b.stylize = true
		b.streak_length = 2.4
		b.streak_radius = 0.07
		b.color = Color("#ff6a3a")
		var wc: Dictionary = content.weapons.get(str(s.get("weapon_id", "")), {})
		b.splash_radius = float(wc.get("splash_radius", 0.0))
		b.splash_damage = float(wc.get("splash_damage", 0.0))
		if ground.sphere() != null:
			# Issue #93: round the ball the ground is what is under the bolt along "up", not
			# the flat (x, z) line (which is only the port's half of the planet).
			b.over_ground = func(p: Vector3) -> float: return ground.height_above(p)
			b.ground_up = func(p: Vector3) -> Vector3: return ground.up_at(p)
		else:
			b.ground_at = func(x: float, z: float) -> float: return ground.terrain.height_at(x, z)
		demo.add_child(b)
		b.global_position = s.origin
		shots += 1
		volley = true
	if volley:
		Sound.play("ship_cannon", atmo.position())


## A bolt hit berth `i`'s hull. Only the ship you are flying keeps score; a hull
## shot to nothing goes down like a crash (and is towed home).
func _on_hull_hit(amount: float, shooter: Node, i: int) -> void:
	if i < berths.size() and _parked_target(i, shooter):
		_hit_parked(i, amount)
		return
	if i != berth or not piloting or fight != null or atmo.state == AtmoFlight.State.CRASHED:
		return
	defense.apply_damage(amount)
	if defense.is_alive():
		return
	var at := atmo.position()
	atmo._crash(at, "shot_down")
	_on_event({ "type": "crashed", "at": at, "what": "shot_down" })


# ------------------------------------------------------------------ parked ships (issue #64)

## A parked ship shot by another ship (its guns: the shooter is a ship's hull)
## takes the damage. Not the one you sit in.
func _parked_target(i: int, shooter: Node) -> bool:
	var b: Dictionary = berths[i]
	if bool(b.get("destroyed", false)) or not (shooter is ShipHull) or shooter == b.hull:
		return false
	return not (i == berth and (piloting or atmo.state != AtmoFlight.State.PARKED))


func _hit_parked(i: int, amount: float) -> void:
	var b: Dictionary = berths[i]
	if not b.has("defense"):
		b.defense = ShipDefense.new(b.cfg)
	(b.defense as ShipDefense).apply_damage(amount)
	if not (b.defense as ShipDefense).is_alive():
		_wreck_berth(i, true)


## Berth `i` is gone for good: it blows up (when `boom`), its model and hull go,
## nobody can board it, and the save remembers (WorldState.ships_destroyed), so it
## never comes back. A ship bought from T-89 frees his pad.
func _wreck_berth(i: int, boom: bool) -> void:
	var b: Dictionary = berths[i]
	if bool(b.get("destroyed", false)):
		return
	b.destroyed = true
	var v: Node3D = b.visual
	if boom and is_instance_valid(v):
		var at := v.global_position + Vector3(0, 1.5, 0)
		_crash_fx(at)
		Sound.play("ship_boom", at)
		WorldState.log_event("A parked ship in the pit was shot to pieces.")
	if is_instance_valid(v):
		v.visible = false
	if b.hull != null and is_instance_valid(b.hull):
		b.hull.collision_layer = 0
		b.hull.collision_mask = 0
	var key := str(b.get("box_id", ""))
	var pad_id := ""
	if demo.salesman != null:
		pad_id = str(demo.salesman.cfg.get("pad", "spare_pad"))
	if key != "" and key == pad_id:
		WorldState.hangar = ""             # T-89's pad is free again
		demo.salesman.bought_ship = null
	elif key != "" and not WorldState.ships_destroyed.has(key):
		WorldState.ships_destroyed.append(key)
	if i == berth and not piloting:
		for j in berths.size():
			if not bool(berths[j].get("destroyed", false)):
				_use_berth(j)
				break


# ------------------------------------------------------------------ helpers

## Beside the ship (left, then right, then behind), on whatever ground is there.
func _exit_spot() -> Vector3:
	var b: Basis = atmo.flight.basis
	var s := atmo.position()
	var u := atmo.up()
	var side := 5.5
	for off in [-b.x * side, b.x * side, b.z * (side + 3.0), -b.z * (side + 3.0)]:
		var flat: Vector3 = off - u * off.dot(u)
		var at := ground.surface_below(s + flat) + u * 0.05
		if ground.hit(at + u, 0.6) == "":
			return at
	return ground.surface_below(s + u * 5.0) + u * 0.05


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
