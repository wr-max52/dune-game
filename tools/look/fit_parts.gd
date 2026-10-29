extends SceneTree
## Puts separately generated parts on a split character's skeleton (issue #48). Each
## part was made by Hyper3D from renders of one split part (tools/look/shoot_sheet.gd,
## crops), so it has the right shape but no rig and the generator's own scale.
##
##   godot --headless --path . -s res://tools/look/fit_parts.gd -- id=smuggler
##
## Reads "fit" from content/look/character_models.json:
##   out:   res:// path of the fitted model
##   parts: { part name: { source: raw .glb, decimate: triangles,
##            from: reference part (default: the same name; a new name adds a piece),
##            uniform: true to keep the piece's proportions (smallest axis ratio, centred
##              on the box, standing on its floor); axis: "y" scales by height alone, so a
##              hat brim or a pauldron sticking out past the body is not squeezed in;
##              scale: a correction on top, chosen by eye,
##            box: { min, max } to fit into instead of the reference part's bounds,
##            trim_top: share of the piece's height cut off the top first,
##            yaw: degrees to turn the piece about the vertical axis first,
##            straighten: share of the height that is hips; the legs below are
##              stood up straight (a piece generated mid-stride),
##            align_top: share of the height whose middle is matched to the
##              reference's (a waistband onto the hips) instead of the bounds' } }
##   dress: { outfit name: { source: raw .glb of a whole dressed character, decimate,
##            uniform, axis, scale, own_weights: true keeps a rigged source's own
##            weights (bones matched by name) instead of the copied ones, recolor: { swaps: { "#from": "#to" }, tol, min_l } bakes
##            a new base colour into the outfit's texture, move: [{ from, to, hue, min_sv,
##            above }] hands triangles of one colour to another piece, trim_top: { part: share of its height cut off the
##            top, e.g. stray scarf bits above the collar }, trim_below: { part: [y, radius] }
##            drops the part's triangles under y and within radius of the vertical axis
##            (hanging armour between the hands; the hands, further out, stay) }, skip: [parts left out, e.g. a head replaced by a
##            separately made piece in `parts`], rigged: true when the source has a human-template
##            skeleton (Hyper3D rigging): its limbs are first turned to the reference
##            body's rest pose, so a costume made in any A-pose lines up } } (optional)
## The reference is the character's split model (its "out", from prep_character.gd).
## For every part:
## - fit: scale and move the new mesh, per axis, onto the reference part's bounds;
## - skin: each vertex copies the bones and weights of the nearest reference vertex
##   of the same part (a grid lookup), so the part bends like the original.
## The reference part's mesh is swapped for the new one: same node, skin and skeleton.
## A piece with its own name (a helmet `from` the head) is added beside it instead.
## A dressed outfit is fitted by height onto the whole reference body, and each vertex
## copies its weights and its part from the nearest reference vertex, so every outfit
## is cut at the same seams: it becomes <outfit>_<part> for each reference part, and
## any outfit's head goes with any other's torso and legs.

const CFG_PATH := "res://content/look/character_models.json"
const CELL := 0.03
const Prep := preload("res://tools/look/prep_character.gd")
const Recolor := preload("res://tools/look/recolor_fitted.gd")


func _init() -> void:
	var id := "smuggler"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("id="):
			id = a.substr(3)
	var all: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CFG_PATH))
	var cfg: Dictionary = all.get(id, {})
	if not cfg.has("fit"):
		push_error("fit: no fit config for '%s'" % id)
		quit(1)
		return
	var scene := _load(str(cfg.out))
	if scene == null:
		quit(1)
		return
	var parts: Dictionary = cfg.fit.get("parts", {})
	var refs := {}                     ## reference meshes, before any swap
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		refs[String(mi.name)] = mi.mesh
	for part in parts:
		var from := str(parts[part].get("from", part))
		var ref := scene.find_child(from, true, false) as MeshInstance3D
		if ref == null or ref.skin == null or not refs.has(from):
			push_error("fit: no skinned part '%s' in %s" % [from, cfg.out])
			quit(1)
			return
		var target := ref
		if from != part:
			target = MeshInstance3D.new()
			target.name = part
			target.skin = ref.skin
			target.transform = ref.transform
			ref.get_parent().add_child(target)
			target.owner = scene
			target.skeleton = target.get_path_to(ref.get_node(ref.skeleton))
		_fit(target, refs[from], parts[part])
	var bases: Array = []
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		if refs.has(String(mi.name)) and mi.skin != null:
			bases.append(mi)
	for outfit in cfg.fit.get("dress", {}):
		_dress(outfit, cfg.fit.dress[outfit], bases, refs)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	doc.append_from_scene(scene, state)
	var out := ProjectSettings.globalize_path(str(cfg.fit.out))
	if doc.write_to_filesystem(state, out) != OK:
		push_error("fit: cannot write " + out)
		quit(1)
		return
	print("fit: wrote ", out)
	scene.free()
	quit()


