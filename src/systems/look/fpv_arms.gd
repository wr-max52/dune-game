class_name FpvArms
extends RefCounted
## First person arms (issue #65 D): a black sleeve and glove per side, built over
## the kit's elbow and wrist joints so the two-bone IK still drives them.
##
## - The kit's own forearm and hand are heroic primitives, and a skinned body is one
##   mesh, so neither reads well from the eye. These replace both in first person
##   for every outfit; third person never sees them.
## - Forearm: a few stacked cylinders (slight muscle belly, taper to the wrist) and
##   a folded cuff. Hand: palm block, knuckle ridge, four two-segment fingers and
##   a thumb. Real proportions (hand ~0.19 m, palm ~0.086 m wide).
## - The hand hangs along -Y from the wrist joint with the palm facing the body's
##   centre and the thumb up (+Z), which is where the IK leaves it. The palm sits a
##   little off the joint axis (the IK aims the axis at the grip centre), so the
##   glove wraps the grip instead of clipping through it.
## - set_grip(side, 0..1) curls the finger segments; ease_grip() glides there.
##   Colours and sizes live in content/look/fpv_arms.json.

const PATH := "res://content/look/fpv_arms.json"
const META := "fpv_arm"

var spec: Dictionary = {}
var joints: Dictionary = {}
var roots: Dictionary = {}       ## side -> forearm node (child of the elbow)
var hands: Dictionary = {}       ## side -> hand node (child of the wrist)
var fingers: Dictionary = {}     ## side -> [{seg1, seg2, k, thumb}]
var grip: Dictionary = { "l": 0.0, "r": 0.0 }
var visible := false

var _kit: CharacterKit


## Build both arms on `joints_in` (CharacterKit's joint dict), replacing any made before.
static func attach(joints_in: Dictionary, kit: CharacterKit) -> FpvArms:
	var a := FpvArms.new()
	a._kit = kit
	a.joints = joints_in
	a.spec = CharacterKit._read_json(PATH)
	for side in ["l", "r"]:
		a._build_side(side)
		a.set_grip(side, float(a._hand().get("relaxed", 0.3)))
	a.set_visible(false)
	return a


## True when `n` is part of an FpvArms arm (so the avatar can tell it from the kit's).
static func owns(n: Node) -> bool:
	while n != null:
		if n.has_meta(META):
			return true
		n = n.get_parent()
	return false


## Still built on these joints (a new outfit makes new ones).
func fits(joints_in: Dictionary) -> bool:
	return joints_in == joints and roots.has("l") and is_instance_valid(roots["l"])


func set_visible(on: bool) -> void:
	visible = on
	for side in roots:
		(roots[side] as Node3D).visible = on
		(hands[side] as Node3D).visible = on


func meshes() -> Array:
	var out: Array = []
	for side in roots:
		out.append_array(PlayerAvatar._meshes_under(roots[side]))
		out.append_array(PlayerAvatar._meshes_under(hands[side]))
	return out


## 0 = fingers open, 1 = closed round a grip.
func set_grip(side: String, amount: float) -> void:
	var g := clampf(amount, 0.0, 1.0)
	grip[side] = g
	var h := _hand()
	var c1: Array = h.get("curl1", [8, 72])
	var c2: Array = h.get("curl2", [14, 88])
	var ct: Array = h.get("thumb_curl", [12, 40])
	var s_in := _s_in(side)
	for f in fingers.get(side, []):
		var lo1 := float(c1[0])
		var hi1 := float(c1[1])
		var lo2 := float(c2[0])
		var hi2 := float(c2[1])
		if f.thumb:
			lo1 = float(ct[0])
			hi1 = float(ct[1])
			lo2 = lo1 * 0.8
			hi2 = hi1 * 1.2
		var k: float = f.k
		(f.seg1 as Node3D).rotation.z = s_in * deg_to_rad(lerpf(lo1, hi1, g) * k)
		(f.seg2 as Node3D).rotation.z = s_in * deg_to_rad(lerpf(lo2, hi2, g) * k)


## Move the grip toward `target` at about 6 per second, so closing is a quick clench.
func ease_grip(side: String, target: float, dt: float) -> void:
	set_grip(side, move_toward(float(grip[side]), target, dt * 6.0))


# ------------------------------------------------------------------ build

func _hand() -> Dictionary:
	return spec.get("hand", {})


## Which way the palm faces along local X: toward the body's centre, so +1 for the
## right hand (it sits at -X) and -1 for the left.
func _s_in(side: String) -> float:
	return -1.0 if side == "l" else 1.0


func _col(key: String, fallback: String) -> Color:
	return Color.html(str(spec.get(key, fallback)))


