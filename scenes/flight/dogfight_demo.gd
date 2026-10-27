extends Node3D
## M10: playable dogfight. Fly the player's starfighter against the waves of an
## encounter from data (default orbital_skirmish). Everything that matters runs in
## the pure dogfight director (src/systems/flight/dogfight.gd); this scene only
## reads input, draws ships, bolts and explosions, moves the camera and paints a
## small HUD. The headless trace (scenes/m10_dogfight_trace.gd) runs the same
## director with the AI flying the player.
##
## Run: open the project and press F6 on this scene, or
##   godot --path . res://scenes/flight/dogfight_demo.tscn
## Controls are in LAUNCH.md. Set `autopilot` to watch the AI fly your ship.

const CoreContent := preload("res://src/systems/dataload/core_content.gd")
const Dogfight := preload("res://src/systems/flight/dogfight.gd")
const ChaseCamera := preload("res://src/systems/camera/chase_camera.gd")
const SPACE_PATH := "res://content/look/space.json"

@export var encounter_id := "orbital_skirmish"
@export var autopilot := false
@export var rng_seed := 1
@export var mouse_sensitivity := 0.004
@export var fixed_step := 0.0   ## > 0: step the fight by this, not the frame time (review renders)

var content
var df
var kit: ShipKit
var camera: Camera3D
var chase = ChaseCamera.new()
var hud: Control
var hud_label: Label
var banner: Label

var view: DogfightView     ## issue #46: ships, bolts and flashes (shared with SpaceFight)
var ship_nodes: Dictionary:  ## runtime id -> ShipNode
	get: return view.ship_nodes if view != null else {}
var bolt_nodes: Dictionary:  ## projectile uid -> Node3D (from ShipKit.build_bolt)
	get: return view.bolt_nodes if view != null else {}
var _throttle := 0.6
var _stick := Vector2.ZERO  ## mouse "virtual stick" (x = yaw, y = pitch)
var _banner_left := 0.0
var _space: Dictionary = {}
var return_left := -1.0     ## >= 0: counting down to the port (launched from a pad)
var _outcome := ""
var _payout := 0
var _return_how := "pad"    ## M14: "pad" (on foot at the pad) or "reentry" (back in the port's sky)
var reentry_margin := 600.0 ## M14: metres above the planet's surface where a dive re-enters
var planet_center := Vector3.ZERO
var planet_radius := 0.0
var planet_name := ""       ## issue #15: the world below, named (the encounter's "world")


func _ready() -> void:
	# Launched from a port pad: fly that pad's encounter. Opened on its own: unchanged.
	if GameFlow.in_flight and GameFlow.encounter_id != "":
		encounter_id = GameFlow.encounter_id
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	content = CoreContent.new()
	content.load_from()
	df = Dogfight.new(content, encounter_id, rng_seed)
	# Issue #15: everyone who spawns gets a name; each sortie brings new pilots.
	df.names = WorldState.names
	df.name_scope = "pilot:%s/%d" % [encounter_id, WorldState.bump("sorties_" + encounter_id)]
	df.start()
	df.set_player_autopilot(autopilot)
	kit = ShipKit.new()
	view = DogfightView.new(kit)
	add_child(view)
	_space = ShipKit._read_json(SPACE_PATH)
	_build_space()
	camera = Camera3D.new()
	camera.name = "FlightCamera"
	camera.far = 20000.0
	camera.fov = 70.0
	add_child(camera)
	camera.current = true
	var me: Dictionary = df.get_ship(df.player_id)
	if not me.is_empty():
		var look: Dictionary = kit.looks.get(me.look, {})
		chase.fit_to(float(look.get("length", 9.0)))
	_build_hud()
	view.sync(df)
	var title := str(df.encounter.get("label", "Dogfight"))
	planet_name = NameHooks.planet(content.get_world(str(df.encounter.get("world", ""))))
	if planet_name != "":
		title += "  ·  above " + planet_name
	_show_banner(title)
	if GameFlow.in_flight and GameFlow.mode == "ascent":
		_show_banner(GameFlow.label("dive_to_land"), 5.0)


# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_stick.x = clampf(_stick.x + event.relative.x * mouse_sensitivity, -1.0, 1.0)
		_stick.y = clampf(_stick.y - event.relative.y * mouse_sensitivity, -1.0, 1.0)
	if _action_pressed(event, "toggle_view"):
		chase.toggle_mode()
	if _action_pressed(event, "flight_next_target"):
		df.cycle_player_target()


func _action_pressed(event: InputEvent, action: String) -> bool:
	return InputMap.has_action(action) and event.is_action_pressed(action)


func _axis(neg: String, pos: String) -> float:
	if not InputMap.has_action(neg) or not InputMap.has_action(pos):
		return 0.0
	return Input.get_axis(neg, pos)


func _held(action: String) -> bool:
	return InputMap.has_action(action) and Input.is_action_pressed(action)


func _read_player_input(dt: float) -> void:
	_throttle = clampf(_throttle + _axis("flight_throttle_down", "flight_throttle_up") * dt * 0.8, 0.0, 1.0)
	var pitch := clampf(_axis("flight_pitch_down", "flight_pitch_up") + _stick.y, -1.0, 1.0)
	var yaw := clampf(_axis("flight_yaw_left", "flight_yaw_right") + _stick.x, -1.0, 1.0)
	var roll := _axis("flight_roll_left", "flight_roll_right")
	_stick = _stick.lerp(Vector2.ZERO, minf(1.0, dt * 3.0))   # the mouse stick re-centres
	df.set_player_command(pitch, yaw, roll, _throttle, _held("flight_boost"),
		_held("flight_fire"), _held("flight_missile"))


# ------------------------------------------------------------------ frame

func _process(frame_dt: float) -> void:
	var dt := fixed_step if fixed_step > 0.0 else minf(frame_dt, 0.05)
	if not autopilot:
		_read_player_input(dt)
	var ev: Array = df.step(dt)
	for e in ev:
		_on_event(e)
	view.sync(df)
	view.tick(dt)
	var me: Dictionary = df.get_ship(df.player_id)
	if not me.is_empty():
		camera.global_transform = chase.update(dt, me.flight.transform())
	_update_hud(dt)
	_tick_return(dt)
	_check_reentry()


## M14: flying down at the planet takes you back to the port's sky, whenever you
## like (only when this flight came from a town; a stand-alone dogfight stays).
func _check_reentry() -> void:
	if not GameFlow.in_flight or planet_radius <= 0.0:
		return
	var me: Dictionary = df.get_ship(df.player_id)
	if me.is_empty() or not me.alive:
		return
	if me.flight.position.distance_to(planet_center) <= planet_radius + reentry_margin:
		var done: bool = df.state == Dogfight.State.COMPLETE
		return_left = -1.0
		GameFlow.finish_flight(get_tree(), "complete" if done else "left",
			int(df.encounter.get("payout", 0)) if done else 0, "reentry")


## After the fight ends, go back to the port this flight launched from.
func _tick_return(dt: float) -> void:
	if return_left < 0.0:
		return
	return_left -= dt
	if return_left <= 0.0:
		return_left = -1.0
		GameFlow.finish_flight(get_tree(), _outcome, _payout, _return_how)


## After a fight: a lost ship limps home to the pad. A won fight flown up from the
## town (M14) gives you time to dive back down yourself, then re-enters anyway.
func _queue_return(outcome: String, payout: int) -> void:
	if not GameFlow.in_flight or return_left >= 0.0:
		return
	_outcome = outcome
	_payout = payout
	_return_how = "pad"
	return_left = GameFlow.setting("return_delay", 4.0)
	if outcome == "complete" and GameFlow.mode == "ascent":
		_return_how = "reentry"
		return_left = GameFlow.setting("reentry_delay", 25.0)


