class_name FpvArms
extends RefCounted
## First person arms (issue #65 D): a black sleeve and glove per side, built over
## the kit's elbow and wrist joints so the two-bone IK still drives them.
##
## - The kit's own forearm and hand are heroic primitives, and a skinned body is one
##   mesh, so neither reads well from the eye. These replace both in first person
##   for every outfit; third person never sees them.
## - Forearm: one lathed mesh through the profile rings (smooth muscle belly, taper
##   to the wrist, a rounded cap at the elbow so its end never shows as a disc) and
##   a folded cuff. Upper arm: a lathed sleeve from the shoulder down into the
##   elbow, so looking down the arm runs out of the view instead of ending in mid
##   air. Hand: one mesh for the gauntlet, a rounded palm, the thumb's
##   pad and the knuckle ridge; four two-segment tapered fingers and a thumb. Real
##   proportions (hand ~0.19 m, palm ~0.086 m wide). Issue #229.
## - Materials: fpv_glove.gdshader (leather grain, knit sleeve, stitched seams,
##   scuffs, a rim). UVs are metres, so the patterns keep one size on every piece.
## - The hand hangs along -Y from the wrist joint with the palm facing the body's
##   centre and the thumb up (+Z), which is where the IK leaves it. The palm sits a
##   little off the joint axis (the IK aims the axis at the grip centre), so the
##   glove wraps the grip instead of clipping through it.
## - set_grip(side, 0..1) curls the finger segments; ease_grip() glides there.
##   set_pose(side, name) weights each finger (a pistol's trigger finger stays
##   straighter, a relaxed hand curls more toward the little finger).
##   Colours, sizes and poses live in content/look/fpv_arms.json.

const PATH := "res://content/look/fpv_arms.json"
const META := "fpv_arm"
const GLOVE := preload("res://src/systems/look/shaders/fpv_glove.gdshader")
const GLOVE_FADE := preload("res://src/systems/look/shaders/fpv_glove_fade.gdshader")

var spec: Dictionary = {}
var joints: Dictionary = {}
var roots: Dictionary = {}       ## side -> forearm node (child of the elbow)
var uppers: Dictionary = {}      ## side -> upper arm node (child of the shoulder)
var hands: Dictionary = {}       ## side -> hand node (child of the wrist)
var fingers: Dictionary = {}     ## side -> [{seg1, seg2, k, thumb}]
var grip: Dictionary = { "l": 0.0, "r": 0.0 }
var pose: Dictionary = { "l": "relaxed", "r": "relaxed" }
var weights: Dictionary = {}     ## side -> [index, middle, ring, little, thumb] curl weights (eased)
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
		a.weights[side] = a._pose_weights("relaxed")
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
		(uppers[side] as Node3D).visible = on
		(hands[side] as Node3D).visible = on


func meshes() -> Array:
	var out: Array = []
	for side in roots:
		out.append_array(PlayerAvatar._meshes_under(roots[side]))
		out.append_array(PlayerAvatar._meshes_under(uppers[side]))
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
	var w: Array = weights.get(side, [1.0, 1.0, 1.0, 1.0, 1.0])
	var i := 0
	for f in fingers.get(side, []):
		var gi := clampf(g * float(w[mini(i, w.size() - 1)]), 0.0, 1.0)
		i += 1
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
		(f.seg1 as Node3D).rotation.z = s_in * deg_to_rad(lerpf(lo1, hi1, gi) * k)
		(f.seg2 as Node3D).rotation.z = s_in * deg_to_rad(lerpf(lo2, hi2, gi) * k)


## Move the grip toward `target` at about 6 per second, so closing is a quick clench.
## The finger weights glide to the current pose's at the same rate.
func ease_grip(side: String, target: float, dt: float) -> void:
	var want := _pose_weights(str(pose.get(side, "relaxed")))
	var w: Array = weights.get(side, want)
	for i in w.size():
		w[i] = move_toward(float(w[i]), float(want[i]), dt * 6.0)
	weights[side] = w
	set_grip(side, move_toward(float(grip[side]), target, dt * 6.0))


