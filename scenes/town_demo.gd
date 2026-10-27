extends Node3D
## The demo. Builds port_town from content/core at runtime, dresses it with the
## look-dev lighting and materials, places placeholder capsules at the npc /
## trooper / ambient markers, and spawns the player beside the ship in the pit.
## The ship's pad launches the dogfight (GameFlow); after the fight the player
## lands back here. No coordinates live in this file.
##
## Layers: the gameplay layer (boxes + collision, from TownLayout) is built first
## and never changes; TownDecor only adds visuals on top. `use_look = false` gives
## the plain greybox the CI walk trace uses.
##
## The desert: the town sits on the same DesertTerrain as the beauty corner, seated
## at its floor level, so walking out of the gate (or flying over a wall) lands on
## sand that runs on into the dunes. Its collider follows the player. The greybox
## builds the collider only; the look adds the mesh, sand on the aprons and the
## landforms on the horizon. `with_desert = false` is the old town in the void.

const TownLayout := preload("res://src/systems/world/town_layout.gd")
const Greybox := preload("res://src/systems/world/greybox.gd")
const TownDecor := preload("res://src/systems/world/town_decor.gd")
const StairTower := preload("res://src/systems/world/stair_tower.gd")
const PitBowl := preload("res://src/systems/world/pit_bowl.gd")
const LaunchPad := preload("res://src/systems/flow/launch_pad.gd")
const CharacterBody := preload("res://src/systems/player/character_body.gd")
const CameraRigNode := preload("res://src/systems/camera/camera_rig_node.gd")
const CantinaOwnerNPC := preload("res://src/systems/npc/cantina_owner_npc.gd")
const CoreContent := preload("res://src/systems/dataload/core_content.gd")
const SCENE_PATH := "res://scenes/town_demo.tscn"
const SHOTS_PATH := "res://content/look/town_shots.json"

## Placeholder colors per marker role (greybox).
const ROLE_COLORS := {
	"npc":          Color(0.20, 0.70, 0.60),
	"trooper_post": Color(0.90, 0.90, 0.90),
	"ambient":      Color(0.70, 0.55, 0.80),
}

@export var use_look := true          ## false: plain sun + sky, no decor (CI trace)
@export var lookdev_mode := false     ## true: fixed review cameras, no player
@export var preset := ""              ## "" = default preset in time_of_day.json
@export var with_body := true         ## M11: animated body + hand weapons (needs use_look)
@export var with_bar := true          ## M12: the live cantina owner (needs use_look)
@export var with_gear := true         ## M13: pickups, the gear trader, the jetpack (works in greybox too)
@export var with_desert := true       ## the terrain around the town (collider in greybox too)
@export var terrain_resolution := 320 ## mesh vertices per side (look only; issue #46: was 400)
@export var with_landforms := true    ## mesas, hoodoos, boulders (look only)
@export var with_ship := true         ## M14: the pit's ship is flyable (E boards it instead of quick-launching)
@export var with_npcs := true         ## NPCs on foot: trooper posts with a "soldier" profile get a body, pathing and senses
@export var nav_async := true         ## bake the navmesh on a worker thread (traces may bake in place)
@export var npc_brains := true        ## M15: guards and locals think (patrol, challenge, fight). Off = bodies hold their posts

