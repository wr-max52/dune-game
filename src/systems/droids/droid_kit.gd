class_name DroidKit
extends RefCounted
## Droid looks. Issue #25: each kind's "look" in content/core/droids/droids.json
## names a Hyper3D model (assets/gear/, prepped by tools/look/prep_gear.gd), tinted
## by the variant's body colour, with glowing eyes and a muzzle placed from data.
## Without a model (or if it is missing) the issue #51 primitives stand in.
##
## Every look is a Node3D whose origin sits on the ground, facing -Z, with:
##   "Model"  the part that tips over (a wreck lies down) or spins
##   "Eye*"   glowing meshes (brightness shows whether it is awake)
##   "Muzzle" where bolts leave (assassin only)

static func build(kind: String, variant: Dictionary, mats: LookMaterials, look: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = "Droid_" + kind
	var model := Node3D.new()
	model.name = "Model"
	root.add_child(model)
	var body := Color(str(variant.get("body", "#808080")))
	var trim := Color(str(variant.get("trim", "#404040")))
	var eye := Color(str(variant.get("eye", "#4ad0ff")))
	if _from_model(model, look, body, eye, mats):
		root.set_meta("source", "model")
		return root
	root.set_meta("source", "kit")
	match kind:
		"floating":
			_floating(model, body, trim, eye, mats)
		"cargo":
			_cargo(model, body, trim, eye, mats)
		"assassin":
			_assassin(model, body, trim, eye, mats)
	return root


## The kind's model, tinted toward the body colour (look.tint: 0 = as generated,
## 1 = full body colour), with an "Eye" per look.eyes entry and a "Muzzle" at
## look.muzzle. False when there is no model to load.
static func _from_model(model: Node3D, look: Dictionary, body: Color, eye: Color, mats: LookMaterials) -> bool:
	var path := str(look.get("model", ""))
	if path == "" or not ResourceLoader.exists(path):
		return false
	var scene = load(path)
	if not (scene is PackedScene):
		return false
	var n: Node3D = (scene as PackedScene).instantiate()
	model.add_child(n)
	var k := float(look.get("tint", 0.8))
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if src == null:
				continue
			var m := src.duplicate() as BaseMaterial3D
			m.albedo_color = Color.WHITE.lerp(body, k)
			mi.set_surface_override_material(s, m)
	_animations(n, look)
	var r := float(look.get("eye_radius", 0.04))
	var i := 0
	for e in look.get("eyes", []):
		_mesh(model, _ball(r), mats.glow(eye), Vector3(float(e[0]), float(e[1]), float(e[2])), Vector3.ZERO, "Eye" if i == 0 else "Eye%d" % (i + 1))
		i += 1
	if look.has("muzzle"):
		var mz := Node3D.new()
		mz.name = "Muzzle"
		var a: Array = look.muzzle
		mz.position = Vector3(float(a[0]), float(a[1]), float(a[2]))
		model.add_child(mz)
	# A carried weapon (look.carry: scene, pos, rot_deg, scale, muzzle): placed in
	# model space for the rest pose, then pinned to its bone below. Its muzzle is
	# the droid's.
	var carry: Dictionary = look.get("carry", {})
	if not carry.is_empty() and ResourceLoader.exists(str(carry.get("scene", ""))):
		var w: Node3D = (load(str(carry.scene)) as PackedScene).instantiate()
		w.name = "Carry"
		var cp: Array = carry.get("pos", [0, 0, 0])
		var cr: Array = carry.get("rot_deg", [0, 0, 0])
		w.position = Vector3(float(cp[0]), float(cp[1]), float(cp[2]))
		w.rotation_degrees = Vector3(float(cr[0]), float(cr[1]), float(cr[2]))
		w.scale = Vector3.ONE * float(carry.get("scale", 1.0))
		model.add_child(w)
		var old := model.get_node_or_null("Muzzle")
		if old != null:
			old.free()
		var mz := Node3D.new()
		mz.name = "Muzzle"
		var cm: Array = carry.get("muzzle", [0, 0, 0.2])
		mz.position = Vector3(float(cm[0]), float(cm[1]), float(cm[2]))
		w.add_child(mz)
	# A rig carries its eyes on the head bone and its weapon on the hand, so they
	# move with the clips (look.eye_bone, look.carry.bone).
	var sk := n.find_child("Skeleton3D", true, false) as Skeleton3D
	if sk != null:
		for c in model.get_children():
			var bone := ""
			if str(c.name).begins_with("Eye"):
				bone = str(look.get("eye_bone", ""))
			elif c.name == "Muzzle":
				bone = str(look.get("muzzle_bone", ""))
			elif c.name == "Carry":
				bone = str(carry.get("bone", ""))
			if bone != "" and sk.find_bone(bone) >= 0:
				_pin_to_bone(c as Node3D, model, sk, bone)
		# carry.bone_local { pos, rot_deg, scale }: the weapon's place in the bone's own
		# frame, solved so it sits level and forward in the clips (tools: see DECISIONS).
		var w := model.find_child("Carry", true, false) as Node3D
		var bl: Dictionary = carry.get("bone_local", {})
		if w != null and not bl.is_empty():
			var bp: Array = bl.get("pos", [0, 0, 0])
			var br: Array = bl.get("rot_deg", [0, 0, 0])
			w.position = Vector3(float(bp[0]), float(bp[1]), float(bp[2]))
			w.rotation_degrees = Vector3(float(br[0]), float(br[1]), float(br[2]))
			w.scale = Vector3.ONE * float(bl.get("scale", 1.0))
	return true


## Move `node` (a child of `model`) under a BoneAttachment3D on `bone`, keeping
## where it sits in the rest pose.
static func _pin_to_bone(node: Node3D, model: Node3D, sk: Skeleton3D, bone: String) -> void:
	var att := sk.get_node_or_null("At_" + bone) as BoneAttachment3D
	if att == null:
		att = BoneAttachment3D.new()
		att.name = "At_" + bone
		att.bone_name = bone
		sk.add_child(att)
	var sk_in_model := Transform3D.IDENTITY
	var p: Node = sk
	while p != model and p != null:
		sk_in_model = (p as Node3D).transform * sk_in_model
		p = p.get_parent()
	# Where the bone was when the mesh was modelled (the skin's bind pose), not the
	# skeleton's rest (a T-pose): what is placed in model space lines up with the mesh.
	var bone_in_skel := sk.get_bone_global_rest(sk.find_bone(bone))
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mi.skin == null:
			continue
		for b in mi.skin.get_bind_count():
			if mi.skin.get_bind_name(b) == bone or mi.skin.get_bind_bone(b) == sk.find_bone(bone):
				bone_in_skel = mi.skin.get_bind_pose(b).affine_inverse()
		break
	var bone_in_model := sk_in_model * bone_in_skel
	var at := bone_in_model.affine_inverse() * node.transform
	model.remove_child(node)
	att.add_child(node)
	node.transform = at


## A rigged model (the assassin): its clips from look.anims { idle, walk, run, die }
## loop (all but die), and the AnimationPlayer is kept as the root's "anim" meta
## for play_anim(). Starts idle.
static func _animations(model: Node, look: Dictionary) -> void:
	var names: Dictionary = look.get("anims", {})
	var ap := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap == null or names.is_empty():
		return
	var root_bone := str(look.get("root_bone", "Hips"))
	for key in names:
		var a := ap.get_animation(str(names[key]))
		if a == null or key == "die":
			continue
		a.loop_mode = Animation.LOOP_LINEAR
		# In place: the game moves the droid, so the root bone keeps only its bob.
		for t in a.get_track_count():
			if a.track_get_type(t) == Animation.TYPE_POSITION_3D \
					and str(a.track_get_path(t)).ends_with(":" + root_bone) and a.track_get_key_count(t) > 0:
				var p0: Vector3 = a.track_get_key_value(t, 0)
				for k in a.track_get_key_count(t):
					var v: Vector3 = a.track_get_key_value(t, k)
					a.track_set_key_value(t, k, Vector3(p0.x, v.y, p0.z))
	model.set_meta("anim", ap)
	model.set_meta("anims", names)
	ap.play(str(names.get("idle", "")))


## Play a look's clip by role ("idle", "walk", "run", "die") at `speed`. False when
## the look has no rig (the caller falls back to its old wobble).
static func play_anim(look: Node3D, role: String, speed := 1.0, blend := 0.2) -> bool:
	var holder: Node = null
	for n in look.find_children("*", "Node3D", true, false):
		if n.has_meta("anim"):
			holder = n
			break
	if holder == null:
		return false
	var ap: AnimationPlayer = holder.get_meta("anim")
	var clip := str((holder.get_meta("anims") as Dictionary).get(role, ""))
	if clip == "" or not ap.has_animation(clip):
		return false
	if ap.current_animation != clip:
		ap.play(clip, blend)
	ap.speed_scale = speed
	return true


## Issue #64: hold one frame of a clip, still (a droid in a fight stands in its
## ready stance instead of running the idle's shuffle). look.anims[role] at
## `at` seconds. False when the look has no rig or no such clip.
static func hold_pose(look: Node3D, role: String, at := 0.0, blend := 0.2) -> bool:
	var holder: Node = null
	for n in look.find_children("*", "Node3D", true, false):
		if n.has_meta("anim"):
			holder = n
			break
	if holder == null:
		return false
	var ap: AnimationPlayer = holder.get_meta("anim")
	var clip := str((holder.get_meta("anims") as Dictionary).get(role, ""))
	if clip == "" or not ap.has_animation(clip):
		return false
	if ap.current_animation != clip or ap.speed_scale != 0.0:
		ap.play(clip, blend)
		ap.seek(at, true)
	ap.speed_scale = 0.0
	return true


## Jump the current clip to its last frame (a wreck that has lain there for days).
static func finish_anim(look: Node3D) -> void:
	for n in look.find_children("*", "Node3D", true, false):
		if n.has_meta("anim"):
			var ap: AnimationPlayer = n.get_meta("anim")
			if ap.current_animation != "":
				ap.seek(ap.current_animation_length, true)
			return


## All the glowing eyes under a look.
static func eyes(root: Node) -> Array:
	var out := []
	for c in root.find_children("Eye*", "MeshInstance3D", true, false):
		out.append(c)
	return out


static func set_awake(root: Node, awake: bool) -> void:
	for e in eyes(root):
		var m := (e as MeshInstance3D).material_override as StandardMaterial3D
		if m != null:
			m.emission_energy_multiplier = 4.0 if awake else 0.15


static func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot_deg := Vector3.ZERO, nm := "") -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.rotation_degrees = rot_deg
	if nm != "":
		m.name = nm
	parent.add_child(m)
	return m