## Pick the finger weighting ("relaxed", "trigger", "support", "hilt", ...); ease_grip
## glides there, set_pose(..., true) snaps.
func set_pose(side: String, name: String, snap := false) -> void:
	pose[side] = name if (spec.get("poses", {}) as Dictionary).has(name) else "relaxed"
	if snap:
		weights[side] = _pose_weights(pose[side])
		set_grip(side, float(grip[side]))


## [index, middle, ring, little, thumb] for a named pose (1 = the plain curl).
func _pose_weights(name: String) -> Array:
	var p = (spec.get("poses", {}) as Dictionary).get(name, {})
	var f: Array = p.get("fingers", [1.0, 1.0, 1.0, 1.0]) if p is Dictionary else [1.0, 1.0, 1.0, 1.0]
	var t := float(p.get("thumb", 1.0)) if p is Dictionary else 1.0
	return [float(f[0]), float(f[1]), float(f[2]), float(f[3]), t]


# ------------------------------------------------------------------ build

func _hand() -> Dictionary:
	return spec.get("hand", {})


## Which way the palm faces along local X: toward the body's centre, so +1 for the
## right hand (it sits at -X) and -1 for the left.
func _s_in(side: String) -> float:
	return -1.0 if side == "l" else 1.0


static func _v2(a) -> Vector2:
	return Vector2(float(a[0]), float(a[1])) if a is Array and a.size() >= 2 else Vector2.ZERO


func _col(key: String, fallback: String) -> Color:
	return Color.html(str(spec.get(key, fallback)))


## A glove-shader material; `params` are its uniforms. Shared per key.
func _mat(key: String, color: Color, params: Dictionary) -> ShaderMaterial:
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = GLOVE
	m.set_shader_parameter("base", color)
	m.set_shader_parameter("noise_tex", _kit.mats.noise)
	for k in params:
		m.set_shader_parameter(k, params[k])
	_mats[key] = m
	return m

var _mats: Dictionary = {}


