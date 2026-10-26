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

const TownLayout := preload("res://src/systems/world/town_layout.gd")
const Greybox := preload("res://src/systems/world/greybox.gd")
const TownDecor := preload("res://src/systems/world/town_decor.gd")
const LaunchPad := preload("res://src/systems/flow/launch_pad.gd")
const CharacterBody := preload("res://src/systems/player/character_body.gd")
const CameraRigNode := preload("res://src/systems/camera/camera_rig_node.gd")
const BartenderNPC := preload("res://src/systems/npc/bartender_npc.gd")
const BarScene := preload("res://src/systems/npc/bar_scene.gd")
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
@export var with_bar := true          ## M12: the live bartender (needs use_look)

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
var bartender: Node3D                 ## M12 (null in the CI greybox)
var bar: Node
var characters: Dictionary = {}       ## marker id -> built character
var built_boxes := 0          # read by the trace and tests
var built_markers := 0


func _ready() -> void:
	if not town.load_town("port_town"):
		push_error("TownDemo: port_town failed to load")
		return
	var errs := town.validate()
	if not errs.is_empty():
		for e in errs:
			push_error("TownDemo: " + str(e))
		return                  # never build a broken town
	_build_boxes()
	_build_markers()
	if use_look:
		look = LookEnvironment.new()
		add_child(look)
		set_preset(preset)
		decor = TownDecor.new()
		add_child(decor)
		decor.dress(town, look)
	else:
		_add_light_and_sky()
	if lookdev_mode:
		shots = _load_shots()
		camera = Camera3D.new()
		camera.name = "ShotCamera"
		camera.far = 4000.0
		add_child(camera)
		camera.current = true
		show_shot("gate_approach")
	else:
		_spawn_player()
		_build_launch_pads()
		_world_from_scene()
		if use_look and with_body:
			_attach_body()
		if use_look and with_bar:
			_build_bar()


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
		else:
			var cs := Greybox.center_size(b)
			node = Greybox.make_box(b.id, cs[0], cs[1], color)
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
		var v := _make_marker_visual(m)
		v.name = m.id
		# Capsules are centered; built characters stand on their feet.
		v.position = town.marker_pos(m.id) + (Vector3.ZERO if v.has_meta("feet") else Vector3(0, 0.9, 0))
		root.add_child(v)
		built_markers += 1


## The one seam the character art pass replaces. M11: with the look on, markers
## get CharacterKit characters (the bartender is built separately by the bar);
## the CI greybox keeps the capsules.
const MARKER_ARCHETYPES := { "npc": "smuggler", "trooper_post": "remnant_trooper", "ambient": "local" }

func _make_marker_visual(m: Dictionary) -> Node3D:
	if use_look and not lookdev_mode:
		if str(m.get("npc", "")) == "bartender" and with_bar:
			var holder := Node3D.new()      # the bar puts her here
			holder.set_meta("feet", true)
			return holder
		var c := _kit().build(MARKER_ARCHETYPES.get(m.role, "local"))
		c.set_meta("feet", true)
		var face := town.marker_pos("gate") if m.role == "trooper_post" else town.marker_pos("cantina_door")
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
		_rig._camera.far = 4000.0
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


# ---------------------------------------------------------------- M11 / M12

## Facts the scene itself makes true, plus whatever the flight we just came back
## from did. The bartender reads these (WorldState), so her talk matches the town.
func _world_from_scene() -> void:
	WorldState.set_flag("gate_checkpoint_up", not town.markers_with_role("trooper_post").is_empty())
	WorldState.time_of_day = preset if preset != "" else WorldState.time_of_day
	WorldState.on_flight_returned(_arrival)


func _attach_body() -> void:
	player_kit = PlayerKit.attach(_player, _rig, self, _flat_mats())
	training_range = TrainingRange.new()
	add_child(training_range)
	training_range.player = _player
	training_range.blade_out = func(): return player_kit.weapons.holder.current == "energy_blade" and player_kit.weapons.blade_extent > 0.5
	player_kit.weapons.in_range_zone = training_range.contains


## `scripted` = CI providers (no network); `save_path` "" = do not persist.
func _build_bar(scripted = null, save_path: String = "user://save.json") -> void:
	bar = BarScene.new()
	bar.name = "Bar"
	bar.autosave = save_path != ""
	if save_path != "":
		bar.save_path = save_path
	add_child(bar)
	bar.setup(self, scripted)
	bartender = bar.npc


func _physics_process(dt: float) -> void:
	WorldState.tick(dt)


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
	elif event is InputEventKey and event.pressed and event.keycode == KEY_L:
		# L cycles the lighting (1/2/3 are weapons since M11).
		var ids := ["golden", "noon", "dusk"]
		set_preset(ids[(ids.find(preset) + 1) % ids.size()])
