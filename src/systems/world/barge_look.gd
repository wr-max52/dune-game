class_name BargeLook
extends Node3D
## #269 cleanup: how the party barge looks (the look layer; PartyBarge works
## without it in flat colours). A franchise of the town's cantina club, afloat:
##
##   hull     rusted iron plates (ClubTextures.rust) in a skin that flares out to
##            the gunwale and runs forward into a raked prow, lit portholes down
##            both sides, repulsor pods glowing blue underneath
##   decks    wood planks (ClubTextures.wood), darker boards in steerage
##   sails    two masts of solar panels: navy cells, the lines between them
##            glowing blue (ClubTextures.solar), pulsing slowly with the music
##   top      the cantina's look: a checker dance floor in front of the band's
##            stage, panelled wall and velvet drape behind the band, the club's
##            neon sign (the cocktail glass and the moon) over it, warm and blue
##            stage spots, jazz speakers, an upright piano and a sax on its stand,
##            candlelit tables, the bar's bottles; the band's instruments are the
##            cantina's (ClubProps.drum_kit, upright_bass)
##   lower    a small rave: the DJ desk, a light-up floor, a hologram wall behind
##            the DJ, speaker stacks with strobes, moving heads, a mirror ball and
##            neon strips; a lounge aft with leather booths and a rug
##   panel    the control panel at the stern in the cruiser bridge's style: a
##            screen with a compass and a course needle, a hologram arrow over
##            it, rows of glowing buttons, a big engage button and a lever
##
## Everything is in the barge's own space (it is a child of PartyBarge.look) and
## every texture is mapped in its mesh's own space (ClubTextures.local), so
## nothing swims as the barge moves. The barge's parts are merged into one mesh
## a finish; small props fade out past PROP_M and their lights past LIGHT_M.

const PROP_M := 140.0
const LIGHT_M := 90.0
const SCREEN := Color("#1d86b0")      ## the cruiser's console screens

var barge: PartyBarge
var jazz: ClubProps                   ## the top deck (the cantina's style)
var rave: ClubProps                   ## the lower deck
var needle: Node3D                    ## the course on the panel's compass
var arrow: Node3D                     ## the hologram arrow over the panel
var lever: Node3D
var engage_mat: StandardMaterial3D
var _solar: StandardMaterial3D
var _top := 0.0
var _bow := 0.0


func build(b: PartyBarge) -> void:
	barge = b
	name = "BargeLook"
	_top = float(b._y[2])
	_bow = -b._L * 0.5 + 0.4
	jazz = ClubProps.new("jazz", float(b.cfg.get("bpm", 100.0)))
	jazz.name = "Jazz"
	jazz.live_fn = b.party_on
	add_child(jazz)
	rave = ClubProps.new("rave", float(b.cfg.get("bpm", 100.0)))
	rave.name = "Rave"
	rave.live_fn = b.party_on
	add_child(rave)
	var mats := _materials()
	for f in mats:
		if mats[f] is StandardMaterial3D and (mats[f] as StandardMaterial3D).uv1_world_triplanar:
			mats[f] = ClubTextures.local(mats[f])
	for mi in b.merged(mats):
		b.look.add_child(mi)
	_skin()
	_portholes()
	_repulsors()
	_top_deck()
	_band()
	_lower_deck()
	_steerage()
	_console()
	_finish(self)


## Each finish of the barge's parts, painted.
func _materials() -> Dictionary:
	_solar = (ClubTextures.local(ClubTextures.solar(Color("#3aa8ff"), 0.45, 1.4)).duplicate() as StandardMaterial3D)
	jazz.pulses.append([_solar, 1.0, 1.8, 4.0, 0.0])
	var lamp := ClubTextures.glow(Color("#ffb860"), 3.0)
	return {
		"hull": ClubTextures.rust(Color("#5a5450")),
		"deck": ClubTextures.wood(Color("#9a7448"), 0.2, 0.7),
		"steerage": ClubTextures.wood(Color("#4a3424"), 0.24, 0.8),
		"stage": ClubTextures.wood(Color("#6a4024"), 0.12, 0.4),
		"trim": ClubTextures.rust(Color("#3a3634"), 1.6),
		"brass": ClubTextures.brushed(Color("#b08e50"), 0.9),
		"solar": _solar,
		"awning": ClubTextures.velvet(Color("#5a1420")),
		"awning_stripe": ClubTextures.velvet(Color("#d9c9a3")),
		"velvet": ClubTextures.velvet(Color("#5a1420")),
		"bar": ClubTextures.panels(Color("#3e2414"), 1.0),
		"console": ClubTextures.rust(Color("#4a4e52"), 1.6),
		"crate": ClubTextures.wood(Color("#7a5a38"), 0.15),
		"lamp": lamp,
		"screen": ClubTextures.glow(SCREEN, 1.3),
	}