## Run the fight forward without drawing (for review renders and tests), then sync.
func warm_up(seconds: float, step: float = 1.0 / 60.0) -> void:
	var n := int(seconds / step)
	for i in n:
		if not autopilot:
			_read_player_input(step)
		df.step(step)
	view.sync(df)
	var me: Dictionary = df.get_ship(df.player_id)
	if not me.is_empty():
		chase._primed = false
		camera.global_transform = chase.update(step, me.flight.transform())


func _on_event(e: Dictionary) -> void:
	view.on_event(e)
	match str(e.type):
		"kill":
			if e.by == df.player_id:
				_show_banner("Kill  ·  " + str(e.who) if str(e.get("who", "")) != "" else "Kill")
		"wave":
			_show_banner("Wave %d" % e.index)
		"complete":
			_show_banner("Sector clear  +%d credits" % e.payout, 6.0)
			_queue_return("complete", int(e.payout))
			if GameFlow.in_flight and GameFlow.mode == "ascent":
				_show_banner(GameFlow.label("sector_clear_dive"), 8.0)
		"failed":
			_show_banner("Fighter lost", 6.0)
			_queue_return("failed", 0)


# ------------------------------------------------------------------ world

func _col(d: Dictionary, key: String, fallback: String) -> Color:
	return Color(str(d.get(key, fallback)))


func _build_space() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = _col(_space, "background", "#05060b")
	var amb: Dictionary = _space.get("ambient", {})
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = _col(amb, "color", "#6a5a4a")
	env.ambient_light_energy = float(amb.get("energy", 0.35))
	var glow: Dictionary = _space.get("glow", {})
	env.glow_enabled = float(glow.get("intensity", 0.9)) > 0.0
	env.glow_intensity = float(glow.get("intensity", 0.9))
	env.glow_bloom = float(glow.get("bloom", 0.0))
	# Additive glow: the default soft-light blend lifts the black of space to navy.
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_hdr_threshold = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_AGX   # docs/ART_DIRECTION.md, Camera and post
	var we := WorldEnvironment.new()
	we.name = "Space"
	we.environment = env
	add_child(we)

	var sun_d: Dictionary = _space.get("sun", {})
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = _col(sun_d, "color", "#ffe2b0")
	sun.light_energy = float(sun_d.get("energy", 2.0))
	var dir := LookEnvironment.direction(float(sun_d.get("azimuth", -35.0)), float(sun_d.get("elevation", 22.0)))
	add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, -dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.BACK)

	var pl: Dictionary = _space.get("planet", {})
	planet_center = Dogfight._vec(pl.get("center", [0, -6400, -2600]))
	planet_radius = float(pl.get("radius", 5000.0))
	var planet := MeshInstance3D.new()
	planet.name = "Planet"
	var ps := SphereMesh.new()
	var pr := float(pl.get("radius", 5000.0))
	ps.radius = pr
	ps.height = pr * 2.0
	ps.radial_segments = 96
	ps.rings = 48
	planet.mesh = ps
	planet.material_override = kit.mats.flat(_col(pl, "color", "#c49a63"), 1.0, 0.0)
	planet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(planet)
	planet.position = Dogfight._vec(pl.get("center", [0, -6400, -2600]))
	var atmo := MeshInstance3D.new()
	atmo.name = "Atmosphere"
	var asph := SphereMesh.new()
	asph.radius = pr * 1.02
	asph.height = pr * 2.04
	asph.radial_segments = 96
	asph.rings = 48
	atmo.mesh = asph
	var am := StandardMaterial3D.new()
	am.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	am.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	am.cull_mode = BaseMaterial3D.CULL_FRONT
	am.albedo_color = _col(pl, "atmosphere", "#f0b979").darkened(0.82)
	atmo.material_override = am
	add_child(atmo)
	atmo.position = planet.position

	var st: Dictionary = _space.get("stars", {})
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var quad := QuadMesh.new()
	var sz := float(st.get("size", 9.0))
	quad.size = Vector2(sz, sz)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sm.albedo_color = _col(st, "color", "#e9e6f2")
	quad.material = sm
	mm.mesh = quad
	var n := int(st.get("count", 1200))
	mm.instance_count = n
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var dist := float(st.get("distance", 9000.0))
	for i in n:
		var v := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.2, 1), rng.randf_range(-1, 1)).normalized()
		var scl := rng.randf_range(0.3, 1.0)
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * scl), v * dist))
	var stars := MultiMeshInstance3D.new()
	stars.name = "Stars"
	stars.multimesh = mm
	stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(stars)