var town := TownLayout.new()
var look: LookEnvironment
var decor
var camera: Camera3D
var shots: Dictionary = {}
var pads: Array = []
var _player: Node
var _rig: Node
var _arrival: Dictionary = {}
var player_kit: PlayerKit             ## M11 body + weapons (null in the CI greybox)
var training_range: TrainingRange
var cantina_owner: Node3D                 ## M12 (null in the CI greybox)
var bar: Node
var gear: GearController              ## M13
var pilot: ShipPilot                  ## M14
var characters: Dictionary = {}       ## marker id -> built character
var terrain: DesertTerrain            ## null when with_desert is off
var landforms: DesertLandforms
var built_boxes := 0          # read by the trace and tests
var built_markers := 0
var nav: TownNav                      ## the walkable surface NPCs path on
var npcs: Array = []                  ## NpcBody, one per Remnant soldier marker (the garrison)
var garrison: Garrison                ## M15: runs every trooper in town (null with npc_brains off)
var locals: Array = []                ## NpcBody, one per marker whose profile is in the "locals" faction
var townsfolk: Townsfolk              ## runs every local (null with npc_brains off)
var town_name := ""                   ## issue #15: this town's generated name ("" when its world names none)
var planet_name := ""                 ## and the planet it is on
var place_card: Label                 ## "<town>  ·  <planet>", shown for a few seconds on arrival
var retro_hud: RetroHud               ## issue #52: banner, footer and the F1 info screen (null in the CI greybox)
var dev_settings: DevSettingsPanel    ## F11: time of day, standing, trust, player cheats
var detail: AltitudeDetail            ## issue #46: less to draw and run the higher you fly
var speeder_post: SpeederPost         ## issue #42: Skrugs's stall outside the back gate, and the speeders
var planet: Dictionary = {}           ## issue #45: the planet this scene is (PlanetGen.build), from GameFlow
var world: Dictionary = {}            ## its world (terrain, atmosphere, detail): authored or generated
var style: TownStyle                  ## its town style (metallic, snowy, pastel, words...)
var platform: PlatformWorld           ## the deck, glass, shield and what lies below (platform planets only)
@export var with_speeders := true     ## issue #42: Skrugs's post (needs with_ship: it shares the ship's ground)


func _ready() -> void:
	# Issue #45: the planet decides the town, the world, the ground and the look.
	planet = GameFlow.planet()
	if planet.is_empty():
		push_error("TownDemo: no planet " + GameFlow.current_planet_id())
		return
	world = planet.world
	style = TownStyle.parse(str(planet.get("style", "")))
	PlanetGen.reserve_names(planet)
	town.load_from_dict(planet.town)
	if town.data.is_empty():
		push_error("TownDemo: planet %s has no town" % str(planet.id))
		return
	var errs := town.validate()
	if not errs.is_empty():
		for e in errs:
			push_error("TownDemo: " + str(e))
		return                  # never build a broken town
	_build_boxes()
	_build_markers()
	if with_npcs and not lookdev_mode:
		_build_nav()
	if with_desert and str(planet.get("ground", "terrain")) == "terrain":
		_build_desert()
	if str(planet.get("ground", "")) == "platform":
		platform = PlatformWorld.new()
		platform.setup(self, planet)
		add_child(platform)
	if use_look:
		look = LookEnvironment.new()
		_lay_sky(look, planet.get("sky", {}))
		add_child(look)
		set_preset(preset)
		decor = TownDecor.new()
		decor.style = style
		add_child(decor)
		decor.dress(town, look)
		if terrain != null:
			_dress_desert()
		if platform != null:
			platform.dress(look, decor.mats)
	else:
		_add_light_and_sky()
	if use_look and not lookdev_mode:
		add_child(RetroSkin.new())   # issue #52: the 80s HUD look, on everything from here on
	if lookdev_mode:
		shots = _load_shots()
		camera = Camera3D.new()
		camera.name = "ShotCamera"
		camera.far = view_far()
		add_child(camera)
		camera.current = true
		show_shot("gate_approach")
	else:
		Sound.start_music()      # issue #16: carries on across launches and landings
		_spawn_player()
		_build_launch_pads()
		_world_from_scene()
		if use_look and with_body:
			_attach_body(has_feature("training_range"))
		if use_look and with_bar:
			_build_bar()
		if with_gear:
			_build_gear()            # after the bar: the save (and the inventory in it) is loaded
		if with_ship:
			_build_ship()
		if with_npcs:
			_build_npcs()
		if with_speeders and pilot != null and has_feature("speeders"):
			_build_speeder_post()
		_build_detail()
		_name_places()          # after the bar: a loaded save keeps the names it had
		dev_settings = DevSettingsPanel.new()
		dev_settings.name = "DevSettings"
		dev_settings.demo = self
		add_child(dev_settings)
		if use_look:
			retro_hud = RetroHud.new()
			retro_hud.demo = self
			add_child(retro_hud)
			DisclaimerOverlay.show_once(self)   # issue #29: AI characters are not real people