# ------------------------------------------------------------------ the hull's skin

## The outside of the hull: a cross-section that runs from a flat bottom under the
## keel out to the bilge and up to the gunwale, flaring out a little; forward of
## the bow wall it narrows and lifts into a raked prow, capped at the gunwale.
## The barge's own walls stand just inside it.
func _skin() -> void:
	var d := barge.dims()
	var L := float(d.length)
	var W := float(d.width)
	var h := float(d.hover)
	var y1 := float(d.decks[1])
	var gun := _top + 1.1
	var prow := float(d.prow)
	# Stations from the stern forward: [z, how far into the prow 0..1].
	var stations: Array = [[L * 0.5 + 0.05, 0.0], [-L * 0.5, 0.0]]
	for k in [0.2, 0.4, 0.6, 0.78, 0.92, 1.0]:
		stations.append([-L * 0.5 - prow * k, k])
	var rings: Array = []
	for s in stations:
		var f := float(s[1])
		var wf := pow(cos(f * PI * 0.5), 0.75)
		var keel := lerpf(h - 0.35, y1 + 0.6, pow(f, 1.4))
		var bilge := lerpf(h - 0.02, (keel + gun) * 0.5, pow(f, 1.6))
		rings.append([
			Vector3(0.0, keel, float(s[0])),
			Vector3(W * 0.4 * wf, keel, float(s[0])),
			Vector3((W * 0.5 + 0.05) * wf, bilge, float(s[0])),
			Vector3((W * 0.5 + 0.15) * wf, gun, float(s[0])),
		])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	for i in rings.size() - 1:
		var a: Array = rings[i]
		var b: Array = rings[i + 1]
		for j in a.size() - 1:
			for sx in [1.0, -1.0]:
				var m := Vector3(sx, 1, 1)
				_quad(st, (a[j] as Vector3) * m, (b[j] as Vector3) * m, (b[j + 1] as Vector3) * m, (a[j + 1] as Vector3) * m, sx < 0.0)
	# The transom at the stern (up to the top deck: the gangplank goes over it) and
	# the cap over the prow at the gunwale, flat.
	st.set_smooth_group(-1)
	var stern: Array = rings[0]
	var poly := PackedVector3Array()
	for j in stern.size():
		var p: Vector3 = stern[j]
		poly.append(Vector3(p.x, minf(p.y, _top), p.z))
	for j in range(stern.size() - 1, -1, -1):
		var p: Vector3 = stern[j]
		poly.append(Vector3(-p.x, minf(p.y, _top), p.z))
	_fan(st, poly)
	var cap := PackedVector3Array()
	for i in range(1, rings.size()):
		cap.append(rings[i][3])
	for i in range(rings.size() - 1, 0, -1):
		var p: Vector3 = rings[i][3]
		cap.append(Vector3(-p.x, p.y, p.z))
	_fan(st, cap)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "HullSkin"
	mi.mesh = st.commit()
	var m := ClubTextures.local(ClubTextures.rust(Color("#5a5450"))).duplicate() as StandardMaterial3D
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	barge.look.add_child(mi)
	# A lamp at the tip of the prow, and a brass band round the gunwale's edge.
	var tip: Vector3 = rings[rings.size() - 1][3]
	jazz._sphere(jazz, 0.4, tip + Vector3(0, 0.5, 0), ClubTextures.glow(Color("#ffb860"), 4.0))
	jazz._rod(jazz, tip, tip + Vector3(0, 0.5, 0), 0.06, ClubTextures.brushed(Color("#b08e50"), 0.9))


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, flip: bool) -> void:
	var tri := [a, b, c, a, c, d] if not flip else [a, c, b, a, d, c]
	for v in tri:
		st.add_vertex(v)


func _fan(st: SurfaceTool, poly: PackedVector3Array) -> void:
	var c := Vector3.ZERO
	for p in poly:
		c += p
	c /= maxf(1.0, poly.size())
	for i in poly.size():
		st.add_vertex(c)
		st.add_vertex(poly[i])
		st.add_vertex(poly[(i + 1) % poly.size()])


