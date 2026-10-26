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
const SCENE_PATH := "res://scenes/town_demo.tscn"
const SHOTS_PATH := "res://content/look/town_shots.json"
const CAST_PATH := "res://content/look/town_cast.json"

## Placeholder colors per marker role (greybox).
const ROLE_COLORS := {
	"npc":          Color(0.20, 0.70, 0.60),
	"trooper_post": Color(0.90, 0.90, 0.90),
	"ambient":      Color(0.70, 0.55, 0.80),
}

@export var use_look := true          ## false: plain sun + sky, no decor (CI trace)
@export var lookdev_mode := false     ## true: fixed review cameras, no player
@export var preset := ""              ## "" = default preset in time_of_day.json

var town := TownLayout.new()
var look: LookEnvironment
var decor
var camera: Camera3D
var shots: Dictionary = {}
var cast: Dictionary = {}
var _kits := {}
var pads: Array = []
var _player: Node
var _rig: Node
var _arrival: Dictionary = {}
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
	if use_look:
		look = LookEnvironment.new()
		add_child(look)
		set_preset(preset)
		decor = TownDecor.new()
		add_child(decor)
		decor.dress(town, look)
	else:
		_add_light_and_sky()
	_build_markers()
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
	## Static figures: no AI, no collision (so they never block the bot).
	var root := Node3D.new()
	root.name = "Markers"
	add_child(root)
	for m in town.markers():
		if not ROLE_COLORS.has(m.role):
			continue           # spawn/waypoint/interact are invisible
		var v := _make_marker_visual(m)
		v.name = m.id
		v.position = town.marker_pos(m.id)       # origin is at the feet
		root.add_child(v)
		built_markers += 1


## The one seam the character art pass replaces. With the look layer on it is a
## character from the beauty corner's kit; the plain greybox (CI) keeps capsules.
func _make_marker_visual(m: Dictionary) -> Node3D:
	return _make_character(m) if use_look else _make_capsule(m)


func _make_capsule(m: Dictionary) -> Node3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.35
	mesh.height = 1.8
	var mat := StandardMaterial3D.new()
	mat.albedo_color = ROLE_COLORS[m.role]
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "Capsule"
	mi.mesh = mesh
	mi.position = Vector3(0, 0.9, 0)             # capsule is centered, feet at the origin
	var root := Node3D.new()
	root.add_child(mi)
	return root


## Who stands here comes from content/look/town_cast.json: role default, then the
## marker's own entry. Characters face +Z, so yaw = atan2(dir.x, dir.z).
func _make_character(m: Dictionary) -> Node3D:
	if cast.is_empty():
		cast = _read_json(CAST_PATH)
	var pick: Dictionary = cast.get("roles", {}).get(str(m.role), {}).duplicate()
	pick.merge(cast.get("markers", {}).get(str(m.id), {}), true)
	var archetype := str(pick.get("archetype", "local"))
	var pos := town.marker_pos(m.id)
	var c := _kit(pos.y).build(archetype, str(pick.get("pose", "")))
	c.set_meta("archetype", archetype)
	var target := town.marker_pos(str(pick.face)) if pick.has("face") and not town.get_marker(str(pick.face)).is_empty() \
		else _bounds_center()
	var dir := Vector3(target.x - pos.x, 0.0, target.z - pos.z)
	if dir.length() > 0.01:
		c.rotation.y = atan2(dir.x, dir.z)
	return c


## One kit per ground height: the kit's dirt gradients are measured from its floor_y.
func _kit(ground_y: float) -> CharacterKit:
	var key := snappedf(ground_y, 0.01)
	if not _kits.has(key):
		_kits[key] = CharacterKit.new(decor.mats, ground_y)
	return _kits[key]


func _bounds_center() -> Vector3:
	var b: Dictionary = town.data.get("bounds", {})
	if b.is_empty():
		return Vector3.ZERO
	return Vector3((float(b.min[0]) + float(b.max[0])) * 0.5, 0.0, (float(b.min[1]) + float(b.max[1])) * 0.5)


static func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


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
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and not lookdev_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and event.keycode >= KEY_1 and event.keycode <= KEY_3:
		var ids := ["golden", "noon", "dusk"]
		set_preset(ids[event.keycode - KEY_1])