func _build_side(side: String) -> void:
	var shoulder: Node3D = joints[side + "_shoulder"]
	var elbow: Node3D = joints[side + "_elbow"]
	var wrist: Node3D = joints[side + "_wrist"]
	for old in [shoulder.get_node_or_null("FpvUpper"), elbow.get_node_or_null("FpvArm"),
			wrist.get_node_or_null("FpvHand")]:
		if old != null:
			old.get_parent().remove_child(old)
			old.free()
	var seg := int(spec.get("seg", 20))
	var fa: Dictionary = spec.get("forearm", {})
	var rings: Array = fa.get("rings", [])
	var length := float(fa.get("length", 0.27))
	var cuff_len := float(fa.get("cuff_len", 0.04))
	var cuff_r := float(fa.get("cuff_r", 0.0385))
	var s_in := _s_in(side)
	var sleeve := _mat("sleeve", _col("sleeve", "#191715"),
			{ "roughness": 1.0, "spec": 0.12, "sheen": 0.15, "weave": 1.0, "stitch": 0.6, "wear": 0.1,
			"stitch_u": _seam_u(rings, 0.25 if side == "r" else 0.75) })
	var cuff := _mat("cuff", _col("cuff", "#121110"),
			{ "roughness": 0.95, "spec": 0.15, "sheen": 0.12, "weave": 0.7, "stitch": 0.9, "stitch_u": -1.0,
			"stitch_rings": 0.008, "length_v": cuff_len + 0.018, "wear": 0.2 })
	var glove := _mat("glove", _col("glove", "#161311"),
			{ "roughness": 0.5, "sheen": 0.16, "grain": 1.0, "wear": 0.3 })

	# Forearm: one lathe from a rounded elbow cap down the rings to the wrist.
	var arm := Node3D.new()
	arm.name = "FpvArm"
	arm.set_meta(META, true)
	elbow.add_child(arm)
	roots[side] = arm
	var prof: Array = []
	var r0 := float(rings[0][1])
	var y0 := float(rings[0][0])
	for c in range(5, 0, -1):          # the elbow cap: a squashed quarter circle
		var a := PI * 0.5 * float(c) / 5.0
		prof.append(Vector2(r0 * cos(a), y0 + r0 * 0.7 * sin(a)))
	prof.append_array(_smooth(rings, 4))
	_mi(arm, _lathe(prof, seg, true), sleeve, Vector3.ZERO)
	# Upper arm: rounded at the shoulder, ending in a round tip inside the elbow cap.
	# Only its elbow end shows (len_fade): near the shoulder it is at the lens.
	var upper := Node3D.new()
	upper.name = "FpvUpper"
	upper.set_meta(META, true)
	shoulder.add_child(upper)
	uppers[side] = upper
	var up_rings: Array = (spec.get("upper_arm", {}) as Dictionary).get("rings", [])
	if up_rings.size() >= 2:
		var uprof: Array = []
		var u0 := float(up_rings[0][1])
		var uy := float(up_rings[0][0])
		for c in range(5, 0, -1):
			var a := PI * 0.5 * float(c) / 5.0
			uprof.append(Vector2(u0 * cos(a), uy + u0 * 0.7 * sin(a)))
		uprof.append_array(_smooth(up_rings, 4))
		if not _mats.has("upper"):
			var um := sleeve.duplicate() as ShaderMaterial
			um.shader = GLOVE_FADE
			um.set_shader_parameter("near_fade", _v2(spec.get("near_fade", [])))
			um.set_shader_parameter("len_fade", _v2((spec.get("upper_arm", {}) as Dictionary).get("fade", [])))
			_mats["upper"] = um
		_mi(upper, _lathe(uprof, seg, true), _mats["upper"], Vector3.ZERO)
	# The cuff: a fold ring proud of the band, the band, a slight flare at the hem.
	var top := -length + cuff_len + 0.012
	var cuff_prof := [
		Vector2(cuff_r - 0.003, top + 0.004), Vector2(cuff_r + 0.0035, top),
		Vector2(cuff_r + 0.004, top - 0.008), Vector2(cuff_r, top - 0.012),
		Vector2(cuff_r, -length + 0.004), Vector2(cuff_r + 0.0015, -length - 0.002),
		Vector2(cuff_r - 0.002, -length - 0.006)]
	_mi(arm, _lathe(cuff_prof, seg, false), cuff, Vector3.ZERO)

	# The hand: gauntlet, palm, thumb pad and knuckles as one mesh.
	var hn := Node3D.new()
	hn.name = "FpvHand"
	hn.set_meta(META, true)
	wrist.add_child(hn)
	hands[side] = hn
	var h := _hand()
	var palm: Array = h.get("palm", [0.032, 0.098, 0.086])
	var px := -s_in * float(h.get("offset", 0.03))     # shifted away from the grip centre
	var pt := float(palm[0])
	var pl := float(palm[1])
	var pw := float(palm[2])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Gauntlet: up into the cuff, narrowing at the wrist, flaring into the palm.
	var gl := _lathe([Vector2(cuff_r - 0.004, 0.035), Vector2(0.03, 0.02), Vector2(0.0265, 0.0),
			Vector2(0.028, -0.012)], seg, false)
	st.append_from(gl, 0, Transform3D(Basis(), Vector3(px * 0.35, 0, 0)))
	st.append_from(_rounded_box(Vector3(pt, pl, pw), 0.35, 16), 0,
			Transform3D(Basis(), Vector3(px, -pl * 0.5, 0)))
	# Heel of the hand and the thumb's pad: soft lumps on the palm side.
	st.append_from(_rounded_box(Vector3(pt * 0.9, pl * 0.42, pw * 0.5), 0.8, 12), 0,
			Transform3D(Basis(), Vector3(px + s_in * pt * 0.22, -pl * 0.3, pw * 0.22)))
	# Knuckle ridge: a capsule across the back of the hand where the fingers start.
	st.append_from(_rounded_box(Vector3(pt * 0.95, pt * 0.62, pw * 1.0), 0.6, 12), 0,
			Transform3D(Basis(), Vector3(px - s_in * pt * 0.12, -pl + 0.006, 0)))
	_mi(hn, st.commit(), glove, Vector3.ZERO)

	var list: Array = []
	var flen: Array = h.get("finger_len", [0.043, 0.036])
	var fr := float(h.get("finger_r", 0.0092))
	var fz: Array = h.get("finger_z", [])
	var fk: Array = h.get("finger_scale", [])
	for i in fz.size():
		var base := Node3D.new()
		base.name = "Finger%d" % i
		base.position = Vector3(px + s_in * pt * 0.25, -pl + 0.004, float(fz[i]))
		hn.add_child(base)
		var k := float(fk[i])
		list.append(_finger(base, [float(flen[0]) * k, float(flen[1]) * k], fr * (1.0 if i < 3 else 0.88), glove, k, false))
	# Thumb: from the palm's top edge near the wrist, its tip toward the palm.
	var tl: Array = h.get("thumb_len", [0.038, 0.032])
	var tb := Node3D.new()
	tb.name = "Thumb"
	tb.position = Vector3(px + s_in * pt * 0.35, -pl * 0.32, pw * 0.42)
	tb.rotation = Vector3(deg_to_rad(-35.0), 0, 0)       # splay out along +T
	hn.add_child(tb)
	list.append(_finger(tb, tl, fr * 1.22, glove, 1.0, true))
	fingers[side] = list


