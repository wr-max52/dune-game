class_name ShipKit
extends RefCounted
## Starfighter looks (M10). Builds the visible ship for a "look" id. Gameplay never
## touches this: the flight model, guns and AI read content/core/ships/*.json; this
## kit reads content/look/ships.json and only decides what the ship looks like.
##
## Two ways to get a design on screen, both data-only:
##   1. A real model: set the look's "scene" to a .tscn or .glb path. The kit
##      instantiates it as-is (forward = -Z, 1 unit = 1 metre).
##   2. A stand-in: leave "scene" empty and pick a "frame" ("dart", "blade",
##      "hauler"). Sizes and colours come from the look entry, shapes from here.
##
## Every built ship has the same contract, so the scene code never cares which path
## made it: a root Node3D named after the look, with meta "look_id", and an
## "Engines" child holding the engine glows (empty for a model that brings its own).
##
## Design rules (docs/ART_DIRECTION.md, Ships): silhouette first; the smuggler side
## is warm, worn and asymmetric-friendly; the remnant side is dark plate with oxblood
## trim and amber glass, the same language as the remnant trooper.

const LOOKS_PATH := "res://content/look/ships.json"
const FALLBACK_FRAME := "dart"

var mats: LookMaterials
var looks: Dictionary = {}
var bolts: Dictionary = {}


func _init(materials: LookMaterials = null, looks_override: Dictionary = {}) -> void:
	mats = materials if materials != null else LookMaterials.new()
	var data := looks_override if not looks_override.is_empty() else _read_json(LOOKS_PATH)
	looks = data.get("looks", {})
	bolts = data.get("bolts", {})


static func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func look_ids() -> Array:
	return looks.keys()


func has_look(look_id: String) -> bool:
	return looks.has(look_id)


## Build the ship for a look id. Unknown ids get the fallback stand-in so a missing
## look is visible in game instead of an invisible ship.
func build(look_id: String) -> Node3D:
	var p: Dictionary = looks.get(look_id, {})
	if p.is_empty():
		push_warning("ShipKit: unknown look id: ", look_id)
	var root := Node3D.new()
	root.name = look_id.to_pascal_case() if look_id != "" else "Ship"
	root.set_meta("look_id", look_id)
	var engines := Node3D.new()
	engines.name = "Engines"
	var scene_path := str(p.get("scene", ""))
	var model := _load_model(scene_path)
	if model != null:
		model.name = "Model"
		root.add_child(model)
		root.add_child(engines)
		root.set_meta("source", "scene")
		return root
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	root.add_child(engines)
	match str(p.get("frame", FALLBACK_FRAME)):
		"blade":
			_blade(body, engines, p)
		"hauler":
			_hauler(body, engines, p)
		_:
			_dart(body, engines, p)
	root.set_meta("source", "kit")
	return root


func _load_model(path: String) -> Node3D:
	if path == "" or not ResourceLoader.exists(path):
		if path != "":
			push_warning("ShipKit: model not found, using stand-in: ", path)
		return null
	var res = load(path)
	if res is PackedScene:
		var inst = res.instantiate()
		if inst is Node3D:
			return inst
		if inst != null:
			inst.free()
	push_warning("ShipKit: not a 3D scene, using stand-in: ", path)
	return null


## A bolt or seeker for the projectile field. `style` is "player", "hostile" or
## "missile" (keys of "bolts" in ships.json). The returned pivot's -Z is the
## direction of travel, so the scene can aim it with Basis.looking_at(velocity).
func build_bolt(style: String) -> Node3D:
	var b: Dictionary = bolts.get(style, {})
	var col := Color(str(b.get("color", "#ffffff")))
	var pivot := Node3D.new()
	pivot.name = "Bolt"
	var cyl := CylinderMesh.new()
	var w := float(b.get("width", 0.2))
	cyl.top_radius = w
	cyl.bottom_radius = w
	cyl.height = float(b.get("length", 5.0))
	cyl.radial_segments = 6
	cyl.rings = 1
	var mi := _mi(pivot, cyl, _glow(col, 6.0), Vector3.ZERO, TIP_FORWARD, Vector3.ONE, "Glow")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return pivot


# ------------------------------------------------------------------ materials

func _c(p: Dictionary, key: String, fallback: String) -> Color:
	return Color(str(p.get(key, fallback)))


func _plate(color: Color) -> StandardMaterial3D:
	return mats.flat(color, 0.55, 0.35)


