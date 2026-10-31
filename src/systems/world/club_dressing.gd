class_name ClubDressing
extends Node3D
## Issue #261: the cantina dressed as a club, from the town data's "club" block:
##
##   "club": { "style": "jazz", "bpm": 100 }
##
## Every marker with a "prop" gets that instrument in front of it (ClubProps:
## "dj_desk", "drum_kit", "upright_bass"), built in the performer's own space so
## their hands land on it. Then the room for the style:
##
##   jazz  the desert port: a chill, low-lit jazz club. Wood plank floor with a
##         checker floor round the stage, panelled walls under velvet drapes,
##         leather booths with candlelit tables, round tables over the cantina's
##         own, warm and blue stage spots through the haze, a neon sign over the
##         door and an upright piano and a saxophone on a stand by the stage.
##
## Visual only (no collision): the town's boxes are what block. Positions come
## from the cantina's wall, stage, table and counter boxes.

var props: ClubProps
var cfg: Dictionary = {}
var inner := Rect2()          ## the cantina's floor inside its walls (x, z)
var ceiling := 5.0
var stage_c := Vector3.ZERO   ## the stage's centre on its top
var stage_r := 0.0


func dress(town, scene: Node) -> void:
	name = "ClubDressing"
	cfg = town.data.get("club", {})
	if cfg.is_empty():
		return
	props = ClubProps.new(str(cfg.get("style", "jazz")), float(cfg.get("bpm", 100.0)))
	add_child(props)
	_measure(town)
	for m in town.markers():
		if m.has("prop"):
			_instrument(town, m)
	match props.style:
		"jazz":
			_jazz(town, scene)


## The room's floor, ceiling and stage from the town's boxes.
func _measure(town) -> void:
	var w: Dictionary = town.get_box("cantina_wall_w")
	var e: Dictionary = town.get_box("cantina_wall_e_s")
	var n: Dictionary = town.get_box("cantina_wall_n")
	var s: Dictionary = town.get_box("cantina_wall_s")
	if not (w.is_empty() or e.is_empty() or n.is_empty() or s.is_empty()):
		inner = Rect2(float(w.max[0]), float(s.max[2]), float(e.min[0]) - float(w.max[0]), float(n.min[2]) - float(s.max[2]))
	var roof: Dictionary = town.get_box("cantina_roof")
	if not roof.is_empty():
		ceiling = float(roof.min[1])
	var st: Dictionary = town.get_box("cantina_stage")
	if not st.is_empty():
		stage_c = Vector3((float(st.min[0]) + float(st.max[0])) * 0.5, float(st.max[1]), (float(st.min[2]) + float(st.max[2])) * 0.5)
		stage_r = (float(st.max[0]) - float(st.min[0])) * 0.5


## The instrument for the performer at marker `m`, facing where they face.
func _instrument(town, m: Dictionary) -> void:
	var here: Vector3 = town.marker_pos(str(m.id))
	var yaw := 0.0
	if m.has("face"):
		yaw = atan2(float(m.face[0]) - here.x, float(m.face[2]) - here.z)
	var at := Transform3D(Basis(Vector3.UP, yaw), here)
	match str(m.prop):
		"dj_desk":
			props.dj_desk(at)
		"drum_kit":
			props.drum_kit(at)
		"upright_bass":
			props.upright_bass(at)


## Hide a box's greybox mesh (its collision stays) where the club draws its own.
func _hide_box(scene: Node, id: String) -> void:
	var body := scene.get_node_or_null("Town/" + id) if scene != null else null
	if body == null:
		return
	for c in body.get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).visible = false


