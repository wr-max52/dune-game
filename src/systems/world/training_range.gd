class_name TrainingRange
extends Node3D
## The practice range in the landing pit (M11). Data: content/core/locations/
## training_range.json.
##
## - Targets: a plate on a post. Shoot or cut them; at 0 hp they tip over and
##   stand back up a few seconds later. Knock all of them down inside the record
##   time and WorldState hears about it (the bar has a standing bet on that).
## - Sparring remote: a hovering drone that fires slow stun bolts at you while
##   your blade is out (and only then), so deflection can be practiced. Bolts
##   you send back knock it around and count.

const BoltScene := preload("res://scenes/entities/bolt.tscn")
const DATA := "res://content/core/locations/training_range.json"

signal target_down(id: String)
signal record_set(seconds: float)

var spec: Dictionary = {}
var player: Node3D
var blade_out: Callable = Callable()      ## () -> bool
var targets: Array = []                   ## RangeTarget nodes
var remote: Node3D
var remote_shots := 0
var remote_hits := 0
var _remote_cd := 2.0
var _chirp_cd := 3.0                      ## issue #16: seconds to the remote's next idle chirp
var _first_down_at := -1.0
var _time := 0.0
var _mats: LookMaterials


func _ready() -> void:
	name = "TrainingRange"
	spec = CharacterKit._read_json(DATA)
	_mats = LookMaterials.new()
	for t in spec.get("targets", []):
		var n := RangeTarget.new()
		n.setup(str(t.id), float(t.get("hp", 30)), float(spec.get("reset_seconds", 4.0)), _mats)
		add_child(n)
		n.global_position = _v3(t.pos)
		n.knocked_down.connect(_on_down.bind(str(t.id)))
		targets.append(n)
	if spec.has("remote"):
		remote = _build_remote()
		add_child(remote)
		remote.global_position = _v3(spec.remote.pos)
		var hum = Sound.loop("droid_hum", remote)   # issue #16: droids sound like droids
		if hum != null:
			hum.autoplay = true


## Is a world position inside the sanctioned range (the pit)?
func contains(p: Vector3) -> bool:
	var z: Dictionary = spec.get("zone", {})
	if z.is_empty():
		return false
	var mn := _v3(z.min)
	var mx := _v3(z.max)
	return p.x >= mn.x and p.x <= mx.x and p.y >= mn.y and p.y <= mx.y and p.z >= mn.z and p.z <= mx.z


func _on_down(id: String) -> void:
	target_down.emit(id)
	if _first_down_at < 0.0 or _time - _first_down_at > float(spec.get("record_seconds", 20.0)):
		_first_down_at = _time
	var all_down := true
	for t in targets:
		if not t.is_down:
			all_down = false
	if all_down:
		var secs := _time - _first_down_at
		if secs <= float(spec.get("record_seconds", 20.0)):
			record_set.emit(secs)
			WorldState.on_range_record(secs)


func _physics_process(dt: float) -> void:
	_time += dt
	if remote == null or player == null:
		return
	var r: Dictionary = spec.remote
	var home := _v3(r.pos)
	# Bob and face the player.
	remote.global_position = home + Vector3(sin(_time * 1.3) * 0.6, sin(_time * 2.1) * 0.25, cos(_time * 0.9) * 0.4)
	var to_p := player.global_position + Vector3(0, 1.2, 0) - remote.global_position
	if to_p.length() > 0.1:
		remote.look_at(remote.global_position + to_p, Vector3.UP)
	var active := to_p.length() <= float(r.get("range", 14.0))
	_chirp_cd -= dt
	if _chirp_cd <= 0.0:
		_chirp_cd = randf_range(4.0, 9.0)
		if to_p.length() <= 20.0:
			Sound.play("droid_beep", remote.global_position)
	if bool(r.get("only_when_blade_out", true)):
		active = active and blade_out.is_valid() and bool(blade_out.call())
	(remote.get_node("Eye") as MeshInstance3D).material_override.emission_energy_multiplier = 4.0 if active else 0.6
	if not active:
		_remote_cd = maxf(_remote_cd, 1.0)
		return
	_remote_cd -= dt
	if _remote_cd <= 0.0:
		_remote_cd = float(r.get("interval", 1.7))
		fire_remote()


func fire_remote() -> Node:
	var r: Dictionary = spec.remote
	var b = BoltScene.instantiate()
	var origin := remote.global_position + (-remote.global_basis.z) * 0.35
	var aim := player.global_position + Vector3(0, 1.25, 0)
	b.direction = (aim - origin).normalized()
	b.speed = float(r.get("bolt_speed", 13.0))
	b.damage = 0.0
	b.range_m = 30.0
	b.shooter = remote.get_node("Hull")
	b.stylize = true
	b.sweep = true
	b.color = Color.html(str(r.get("bolt_color", "#4ad0ff")))
	b.streak_length = 0.5
	add_child(b)
	b.global_position = origin
	remote_shots += 1
	if randf() < 0.35:
		Sound.play("droid_beep", origin)
	return b