# ---------------------------------------------------------------- names (issue #15)

## The town and its planet get their names from the world's "naming" block
## (NameHooks); a card shows them when you arrive, like entering a region.
func _name_places() -> void:
	town_name = NameHooks.town(world)
	planet_name = NameHooks.planet(world)
	if town_name == "":
		return
	var layer := CanvasLayer.new()
	layer.name = "PlaceCard"
	layer.layer = 6
	add_child(layer)
	place_card = Label.new()
	place_card.text = town_name + ("  ·  " + planet_name if planet_name != "" else "")
	place_card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	place_card.position = Vector2(-360, 64)
	place_card.size = Vector2(720, 40)
	place_card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	place_card.add_theme_font_size_override("font_size", 28)
	place_card.add_theme_color_override("font_color", Color(0.97, 0.92, 0.82))
	place_card.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	place_card.add_theme_constant_override("outline_size", 6)
	place_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(place_card)
	var tw := create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(place_card, "modulate:a", 0.0, 1.5)


# ---------------------------------------------------------------- gameplay layer

func _build_boxes() -> void:
	var root := Node3D.new()
	root.name = "Town"
	add_child(root)
	for b in town.boxes():
		var color: Color = Greybox.KIND_COLORS.get(b.kind, Color.MAGENTA)
		var node: StaticBody3D
		if b.kind == "ramp":
			var rt := TownLayout.ramp_transform(b)
			node = Greybox.make_box(b.id, rt.center, rt.size, color, rt.basis)
		elif b.kind == "spiral":
			node = Greybox.make_trimesh(b.id, StairTower.merged(StairTower.tower_parts(b)), color)
		elif b.kind == "bowl":
			node = Greybox.make_trimesh(b.id, StairTower.merged(PitBowl.parts(b, town)), color)
		elif b.kind == "lookout":
			var tower: Dictionary = town.get_box(str(b.get("stair", "")))
			node = Greybox.make_trimesh(b.id, StairTower.merged(StairTower.lookout_parts(b, tower)), color)
		else:
			var cs := Greybox.center_size(b)
			node = Greybox.make_box(b.id, cs[0], cs[1], color, Basis.IDENTITY, str(b.get("shape", "")) == "round")
		root.add_child(node)
		built_boxes += 1


func _build_markers() -> void:
	## Static capsules: no AI, no collision (so they never block the bot).
	var root := Node3D.new()
	root.name = "Markers"
	add_child(root)
	for m in town.markers():
		if not ROLE_COLORS.has(m.role):
			continue           # spawn/waypoint/interact are invisible
		if _is_live_npc(m):
			continue           # gets a real body in _build_npcs instead
		var v := _make_marker_visual(m)
		v.name = m.id
		# Capsules are centered; built characters stand on their feet.
		v.position = town.marker_pos(m.id) + (Vector3.ZERO if v.has_meta("feet") else Vector3(0, 0.9, 0))
		root.add_child(v)
		built_markers += 1


## The one seam the character art pass replaces. M11: with the look on, markers
## get CharacterKit characters (the cantina owner is built separately by the bar);
## the CI greybox keeps the capsules.
const MARKER_ARCHETYPES := { "npc": "smuggler", "trooper_post": "remnant_trooper", "ambient": "local" }