## Two tapered segments hanging along -Y from `base`; the pivots are what set_grip
## turns. Each overlaps the next joint so a bent finger shows no gap.
func _finger(base: Node3D, lens: Array, r: float, mat: Material, k: float, thumb: bool) -> Dictionary:
	var l1 := float(lens[0])
	var l2 := float(lens[1])
	var s1 := Node3D.new()
	s1.name = "Seg1"
	base.add_child(s1)
	_mi(s1, _digit(r, r * 0.9, l1), mat, Vector3.ZERO)
	var s2 := Node3D.new()
	s2.name = "Seg2"
	s2.position = Vector3(0, -l1, 0)
	s1.add_child(s2)
	_mi(s2, _digit(r * 0.9, r * 0.74, l2), mat, Vector3.ZERO)
	return { "seg1": s1, "seg2": s2, "k": k, "thumb": thumb }


func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # the body already casts
	parent.add_child(m)
	return m


## Where on the sleeve's UV (metres round) a seam at fraction `f` of the way round sits.
func _seam_u(rings: Array, f: float) -> float:
	var r := 0.0
	for ring in rings:
		r = maxf(r, float(ring[1]))
	return TAU * r * f


## Catmull-Rom through the [y, r] rings, `steps` points per span: a smooth profile.
static func _smooth(rings: Array, steps: int) -> Array:
	var pts: Array = []
	for ring in rings:
		pts.append(Vector2(float(ring[1]), float(ring[0])))
	var out: Array = []
	for i in pts.size() - 1:
		var p0: Vector2 = pts[maxi(i - 1, 0)]
		var p1: Vector2 = pts[i]
		var p2: Vector2 = pts[i + 1]
		var p3: Vector2 = pts[mini(i + 2, pts.size() - 1)]
		for s in steps:
			var t := float(s) / float(steps)
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
					+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t))
	out.append(pts[pts.size() - 1])
	return out