## Round windows down both sides, lit warm from inside, in brass rims.
func _portholes() -> void:
	var W := barge._W
	var rim := ClubTextures.local(ClubTextures.brushed(Color("#b08e50"), 0.9))
	var glass := ClubTextures.glow(Color("#ffc070"), 2.2)
	var rims := SurfaceTool.new()
	rims.begin(Mesh.PRIMITIVE_TRIANGLES)
	var panes := SurfaceTool.new()
	panes.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring := CylinderMesh.new()
	ring.top_radius = 0.32
	ring.bottom_radius = 0.32
	ring.height = 0.08
	ring.radial_segments = 16
	var pane := CylinderMesh.new()
	pane.top_radius = 0.24
	pane.bottom_radius = 0.24
	pane.height = 0.1
	pane.radial_segments = 16
	for row in [[float(barge._y[1]) + 1.7, 3.2], [float(barge._y[0]) + 1.3, 4.0]]:
		var z := -barge._L * 0.5 + 2.4
		var y := float(row[0])
		var h := float(barge.cfg.get("hover_m", 1.2)) - 0.02
		var x := W * 0.5 + 0.05 + 0.1 * (y - h) / (_top + 1.1 - h) + 0.02
		while z < barge._L * 0.5 - 2.0:
			for sx in [-1.0, 1.0]:
				var xf := Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(sx * x, y, z))
				rims.append_from(ring, 0, xf)
				panes.append_from(pane, 0, xf)
			z += float(row[1])
	for pair in [[rims, rim], [panes, glass]]:
		var mi := MeshInstance3D.new()
		mi.mesh = (pair[0] as SurfaceTool).commit()
		mi.material_override = pair[1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		barge.look.add_child(mi)


## Four repulsor pods under the hull, glowing blue onto the sand.
func _repulsors() -> void:
	var h := float(barge.cfg.get("hover_m", 1.2))
	var iron := ClubTextures.rust(Color("#3a3634"), 1.6)
	var glow := ClubTextures.glow(Color("#3aa8ff"), 5.0)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var at := Vector3(sx * barge._W * 0.28, h - 0.45, sz * barge._L * 0.3)
			jazz._cyl(jazz, 0.9, 0.5, at, iron)
			jazz._cyl(jazz, 0.7, 0.06, at - Vector3(0, 0.27, 0), glow)
	jazz.pulses.append([glow, 3.0, 6.0, 2.0, 0.0])
	var l := OmniLight3D.new()
	l.light_color = Color("#3aa8ff")
	l.light_energy = 2.0
	l.omni_range = 9.0
	l.position = Vector3(0, h - 1.0, 0)
	jazz.add_child(l)


# ------------------------------------------------------------------ the top deck

func _top_deck() -> void:
	var W := barge._W
	var top := _top
	var stage_end := _bow + PartyBarge.STAGE_D
	var brass := ClubTextures.brushed(Color("#b08e50"), 0.9)
	# The checker dance floor between the stage and the awning's far poles, in brass.
	var fz0 := stage_end
	var fz1 := -6.8
	var fw := W - 1.6
	jazz._box(jazz, Vector3(fw, 0.012, fz1 - fz0), Vector3(0, top + 0.006, (fz0 + fz1) * 0.5), ClubTextures.checker(Color("#151312"), Color("#d6c8a8"), 0.6))
	for z in [fz0 + 0.03, fz1 - 0.03]:
		jazz._box(jazz, Vector3(fw + 0.06, 0.016, 0.06), Vector3(0, top + 0.008, z), brass)
	for sx in [-1.0, 1.0]:
		jazz._box(jazz, Vector3(0.06, 0.016, fz1 - fz0), Vector3(sx * fw * 0.5, top + 0.008, (fz0 + fz1) * 0.5), brass)
	jazz._box(jazz, Vector3(W - 1.2, 0.03, 0.06), Vector3(0, top + 0.135, stage_end), brass)       # the stage's lip
	# Behind the band: wainscot, a brass rail and a velvet drape on the bow wall.
	var wall_z := _bow + 0.27
	jazz._box(jazz, Vector3(W - 1.4, 1.3, 0.04), Vector3(0, top + 0.12 + 0.65, wall_z), ClubTextures.panels(Color("#3e2414"), 1.1))
	jazz._box(jazz, Vector3(W - 1.4, 0.05, 0.08), Vector3(0, top + 0.12 + 1.32, wall_z + 0.02), brass)
	var velvet := ClubTextures.velvet(Color("#5a1420"))
	jazz._box(jazz, Vector3(W - 1.4, 1.9, 0.04), Vector3(0, top + 0.12 + 1.35 + 0.95, wall_z), velvet)
	for k in 14:
		jazz._box(jazz, Vector3(0.12, 1.9, 0.05), Vector3(-W * 0.5 + 1.1 + k * (W - 2.2) / 13.0, top + 0.12 + 1.35 + 0.95, wall_z + 0.03), velvet)
	_sign(Vector3(0, top + 4.3, _bow + 0.12))
	# Spots on the band from the awning's front edge, a blue wash from the corners.
	var band_at := Vector3(0, top + 1.2, _bow + 2.6)
	for x in [-3.2, 0.0, 3.2]:
		jazz.spot(Vector3(x, top + 4.25, stage_end + 0.5), band_at + Vector3(x * 0.4, 0, 0), Color("#ffb468"), 7.0)
	for sx in [-1.0, 1.0]:
		jazz.spot(Vector3(sx * (W * 0.5 - 0.8), top + 3.6, _bow + 0.6), band_at + Vector3(-sx * 1.0, -0.6, 1.0), Color("#3a6aff"), 5.0, 10.0)
	# Speaker stacks at the stage's front corners, facing aft.
	for sx in [-1.0, 1.0]:
		var foot := Vector3(sx * (W * 0.5 - 1.1), top + 0.12, stage_end - 0.5)
		jazz.speaker(Transform3D(Basis(Vector3.UP, -sx * 0.25), foot), Vector3(0.8, 1.4, 0.6))
		jazz.speaker(Transform3D(Basis(Vector3.UP, -sx * 0.25), foot + Vector3(0, 1.4, 0)), Vector3(0.7, 0.7, 0.55))
	_piano(Transform3D(Basis.IDENTITY, Vector3(-W * 0.5 + 1.6, top + 0.12, _bow + 0.85)))
	_sax(Transform3D(Basis(Vector3.UP, -0.6), Vector3(W * 0.5 - 1.7, top + 0.12, _bow + 3.4)))
	# The bar: bottles along it and glasses, a lamp over it.
	var colors := CantinaDressing.SERVED_COLORS
	for i in 11:
		var bottle := CantinaDressing.bottle_mesh(Color(colors[i % colors.size()]))
		jazz.add_child(bottle)
		bottle.position = Vector3(W * 0.5 - 1.45 + (i % 2) * 0.22, top + 1.18, -3.6 + i * 0.5)
	for i in 4:
		jazz._glass(jazz, Vector3(W * 0.5 - 1.0, top + 1.18, -2.8 + i * 1.2), Color(colors[(i * 3) % colors.size()]))
	_lamp(Vector3(W * 0.5 - 1.6, top + 3.0, -1.0), 1.6, 8.0)
	# Candlelit tables aft of the dance floor, and lamps over the dais.
	for at in [Vector3(-W * 0.5 + 1.6, top, 5.0), Vector3(-W * 0.5 + 1.6, top, 8.0), Vector3(W * 0.5 - 1.6, top, 4.4), Vector3(W * 0.5 - 1.6, top, 7.4)]:
		jazz.cocktail_table(at, 0.42, 0.8)
	_lamp(Vector3(0, top + 3.4, 10.5), 1.8, 9.0)
	_lamp(Vector3(0, top + 3.8, 1.0), 1.4, 10.0)


## The club's neon sign, as over the cantina's bar: a cocktail glass and a
## crescent moon over a wavy line, on a dark board, facing aft.
func _sign(at: Vector3) -> void:
	var board := ClubTextures.brushed(Color("#141210"), 0.4)
	jazz._box(jazz, Vector3(4.6, 1.9, 0.12), at, board)
	jazz._box(jazz, Vector3(4.7, 0.06, 0.16), at + Vector3(0, 0.98, 0), ClubTextures.brushed(Color("#b08e50"), 0.9))
	var z := at.z + 0.08
	var x := at.x - 0.9
	var y := at.y - 0.2
	var pink := Color("#ff4aa0")
	var teal := Color("#3fe8d8")
	var amber := Color("#ffb040")
	jazz.neon(PackedVector3Array([Vector3(x - 0.5, y + 0.85, z), Vector3(x, y + 0.15, z), Vector3(x + 0.5, y + 0.85, z)]), pink, true)
	jazz.neon(PackedVector3Array([Vector3(x, y + 0.15, z), Vector3(x, y - 0.35, z)]), pink)
	jazz.neon(PackedVector3Array([Vector3(x - 0.3, y - 0.35, z), Vector3(x + 0.3, y - 0.35, z)]), pink)
	jazz.neon(PackedVector3Array([Vector3(x - 0.25, y + 0.65, z), Vector3(x + 0.15, y + 1.0, z)]), amber)
	var moon := PackedVector3Array()
	for k in 13:
		var a := lerpf(-2.2, 2.2, k / 12.0)
		moon.append(Vector3(x + 1.5 - cos(a) * 0.5, y + 0.5 + sin(a) * 0.5, z))
	for k in 13:
		var a := lerpf(2.2, -2.2, k / 12.0)
		moon.append(Vector3(x + 1.66 - cos(a) * 0.35, y + 0.5 + sin(a) * 0.37, z))
	jazz.neon(moon, teal, true)
	var wave := PackedVector3Array()
	for k in 17:
		var u := k / 16.0
		wave.append(Vector3(x - 0.7 + u * 3.2, y - 0.62 + 0.07 * sin(u * TAU * 2.0), z))
	jazz.neon(wave, amber)


## An upright piano against the wall, keys facing aft: nobody plays it tonight.
func _piano(at: Transform3D) -> void:
	var root := jazz._group("Piano", at)
	var lacquer := StandardMaterial3D.new()
	lacquer.albedo_color = Color("#0e0b0a")
	lacquer.roughness = 0.12
	lacquer.clearcoat_enabled = true
	lacquer.clearcoat = 1.0
	jazz._box(root, Vector3(1.5, 1.25, 0.55), Vector3(0, 0.625, -0.05), lacquer)
	jazz._box(root, Vector3(1.52, 0.06, 0.6), Vector3(0, 1.28, -0.05), lacquer)
	jazz._box(root, Vector3(1.4, 0.06, 0.3), Vector3(0, 0.74, 0.32), lacquer)
	jazz._box(root, Vector3(1.3, 0.025, 0.16), Vector3(0, 0.78, 0.34), jazz._flat(Color("#f2ece0"), 0.3))
	for k in 36:
		if k % 7 in [2, 6]:
			continue
		jazz._box(root, Vector3(0.016, 0.02, 0.09), Vector3(-0.63 + k * 0.036, 0.8, 0.31), jazz._flat(Color("#0a0a0a"), 0.3))
	for side in [-1.0, 1.0]:
		jazz._box(root, Vector3(0.08, 0.74, 0.08), Vector3(side * 0.66, 0.37, 0.4), lacquer)
	jazz._box(root, Vector3(0.8, 0.06, 0.36), Vector3(0, 0.5, 0.85), ClubTextures.leather(Color("#2a1410"), 0.12))
	jazz.candle(root, Vector3(0.5, 1.31, -0.05))


## A saxophone resting on its stand.
func _sax(at: Transform3D) -> void:
	var sax := jazz._group("Sax", at)
	var b := ClubTextures.brushed(Color("#c9a048"), 0.95)
	var path := [Vector3(0.0, 0.95, -0.02), Vector3(0.0, 0.82, 0.0), Vector3(0.0, 0.35, 0.02), Vector3(0.03, 0.22, 0.06),
		Vector3(0.06, 0.22, 0.13), Vector3(0.07, 0.34, 0.16), Vector3(0.07, 0.5, 0.18)]
	for k in path.size() - 1:
		jazz._rod(sax, path[k], path[k + 1], lerpf(0.018, 0.05, float(k) / (path.size() - 1)), b)
	jazz._cone(sax, 0.09, 0.05, 0.12, Vector3(0.07, 0.56, 0.18), b)
	var stand := jazz._flat(Color("#1a1a1a"), 0.5, 0.6)
	jazz._rod(sax, Vector3.ZERO, Vector3(0.02, 0.3, 0.06), 0.012, stand)
	for k in 3:
		var a := TAU * k / 3.0
		jazz._rod(sax, Vector3(0.0, 0.02, 0.0), Vector3(cos(a) * 0.22, 0.0, sin(a) * 0.22), 0.01, stand)


## A warm hanging lamp: a shade, a bulb and its light.
func _lamp(at: Vector3, energy: float, reach: float, props: ClubProps = null) -> void:
	var p := props if props != null else jazz
	p._cone(p, 0.08, 0.28, 0.22, at + Vector3(0, 0.1, 0), ClubTextures.brushed(Color("#2a2420"), 0.8))
	p._sphere(p, 0.09, at, ClubTextures.glow(Color("#ffc070"), 4.0))
	var l := OmniLight3D.new()
	l.light_color = Color("#ffb860")
	l.light_energy = energy
	l.omni_range = reach
	l.shadow_enabled = false
	l.position = at - Vector3(0, 0.2, 0)
	p.add_child(l)


## The cantina's instruments in front of the band (built in each performer's own
## space, so their hands land on them), the DJ's desk below, sticks for the drummer.
func _band() -> void:
	for p in barge.band:
		var at := Transform3D(Basis(Vector3.UP, float(p.yaw)), p.spot)
		match str(p.perform):
			"drum":
				jazz.drum_kit(at)
				var body: Node3D = p.body
				if body.has_meta("joints"):
					ClubProps.sticks(body.get_meta("joints"))
			"bass":
				jazz.upright_bass(at)
			"dj":
				rave.dj_desk(at)


# ------------------------------------------------------------------ below

## The lower deck: a small rave at the bow end round the DJ, a lounge aft.
func _lower_deck() -> void:
	var W := barge._W
	var y1 := float(barge._y[1])
	var ceil := _top - 0.3
	var dj_z := _bow + 3.0
	# The light-up floor in front of the DJ.
	var fz0 := _bow + 5.0
	var cols := 6
	var rows := 7
	rave._box(rave, Vector3(cols + 0.4, 0.03, rows + 0.4), Vector3(0, y1 + 0.015, fz0 + rows * 0.5), ClubTextures.brushed(Color("#0c0c0e"), 0.6))
	for cx in cols:
		for cz in rows:
			var x := -cols * 0.5 + 0.5 + cx
			var z := fz0 + 0.5 + cz
			var m := ClubTextures.glow(Color.from_hsv(0.0, 0.8, 1.0), 1.0)
			m.albedo_color = Color("#101012")
			m.roughness = 0.15
			rave._box(rave, Vector3(0.92, 0.035, 0.92), Vector3(x, y1 + 0.02, z), m)
			rave.cycles.append([m, 0.06, (x + z) * 0.03])
			rave.pulses.append([m, 0.25, 2.6, 1.0, -Vector2(x, z - fz0 - rows * 0.5).length() * 0.09])
	_hologram(Vector3(0, y1, _bow + 0.5), 6.4, ceil - y1 - 0.6)
	# Speaker stacks either side of the DJ, a strobe on each.
	for sx in [-1.0, 1.0]:
		var foot := Vector3(sx * 3.6, y1, dj_z - 0.2)
		var yaw := Basis(Vector3.UP, -sx * 0.3)
		rave.speaker(Transform3D(yaw, foot), Vector3(1.1, 1.0, 0.8))
		rave.speaker(Transform3D(yaw, foot + Vector3(0, 1.0, 0)), Vector3(0.9, 0.8, 0.7))
		var strobe := ClubTextures.glow(Color("#ffffff"), 1.0)
		rave._box(rave, Vector3(0.4, 0.14, 0.1), foot + Vector3(0, 1.9, 0.1), strobe).basis = yaw
		rave.pulses.append([strobe, 0.0, 30.0, 2.0, 0.0])
		var flash := OmniLight3D.new()
		flash.light_color = Color("#e8f0ff")
		flash.omni_range = 9.0
		flash.shadow_enabled = false
		flash.position = foot + Vector3(0, 2.0, 0.5)
		rave.add_child(flash)
		rave.lights.append([flash, 0.0, 3.0, 2.0, 0.0])
	# Moving heads on the ceiling, sweeping over the floor; a mirror ball.
	var hues := [Color("#ff2bd6"), Color("#2bd9ff"), Color("#7aff5a"), Color("#ff2bd6")]
	var k := 0
	for z in [fz0 + 0.5, fz0 + rows - 0.5]:
		for sx in [-1.0, 1.0]:
			var from := Vector3(sx * 2.6, ceil - 0.15, z)
			var l := rave.spot(from, Vector3(-sx * 1.0, y1, fz0 + rows * 0.5), hues[k], 8.0, 24.0)
			rave.lights.append([l, 3.0, 9.0, 1.0, k * 0.25])
			k += 1
	rave.mirror_ball(Vector3(0, ceil - 0.6, fz0 + rows * 0.5), ceil, 0.28)
	# Neon strips down both walls over the rave, cyan low, magenta high.
	for sx in [-1.0, 1.0]:
		var x: float = sx * (W * 0.5 - 0.44)
		rave.neon(PackedVector3Array([Vector3(x, y1 + 0.35, _bow + 0.6), Vector3(x, y1 + 0.35, -7.2)]), Color("#2bd9ff"), false, 0.025, 4.0)
		rave.neon(PackedVector3Array([Vector3(x, ceil - 0.25, _bow + 0.6), Vector3(x, ceil - 0.25, -7.2)]), Color("#ff2bd6"), false, 0.025, 4.0)
	# The lounge aft: booths on the port wall, a rug, tables and warm lamps.
	jazz._box(jazz, Vector3(4.0, 0.012, 7.6), Vector3(-W * 0.5 + 2.7, y1 + 0.006, 8.4), ClubTextures.rug(Color("#5a1e22"), Color("#c9a058"), 1.2))
	for z in [6.2, 10.4]:
		jazz.booth(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-W * 0.5 + 0.42, y1, z)), 3.2, Color("#5a1e1a"))
		jazz.cocktail_table(Vector3(-W * 0.5 + 1.75, y1, z), 0.38, 0.72)
	jazz.cocktail_table(Vector3(-1.4, y1, 7.0), 0.42, 0.78)
	jazz.cocktail_table(Vector3(-1.4, y1, 10.6), 0.42, 0.78)
	_lamp(Vector3(-W * 0.5 + 2.4, ceil - 0.4, 6.2), 1.4, 7.0)
	_lamp(Vector3(-W * 0.5 + 2.4, ceil - 0.4, 10.4), 1.4, 7.0)
	_lamp(Vector3(1.6, ceil - 0.4, 15.0), 1.2, 8.0)