# ------------------------------------------------------------------ HUD

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)
	hud.draw.connect(_draw_hud)
	hud_label = Label.new()
	hud_label.position = Vector2(16, 12)
	hud.add_child(hud_label)
	banner = Label.new()
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.position = Vector2(-160, 80)
	banner.size = Vector2(320, 30)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(banner)


func _show_banner(text: String, secs: float = 2.0) -> void:
	if banner != null:
		banner.text = text
	_banner_left = secs


func _update_hud(dt: float) -> void:
	_banner_left -= dt
	if banner != null:
		banner.visible = _banner_left > 0.0
	var me: Dictionary = df.get_ship(df.player_id)
	if me.is_empty() or hud_label == null:
		return
	var f = me.flight
	var d = me.defense
	var tgt: Dictionary = df.get_ship(df.player_target_id)
	var tline := "no target"
	if not tgt.is_empty() and tgt.alive:
		tline = "%s  %d m" % [str(tgt.cfg.get("label", tgt.ship_id)),
			int((tgt.flight.position - f.position).length())]
	hud_label.text = "SPEED %3d  THR %3d%%  BOOST %3d%%\nSHIELD %3d  HULL %3d\nGUNS %d%s  SEEKERS %d%s  LOCK %3d%%\nTARGET %s\nWAVE %d/%d  HOSTILES %d  %s" % [
		int(f.speed), int(f.throttle * 100.0), int(f.boost_left / maxf(f.boost_time(), 0.001) * 100.0),
		int(d.shield), d.hull_hp(),
		me.loadout.group_ammo("primary"), " (cooling)" if me.loadout.group_reloading("primary") else "",
		me.loadout.group_ammo("secondary"), " (reloading)" if me.loadout.group_reloading("secondary") else "",
		int(me.lock.fraction() * 100.0), tline,
		df.stats.waves, df.waves_total(), df.alive_on(Dogfight.TEAM_HOSTILE).size(), df.state_label()]
	if return_left >= 0.0:
		hud_label.text += "\n" + GameFlow.label("returning")
	hud.queue_redraw()


func _draw_hud() -> void:
	if camera == null:
		return
	var vp := hud.get_viewport_rect().size
	var c := vp * 0.5
	var ink := Color(0.5, 0.95, 1.0, 0.8)
	hud.draw_arc(c, 14.0, 0.0, TAU, 24, ink, 1.5)
	hud.draw_line(c + Vector2(-26, 0), c + Vector2(-18, 0), ink, 1.5)
	hud.draw_line(c + Vector2(18, 0), c + Vector2(26, 0), ink, 1.5)
	var tgt: Dictionary = df.get_ship(df.player_target_id)
	if tgt.is_empty() or not tgt.alive:
		return
	var tp: Vector3 = tgt.flight.position
	if not camera.is_position_behind(tp):
		var sp := camera.unproject_position(tp)
		var lock_col := Color(1.0, 0.45, 0.3, 0.9)
		hud.draw_rect(Rect2(sp - Vector2(18, 18), Vector2(36, 36)), lock_col, false, 1.5)
		var me: Dictionary = df.get_ship(df.player_id)
		if not me.is_empty() and me.lock.fraction() > 0.0:
			hud.draw_arc(sp, 26.0, -PI * 0.5, -PI * 0.5 + TAU * me.lock.fraction(), 32, lock_col, 2.5)
	var lead: Dictionary = df.player_lead()
	if lead.get("valid", false) and not camera.is_position_behind(lead.point):
		var lp := camera.unproject_position(lead.point)
		hud.draw_circle(lp, 5.0, Color(1.0, 0.85, 0.4, 0.9))