func _build_side(side: String) -> void:
	var elbow: Node3D = joints[side + "_elbow"]
	var wrist: Node3D = joints[side + "_wrist"]
	for old in [elbow.get_node_or_null("FpvArm"), wrist.get_node_or_null("FpvHand")]:
		if old != null:
			old.get_parent().remove_child(old)
			old.free()
	var sleeve := _kit._m(_col("sleeve", "#171717"), "cloth", 0.7)
	var cuff := _kit._m(_col("cuff", "#0f0f0f"), "cloth", 0.7)
	var glove := _kit._m(_col("glove", "#0d0d0d"), "leather", 0.4)
	var seg := int(spec.get("seg", 12))

	# Forearm and cuff, from the elbow (y = 0) down to the wrist joint.
	var arm := Node3D.new()
	arm.name = "FpvArm"
	arm.set_meta(META, true)
	elbow.add_child(arm)
	roots[side] = arm
	var fa: Dictionary = spec.get("forearm", {})
	var rings: Array = fa.get("rings", [])
	for i in range(rings.size() - 1):
		var y0 := float(rings[i][0])
		var y1 := float(rings[i + 1][0])
		var piece := _cyl(float(rings[i][1]), float(rings[i + 1][1]), y0 - y1, seg)
		_mi(arm, piece, sleeve, Vector3(0, (y0 + y1) * 0.5, 0))
	var length := float(fa.get("length", 0.27))
	var cuff_len := float(fa.get("cuff_len", 0.04))
	var cuff_r := float(fa.get("cuff_r", 0.0385))
	# A folded cuff: a band slightly proud of the sleeve, a fold ring above it.
	_mi(arm, _cyl(cuff_r, cuff_r, cuff_len, seg), cuff, Vector3(0, -length + cuff_len * 0.5 - 0.004, 0))
	_mi(arm, _cyl(cuff_r + 0.004, cuff_r + 0.004, 0.012, seg), cuff, Vector3(0, -length + cuff_len + 0.002, 0))

	# The hand: palm block (N thick, Y long, T wide), N toward the body centre.
	var hn := Node3D.new()
	hn.name = "FpvHand"
	hn.set_meta(META, true)
	wrist.add_child(hn)
	hands[side] = hn
	var h := _hand()
	var palm: Array = h.get("palm", [0.032, 0.098, 0.086])
	var s_in := _s_in(side)
	var px := -s_in * float(h.get("offset", 0.03))     # shifted away from the grip centre
	var pt := float(palm[0])
	var pl := float(palm[1])
	var pw := float(palm[2])
	# Gloved wrist continues the cuff, then the palm, a heel pad and a knuckle ridge.
	_mi(hn, _cyl(0.03, 0.03, 0.03, seg), glove, Vector3(px * 0.5, 0.005, 0))
	_mi(hn, _box(Vector3(pt, pl, pw)), glove, Vector3(px, -pl * 0.5, 0))
	_mi(hn, _sphere(pt * 0.62, seg), glove, Vector3(px, -0.012, 0), Vector3.ZERO, Vector3(0.9, 0.8, 2.3))
	_mi(hn, _cyl(pt * 0.42, pt * 0.42, pw * 0.96, 8), glove,
			Vector3(px - s_in * pt * 0.42, -pl + 0.004, 0), Vector3(90, 0, 0))

	var list: Array = []
	var flen: Array = h.get("finger_len", [0.043, 0.036])
	var fr := float(h.get("finger_r", 0.0092))
	var fz: Array = h.get("finger_z", [])
	var fk: Array = h.get("finger_scale", [])
	for i in fz.size():
		var base := Node3D.new()
		base.name = "Finger%d" % i
		base.position = Vector3(px + s_in * pt * 0.4, -pl, float(fz[i]))
		hn.add_child(base)
		list.append(_finger(base, flen, fr * (1.0 if i < 3 else 0.9), glove, float(fk[i]), false))
	# Thumb: from the top edge of the palm, near the wrist, its tip toward the palm.
	var tl: Array = h.get("thumb_len", [0.038, 0.032])
	var tb := Node3D.new()
	tb.name = "Thumb"
	tb.position = Vector3(px + s_in * pt * 0.45, -pl * 0.36, pw * 0.5)
	tb.rotation = Vector3(deg_to_rad(-35.0), 0, 0)       # splay out along +T
	hn.add_child(tb)
	list.append(_finger(tb, tl, fr * 1.25, glove, 1.0, true))
	fingers[side] = list


## Two segments hanging along -Y from `base`; the pivots are what set_grip turns.
func _finger(base: Node3D, lens: Array, r: float, mat: Material, k: float, thumb: bool) -> Dictionary:
	var l1 := float(lens[0])
	var l2 := float(lens[1])
	var s1 := Node3D.new()
	s1.name = "Seg1"
	base.add_child(s1)
	_mi(s1, _capsule(r, l1), mat, Vector3(0, -l1 * 0.5, 0))
	var s2 := Node3D.new()
	s2.name = "Seg2"
	s2.position = Vector3(0, -l1, 0)
	s1.add_child(s2)
	_mi(s2, _capsule(r * 0.92, l2), mat, Vector3(0, -l2 * 0.5, 0))
	return { "seg1": s1, "seg2": s2, "k": k, "thumb": thumb }


func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3,
		rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.rotation_degrees = rot
	m.scale = scl
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # the body already casts
	parent.add_child(m)
	return m


func _cyl(top: float, bottom: float, h: float, seg: int) -> CylinderMesh:
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


func _sphere(r: float, seg: int) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = seg
	s.rings = maxi(seg / 2, 4)
	return s


## A finger segment: `len` is its length, a little extra for the rounded ends.
func _capsule(r: float, len: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = maxf(len + r * 0.6, r * 2.0)
	c.radial_segments = 8
	c.rings = 2
	return c