static func _load(path: String) -> Node:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(path), state) != OK:
		push_error("fit: cannot read " + path)
		return null
	return doc.generate_scene(state)


func _fit(target: MeshInstance3D, ref_mesh: Mesh, pc: Dictionary) -> void:
	var src := _source(pc)
	if src.is_empty():
		return
	var arr: Array = src[0]
	var to := ref_mesh.get_aabb()
	if pc.has("box"):
		var lo := Vector3(pc.box.min[0], pc.box.min[1], pc.box.min[2])
		to = AABB(lo, Vector3(pc.box.max[0], pc.box.max[1], pc.box.max[2]) - lo)
	if pc.has("yaw"):
		_turn(arr, deg_to_rad(float(pc.yaw)))
	if float(pc.get("trim_top", 0.0)) > 0.0:
		arr = _trim_top(arr, float(pc.trim_top))
	var k := _place(arr, to, pc)
	var ref_arr := ref_mesh.surface_get_arrays(0)
	if float(pc.get("align_top", 0.0)) > 0.0:
		_align_top(arr, ref_arr[Mesh.ARRAY_VERTEX], float(pc.align_top))
	if float(pc.get("straighten", 0.0)) > 0.0:
		_straighten(arr, float(pc.straighten), ref_arr[Mesh.ARRAY_VERTEX])
	var per := (ref_arr[Mesh.ARRAY_BONES] as PackedInt32Array).size() / (ref_arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	_skin_from(arr, ref_arr, per)
	target.mesh = _mesh(arr, src[1], per)
	print("fit: %s  %d triangles, scale %s" % [target.name, (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3, k])


## Turns the arrays about the vertical axis (a piece the generator stood at an angle).
static func _turn(arr: Array, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	for i in v.size():
		v[i] = b * v[i]
	for i in n.size():
		n[i] = b * n[i]
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	if arr[Mesh.ARRAY_TANGENT] != null:
		var tg: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT]
		for i in range(0, tg.size(), 4):
			var d := b * Vector3(tg[i], tg[i + 1], tg[i + 2])
			tg[i] = d.x
			tg[i + 1] = d.y
			tg[i + 2] = d.z
		arr[Mesh.ARRAY_TANGENT] = tg


## Stands a legs piece made mid-stride up straight on the reference's legs: below
## the crotch (the top `share` of the height is the hips), each leg (split left and
## right of the middle) is slid front to back, height band by height band, so its
## middle sits where the reference's leg is at that height. The slide eases in over
## the first third below the crotch, so the hips keep their shape.
static func _straighten(arr: Array, share: float, ref: PackedVector3Array) -> void:
	const BAND := 0.03
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var lo := INF
	var hi := -INF
	var mid := 0.0
	for p in v:
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
		mid += p.x
	mid /= v.size()
	var crotch := hi - (hi - lo) * share
	var ease := (crotch - lo) / 3.0
	var ref_mid := 0.0
	for p in ref:
		ref_mid += p.x
	ref_mid /= ref.size()
	for side in [-1.0, 1.0]:
		var want := _band_z(ref, ref_mid, side, lo, BAND)
		var have := _band_z(v, mid, side, lo, BAND)
		var most := 0.0
		for i in v.size():
			if v[i].y >= crotch or signf(v[i].x - mid) != side:
				continue
			var k := int(floor((v[i].y - lo) / BAND))
			if not want.has(k):
				continue
			var shift: float = (want[k] - have[k]) * clampf((crotch - v[i].y) / ease, 0.0, 1.0)
			v[i].z += shift
			most = maxf(most, absf(shift))
		print("fit: straightened the %s leg, up to %.3f m" % ["right" if side < 0.0 else "left", most])
	arr[Mesh.ARRAY_VERTEX] = v


## band -> middle z of one leg's points (x on `side` of `mid`) in bands of `band` up from `lo`.
static func _band_z(v: PackedVector3Array, mid: float, side: float, lo: float, band: float) -> Dictionary:
	var sums := {}
	for p in v:
		if signf(p.x - mid) == side:
			var k := int(floor((p.y - lo) / band))
			var e: Array = sums.get(k, [INF, -INF])
			sums[k] = [minf(e[0], p.z), maxf(e[1], p.z)]
	var out := {}
	for k in sums:
		out[k] = (sums[k][0] + sums[k][1]) * 0.5
	return out


## Slides the piece across the ground so the middle of its top `share` (a waistband)
## sits on the middle of the reference's: the bounding box is thrown off by whatever
## sticks out lower down (boot toes), which left a legs piece behind the hips.
static func _align_top(arr: Array, ref: PackedVector3Array, share: float) -> void:
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var shift := _top_middle(ref, share) - _top_middle(v, share)
	shift.y = 0.0
	for i in v.size():
		v[i] += shift
	arr[Mesh.ARRAY_VERTEX] = v
	print("fit: aligned by the top, moved %s" % shift)


## The middle (bounds centre) of the points in the top `share` of the height.
static func _top_middle(v: PackedVector3Array, share: float) -> Vector3:
	var hi := -INF
	var lo := INF
	for p in v:
		hi = maxf(hi, p.y)
		lo = minf(lo, p.y)
	var cut := hi - (hi - lo) * share
	var box := AABB()
	var first := true
	for p in v:
		if p.y < cut:
			continue
		if first:
			box = AABB(p, Vector3.ZERO)
			first = false
		else:
			box = box.expand(p)
	return box.get_center()


## The arrays without the triangles that reach into the top `share` of the height
## (bare skin the generator left above a waistband).
static func _trim_top(arr: Array, share: float) -> Array:
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var lo := INF
	var hi := -INF
	for p in v:
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
	var cut := hi - (hi - lo) * share
	var kept := PackedInt32Array()
	for t in range(0, idx.size(), 3):
		if maxf(v[idx[t]].y, maxf(v[idx[t + 1]].y, v[idx[t + 2]].y)) <= cut:
			kept.append_array([idx[t], idx[t + 1], idx[t + 2]])
	return _subset(arr, kept)


## Fits a whole dressed character onto all the reference parts and cuts it where they
## are cut: a new skinned mesh <outfit>_<part> beside each reference part.
func _dress(outfit: String, pc: Dictionary, bases: Array, refs: Dictionary) -> void:
	var base_skel := (bases[0] as MeshInstance3D).get_node((bases[0] as MeshInstance3D).skeleton) as Skeleton3D
	var src := _source(pc, base_skel if pc.get("rigged", false) else null)
	if src.is_empty():
		return
	if pc.has("recolor"):
		src[1] = _recolored(src[1], pc.recolor)
	var arr: Array = src[0]
	var ref_arr: Array = []                ## all reference parts as one vertex list
	var label := PackedInt32Array()        ## which part each reference vertex is in
	var to := AABB()
	for i in bases.size():
		var a: Array = (refs[String(bases[i].name)] as Mesh).surface_get_arrays(0)
		if i == 0:
			to = AABB((a[Mesh.ARRAY_VERTEX] as PackedVector3Array)[0], Vector3.ZERO)
		for p: Vector3 in a[Mesh.ARRAY_VERTEX]:
			to = to.expand(p)
		if ref_arr.is_empty():
			ref_arr = [PackedVector3Array(), PackedInt32Array(), PackedFloat32Array()]
		ref_arr[0].append_array(a[Mesh.ARRAY_VERTEX])
		ref_arr[1].append_array(a[Mesh.ARRAY_BONES])
		ref_arr[2].append_array(a[Mesh.ARRAY_WEIGHTS])
		var n := label.size()
		label.resize(n + (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
		for j in range(n, label.size()):
			label[j] = i
	var whole := []
	whole.resize(Mesh.ARRAY_MAX)
	whole[Mesh.ARRAY_VERTEX] = ref_arr[0]
	whole[Mesh.ARRAY_BONES] = ref_arr[1]
	whole[Mesh.ARRAY_WEIGHTS] = ref_arr[2]
	var per := (ref_arr[1] as PackedInt32Array).size() / (ref_arr[0] as PackedVector3Array).size()
	var k := _place(arr, to, pc)
	var own_b = arr[Mesh.ARRAY_BONES]
	var own_w = arr[Mesh.ARRAY_WEIGHTS]
	var near := _skin_from(arr, whole, per)
	if pc.get("own_weights", false) and own_b != null:
		_own_weights(arr, own_b, own_w, src[2], (bases[0] as MeshInstance3D).skin, base_skel, per)
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var lab := PackedInt32Array()
	lab.resize(near.size())
	for i in near.size():
		lab[i] = label[maxi(near[i], 0)]
	lab = _smooth_labels(arr, lab, bases.size(), int(pc.get("smooth", 8)))
	var tris: Array = []
	for i in bases.size():
		tris.append(PackedInt32Array())
	for t in range(0, idx.size(), 3):
		var a := lab[idx[t]]
		var b := lab[idx[t + 1]]
		var c := lab[idx[t + 2]]
		tris[b if b == c else a].append_array([idx[t], idx[t + 1], idx[t + 2]])
	for mv: Dictionary in pc.get("move", []):
		_move_by_colour(arr, src[1], tris, bases, mv)
	var vv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in bases.size():
		var ref: MeshInstance3D = bases[i]
		if (pc.get("skip", []) as Array).has(String(ref.name)):
			continue
		var trim := float((pc.get("trim_top", {}) as Dictionary).get(String(ref.name), 0.0))
		if trim > 0.0 and tris[i].size() > 0:
			var lo := INF
			var hi := -INF
			for j in tris[i]:
				lo = minf(lo, vv[j].y)
				hi = maxf(hi, vv[j].y)
			var cut := hi - (hi - lo) * trim
			var kept := PackedInt32Array()
			for t in range(0, tris[i].size(), 3):
				if maxf(vv[tris[i][t]].y, maxf(vv[tris[i][t + 1]].y, vv[tris[i][t + 2]].y)) <= cut:
					kept.append_array([tris[i][t], tris[i][t + 1], tris[i][t + 2]])
			tris[i] = kept
		if (pc.get("trim_below", {}) as Dictionary).has(String(ref.name)):
			var tb: Array = pc.trim_below[String(ref.name)]
			tris[i] = _trim_below(arr, tris[i], float(tb[0]), float(tb[1]))
		var mi := MeshInstance3D.new()
		mi.name = "%s_%s" % [outfit, ref.name]
		mi.skin = ref.skin
		mi.transform = ref.transform
		ref.get_parent().add_child(mi)
		mi.owner = ref.owner
		mi.skeleton = mi.get_path_to(ref.get_node(ref.skeleton))
		mi.mesh = _mesh(_subset(arr, tris[i]), src[1], per)
		print("fit: %s  %d triangles, scale %s" % [mi.name, tris[i].size() / 3, k])


## A copy of the material with its albedo recoloured (recolor_fitted.gd's swap):
## rc = { swaps: { "#from": "#to" }, tol, min_l }. Bakes a new base colour into the
## outfit (the guard's white armour made gunmetal grey).
static func _recolored(mat: Material, rc: Dictionary) -> Material:
	var m := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
	var img := m.albedo_texture.get_image()
	img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	for from in rc.swaps:
		img = Recolor._recolor(img, Color(str(from)), Color(str(rc.swaps[from])), float(rc.get("tol", 0.35)), float(rc.get("min_l", 0.02)))
	m.albedo_texture = ImageTexture.create_from_image(img)
	return m


## Moves triangles of one colour from one piece to another: the texture under each
## triangle's centre is sampled, and a triangle whose hue is within mv.hue (degrees,
## [low, high]; any hue when left out), whose saturation and value reach mv.min_sv and
## stay under mv.max_sv (grey hoses beside a yellow hood), with its centre above
## mv.above (so the boots, further down, stay) and under mv.below (a stand-up collar
## the cut gave the head) and inside mv.box ({ min, max }, the triangle's centre), goes from mv.from to
## mv.to (a tunic hem that hangs past the waist stays with the tunic), pushed out along
## its normals by mv.push (so a separately made legs piece stays under it). With
## mv.drop_back, the matching triangles behind the body (z < 0) are dropped instead,
## so a tunic hem hangs only in front, like an apron. With mv.copy the triangles stay
## in mv.from as well (a collar both the head and the jacket should have); no push.
static func _move_by_colour(arr: Array, mat: Material, tris: Array, bases: Array, mv: Dictionary) -> void:
	var from := -1
	var to := -1
	for i in bases.size():
		if String(bases[i].name) == str(mv.from):
			from = i
		if String(bases[i].name) == str(mv.to):
			to = i
	if from < 0 or to < 0 or not (mat is BaseMaterial3D) or (mat as BaseMaterial3D).albedo_texture == null:
		push_error("fit: cannot move '%s' to '%s'" % [mv.from, mv.to])
		return
	var img := (mat as BaseMaterial3D).albedo_texture.get_image()
	img.decompress()
	var w := img.get_width()
	var h := img.get_height()
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var vv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var hue: Array = mv.get("hue", [0.0, 360.0])
	var lo := float(hue[0]) / 360.0
	var hi := float(hue[1]) / 360.0
	var sv: Array = mv.get("min_sv", [0.4, 0.3] if mv.has("hue") else [0.0, 0.0])
	var sv_max: Array = mv.get("max_sv", [1.0, 1.0])
	var above := float(mv.get("above", -INF))
	var below := float(mv.get("below", INF))
	var drop_back := bool(mv.get("drop_back", false))
	var copy := bool(mv.get("copy", false))
	var box := AABB(-Vector3.INF, Vector3.INF)
	if mv.has("box"):
		var b_lo := Vector3(mv.box.min[0], mv.box.min[1], mv.box.min[2])
		box = AABB(b_lo, Vector3(mv.box.max[0], mv.box.max[1], mv.box.max[2]) - b_lo)
	var kept := PackedInt32Array()
	var moved := 0
	var t_from: PackedInt32Array = tris[from]
	for t in range(0, t_from.size(), 3):
		var c := (uv[t_from[t]] + uv[t_from[t + 1]] + uv[t_from[t + 2]]) / 3.0
		var px := img.get_pixel(clampi(int(fposmod(c.x, 1.0) * w), 0, w - 1), clampi(int(fposmod(c.y, 1.0) * h), 0, h - 1))
		var cc := (vv[t_from[t]] + vv[t_from[t + 1]] + vv[t_from[t + 2]]) / 3.0
		var cy := cc.y
		if cy >= above and cy < below and (not mv.has("box") or box.has_point(cc)) and px.h >= lo and px.h <= hi and px.s >= float(sv[0]) and px.v >= float(sv[1]) \
				and px.s <= float(sv_max[0]) and px.v <= float(sv_max[1]):
			if drop_back and (vv[t_from[t]].z + vv[t_from[t + 1]].z + vv[t_from[t + 2]].z) / 3.0 < 0.0:
				continue
			tris[to].append_array([t_from[t], t_from[t + 1], t_from[t + 2]])
			moved += 1
			if copy:
				kept.append_array([t_from[t], t_from[t + 1], t_from[t + 2]])
		else:
			kept.append_array([t_from[t], t_from[t + 1], t_from[t + 2]])
	tris[from] = kept
	var push := float(mv.get("push", 0.0))
	if push != 0.0 and moved > 0 and not copy:
		var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var done := {}
		var t_to: PackedInt32Array = tris[to]
		for i in range(t_to.size() - moved * 3, t_to.size()):
			if not done.has(t_to[i]):
				done[t_to[i]] = true
				vv[t_to[i]] += nn[t_to[i]] * push
		arr[Mesh.ARRAY_VERTEX] = vv
	print("fit: %s %d triangles %s -> %s" % ["copied" if copy else "moved", moved, mv.from, mv.to])


## The triangles that stay when those whose centre is under `y` and within `radius`
## of the vertical axis are dropped.
static func _trim_below(arr: Array, tri: PackedInt32Array, y: float, radius: float) -> PackedInt32Array:
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var kept := PackedInt32Array()
	for t in range(0, tri.size(), 3):
		var c := (v[tri[t]] + v[tri[t + 1]] + v[tri[t + 2]]) / 3.0
		if c.y >= y or Vector2(c.x, c.z).length() >= radius:
			kept.append_array([tri[t], tri[t + 1], tri[t + 2]])
	return kept


## Evens out per-vertex part labels: each pass gives every vertex the most common
## label among itself and its edge neighbours (vertices at one position count as one),
## so loose clothing far from the body (a hat brim over the shoulder, a coat hem)
## follows the piece it is attached to and the cut runs clean.
static func _smooth_labels(arr: Array, lab: PackedInt32Array, count: int, passes: int) -> PackedInt32Array:
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var weld := PackedInt32Array()          ## vertex -> first vertex at its position
	weld.resize(v.size())
	var seen := {}
	for i in v.size():
		var key := Vector3i((v[i] * 2000.0).round())
		if not seen.has(key):
			seen[key] = i
		weld[i] = seen[key]
	var nbr := {}                           ## welded vertex -> PackedInt32Array
	for t in range(0, idx.size(), 3):
		for e in 3:
			var a := weld[idx[t + e]]
			var b := weld[idx[t + (e + 1) % 3]]
			if not nbr.has(a):
				nbr[a] = PackedInt32Array()
			if not nbr.has(b):
				nbr[b] = PackedInt32Array()
			nbr[a].append(b)
			nbr[b].append(a)
	var cur := PackedInt32Array()
	cur.resize(v.size())
	for i in v.size():
		cur[i] = lab[i]
	var votes := PackedInt32Array()
	votes.resize(count)
	for p in passes:
		var nxt := cur.duplicate()
		for w in nbr:
			votes.fill(0)
			votes[cur[w]] += 1
			for o in nbr[w]:
				votes[cur[o]] += 1
			var best := cur[w]
			for c in count:
				if votes[c] > votes[best]:
					best = c
			nxt[w] = best
		cur = nxt
	var out := PackedInt32Array()
	out.resize(v.size())
	for i in v.size():
		out[i] = cur[weld[i]]
	return out


## The source's first surface (decimated when asked), its material and (when posed)
## its bind bone names, or [] when it cannot be read. With `pose_to`, the source is
## skinned and is baked in the pose that matches pose_to's rest (_repose); its own
## bones and weights stay in the arrays.
static func _source(pc: Dictionary, pose_to: Skeleton3D = null) -> Array:
	var raw := _load(str(pc.source))
	if raw == null:
		return []
	var smi := raw.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var src := smi.mesh
	var arr := src.surface_get_arrays(0)
	var mat := src.surface_get_material(0)
	var names := PackedStringArray()     ## the source's bone per bind, for own_weights
	if pose_to != null:
		_repose(arr, smi, raw, pose_to)
		names = _bind_names(smi.skin, smi.get_node(smi.skeleton) as Skeleton3D)
	raw.free()
	if pc.has("decimate"):
		arr = Prep._decimate(arr, int(pc.decimate))
	return [arr, mat, names]


## The bone name behind each of a skin's binds.
static func _bind_names(skin: Skin, skel: Skeleton3D) -> PackedStringArray:
	var out := PackedStringArray()
	for i in skin.get_bind_count():
		var bone := skin.get_bind_bone(i)
		out.append(String(skin.get_bind_name(i)) if bone < 0 else skel.get_bone_name(bone))
	return out


## Limb bones turned to the reference rest direction: bone -> the child it points at.
const LIMB_AIM := {
	"LeftArm": "LeftForeArm", "LeftForeArm": "LeftHand",
	"RightArm": "RightForeArm", "RightForeArm": "RightHand",
	"LeftUpLeg": "LeftLeg", "LeftLeg": "LeftFoot",
	"RightUpLeg": "RightLeg", "RightLeg": "RightFoot",
}


## Bakes a skinned mesh into the pose where each LIMB_AIM bone points the way the
## same bone points in `to` at rest; other bones keep their rest. Vertices end in the
## source scene's space, without bones (the fit copies new weights).
static func _repose(arr: Array, mi: MeshInstance3D, scene: Node, to: Skeleton3D) -> void:
	var skel := mi.get_node(mi.skeleton) as Skeleton3D
	var skin := mi.skin
	var n := skel.get_bone_count()
	var pose: Array = []               ## bone -> posed global transform (skeleton space)
	pose.resize(n)
	var order: Array = range(n)
	order.sort_custom(func(a, b): return _depth(skel, a) < _depth(skel, b))
	for b in order:
		var parent := skel.get_bone_parent(b)
		var g: Transform3D = (pose[parent] if parent >= 0 else Transform3D()) * skel.get_bone_rest(b)
		var nm := skel.get_bone_name(b)
		var tb := to.find_bone(nm)
		var kid := skel.find_bone(str(LIMB_AIM.get(nm, "")))
		var tk := to.find_bone(str(LIMB_AIM.get(nm, "")))
		if tb >= 0 and kid >= 0 and tk >= 0:
			var now := g.basis * skel.get_bone_rest(kid).origin
			var want := to.get_bone_global_rest(tk).origin - to.get_bone_global_rest(tb).origin
			if now.length() > 0.0001 and want.length() > 0.0001:
				var axis := now.normalized().cross(want.normalized())
				var ang := now.angle_to(want)
				if axis.length() > 0.00001:
					g.basis = Basis(axis.normalized(), ang) * g.basis
		pose[b] = g
	var xf: Array = []                 ## bind -> skinning transform
	for i in skin.get_bind_count():
		var bone := skin.get_bind_bone(i)
		if bone < 0:
			bone = skel.find_bone(String(skin.get_bind_name(i)))
		xf.append((pose[bone] as Transform3D) * skin.get_bind_pose(i) if bone >= 0 else Transform3D())
	var to_scene := _rel(scene, skel)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nr: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / v.size()
	for i in v.size():
		var p := Vector3.ZERO
		var q := Vector3.ZERO
		for k in per:
			var w := weights[i * per + k]
			if w <= 0.0:
				continue
			var t: Transform3D = xf[bones[i * per + k]]
			p += (t * v[i]) * w
			q += (t.basis * nr[i]) * w
		v[i] = to_scene * p
		nr[i] = (to_scene.basis * q).normalized()
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nr
	arr[Mesh.ARRAY_TANGENT] = null


static func _depth(skel: Skeleton3D, b: int) -> int:
	var d := 0
	while skel.get_bone_parent(b) >= 0:
		b = skel.get_bone_parent(b)
		d += 1
	return d


static func _rel(root: Node, node: Node) -> Transform3D:
	var t := Transform3D()
	var at := node
	while at != null and at != root:
		if at is Node3D:
			t = (at as Node3D).transform * t
		at = at.get_parent()
	return t


## Scales and moves the arrays into `to` (per axis, or uniform: see the header).
## Returns the scale.
static func _place(arr: Array, to: AABB, pc: Dictionary) -> Vector3:
	var from := AABB()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	from.position = v[0]
	for p in v:
		from = from.expand(p)
	var k := to.size / from.size
	var at := to.position
	if pc.get("uniform", false):
		match str(pc.get("axis", "")):
			"y":
				k = Vector3.ONE * k.y
			_:
				k = Vector3.ONE * minf(k.y, minf(k.x, k.z))
		k *= float(pc.get("scale", 1.0))
		at = to.get_center() - from.size * k * 0.5
		at.y = to.position.y
	for i in v.size():
		v[i] = at + (v[i] - from.position) * k
	arr[Mesh.ARRAY_VERTEX] = v
	var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	for i in n.size():
		n[i] = (n[i] / k).normalized()
	arr[Mesh.ARRAY_NORMAL] = n
	if arr[Mesh.ARRAY_TANGENT] != null:
		var t: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT]
		for i in range(0, t.size(), 4):
			var d := (Vector3(t[i], t[i + 1], t[i + 2]) * k).normalized()
			t[i] = d.x
			t[i + 1] = d.y
			t[i + 2] = d.z
		arr[Mesh.ARRAY_TANGENT] = t
	return k


static func _mesh(arr: Array, mat: Material, per: int) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0)
	mesh.surface_set_material(0, mat)
	return mesh


## The arrays cut down to the given triangles, keeping only the vertices they use.
static func _subset(arr: Array, idx: PackedInt32Array) -> Array:
	var count := (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var remap := {}
	var keep := PackedInt32Array()
	var out_idx := PackedInt32Array()
	out_idx.resize(idx.size())
	for i in idx.size():
		if not remap.has(idx[i]):
			remap[idx[i]] = keep.size()
			keep.append(idx[i])
		out_idx[i] = remap[idx[i]]
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	for a in Mesh.ARRAY_MAX:
		if a == Mesh.ARRAY_INDEX or arr[a] == null:
			continue
		var src = arr[a]
		var stride: int = src.size() / count
		var dst = src.duplicate()
		dst.resize(keep.size() * stride)
		for i in keep.size():
			for s in stride:
				dst[i * stride + s] = src[keep[i] * stride + s]
		out[a] = dst
	out[Mesh.ARRAY_INDEX] = out_idx
	return out


## Puts the source's own weights (its Hyper3D rig, the same human template as the
## base body) back in place of the copied ones, each bone found by name among the
## base body's binds. The copied weights only lend the cut; the source's rig knows a
## belt pouch or an apron hangs from the hips even where the hands hang beside it.
## A vertex keeps the copied weights when one of its bones has no match.
static func _own_weights(arr: Array, own_b: PackedInt32Array, own_w: PackedFloat32Array, names: PackedStringArray, skin: Skin, skel: Skeleton3D, per: int) -> void:
	var to := {}
	var base_names := _bind_names(skin, skel)
	for i in base_names.size():
		to[base_names[i]] = i
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var src_per := own_b.size() / v.size()
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var kept := 0
	for i in v.size():
		var pairs: Array = []
		var ok := true
		for k in src_per:
			var w := own_w[i * src_per + k]
			if w <= 0.0:
				continue
			var nm := names[own_b[i * src_per + k]] if own_b[i * src_per + k] < names.size() else ""
			if not to.has(nm):
				ok = false
				break
			pairs.append([to[nm], w])
		if not ok or pairs.is_empty():
			kept += 1
			continue
		pairs.sort_custom(func(a, b): return a[1] > b[1])
		pairs = pairs.slice(0, per)
		var sum := 0.0
		for p in pairs:
			sum += p[1]
		for k in per:
			bones[i * per + k] = pairs[k][0] if k < pairs.size() else 0
			weights[i * per + k] = pairs[k][1] / sum if k < pairs.size() else 0.0
	arr[Mesh.ARRAY_BONES] = bones
	arr[Mesh.ARRAY_WEIGHTS] = weights
	print("fit: own weights on %d of %d vertices" % [v.size() - kept, v.size()])


## Bones and weights of the nearest reference vertex, found in a grid of CELL cubes
## that widens ring by ring until it has a candidate. Returns each vertex's nearest
## reference vertex (-1 when none is in reach).
static func _skin_from(arr: Array, ref_arr: Array, per: int) -> PackedInt32Array:
	var rv: PackedVector3Array = ref_arr[Mesh.ARRAY_VERTEX]
	var rb: PackedInt32Array = ref_arr[Mesh.ARRAY_BONES]
	var rw: PackedFloat32Array = ref_arr[Mesh.ARRAY_WEIGHTS]
	var grid := {}
	for i in rv.size():
		var c := Vector3i((rv[i] / CELL).floor())
		if not grid.has(c):
			grid[c] = PackedInt32Array()
		grid[c].append(i)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var near := PackedInt32Array()
	near.resize(v.size())
	near.fill(-1)
	bones.resize(v.size() * per)
	weights.resize(v.size() * per)
	for i in v.size():
		var c := Vector3i((v[i] / CELL).floor())
		var best := -1
		var best_d := INF
		for r in 12:
			for x in range(-r, r + 1):
				for y in range(-r, r + 1):
					for z in range(-r, r + 1):
						if maxi(absi(x), maxi(absi(y), absi(z))) != r:
							continue
						for j in grid.get(c + Vector3i(x, y, z), PackedInt32Array()):
							var d := v[i].distance_squared_to(rv[j])
							if d < best_d:
								best_d = d
								best = j
			if best >= 0:
				break
		if best < 0:
			continue
		near[i] = best
		for b in per:
			bones[i * per + b] = rb[best * per + b]
			weights[i * per + b] = rw[best * per + b]
	arr[Mesh.ARRAY_BONES] = bones
	arr[Mesh.ARRAY_WEIGHTS] = weights
	return near
