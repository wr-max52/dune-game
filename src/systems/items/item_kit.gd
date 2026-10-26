class_name ItemKit
extends RefCounted
## Item looks (M13). Builds the visible item for a "look" id: the same model is
## worn on the body and lies in the world as a pickup. Gameplay never touches this:
## the inventory and the jetpack read content/core/items/*.json; this kit reads
## content/look/items.json and only decides what the item looks like.
##
## Two ways to get a design on screen, both data-only (the ShipKit pattern):
##   1. A real model: set the look's "scene" to a .tscn or .glb path (the wearer's
##      back is -Z, 1 unit = 1 metre). The kit mounts it as-is.
##   2. A stand-in: leave "scene" empty and pick a "frame" ("twin_tank"). Sizes and
##      colours come from the look entry, shapes from here.
##
## Every built item has the same contract: a root Node3D named after the look, meta
## "look_id" and "source" ("scene" or "kit"), and a "Flames" child holding the
## thrust flames (hidden until set_flames()). A model can bring its own "Flames".

const LOOKS_PATH := "res://content/look/items.json"
const FALLBACK_FRAME := "twin_tank"

var mats: LookMaterials
var looks: Dictionary = {}
var pickup_style: Dictionary = {}


func _init(materials: LookMaterials = null, looks_override: Dictionary = {}) -> void:
	mats = materials if materials != null else LookMaterials.new()
	var data := looks_override if not looks_override.is_empty() else _read_json(LOOKS_PATH)
	looks = data.get("looks", {})
	pickup_style = data.get("pickup", {})


static func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func has_look(look_id: String) -> bool:
	return looks.has(look_id)


func look(look_id: String) -> Dictionary:
	return looks.get(look_id, {})


## Where a worn item sits on the chest joint.
func on_back_transform(look_id: String) -> Transform3D:
	var b: Dictionary = look(look_id).get("on_back", {})
	var p: Array = b.get("pos", [0, 0, -0.2])
	var r: Array = b.get("rot", [0, 0, 0])
	var basis := Basis.from_euler(Vector3(deg_to_rad(float(r[0])), deg_to_rad(float(r[1])), deg_to_rad(float(r[2]))))
	return Transform3D(basis, Vector3(float(p[0]), float(p[1]), float(p[2])))


## Build the item for a look id. Unknown ids get the fallback stand-in so a missing
## look is visible in game instead of invisible.
func build(look_id: String) -> Node3D:
	var p := look(look_id)
	if p.is_empty():
		push_warning("ItemKit: unknown look id: ", look_id)
	var root := Node3D.new()
	root.name = look_id.to_pascal_case() if look_id != "" else "Item"
	root.set_meta("look_id", look_id)
	var model := _load_model(str(p.get("scene", "")))
	if model != null:
		model.name = "Model"
		root.add_child(model)
		if model.get_node_or_null("Flames") == null:
			var f := Node3D.new()
			f.name = "Flames"
			root.add_child(f)
		root.set_meta("source", "scene")
		set_flames(root, false)
		return root
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	var flames := Node3D.new()
	flames.name = "Flames"
	root.add_child(flames)
	match str(p.get("frame", FALLBACK_FRAME)):
		_:
			_twin_tank(body, flames, p)
	root.set_meta("source", "kit")
	set_flames(root, false)
	return root


## Show or hide the thrust flames; `power` 0..1 scales their length.
static func set_flames(item: Node3D, on: bool, power: float = 1.0) -> void:
	var f := item.get_node_or_null("Flames")
	if f == null:
		f = item.find_child("Flames", true, false)
	if f == null:
		return
	f.visible = on
	if on:
		(f as Node3D).scale = Vector3(1.0, clampf(power, 0.2, 1.4), 1.0)


func _load_model(path: String) -> Node3D:
	if path == "" or not ResourceLoader.exists(path):
		if path != "":
			push_warning("ItemKit: model not found, using stand-in: ", path)
		return null
	var res = load(path)
	if res is PackedScene:
		var inst = res.instantiate()
		if inst is Node3D:
			return inst
		if inst != null:
			inst.free()
	push_warning("ItemKit: not a 3D scene, using stand-in: ", path)
	return null