## The hologram wall behind the DJ: see-through panels of light rolling through
## the colours, scan lines and a band of light climbing it, over a glowing strip.
func _hologram(foot: Vector3, width: float, height: float) -> void:
	var emitter := ClubTextures.glow(Color("#2bd9ff"), 5.0)
	rave._box(rave, Vector3(width, 0.06, 0.16), foot + Vector3(0, 0.03, 0), emitter)
	rave.cycles.append([emitter, 0.1, 0.0])
	var y0 := 0.35
	var cols := 8
	var rows := 3
	var pw := width / cols
	var ph := height / rows
	for cx in cols:
		for cy in rows:
			var m := ClubTextures.beam(Color.from_hsv(0.0, 0.85, 1.0), 0.3)
			var tile := rave._box(rave, Vector3(pw - 0.08, ph - 0.08, 0.01), foot + Vector3((cx - (cols - 1) * 0.5) * pw, y0 + (cy + 0.5) * ph, 0.1), m)
			tile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			rave.cycles.append([m, 0.1, cx * 0.035 + cy * 0.06])
			rave.fades.append([m, 0.05, 0.3, 1.0, absf(cx - (cols - 1) * 0.5) * 0.06])
	var band_mat := ClubTextures.beam(Color("#e8fbff"), 0.35)
	var band := rave._box(rave, Vector3(width, 0.1, 0.02), foot, band_mat)
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rave.scans.append([band, foot + Vector3(0, y0, 0.12), foot + Vector3(0, y0 + height, 0.12), 2.4, 0.0])
	var wash := OmniLight3D.new()
	wash.omni_range = 7.0
	wash.light_energy = 1.0
	wash.shadow_enabled = false
	wash.position = foot + Vector3(0, y0 + height * 0.5, 1.4)
	rave.add_child(wash)
	rave.cycles.append([wash, 0.1, 0.2])