func _slab(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	return props._box(props, size, pos, mat)


# ------------------------------------------------------------------ jazz

func _jazz(town, scene: Node) -> void:
	if inner.size == Vector2.ZERO:
		return
	var x0 := inner.position.x
	var x1 := inner.end.x
	var z0 := inner.position.y
	var z1 := inner.end.y
	var mid := Vector3((x0 + x1) * 0.5, 0, (z0 + z1) * 0.5)
	# The floor: dark planks wall to wall, a checker floor round the stage.
	_slab(Vector3(x1 - x0, 0.012, z1 - z0), Vector3(mid.x, 0.006, mid.z), ClubTextures.wood(Color("#4a2c1a"), 0.16))
	if stage_r > 0.0:
		var side := stage_r * 2.0 + 4.0
		_slab(Vector3(side, 0.014, side), Vector3(stage_c.x, 0.008, stage_c.z), ClubTextures.checker(Color("#151312"), Color("#d6c8a8"), 0.55))
		_slab(Vector3(side + 0.12, 0.016, 0.06), Vector3(stage_c.x, 0.008, stage_c.z - side * 0.5), ClubTextures.brushed(Color("#b08e50"), 0.9))
		_slab(Vector3(side + 0.12, 0.016, 0.06), Vector3(stage_c.x, 0.008, stage_c.z + side * 0.5), ClubTextures.brushed(Color("#b08e50"), 0.9))
		_slab(Vector3(0.06, 0.016, side), Vector3(stage_c.x - side * 0.5, 0.008, stage_c.z), ClubTextures.brushed(Color("#b08e50"), 0.9))
		_slab(Vector3(0.06, 0.016, side), Vector3(stage_c.x + side * 0.5, 0.008, stage_c.z), ClubTextures.brushed(Color("#b08e50"), 0.9))
		# The stage's own top in planks, a velvet skirt round its rim.
		props._cyl(props, stage_r - 0.13, 0.012, stage_c + Vector3(0, 0.007, 0), ClubTextures.wood(Color("#6a4024"), 0.12, 0.4))
	_walls(town)
	_booths(town)
	_tables(town, scene)
	_stage_lights()
	for side in [-1.0, 1.0]:      # speaker stacks either side of the band, on the floor
		var at := stage_c + Vector3(-stage_r - 0.9, -stage_c.y, side * (stage_r - 0.4))
		props.speaker(Transform3D(Basis(Vector3.UP, PI * 0.5 - side * 0.5), at), Vector3(0.8, 1.5, 0.6))
		props.speaker(Transform3D(Basis(Vector3.UP, PI * 0.5 - side * 0.5), at + Vector3(0, 1.5, 0)), Vector3(0.7, 0.7, 0.55))
	_sign(town)
	_piano_and_sax(town)


## Panelled wainscot to 1.3 m on every wall it fits (not the door, the back bar or
## the stair tower), velvet drapes above it between the hall's pilasters.
func _walls(town) -> void:
	var x0 := inner.position.x
	var x1 := inner.end.x
	var z0 := inner.position.y
	var z1 := inner.end.y
	var panel := ClubTextures.panels(Color("#3e2414"), 1.1)
	var rail := ClubTextures.brushed(Color("#b08e50"), 0.9)
	var velvet := ClubTextures.velvet(Color("#5a1420"))
	var door_lo := -2.0
	var door_hi := 2.0
	var lintel: Dictionary = town.get_box("cantina_door_lintel")
	if not lintel.is_empty():
		door_lo = float(lintel.min[2])
		door_hi = float(lintel.max[2])
	var tower: Dictionary = town.get_box("stair_tower")
	var tower_x := float(tower.max[0]) + 0.3 if not tower.is_empty() else x0
	var tower_z := float(tower.min[2]) - 0.3 if not tower.is_empty() else z1
	var counter: Dictionary = town.get_box("bar_counter")
	# Runs along each wall: [from, to] on that wall's axis.
	var runs := [
		["s", x0, x1], ["n", tower_x, x1],
		["e", z0, door_lo], ["e", door_hi, z1],
		["w", z0, (float(counter.min[2]) - 1.2) if not counter.is_empty() else z1],
	]
	for r in runs:
		var a := float(r[1])
		var b := float(r[2])
		if b - a < 0.5:
			continue
		var c := (a + b) * 0.5
		var len := b - a
		match str(r[0]):
			"s":
				_slab(Vector3(len, 1.3, 0.05), Vector3(c, 0.65, z0 + 0.025), panel)
				_slab(Vector3(len, 0.05, 0.09), Vector3(c, 1.32, z0 + 0.045), rail)
			"n":
				_slab(Vector3(len, 1.3, 0.05), Vector3(c, 0.65, z1 - 0.025), panel)
				_slab(Vector3(len, 0.05, 0.09), Vector3(c, 1.32, z1 - 0.045), rail)
			"e":
				_slab(Vector3(0.05, 1.3, len), Vector3(x1 - 0.025, 0.65, c), panel)
				_slab(Vector3(0.09, 0.05, len), Vector3(x1 - 0.045, 1.32, c), rail)
			"w":
				_slab(Vector3(0.05, 1.3, len), Vector3(x0 + 0.025, 0.65, c), panel)
				_slab(Vector3(0.09, 0.05, len), Vector3(x0 + 0.045, 1.32, c), rail)
	# Drapes between TownDecor's pilasters (every 4 m from 3 m in) on the long walls.
	var x := x0 + 5.0
	while x < x1 - 2.5:
		for side in [-1.0, 1.0]:
			if side > 0 and x < tower_x + 1.4:
				continue
			var z: float = z1 - 0.06 if side > 0 else z0 + 0.06
			var h := minf(4.2, ceiling - 3.0)
			_slab(Vector3(2.9, h, 0.06), Vector3(x, 1.45 + h * 0.5, z), velvet)
			for k in 6:              # folds
				_slab(Vector3(0.12, h, 0.05), Vector3(x - 1.25 + k * 0.5, 1.45 + h * 0.5, z - side * 0.05), velvet)
			_slab(Vector3(3.0, 0.08, 0.12), Vector3(x, 1.45 + h + 0.04, z - side * 0.04), rail)
		x += 4.0


## Leather booths along the side walls, each with a candlelit table.
func _booths(town) -> void:
	var x0 := inner.position.x
	var x1 := inner.end.x
	var z0 := inner.position.y
	var z1 := inner.end.y
	var tower: Dictionary = town.get_box("stair_tower")
	var west_n := float(tower.max[0]) + 0.6 if not tower.is_empty() else x0 + 1.0
	var spots := [
		[Vector3(x0 + 12.5, 0, z0 + 0.05), 0.0, 3.4], [Vector3(x1 - 2.5, 0, z0 + 0.05), 0.0, 3.0],
		[Vector3(west_n + 2.0, 0, z1 - 0.05), PI, 3.4], [Vector3(x1 - 4.0, 0, z1 - 0.05), PI, 3.4],
	]
	for s in spots:
		var p: Vector3 = s[0]
		var yaw: float = s[1]
		var len: float = s[2]
		props.booth(Transform3D(Basis(Vector3.UP, yaw), p), len, Color("#5a1e1a"))
		var fwd := Basis(Vector3.UP, yaw) * Vector3(0, 0, 1)
		props.cocktail_table(p + fwd * 1.15, 0.38, 0.72)


## A round table over each of the cantina's own (their greybox hidden; the box still
## blocks), with a candle and drinks.
func _tables(town, scene: Node) -> void:
	for b in town.boxes():
		var id := str(b.id)
		if not id.begins_with("cantina_table") and id != "fixer_table":
			continue
		var c := Vector3((float(b.min[0]) + float(b.max[0])) * 0.5, 0, (float(b.min[2]) + float(b.max[2])) * 0.5)
		var r := minf(float(b.max[0]) - float(b.min[0]), float(b.max[2]) - float(b.min[2])) * 0.5
		props.cocktail_table(c, r, float(b.max[1]))
		_hide_box(scene, id)


## Warm spots on the band from the ceiling, a cool blue wash from behind, and a
## slow-turning mirror ball over the floor.
func _stage_lights() -> void:
	if stage_r <= 0.0:
		return
	var y := ceiling - 0.6
	var c := stage_c + Vector3(0, 1.2, 0)
	for i in 3:
		var a := TAU * i / 3.0 + 0.4
		props.spot(stage_c + Vector3(cos(a) * (stage_r + 3.0), y, sin(a) * (stage_r + 3.0)), c, Color("#ffb468"), 9.0)
	for i in 2:
		var a := PI + (i - 0.5) * 1.4
		props.spot(stage_c + Vector3(cos(a) * (stage_r + 1.5), y, sin(a) * (stage_r + 1.5)), stage_c + Vector3(0, 0.6, 0), Color("#3a6aff"), 6.0, 12.0)
	props.mirror_ball(stage_c + Vector3(0, ceiling - 1.6 - stage_c.y, 0), ceiling, 0.32)


## A neon sign high on the back wall facing the door: a cocktail glass and a
## crescent moon over a wavy underline.
func _sign(town) -> void:
	var counter: Dictionary = town.get_box("bar_counter")
	var x := inner.position.x + 0.12
	var zc := (inner.position.y + inner.end.y) * 0.5
	var y := 5.6 if ceiling > 7.0 else ceiling - 1.4
	if not counter.is_empty():
		zc = (float(counter.min[2]) + float(counter.max[2])) * 0.5
	var pink := Color("#ff4aa0")
	var teal := Color("#3fe8d8")
	var amber := Color("#ffb040")
	# The glass: a V on a stem, an olive on a pick.
	var g := PackedVector3Array([
		Vector3(x, y + 1.0, zc - 0.9), Vector3(x, y + 0.2, zc - 0.4), Vector3(x, y + 1.0, zc + 0.1),
	])
	props.neon(g, pink, true)
	props.neon(PackedVector3Array([Vector3(x, y + 0.2, zc - 0.4), Vector3(x, y - 0.4, zc - 0.4)]), pink)
	props.neon(PackedVector3Array([Vector3(x, y - 0.4, zc - 0.75), Vector3(x, y - 0.4, zc - 0.05)]), pink)
	props.neon(PackedVector3Array([Vector3(x, y + 0.75, zc - 0.65), Vector3(x, y + 1.15, zc - 0.2)]), amber)
	# The crescent moon.
	var moon := PackedVector3Array()
	for k in 13:
		var a := lerpf(-2.2, 2.2, k / 12.0)
		moon.append(Vector3(x, y + 0.6 + sin(a) * 0.55, zc + 1.0 + cos(a) * 0.55))
	for k in 13:
		var a := lerpf(2.2, -2.2, k / 12.0)
		moon.append(Vector3(x, y + 0.6 + sin(a) * 0.4, zc + 1.18 + cos(a) * 0.38))
	props.neon(moon, teal, true)
	var wave := PackedVector3Array()
	for k in 17:
		var u := k / 16.0
		wave.append(Vector3(x, y - 0.75 + 0.08 * sin(u * TAU * 2.0), zc - 1.0 + u * 2.6))
	props.neon(wave, amber)


## An upright piano against the north wall by the stage and a saxophone resting
## on its stand at the stage's edge: nobody plays them tonight.
func _piano_and_sax(_town) -> void:
	if stage_r <= 0.0:
		return
	var z1 := inner.end.y
	var root := props._group("Piano", Transform3D(Basis(Vector3.UP, PI), Vector3(stage_c.x - 4.6, 0, z1 - 0.4)))
	var lacquer := StandardMaterial3D.new()
	lacquer.albedo_color = Color("#0e0b0a")
	lacquer.roughness = 0.12
	lacquer.clearcoat_enabled = true
	lacquer.clearcoat = 1.0
	props._box(root, Vector3(1.5, 1.25, 0.55), Vector3(0, 0.625, -0.05), lacquer)
	props._box(root, Vector3(1.52, 0.06, 0.6), Vector3(0, 1.28, -0.05), lacquer)
	props._box(root, Vector3(1.4, 0.06, 0.3), Vector3(0, 0.74, 0.32), lacquer)
	props._box(root, Vector3(1.3, 0.025, 0.16), Vector3(0, 0.78, 0.34), props._flat(Color("#f2ece0"), 0.3))
	for k in 36:
		if k % 7 in [2, 6]:
			continue
		props._box(root, Vector3(0.016, 0.02, 0.09), Vector3(-0.63 + k * 0.036, 0.8, 0.31), props._flat(Color("#0a0a0a"), 0.3))
	for side in [-1.0, 1.0]:
		props._box(root, Vector3(0.08, 0.74, 0.08), Vector3(side * 0.66, 0.37, 0.4), lacquer)
	props._box(root, Vector3(0.8, 0.06, 0.36), Vector3(0, 0.5, 0.85), ClubTextures.leather(Color("#2a1410"), 0.12))
	for sx in [-0.35, 0.35]:
		for sz in [0.7, 1.0]:
			props._box(root, Vector3(0.04, 0.48, 0.04), Vector3(sx, 0.24, sz), lacquer)
	props.candle(root, Vector3(0.5, 1.31, -0.05))
	# The saxophone on its stand: a brass body down to the bend and up to the bell.
	var sax := props._group("Sax", Transform3D(Basis(Vector3.UP, 0.6), stage_c + Vector3(stage_r * 0.62, 0, -stage_r * 0.55)))
	var brass := ClubTextures.brushed(Color("#c9a048"), 0.95)
	brass.roughness = 0.22
	var path := [Vector3(0.0, 0.95, -0.02), Vector3(0.0, 0.82, 0.0), Vector3(0.0, 0.35, 0.02), Vector3(0.03, 0.22, 0.06),
		Vector3(0.06, 0.22, 0.13), Vector3(0.07, 0.34, 0.16), Vector3(0.07, 0.5, 0.18)]
	for k in path.size() - 1:
		var r := lerpf(0.018, 0.05, float(k) / (path.size() - 1))
		props._rod(sax, path[k], path[k + 1], r, brass)
	props._cone(sax, 0.09, 0.05, 0.12, Vector3(0.07, 0.56, 0.18), brass)
	props._rod(sax, Vector3(0.0, 0.95, -0.02), Vector3(0.0, 1.02, -0.1), 0.01, props._flat(Color("#141414"), 0.4))
	for k in 6:
		props._cyl(sax, 0.012, 0.01, Vector3(0.0, 0.42 + k * 0.07, 0.04), props._flat(Color("#e8dcc0"), 0.4), Vector3(90, 0, 0))
	var stand := props._flat(Color("#1a1a1a"), 0.5, 0.6)
	props._rod(sax, Vector3(0.0, 0.0, 0.0), Vector3(0.02, 0.3, 0.06), 0.012, stand)
	for k in 3:
		var a := TAU * k / 3.0
		props._rod(sax, Vector3(0.0, 0.02, 0.0), Vector3(cos(a) * 0.22, 0.0, sin(a) * 0.22), 0.01, stand)