func _make_marker_visual(m: Dictionary) -> Node3D:
	if use_look and not lookdev_mode:
		if str(m.get("npc", "")) == "cantina_owner" and with_bar:
			var holder := Node3D.new()      # the bar puts her here
			holder.set_meta("feet", true)
			return holder
		var c := _kit().build(MARKER_ARCHETYPES.get(m.role, "local"), str(m.get("pose", "")))
		c.set_meta("feet", true)
		var face := town.marker_pos("gate") if m.role == "trooper_post" else town.marker_pos("cantina_door")
		if m.has("face"):
			face = Vector3(float(m.face[0]), float(m.face[1]), float(m.face[2]))   # e.g. bar patrons look at the cantina owner
		var here := town.marker_pos(str(m.id))
		c.rotation.y = atan2(face.x - here.x, face.z - here.z)
		characters[str(m.id)] = c
		return c
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.35
	mesh.height = 1.8
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if use_look:
		var role_look := {
			"npc": LookMaterials.CLOTH_TEAL,
			"trooper_post": LookMaterials.REMNANT_OXBLOOD,
			"ambient": LookMaterials.CLOTH_SAND,
		}
		mi.material_override = _flat_mats().flat(role_look[m.role])
	else:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = ROLE_COLORS[m.role]
		mesh.material = mat
	return mi


var _kit_inst: CharacterKit
func _kit() -> CharacterKit:
	if _kit_inst == null:
		_kit_inst = CharacterKit.new(_flat_mats(), 0.0)
	return _kit_inst


var _mats: LookMaterials
func _flat_mats() -> LookMaterials:
	if _mats == null:
		_mats = LookMaterials.new()
	return _mats


func _spawn_player() -> void:
	_player = CharacterBody.new()
	_player.position = town.spawn_pos() + Vector3(0, 0.05, 0)  # origin is at the feet
	var yaw := 0.0
	# Back from a flight: stand at the pad's arrive marker, facing the ship.
	_arrival = GameFlow.take_arrival()
	var from_pad := resolve_pad(GameFlow.pad(str(_arrival.get("pad", ""))))
	if not from_pad.is_empty():
		_player.position = from_pad.arrive
		var c: Vector3 = from_pad.center
		yaw = atan2(c.x - from_pad.arrive.x, c.z - from_pad.arrive.z)
	add_child(_player)
	_rig = CameraRigNode.new()
	add_child(_rig)
	_rig.set_player(_player as Node3D)
	_rig.rig.yaw = yaw
	if _rig._camera is Camera3D:
		_rig._camera.far = view_far()
	if terrain != null:
		terrain.follow(_player)
	if not lookdev_mode and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _add_light_and_sky() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.85, 0.75, 0.60)   # dusty sky placeholder
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.55, 0.5)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


# ---------------------------------------------------------------- NPCs on foot

func _is_live_npc(m: Dictionary) -> bool:
	return with_npcs and not lookdev_mode and m.has("soldier")


func _build_nav() -> void:
	nav = TownNav.new()
	nav.name = "TownNav"
	add_child(nav)
	nav.build(town, nav_async)


## One NpcBody per marker that names a soldier profile. Placed facing the marker's
## "face" point if it has one (a merchant faces the aisle), else the way the statue
## used to (the gate for a trooper post); senses watch the player. Profiles in the
## "locals" faction go to Townsfolk, the rest to the Garrison.
func _build_npcs() -> void:
	var cc := CoreContent.new()
	cc.load_from()
	var root := Node3D.new()
	root.name = "Npcs"
	add_child(root)
	for m in town.markers():
		if not _is_live_npc(m):
			continue
		var soldier: Dictionary = cc.get_soldier(str(m.soldier))
		if soldier.is_empty():
			push_error("TownDemo: unknown soldier profile " + str(m.soldier))
			continue
		var here := town.marker_pos(str(m.id))
		var face := town.marker_pos("gate") if m.role == "trooper_post" else town.marker_pos("cantina_door")
		if m.has("face"):
			face = Vector3(float(m.face[0]), float(m.face[1]), float(m.face[2]))
		var npc := NpcBody.new()
		npc.post_id = str(m.id)
		npc.setup(soldier, here, atan2(face.x - here.x, face.z - here.z), _flat_mats() if use_look else null)
		npc.nav = nav
		npc.bolt_parent = self
		npc.target = _player
		npc.assign_name("npc:%s/%s" % [str(town.data.get("id", "town")), str(m.id)])
		npc.target_crouched = func(): return _player != null and _player.controller.pose == CharacterBody.CharacterController.Pose.CROUCH
		npc.target_armed = func(): return player_kit != null and player_kit.weapons.holder.current != ""
		root.add_child(npc)
		(locals if npc.faction == "locals" else npcs).append(npc)
		characters[str(m.id)] = npc.look_body if npc.look_body != null else npc
		built_markers += 1
	if npc_brains and not npcs.is_empty():
		garrison = Garrison.new()
		garrison.name = "Garrison"
		add_child(garrison)
		garrison.setup(self, npcs)
		garrison.player_armed = func(): return player_kit != null and player_kit.weapons.holder.current != ""
	if npc_brains and not locals.is_empty():
		townsfolk = Townsfolk.new()
		townsfolk.name = "Townsfolk"
		add_child(townsfolk)
		townsfolk.setup(self, locals)
		if gear != null:
			gear.vendor_open = townsfolk.vendor_open
			gear.closed_line = townsfolk.closed_line