func _steerage() -> void:
	var y0 := float(barge._y[0])
	var y1 := float(barge._y[1])
	for z in [-9.0, 6.0]:
		var at := Vector3(0, y1 - 0.75, z)
		jazz._rod(jazz, at, Vector3(0, y1 - 0.3, z), 0.01, jazz._flat(Color("#1a1a1a"), 0.6))
		_lamp(at, 1.2, 9.0)
	jazz.cocktail_table(Vector3(1.4, y0, -2.0), 0.4, 0.74, true)


# ------------------------------------------------------------------ the panel

## The control panel, in the cruiser bridge's colours: a desk tipped toward you,
## a compass screen with the course needle (the bow is up), a hologram arrow over
## it pointing the course, rows of buttons, a big engage button and a lever.
func _console() -> void:
	var c := jazz._group("Console", Transform3D(Basis.IDENTITY, Vector3(3.6, _top, 16.1)))
	var face := jazz._group("Face", Transform3D(Basis(Vector3.RIGHT, 0.38), Vector3(0, 1.04, 0.0)), c)
	jazz._box(face, Vector3(1.86, 0.05, 0.78), Vector3.ZERO, ClubTextures.brushed(Color("#26282c"), 0.7))
	jazz._box(face, Vector3(1.9, 0.03, 0.04), Vector3(0, 0.02, 0.4), ClubTextures.brushed(Color("#b08e50"), 0.9))
	var screen := ClubTextures.glow(SCREEN, 1.3)
	jazz._box(face, Vector3(0.62, 0.012, 0.5), Vector3(0, 0.03, 0.0), screen)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.17
	ring.outer_radius = 0.185
	ring.rings = 24
	jazz._put(face, ring, Vector3(0, 0.04, 0.0), ClubTextures.glow(Color("#9fe8ff"), 3.0))
	jazz._box(face, Vector3(0.02, 0.012, 0.05), Vector3(0, 0.04, -0.2), ClubTextures.glow(Color("#ffffff"), 3.0))     # the bow
	needle = Node3D.new()
	needle.position = Vector3(0, 0.045, 0)
	face.add_child(needle)
	jazz._box(needle, Vector3(0.025, 0.01, 0.17), Vector3(0, 0, -0.085), ClubTextures.glow(Color("#ffcc33"), 4.0))
	# Buttons either side of the screen, blinking on their own time.
	var palette := [Color("#3fe8ff"), Color("#2b8cff"), Color("#ffcc33"), Color("#ff4a3a"), Color("#7aff5a")]
	for sx in [-1.0, 1.0]:
		for gx in 3:
			for gz in 4:
				var b := ClubTextures.glow(palette[(gx * 2 + gz + (1 if sx > 0 else 0)) % palette.size()], 2.0)
				jazz._box(face, Vector3(0.07, 0.025, 0.06), Vector3(sx * (0.45 + gx * 0.11), 0.035, -0.24 + gz * 0.12), b)
				jazz.pulses.append([b, 0.4, 3.0, [2.0, 3.0, 5.0][(gx + gz) % 3], float(gx * 4 + gz) * 0.13])
	engage_mat = ClubTextures.glow(Color("#ffcc33"), 3.0)
	jazz._cyl(face, 0.07, 0.04, Vector3(0.0, 0.04, 0.33), jazz._flat(Color("#1a1a1c"), 0.5, 0.6))
	jazz._cyl(face, 0.055, 0.05, Vector3(0.0, 0.05, 0.33), engage_mat)
	lever = Node3D.new()
	lever.position = Vector3(0.82, 0.03, 0.3)
	face.add_child(lever)
	jazz._rod(lever, Vector3.ZERO, Vector3(0, 0.22, 0), 0.015, jazz._flat(Color("#c0c0c4"), 0.3, 0.9))
	jazz._sphere(lever, 0.04, Vector3(0, 0.24, 0), jazz._flat(Color("#a8322a"), 0.4))
	# The hologram arrow over the panel, turning with the course.
	arrow = Node3D.new()
	arrow.position = Vector3(0, 1.75, -0.2)
	c.add_child(arrow)
	var holo := ClubTextures.beam(Color("#3fe8ff"), 0.45)
	var shaft := jazz._box(arrow, Vector3(0.06, 0.02, 0.4), Vector3(0, 0, 0.05), holo)
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var head := jazz._cone(arrow, 0.0, 0.12, 0.2, Vector3(0, 0, -0.25), holo, Vector3(-90, 0, 0))
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	jazz.fades.append([holo, 0.25, 0.55, 1.0, 0.0])
	jazz._cyl(c, 0.1, 0.02, Vector3(0, 1.33, -0.2), ClubTextures.glow(Color("#3fe8ff"), 2.0))      # its emitter
	var l := OmniLight3D.new()
	l.light_color = SCREEN
	l.light_energy = 0.8
	l.omni_range = 3.0
	l.position = Vector3(0, 1.5, 0.4)
	c.add_child(l)