# ------------------------------------------------------------------ helpers

func _c(p: Dictionary, key: String, fallback: String) -> Color:
	return Color(str(p.get(key, fallback)))


func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO,
		nname: String = "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	if nname != "":
		mi.name = nname
	parent.add_child(mi)
	return mi


func _cyl(top: float, bottom: float, h: float, seg: int = 14) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 14
	s.rings = 7
	return s


func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


# ------------------------------------------------------------------ frames

## "twin_tank": two upright fuel tanks on a back plate with straps, a trim band,
## and a downward nozzle under each tank. Flames hang below the nozzles. The back
## plate is at z = 0 (against the wearer), the tanks sit behind it (-Z).
func _twin_tank(body: Node3D, flames: Node3D, p: Dictionary) -> void:
	var h := float(p.get("height", 0.52))
	var r := float(p.get("tank_radius", 0.085))
	var spread := float(p.get("spread", 0.2))
	var metal := mats.flat(_c(p, "metal", "#8c8478"), 0.45, 0.55)
	var trim := mats.flat(_c(p, "trim", "#d99a2b"), 0.6, 0.2)
	var dark := mats.flat(_c(p, "dark", "#2a2622"), 0.8, 0.2)
	var strap := mats.flat(_c(p, "strap", "#5a3a24"), 0.9, 0.0)
	var nozzle := mats.flat(_c(p, "nozzle", "#3a3632"), 0.5, 0.6)
	var flame := _glow(_c(p, "flame", "#ff8a2a"), 1.6)
	var core := _glow(_c(p, "flame_core", "#ffd9a0"), 2.6)

	_mi(body, _box(Vector3(spread * 1.6, h * 0.9, 0.04)), dark, Vector3(0, 0, -0.02), Vector3.ZERO, "Plate")
	for side in [-1.0, 1.0]:
		var x: float = side * spread * 0.5
		var z := -0.04 - r
		_mi(body, _cyl(r, r, h * 0.8), metal, Vector3(x, 0, z), Vector3.ZERO, "Tank" + ("L" if side > 0 else "R"))
		_mi(body, _sphere(r), metal, Vector3(x, h * 0.4, z))
		_mi(body, _cyl(r * 1.04, r * 1.04, h * 0.08), trim, Vector3(x, h * 0.18, z))
		_mi(body, _cyl(r * 0.55, r * 0.8, h * 0.14), nozzle, Vector3(x, -h * 0.47, z), Vector3.ZERO, "Nozzle")
		# Flames: an outer cone and a hot core from the nozzle, raked back away from
		# the wearer (-Z) so a long coat does not swallow them.
		var fl := Node3D.new()
		fl.position = Vector3(x, -h * 0.54, z)
		fl.rotation.x = float(p.get("flame_rake", 0.35))
		flames.add_child(fl)
		var fh := h * float(p.get("flame_length", 1.3))
		var outer := _mi(fl, _cyl(r * 0.85, 0.0, fh, 10), flame, Vector3(0, -fh * 0.5, 0))
		var inner := _mi(fl, _cyl(r * 0.45, 0.0, fh * 0.6, 8), core, Vector3(0, -fh * 0.3, 0))
		for m in [outer, inner]:
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Harness straps rising off the top of the plate toward the shoulders.
		_mi(body, _box(Vector3(0.045, 0.02, 0.16)), strap, Vector3(side * spread * 0.45, h * 0.45, 0.06),
			Vector3(-0.35, 0, 0))
	_mi(body, _box(Vector3(spread * 1.2, 0.05, 0.08)), trim, Vector3(0, h * 0.3, -0.06), Vector3.ZERO, "Bar")
	_mi(body, _box(Vector3(spread * 1.7, 0.06, 0.05)), strap, Vector3(0, -h * 0.38, -0.01), Vector3.ZERO, "Belt")