## Issue #42: Skrugs's speeder stall outside the back gate. Skrugs joins the bar's
## conversation host when there is one (a test that builds the bar later calls
## speeder_post.attach_host itself).
func _build_speeder_post() -> void:
	speeder_post = SpeederPost.new()
	speeder_post.setup(self, pilot.ground)
	add_child(speeder_post)
	if bar != null:
		speeder_post.attach_host(bar)


## Issue #46: the world's "detail" tiers, and what they may switch off: the
## people (bodies, the cantina owner, and the brains that run them) and the small
## props (lamps, banners, boulders). ShipPilot feeds it the viewer's altitude.
func _build_detail() -> void:
	detail = AltitudeDetail.new()
	detail.setup(world.get("detail", {}), look)
	detail.add_group("people", [get_node_or_null("Markers"), get_node_or_null("Npcs"), cantina_owner, garrison, townsfolk,
		speeder_post.skrugs if speeder_post != null else null])
	if decor != null:
		detail.add_group("props", [decor.get_node_or_null("Lamps"), decor.get_node_or_null("Banners")])
	if landforms != null:
		detail.add_group("props", [landforms.get_node_or_null("Boulders")])
	add_child(detail)


func npc(post_id: String) -> NpcBody:
	for n in npcs + locals:
		if n.post_id == post_id:
			return n
	return null


# ---------------------------------------------------------------- M11 / M12

## Facts the scene itself makes true, plus whatever the flight we just came back
## from did. The cantina owner reads these (WorldState), so her talk matches the town.
func _world_from_scene() -> void:
	WorldState.set_flag("gate_checkpoint_up", not town.markers_with_role("trooper_post").is_empty())
	WorldState.time_of_day = preset if preset != "" else WorldState.time_of_day
	WorldState.on_flight_returned(_arrival)


func _attach_body(with_range: bool = true) -> void:
	player_kit = PlayerKit.attach(_player, _rig, self, _flat_mats())
	if not with_range:
		return                       # issue #45: the practice range is the port's
	training_range = TrainingRange.new()
	add_child(training_range)
	training_range.player = _player
	training_range.blade_out = func(): return player_kit.weapons.holder.current == "energy_blade" and player_kit.weapons.blade_extent > 0.5
	player_kit.weapons.in_range_zone = training_range.contains


## `scripted` = CI providers (no network); `save_path` "" = do not persist.
func _build_bar(scripted = null, save_path: String = "user://save.json") -> void:
	bar = ConversationHost.new()
	bar.name = "Bar"
	bar.autosave = save_path != ""
	if save_path != "":
		bar.save_path = save_path
	add_child(bar)
	bar.setup(self, scripted)
	cantina_owner = bar.npc


## M13: gear in the town. Pickups and vendors come from content/core; the gear
## node puts a jetpack on the player while one is attached.
func _build_gear() -> void:
	gear = GearController.new()
	gear.setup(null, town, _player, _rig, str(planet.get("town_id", "port_town")))
	if terrain != null:
		gear.ground_at = terrain.ground_at
	elif platform != null:
		gear.ground_at = platform.ground_at      # the void: the deck's own fall handles it
	add_child(gear)