## A surface of revolution round Y through `prof` (x = radius, y = height, top to
## bottom). Smooth normals from the profile's slope; UVs in metres (u round the
## widest ring, v down the profile) with tangents for the shader's bumps.
## `cap_end` closes the bottom with a rounded tip.
static func _lathe(prof: Array, seg: int, cap_end: bool) -> ArrayMesh:
	var pr: Array = prof.duplicate()
	if cap_end:
		var last: Vector2 = pr[pr.size() - 1]
		for k in range(1, 4):
			var a := PI * 0.5 * float(k) / 3.0
			pr.append(Vector2(last.x * cos(a), last.y - last.x * 0.6 * sin(a)))
	var rmax := 0.0
	for p in pr:
		rmax = maxf(rmax, (p as Vector2).x)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var v := 0.0
	for j in pr.size():
		var p: Vector2 = pr[j]
		if j > 0:
			v += (p - (pr[j - 1] as Vector2)).length()
		var tan_dir: Vector2 = (pr[mini(j + 1, pr.size() - 1)] as Vector2) - (pr[maxi(j - 1, 0)] as Vector2)
		var n2 := Vector2(-tan_dir.y, tan_dir.x).normalized()      # outward in (radius, y)
		for i in seg + 1:
			var a := TAU * float(i) / float(seg)
			var dir := Vector3(cos(a), 0, sin(a))
			st.set_normal((dir * n2.x + Vector3.UP * n2.y).normalized())
			st.set_uv(Vector2(TAU * rmax * float(i) / float(seg), v))
			st.add_vertex(dir * p.x + Vector3.UP * p.y)
	var row := seg + 1
	for j in pr.size() - 1:
		for i in seg:
			var a := j * row + i
			var b := a + 1
			var c := a + row
			var d := c + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(c)
			st.add_index(b)
			st.add_index(d)
			st.add_index(c)
	st.generate_tangents()
	return st.commit()


## A finger segment from y = 0 down to y = -len, radius r0 tapering to r1, both
## ends rounded (the top one reaches above 0 to fill the joint).
static func _digit(r0: float, r1: float, len: float) -> ArrayMesh:
	var prof: Array = []
	for k in range(4, -1, -1):
		var a := PI * 0.5 * float(k) / 4.0
		prof.append(Vector2(r0 * cos(a), r0 * 0.8 * sin(a)))
	prof.append(Vector2(lerpf(r0, r1, 0.5), -len * 0.5))
	prof.append(Vector2(r1, -len))
	return _lathe(prof, 10, true)


## A superellipsoid: a box of `size` with its edges rounded (e = 0 boxy, 1 an
## ellipsoid). Smooth analytic normals; UVs in metres for the grain.
static func _rounded_box(size: Vector3, e: float, n: int) -> ArrayMesh:
	var h := size * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in n + 1:
		var phi := PI * (float(j) / float(n) - 0.5)
		for i in n * 2 + 1:
			var th := TAU * float(i) / float(n * 2)
			var c := Vector3(cos(phi) * cos(th), sin(phi), cos(phi) * sin(th))
			var p := Vector3(_sp(c.x, e) * h.x, _sp(c.y, e) * h.y, _sp(c.z, e) * h.z)
			var nn := Vector3(_sp(c.x, 2.0 - e) / h.x, _sp(c.y, 2.0 - e) / h.y, _sp(c.z, 2.0 - e) / h.z)
			st.set_normal(nn.normalized() if nn.length() > 0.0 else Vector3.UP)
			st.set_uv(Vector2(th * maxf(h.x, h.z), (phi + PI * 0.5) * h.y))
			st.add_vertex(p)
	var row := n * 2 + 1
	for j in n:
		for i in n * 2:
			var a := j * row + i
			var b := a + 1
			var c := a + row
			var d := c + 1
			st.add_index(a)
			st.add_index(c)
			st.add_index(b)
			st.add_index(b)
			st.add_index(c)
			st.add_index(d)
	st.generate_tangents()
	return st.commit()


static func _sp(x: float, e: float) -> float:
	return signf(x) * pow(absf(x), e)