func _build_remote() -> Node3D:
	var root := Node3D.new()
	root.name = "SparringRemote"
	var hull := RemoteHull.new()
	hull.name = "Hull"
	hull.range_node = self
	var col := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.28
	col.shape = sh
	hull.add_child(col)
	root.add_child(hull)
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.25
	s.height = 0.5
	m.mesh = s
	m.material_override = _mats.flat(Color("#3a3c40"), 0.45, 0.7)
	root.add_child(m)
	var band := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.24
	tor.outer_radius = 0.3
	band.mesh = tor
	band.material_override = _mats.flat(Color("#b08e50"), 0.4, 0.8)
	root.add_child(band)
	var eye := MeshInstance3D.new()
	eye.name = "Eye"
	var es := SphereMesh.new()
	es.radius = 0.07
	es.height = 0.14
	eye.mesh = es
	var em := _mats.glow(Color("#4ad0ff"))
	eye.material_override = em
	eye.position = Vector3(0, 0, -0.22)
	root.add_child(eye)
	return root


func _on_remote_hit() -> void:
	remote_hits += 1
	Sound.play("droid_beep", remote.global_position)
	var tw := remote.create_tween()
	tw.tween_property(remote, "rotation:z", remote.rotation.z + TAU, 0.5)


static func _v3(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## The remote's shootable hull: a reflected bolt hitting it counts.
class RemoteHull extends StaticBody3D:
	var range_node
	func apply_damage(_amount: float) -> void:
		if range_node != null:
			range_node._on_remote_hit()


## A plate on a post. apply_damage() from bolts and blades.
class RangeTarget extends StaticBody3D:
	signal knocked_down
	var id := ""
	var max_hp := 30.0
	var hp := 30.0
	var is_down := false
	var reset_after := 4.0
	var hits := 0
	var _down_left := 0.0
	var _pivot: Node3D
	var _plate: MeshInstance3D
	var _wobble := 0.0

	func setup(tid: String, hp_max: float, reset_s: float, mats: LookMaterials) -> void:
		id = tid
		name = "Target_" + tid
		max_hp = hp_max
		hp = hp_max
		reset_after = reset_s
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.8, 1.9, 0.3)
		col.shape = box
		col.position = Vector3(0, 0.95, 0)
		add_child(col)
		_pivot = Node3D.new()
		add_child(_pivot)
		var post := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.04
		pm.bottom_radius = 0.05
		pm.height = 1.2
		post.mesh = pm
		post.position = Vector3(0, 0.6, 0)
		post.material_override = mats.flat(Color("#4a3a2c"), 0.8)
		_pivot.add_child(post)
		_plate = MeshInstance3D.new()
		var plate := CylinderMesh.new()
		plate.top_radius = 0.38
		plate.bottom_radius = 0.38
		plate.height = 0.05
		_plate.mesh = plate
		_plate.rotation_degrees = Vector3(90, 0, 0)
		_plate.position = Vector3(0, 1.45, 0)
		_plate.material_override = mats.flat(Color("#c9b896"), 0.85)
		_pivot.add_child(_plate)
		var ring := MeshInstance3D.new()
		var rm := CylinderMesh.new()
		rm.top_radius = 0.17
		rm.bottom_radius = 0.17
		rm.height = 0.06
		ring.mesh = rm
		ring.rotation_degrees = Vector3(90, 0, 0)
		ring.position = Vector3(0, 1.45, 0)
		ring.material_override = mats.flat(Color("#a8322a"), 0.8)
		_pivot.add_child(ring)
		var base := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.5, 0.1, 0.5)
		base.mesh = bm
		base.position = Vector3(0, 0.05, 0)
		base.material_override = mats.flat(Color("#3a3634"), 0.7, 0.4)
		add_child(base)

	func apply_damage(amount: float) -> void:
		if is_down:
			return
		hits += 1
		hp -= amount
		_wobble = 1.0
		if hp <= 0.0:
			is_down = true
			_down_left = reset_after
			knocked_down.emit()

	func _physics_process(dt: float) -> void:
		if is_down:
			_pivot.rotation.x = move_toward(_pivot.rotation.x, -PI * 0.47, dt * 6.0)
			_down_left -= dt
			if _down_left <= 0.0:
				is_down = false
				hp = max_hp
		else:
			_pivot.rotation.x = move_toward(_pivot.rotation.x, 0.0, dt * 3.0)
			_wobble = maxf(0.0, _wobble - dt * 3.0)
			_pivot.rotation.z = sin(_wobble * 30.0) * 0.12 * _wobble