## The panel shows the course (`off`: radians off the bow, + to starboard) and
## whether it is under way (the engage button green, the lever forward) or
## stopped against something (red).
func show_panel(off: float, under_way: bool, blocked: bool) -> void:
	if needle == null:
		return
	needle.rotation.y = -off
	arrow.rotation.y = -off
	var c := Color("#7aff5a") if under_way else (Color("#ff4a3a") if blocked else Color("#ffcc33"))
	engage_mat.emission = c
	engage_mat.albedo_color = c.darkened(0.5)
	lever.rotation.x = -0.6 if under_way else 0.4


# ------------------------------------------------------------------ last pass

## Every texture mapped in its mesh's own space, small things fading out far off,
## lights too.
func _finish(n: Node) -> void:
	for ch in n.get_children():
		if ch is GeometryInstance3D:
			var gi := ch as GeometryInstance3D
			var m = gi.material_override
			if m is StandardMaterial3D and (m as StandardMaterial3D).uv1_world_triplanar:
				gi.material_override = ClubTextures.local(m)
			gi.visibility_range_end = PROP_M
			gi.visibility_range_end_margin = 10.0
			gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		elif ch is Light3D:
			var l := ch as Light3D
			l.distance_fade_enabled = true
			l.distance_fade_begin = LIGHT_M
			l.distance_fade_length = 20.0
		_finish(ch)