## M14: the pit's ship becomes the one you fly, and the world opens up around the
## town. The pad stops quick-launching: E boards the ship, and flying out of the
## atmosphere is the way to space.
func _build_ship() -> void:
	for pd in pads:
		pd.quick_launch = false
	pilot = ShipPilot.new()
	pilot.setup(self)
	add_child(pilot)


func _physics_process(dt: float) -> void:
	WorldState.tick(dt)


# ---------------------------------------------------------------- desert

## The far plane: out to the horizon landforms when the desert is on.
func view_far() -> float:
	return 12000.0 if terrain != null or platform != null else 4000.0


# ---------------------------------------------------------------- planets (issue #45)

## True when the planet's config lists this feature (the port's practice range,
## Skrugs's speeders, the desert landforms, the jetpack pickups).
func has_feature(f: String) -> bool:
	return (planet.get("features", []) as Array).has(f)


## The planet type's sky: its values laid over every time-of-day preset, so the
## clock and F11 still work (an asteroid's grey, a snow world's pale blue).
func _lay_sky(env: LookEnvironment, sky: Dictionary) -> void:
	if sky.is_empty():
		return
	for id in env.presets:
		env.presets[id] = deep_merge(env.presets[id], sky)


static func deep_merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for k in over:
		if out.get(k) is Dictionary and over[k] is Dictionary:
			out[k] = deep_merge(out[k], over[k])
		else:
			out[k] = over[k]
	return out


## Footprints from the town data (no coordinates in this file): every floor box
## at floor level, the walled area, and the floors sunk below it (the pit).
func desert_site() -> Dictionary:
	var floor_rect := Rect2()
	var sunken := []
	var first := true
	for b in town.boxes():
		if str(b.kind) != "floor":
			continue
		var r := Rect2(float(b.min[0]), float(b.min[2]), float(b.max[0]) - float(b.min[0]), float(b.max[2]) - float(b.min[2]))
		if float(b.max[1]) < -0.1:
			sunken.append({ "rect": r, "y": float(b.min[1]) })
			continue
		floor_rect = r if first else floor_rect.merge(r)
		first = false
	var bounds: Dictionary = town.data.get("bounds", {})
	var walls := floor_rect
	if not bounds.is_empty():
		walls = Rect2(float(bounds.min[0]), float(bounds.min[1]),
			float(bounds.max[0]) - float(bounds.min[0]), float(bounds.max[1]) - float(bounds.min[1]))
	return { "floor": floor_rect, "walls": walls, "sunken": sunken }


func _build_desert() -> void:
	var site := desert_site()
	terrain = DesertTerrain.new()
	terrain.resolution = terrain_resolution
	terrain.configure_site(site.floor, site.walls, site.sunken, 0.0)
	terrain.collider_size = 512.0
	add_child(terrain)
	terrain.build(use_look)          # greybox: collider only


## Look only: the aprons outside the walls are hidden (still solid) so the terrain's
## sand, which lies exactly at their top, is what you see: paving runs straight
## into sand. The sun drives the sand's glitter, and the horizon gets landforms.
func _dress_desert() -> void:
	look.track_material(terrain.material)
	var walls: Rect2 = desert_site().walls
	for b in town.boxes():
		if str(b.kind) != "floor" or float(b.max[1]) < -0.1:
			continue
		var r := Rect2(float(b.min[0]), float(b.min[2]), float(b.max[0]) - float(b.min[0]), float(b.max[2]) - float(b.min[2]))
		if walls.encloses(r):
			continue
		var mi := get_node_or_null("Town/%s/Mesh" % str(b.id)) as MeshInstance3D
		if mi != null:
			mi.visible = false
	_tint_sand(terrain.material, planet.get("type_cfg", {}).get("sand", {}))
	if with_landforms:
		landforms = DesertLandforms.new()
		add_child(landforms)
		landforms.build(terrain, _flat_mats(), desert_site().floor)
		_tint_rock(landforms, planet.get("type_cfg", {}).get("rock", {}))