static func _box(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	return b


static func _ball(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	return s


static func _rod(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 8
	return c


## A hovering ball with a band and one eye (the range remote's shape).
static func _floating(m: Node3D, body: Color, trim: Color, eye: Color, mats: LookMaterials) -> void:
	_mesh(m, _ball(0.25), mats.flat(body, 0.45, 0.7))
	var tor := TorusMesh.new()
	tor.inner_radius = 0.24
	tor.outer_radius = 0.3
	_mesh(m, tor, mats.flat(trim, 0.4, 0.8))
	_mesh(m, _ball(0.07), mats.glow(eye), Vector3(0, 0, -0.22), Vector3.ZERO, "Eye")


## A small box on four wheels with a lid seam and one eye.
static func _cargo(m: Node3D, body: Color, trim: Color, eye: Color, mats: LookMaterials) -> void:
	var b := mats.flat(body, 0.7, 0.3)
	var t := mats.flat(trim, 0.6, 0.5)
	_mesh(m, _box(0.6, 0.48, 0.7), b, Vector3(0, 0.42, 0))
	_mesh(m, _box(0.64, 0.05, 0.74), t, Vector3(0, 0.67, 0))
	_mesh(m, _box(0.5, 0.18, 0.04), t, Vector3(0, 0.45, -0.36))
	for x in [-0.32, 0.32]:
		for z in [-0.24, 0.24]:
			_mesh(m, _rod(0.12, 0.08), t, Vector3(x, 0.12, z), Vector3(0, 0, 90), "Wheel")
	_mesh(m, _ball(0.05), mats.glow(eye), Vector3(0, 0.58, -0.36), Vector3.ZERO, "Eye")


## Tall, thin and skeletal: rod limbs, a ribbed narrow chest, a skull with two eyes,
## and a pistol in the right hand.
static func _assassin(m: Node3D, body: Color, trim: Color, eye: Color, mats: LookMaterials) -> void:
	var b := mats.flat(body, 0.5, 0.6)
	var t := mats.flat(trim, 0.5, 0.7)
	for x in [-0.12, 0.12]:
		_mesh(m, _rod(0.035, 0.6), b, Vector3(x, 0.3, 0))          # shin
		_mesh(m, _ball(0.05), t, Vector3(x, 0.6, 0))               # knee
		_mesh(m, _rod(0.04, 0.55), b, Vector3(x, 0.88, 0))         # thigh
		_mesh(m, _box(0.08, 0.04, 0.2), t, Vector3(x, 0.02, -0.05))  # foot
	_mesh(m, _box(0.3, 0.08, 0.14), t, Vector3(0, 1.17, 0))        # pelvis
	_mesh(m, _rod(0.035, 0.42), b, Vector3(0, 1.4, 0))             # spine
	for i in 4:
		_mesh(m, _box(0.32 - i * 0.03, 0.035, 0.16), b, Vector3(0, 1.48 + i * 0.08, 0))  # ribs
	_mesh(m, _box(0.5, 0.06, 0.12), t, Vector3(0, 1.82, 0))        # shoulders
	_mesh(m, _rod(0.025, 0.14), b, Vector3(0, 1.9, 0))             # neck
	_mesh(m, _box(0.18, 0.24, 0.22), b, Vector3(0, 2.08, 0), Vector3.ZERO, "Head")
	for x in [-0.045, 0.045]:
		_mesh(m, _ball(0.025), mats.glow(eye), Vector3(x, 2.1, -0.115), Vector3.ZERO, "Eye")
	# Left arm hangs; the right one is raised to aim the pistol forward.
	_mesh(m, _rod(0.03, 0.75), b, Vector3(-0.27, 1.45, 0))
	var arm := Node3D.new()
	arm.name = "GunArm"
	arm.position = Vector3(0.27, 1.8, 0)
	m.add_child(arm)
	_mesh(arm, _rod(0.03, 0.62), b, Vector3(0, 0, -0.31), Vector3(90, 0, 0))
	_mesh(arm, _box(0.05, 0.12, 0.26), t, Vector3(0, 0.02, -0.68))  # pistol
	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0, 0.04, -0.84)
	arm.add_child(muzzle)