func _glass(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color.darkened(0.4)
	m.metallic = 0.6
	m.roughness = 0.15
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 0.6
	return m


func _glow(color: Color, energy: float = 4.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


# ------------------------------------------------------------------ helpers

func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO,
		scl: Vector3 = Vector3.ONE, nname: String = "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	if nname != "":
		mi.name = nname
	parent.add_child(mi)
	return mi


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _cyl(top: float, bottom: float, h: float, seg: int = 12) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 16
	s.rings = 8
	return s


func _prism(size: Vector3) -> PrismMesh:
	var pm := PrismMesh.new()
	pm.size = size
	return pm


## Engine glow disc facing +Z (the exhaust side).
func _engine(engines: Node3D, color: Color, pos: Vector3, r: float) -> void:
	var mi := _mi(engines, _cyl(r, r, 0.12, 14), _glow(color, 5.0), pos, Vector3(PI * 0.5, 0, 0))
	mi.name = "Glow%d" % engines.get_child_count()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


const ALONG_Z := Vector3(PI * 0.5, 0.0, 0.0)      # cylinder axis -> +/-Z
const TIP_FORWARD := Vector3(-PI * 0.5, 0.0, 0.0)  # cylinder top -> -Z
const FIN := Vector3(0.0, PI * 0.5, 0.0)            # prism profile in the side plane


# ------------------------------------------------------------------ frames

## "dart": the smuggler-side interceptor. Long nose, swept wings with tip guns,
## twin engines, one dorsal fin. Reads as a forward arrow at any range.
func _dart(body: Node3D, engines: Node3D, p: Dictionary) -> void:
	var L := float(p.get("length", 9.0))
	var S := float(p.get("span", 7.6))
	var H := float(p.get("height", 1.6))
	var hull := _plate(_c(p, "hull", "#c9c2b4"))
	var trim := _plate(_c(p, "trim", "#d99a2b"))
	var dark := _plate(_c(p, "dark", "#2a2c33"))
	var eng := _c(p, "engine", "#8fd8ff")
	var r := H * 0.36

	_mi(body, _cyl(r, r * 1.15, L * 0.62), hull, Vector3(0, 0, L * 0.08), ALONG_Z, Vector3.ONE, "Fuselage")
	_mi(body, _cyl(0.0, r, L * 0.32, 12), hull, Vector3(0, 0, -L * 0.39), TIP_FORWARD, Vector3.ONE, "Nose")
	_mi(body, _sphere(r * 0.95), _glass(_c(p, "canopy", "#1f7a78")),
		Vector3(0, r * 0.75, -L * 0.12), Vector3.ZERO, Vector3(0.8, 0.6, 1.9), "Canopy")
	for side in [-1.0, 1.0]:
		var wing := _mi(body, _box(Vector3(S * 0.46, 0.14, L * 0.3)), hull,
			Vector3(side * S * 0.25, -r * 0.2, L * 0.14), Vector3(0, -side * 0.38, 0), Vector3.ONE,
			"Wing" + ("L" if side < 0 else "R"))
		_mi(wing, _box(Vector3(S * 0.18, 0.16, L * 0.05)), trim, Vector3(side * S * 0.08, 0.01, -L * 0.07))
		_mi(body, _cyl(0.12, 0.12, L * 0.42, 8), dark, Vector3(side * S * 0.47, -r * 0.2, -L * 0.02), ALONG_Z)
		_mi(body, _cyl(r * 0.55, r * 0.6, L * 0.34), dark, Vector3(side * r * 1.25, -r * 0.1, L * 0.3), ALONG_Z)
		_engine(engines, eng, Vector3(side * r * 1.25, -r * 0.1, L * 0.475), r * 0.46)
	_mi(body, _prism(Vector3(L * 0.26, H * 0.9, 0.12)), hull, Vector3(0, r + H * 0.4, L * 0.32),
		FIN, Vector3.ONE, "Fin")
	_mi(body, _box(Vector3(r * 0.5, 0.06, L * 0.5)), trim, Vector3(0, r * 1.02, L * 0.05))


## "blade": the remnant fighter. A dark armoured pod with forward-swept, drooping
## blade wings and a tall dorsal spine -- a hunched predator silhouette.
func _blade(body: Node3D, engines: Node3D, p: Dictionary) -> void:
	var L := float(p.get("length", 5.0))
	var S := float(p.get("span", 6.0))
	var H := float(p.get("height", 4.2))
	var hull := _plate(_c(p, "hull", "#3d4147"))
	var trim := _plate(_c(p, "trim", "#6b1e1e"))
	var dark := _plate(_c(p, "dark", "#1e1c1c"))
	var r := L * 0.24

	_mi(body, _sphere(r), hull, Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 0.85, 1.5), "Pod")
	_mi(body, _cyl(r * 0.5, r * 0.62, 0.2, 10), _glass(_c(p, "canopy", "#ffae4a")),
		Vector3(0, r * 0.12, -r * 1.42), ALONG_Z, Vector3.ONE, "Eye")
	_mi(body, _cyl(r * 0.66, r * 0.66, 0.08, 10), trim, Vector3(0, r * 0.12, -r * 1.34), ALONG_Z)
	for side in [-1.0, 1.0]:
		var wing := _mi(body, _box(Vector3(S * 0.46, 0.12, L * 0.42)), hull,
			Vector3(side * S * 0.26, -r * 0.35, -L * 0.04), Vector3(0, side * 0.5, -side * 0.38), Vector3.ONE,
			"Wing" + ("L" if side < 0 else "R"))
		_mi(wing, _box(Vector3(S * 0.46, 0.14, L * 0.06)), trim, Vector3(0, 0.01, -L * 0.2))
		_mi(body, _cyl(0.09, 0.09, L * 0.3, 6), dark, Vector3(side * r * 0.45, -r * 0.55, -L * 0.3), ALONG_Z)
	_mi(body, _prism(Vector3(L * 0.62, H * 0.55, 0.14)), dark, Vector3(0, r * 0.8 + H * 0.2, L * 0.08),
		FIN, Vector3.ONE, "Spine")
	_mi(body, _cyl(r * 0.45, r * 0.55, L * 0.18), dark, Vector3(0, 0, r * 1.45), ALONG_Z)
	_engine(engines, _c(p, "engine", "#ff7a4a"), Vector3(0, 0, r * 1.56), r * 0.38)


## "hauler": the remnant heavy fighter. A wide armoured block with a wedge prow,
## two engine nacelles on stub wings and a third engine on the spine.
func _hauler(body: Node3D, engines: Node3D, p: Dictionary) -> void:
	var L := float(p.get("length", 12.0))
	var S := float(p.get("span", 8.4))
	var H := float(p.get("height", 2.6))
	var hull := _plate(_c(p, "hull", "#4b4f55"))
	var trim := _plate(_c(p, "trim", "#a8844a"))
	var dark := _plate(_c(p, "dark", "#1e1c1c"))
	var eng := _c(p, "engine", "#ff7a4a")

	_mi(body, _box(Vector3(S * 0.42, H, L * 0.62)), hull, Vector3(0, 0, L * 0.06), Vector3.ZERO, Vector3.ONE, "Hull")
	_mi(body, _prism(Vector3(S * 0.42, L * 0.3, H)), hull, Vector3(0, 0, -L * 0.4), TIP_FORWARD,
		Vector3.ONE, "Prow")
	_mi(body, _box(Vector3(S * 0.18, H * 0.3, L * 0.08)), _glass(_c(p, "canopy", "#ffae4a")),
		Vector3(0, H * 0.48, -L * 0.2), Vector3(-0.3, 0, 0), Vector3.ONE, "Bridge")
	_mi(body, _box(Vector3(S * 0.43, H * 0.14, L * 0.04)), trim, Vector3(0, H * 0.2, -L * 0.1))
	for side in [-1.0, 1.0]:
		_mi(body, _box(Vector3(S * 0.22, H * 0.22, L * 0.22)), dark, Vector3(side * S * 0.3, 0, L * 0.12))
		_mi(body, _cyl(H * 0.42, H * 0.46, L * 0.6), hull, Vector3(side * S * 0.42, 0, L * 0.04), ALONG_Z,
			Vector3.ONE, "Nacelle" + ("L" if side < 0 else "R"))
		_mi(body, _cyl(H * 0.47, H * 0.47, L * 0.05), trim, Vector3(side * S * 0.42, 0, -L * 0.18), ALONG_Z)
		_engine(engines, eng, Vector3(side * S * 0.42, 0, L * 0.345), H * 0.34)
	_mi(body, _box(Vector3(S * 0.12, H * 0.5, L * 0.3)), dark, Vector3(0, H * 0.7, L * 0.2))
	_engine(engines, eng, Vector3(0, H * 0.7, L * 0.355), H * 0.2)