## Issue #45: a snow world's white drifts, a red desert's red sand. Shader values
## from the planet type ("sand"); the port's own (empty) changes nothing.
func _tint_sand(m: ShaderMaterial, sand: Dictionary) -> void:
	if m == null:
		return
	for k in sand:
		var v = sand[k]
		m.set_shader_parameter(k, Color(str(v)) if v is String else v)


func _tint_rock(root: Node, rock: Dictionary) -> void:
	if rock.is_empty():
		return
	var done := {}
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		var mat = (n as GeometryInstance3D).material_override
		if mat is ShaderMaterial and not done.has(mat):
			done[mat] = true
			for k in rock:
				mat.set_shader_parameter(k, Color(str(rock[k])))


# ---------------------------------------------------------------- launch pads

## A pad anchored to a town box sits on that box's footprint center at its base,
## and returns the player to its arrive marker. Coordinates come from town data.
func resolve_pad(p: Dictionary) -> Dictionary:
	if p.is_empty() or str(p.get("scene", "")) != SCENE_PATH:
		return {}
	var out := p.duplicate(true)
	var box: Dictionary = town.get_box(str(p.get("town_box", "")))
	if box.is_empty():
		return {}
	var cs := Greybox.center_size(box)
	var c: Vector3 = cs[0]
	out.center = Vector3(c.x, float(box.min[1]), c.z)
	var am := str(p.get("arrive_marker", ""))
	out.arrive = (town.marker_pos(am) if not town.get_marker(am).is_empty() else town.spawn_pos()) + Vector3(0, 0.05, 0)
	return out


func _build_launch_pads() -> void:
	for p in GameFlow.pads_for_scene(SCENE_PATH):
		var r := resolve_pad(p)
		if r.is_empty():
			push_warning("TownDemo: launch pad %s has no town_box" % str(p.get("id", "")))
			continue
		var c: Vector3 = r.center
		r.center = [c.x, c.y, c.z]
		var pad := LaunchPad.new()
		pad.configure(r, _player)
		add_child(pad)
		pads.append(pad)
	if not _arrival.is_empty() and not pads.is_empty():
		pads[0].toast(GameFlow.arrival_text(_arrival), 5.0)


# ---------------------------------------------------------------- look + review

func set_preset(id: String) -> void:
	if look == null:
		return
	look.apply(id)
	preset = look.current
	WorldState.time_of_day = preset


## A time of day in hours, blended between presets (F11). `preset` and the
## world's time_of_day follow the nearer preset, so rumors still key on it.
func set_hour(h: float) -> void:
	if look == null:
		return
	look.apply_hour(h)
	preset = look.current
	WorldState.time_of_day = preset


func _load_shots() -> Dictionary:
	var f := FileAccess.open(SHOTS_PATH, FileAccess.READ)
	if f == null:
		return {}
	var data = JSON.parse_string(f.get_as_text())
	return data.get("shots", {}) if data is Dictionary else {}


func shot_ids() -> Array:
	return shots.keys()


func show_shot(id: String) -> bool:
	if camera == null or not shots.has(id):
		return false
	var s: Dictionary = shots[id]
	var pos := Vector3(s["pos"][0], s["pos"][1], s["pos"][2])
	if s.has("height_above_ground") and terrain != null:
		pos.y = terrain.height_at(pos.x, pos.z) + float(s["height_above_ground"])
	var target := Vector3(s["target"][0], s["target"][1], s["target"][2])
	camera.fov = float(s.get("fov", 65.0))
	camera.global_position = pos
	camera.look_at(target, Vector3.UP)
	return true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if bar != null and bar.is_talking():
			return                      # the dialogue panel owns Esc while talking
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and not lookdev_mode \
			and not (bar != null and bar.is_talking()):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F4:
		NpcBody.show_debug = not NpcBody.show_debug   # what each guard sees and hears
	elif event is InputEventKey and event.pressed and event.keycode == KEY_L:
		# L cycles the lighting (1/2/3 are weapons since M11).
		var ids := ["golden", "noon", "dusk"]
		set_preset(ids[(ids.find(preset) + 1) % ids.size()])
