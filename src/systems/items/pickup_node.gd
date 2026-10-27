extends Node3D
## A pickup lying in the world (M13): the item's look from ItemKit, turning slowly
## and bobbing above a soft glow, so it reads as "take me" from across the street.
## It decides nothing: GearController checks reach and takes it.

var pickup: Dictionary = {}     ## the entry from content/core/pickups/<location>.json
var base := Vector3.ZERO        ## resting point on the ground
var reach := 2.0
var _t := 0.0
var _spin := 0.8
var _bob := 0.08
var _lift := 0.75
var _visual: Node3D


func setup(kit: ItemKit, entry: Dictionary, item_cfg: Dictionary, at: Vector3) -> void:
	pickup = entry
	base = at
	reach = float(entry.get("reach", 2.0))
	name = "Pickup_" + str(entry.get("id", "item"))
	var style: Dictionary = kit.pickup_style
	_spin = float(style.get("spin", 0.8))
	_bob = float(style.get("bob", 0.08))
	_lift = float(style.get("lift", 0.75))
	_visual = kit.build(str(item_cfg.get("look", item_cfg.get("id", ""))))
	add_child(_visual)
	position = at
	if bool(entry.get("hidden", false)):
		# A smuggler's drop: sits still in the sand, no glow. You have to look.
		_spin = 0.0
		_bob = 0.0
		_lift = 0.0
		_place()
		return
	var ring := MeshInstance3D.new()
	ring.name = "Glow"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.5
	ring.mesh = torus
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var c := Color(str(style.get("glow", "#d99a2b")))
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 2.0
	ring.material_override = m
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = Vector3(0, 0.03, 0)
	add_child(ring)
	_place()


func in_reach(p: Vector3) -> bool:
	return Vector2(p.x - base.x, p.z - base.z).length() <= reach and absf(p.y - base.y) <= 2.0


func _process(dt: float) -> void:
	_t += dt
	_place()


func _place() -> void:
	if _visual != null:
		_visual.position = Vector3(0, _lift + sin(_t * 2.0) * _bob, 0)
		_visual.rotation.y = _t * _spin
