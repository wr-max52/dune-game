class_name SpeederPost
extends Node3D
## Skrugs's speeder stall, just outside the back gate (issue #42). Its footprint is
## world data (the "skrugs_post" landmark in content/core/worlds/port_desert.json
## and content/core/locations/skrugs_post.json), so the ship and speeders already
## collide with it and the player walks on it. This node adds:
##   - the look: a small house in the town's style, the stall, the sand ramp
##     (with its sloped collider: a box would be a wall),
##   - Skrugs: an all-red local behind the counter, a TalkSpot on the town's
##     ConversationHost, run by the same NpcBrain as the Cantina Owner from his
##     own card (content/core/npcs/skrugs_card.json),
##   - the display speeder on its pad (not rideable),
##   - buying: Skrugs proposes (offer_speeder), the chat box shows the price, and
##     only the player's click pays. 100 credits off, a speeder parked behind the
##     house, his mood warm. Speeders you own are saved (WorldState counter
##     "speeders_owned") and parked there again next time.

const LOCATION := "skrugs_post"
const CARD_PATH := "res://content/core/npcs/skrugs_card.json"
const CoreContent := preload("res://src/systems/dataload/core_content.gd")
const RED := { "head": "red", "torso": "red", "legs": "red" }

var demo                              ## town_demo.gd
var ground: WorldGround
var host: ConversationHost
var spot: TalkSpot                    ## Skrugs's
var skrugs: Node3D                    ## his body
var display: SpeederNode
var speeders: Array = []              ## SpeederNode the player owns, here in the world
var origin := Vector3.ZERO            ## the landmark's anchor (base height included)
var yaw := 0.0
var points: Dictionary = {}           ## local name -> Vector3 (see the location file)
var sales := 0                        ## speeders sold this session (tests, traces)
var _offered: Dictionary = {}         ## the item on the card right now
var _paint_scenes: Dictionary = {}    ## issue #82: path -> the paint's model, loaded in the background


func setup(town_demo, world_ground: WorldGround) -> void:
	demo = town_demo
	ground = world_ground
	name = "SpeederPost"


func _ready() -> void:
	var cc := CoreContent.new()
	cc.load_from()
	var world: Dictionary = demo.world if "world" in demo and not demo.world.is_empty() else cc.world_for_town("port_town")
	for lm in world.get("landmarks", []):
		if str(lm.get("location", "")) == LOCATION:
			var at := WorldGround._v3(lm.get("at", [0, 0, 0]))
			origin = Vector3(at.x, ground.terrain.height_at(at.x, at.z), at.z)
			yaw = deg_to_rad(float(lm.get("yaw_deg", 0.0)))
	var loc: Dictionary = cc.get_location(LOCATION)
	for k in loc.get("points", {}):
		points[k] = WorldGround._v3(loc.points[k])
	_build_ramp_collider()
	if demo.use_look:
		_dress(loc)
	_build_skrugs()
	display = SpeederNode.new()
	display.setup(demo, ground, {}, false, str(HoverModel.load_config("speeder").get("look", {}).get("display_paint", "")))
	add_child(display)
	display.place(world_point("display"), yaw + PI * 0.5)
	for i in WorldState.count("speeders_owned"):
		_park(i)
	# Issue #82: each speeder sold is a new paint job, an 8 MB model; load them
	# now, off the main thread, so buying one does not hitch. Held here so they
	# stay cached.
	var look: Dictionary = HoverModel.load_config("speeder").get("look", {})
	for id in look.get("sold_paints", []):
		var path := str(look.get("paints", {}).get(id, ""))
		if path != "" and ResourceLoader.exists(path) and ResourceLoader.load_threaded_request(path) == OK:
			_paint_scenes[path] = null


func _process(_dt: float) -> void:
	var waiting := false
	for path in _paint_scenes:
		if _paint_scenes[path] != null:
			continue
		var st := ResourceLoader.load_threaded_get_status(path)
		if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			waiting = true
		elif st == ResourceLoader.THREAD_LOAD_LOADED:
			_paint_scenes[path] = ResourceLoader.load_threaded_get(path)
		else:
			_paint_scenes[path] = false
	set_process(waiting)


## A point from the location file, in the world.
func world_point(id: String) -> Vector3:
	var lp: Vector3 = points.get(id, Vector3.ZERO)
	return origin + lp.rotated(Vector3.UP, yaw)


## Hand Skrugs to the town's conversation host (when it has one: the look is on,
## or a test built it). Safe to call twice.
func attach_host(h: ConversationHost) -> void:
	if h == null or host == h:
		return
	host = h
	var brain := NpcBrain.new(null, CARD_PATH)
	spot = TalkSpot.new(brain, skrugs, world_point("customer"))
	spot.radius = 2.2
	spot.face_height = 1.55
	host.add_spot(spot)
	brain.sale_offered.connect(_on_offer)
	host.panel.sale_answered.connect(_on_answer)


# ------------------------------------------------------------------ buying

func _on_offer(item: Dictionary) -> void:
	if host == null or host.active != spot:
		return
	_offered = item
	_offered["text"] = str(spot.brain.card.get("sale", {}).get("text", ""))
	host.panel.show_sale(_offered, WorldState.credits)


func _on_answer(id: String, accepted: bool) -> void:
	if not accepted or host == null or host.active != spot or id != str(_offered.get("id", "")):
		return
	buy()


## Pay and park a new speeder behind the house. False (and nothing charged) if
## the player cannot afford it.
func buy() -> bool:
	var sale: Dictionary = spot.brain.card.get("sale", {}) if spot != null else HoverModel.load_config("speeder")
	var price := int(sale.get("price", 100))
	if WorldState.credits < price:
		return false
	WorldState.credits -= price
	WorldState.bump("speeders_owned")
	WorldState.set_flag("bought_speeder")
	WorldState.log_event("Someone bought a speeder from Skrugs outside the back gate.")
	sales += 1
	_park(WorldState.count("speeders_owned") - 1)
	if spot != null:
		var rel := spot.brain.rel
		rel.mood = "warm"
		rel.add_trust(3, "bought a speeder")
		rel.remember("bought a speeder")
		if host != null and host.active == spot:
			var lines: Array = spot.brain.card.get("canned", {}).get("sold", ["She's behind the house."])
			host.panel.commit_line()
			host.panel.set_line(str(lines[0]))
			host.panel.set_mood(rel.mood)
			host.panel.set_money(WorldState.credits, rel.tab)
			spot.speak_pulse()
	return true


## Speeder number `i` parked behind the house (side by side when there are several).
func _park(i: int) -> SpeederNode:
	var s := _spawn(i)
	var side := Vector3(0, 0, (i % 4) * 4.5).rotated(Vector3.UP, yaw)
	s.place(world_point("spawn") + side, yaw + PI * 0.5)   # nose to the open desert, away from the house
	return s


## Issue #95: speeder `i` with its fit (paint and parts) from WorldState.speeder_fits.
## A speeder from before upgrades gets a fit here, its old paint job included.
func fit_for(i: int) -> Dictionary:
	var paints: Array = HoverModel.load_config("speeder").get("look", {}).get("sold_paints", [""])
	while WorldState.speeder_fits.size() <= i:
		var n := WorldState.speeder_fits.size()
		WorldState.speeder_fits.append(SpeederUpgrades.new_fit(str(paints[n % paints.size()])))   # issue #82: each one a different paint job
	return WorldState.speeder_fits[i]


func _spawn(i: int) -> SpeederNode:
	var s := SpeederNode.new()
	var fit := fit_for(i)
	s.setup(demo, ground, SpeederUpgrades.apply(HoverModel.load_config("speeder"), fit), true, str(fit.get("paint", "")))
	s.set_meta("slot", i)
	demo.add_child(s)
	s.destroyed.connect(func(_at): _lost(s))
	speeders.append(s)
	return s


## Issue #95: rebuild speeder `s` with its fit as it is now (after the mechanic
## changed it), where it stands. Returns the new node.
func refit(s: SpeederNode) -> SpeederNode:
	var i := int(s.get_meta("slot", 0))
	var at := s.model.position
	var heading := s.model.yaw
	speeders.erase(s)
	s.queue_free()
	var n := _spawn(i)
	n.place(at, heading)
	return n


## Issue #95: speeder `s` is gone for good (sold for scrap): no burn-out in the log.
func remove(s: SpeederNode) -> void:
	_forget(s)
	s.queue_free()


func _lost(s: SpeederNode) -> void:
	_forget(s)
	WorldState.log_event("A speeder burned out in the sand.")


func _forget(s: SpeederNode) -> void:
	speeders.erase(s)
	WorldState.counters["speeders_owned"] = maxi(0, WorldState.count("speeders_owned") - 1)
	# Its fit goes with it; the ones parked after it move up a slot.
	var i := int(s.get_meta("slot", -1))
	if i >= 0 and i < WorldState.speeder_fits.size():
		WorldState.speeder_fits.remove_at(i)
		for o in speeders:
			if int(o.get_meta("slot", 0)) > i:
				o.set_meta("slot", int(o.get_meta("slot", 0)) - 1)


# ------------------------------------------------------------------ Skrugs

func _build_skrugs() -> void:
	var at := world_point("merchant")
	var face := world_point("customer")
	if demo.use_look:
		var kit := CharacterKit.new(demo._flat_mats(), 0.0)
		skrugs = MerchantNPC.new(kit, "local", RED)
	else:
		skrugs = MerchantNPC.new(null)
	skrugs.name = "Skrugs"
	add_child(skrugs)
	skrugs.global_position = at
	skrugs.rotation.y = atan2(face.x - at.x, face.z - at.z)
	skrugs.look_at_target = demo._player


# ------------------------------------------------------------------ the look

## A wedge collider for the ramp, matching WorldGround's sloped top, so the player
## can walk up it too.
func _build_ramp_collider() -> void:
	for b in ground.boxes:
		if not str(b.id).begins_with(LOCATION + "/") or str(b.get("rise", "")) == "":
			continue
		var mn: Vector3 = b.min
		var mx: Vector3 = b.max
		var pts := PackedVector3Array()
		# Six corners: the low edge, the high edge up top, and the base.
		match str(b.rise):
			"-z":
				pts = [Vector3(mn.x, mn.y, mx.z), Vector3(mx.x, mn.y, mx.z), Vector3(mn.x, mn.y, mn.z),
					Vector3(mx.x, mn.y, mn.z), Vector3(mn.x, mx.y, mn.z), Vector3(mx.x, mx.y, mn.z)]
			"+z":
				pts = [Vector3(mn.x, mn.y, mn.z), Vector3(mx.x, mn.y, mn.z), Vector3(mn.x, mn.y, mx.z),
					Vector3(mx.x, mn.y, mx.z), Vector3(mn.x, mx.y, mx.z), Vector3(mx.x, mx.y, mx.z)]
			"-x":
				pts = [Vector3(mx.x, mn.y, mn.z), Vector3(mx.x, mn.y, mx.z), Vector3(mn.x, mn.y, mn.z),
					Vector3(mn.x, mn.y, mx.z), Vector3(mn.x, mx.y, mn.z), Vector3(mn.x, mx.y, mx.z)]
			_:
				pts = [Vector3(mn.x, mn.y, mn.z), Vector3(mn.x, mn.y, mx.z), Vector3(mx.x, mn.y, mn.z),
					Vector3(mx.x, mn.y, mx.z), Vector3(mx.x, mx.y, mn.z), Vector3(mx.x, mx.y, mx.z)]
		var body := StaticBody3D.new()
		body.name = "RampCollider"
		var cs := CollisionShape3D.new()
		var shape := ConvexPolygonShape3D.new()
		shape.points = pts
		cs.shape = shape
		body.add_child(cs)
		add_child(body)
		# Issue #77: on the ball the box is in its landmark's own frame.
		body.global_transform = WorldGround.box_xf(b)
		if demo.use_look:
			var mi := MeshInstance3D.new()
			mi.name = "Ramp"
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			# Sloped top, two sides, the high end (the low end is flush with the sand).
			var tris := [[0, 4, 1], [1, 4, 5], [0, 2, 4], [1, 5, 3], [2, 3, 4], [3, 5, 4]]
			for t in tris:
				for k in t:
					st.add_vertex(pts[k])
			st.generate_normals()
			mi.mesh = st.commit()
			var sand := StandardMaterial3D.new()
			sand.albedo_color = Color("#c9955a")
			sand.roughness = 1.0
			sand.cull_mode = BaseMaterial3D.CULL_DISABLED
			mi.material_override = sand
			add_child(mi)
			mi.global_transform = body.global_transform


## The house, the stall and the display pad, in the town's palette. Shapes from
## the location file; colours from docs/ART_DIRECTION.md (plaster, madder red).
func _dress(loc: Dictionary) -> void:
	var mats: LookMaterials = demo._flat_mats()
	var plaster := mats.plaster(origin.y, origin.y + 3.2, Color("#8e3a26"), Color("#d8c2a0"))
	var red := mats.flat(Color("#a8322a"), 0.8)
	var wood := mats.flat(Color("#5a3a24"), 0.75)
	var metal := mats.flat(Color("#4a4c52"), 0.45, 0.6)
	for b in loc.get("buildings", []):
		var s := WorldGround._v3(b.get("size", [1, 1, 1]))
		var c := WorldGround._v3(b.get("position", [0, 0, 0]))     # local; _mesh turns it into the world
		match str(b.id):
			"house":
				_mesh(_box(s + Vector3(0, 1.0, 0)), plaster, c + Vector3(0, s.y * 0.5 - 0.5, 0))
				# A domed roof, a door toward the stall and a red awning over it.
				_mesh(_dome(minf(s.x, s.z) * 0.42), plaster, c + Vector3(0, s.y, 0))
				_mesh(_box(Vector3(0.12, 2.1, 1.3)), wood, c + Vector3(s.x * 0.5 + 0.02, 1.05, 2.2))
				_mesh(_box(Vector3(1.6, 0.08, 2.4)), red, c + Vector3(s.x * 0.5 + 0.8, 2.5, 2.2), Vector3(0, 0, -14))
			"stall":
				_mesh(_box(s), wood, c + Vector3(0, s.y * 0.5, 0))
				_mesh(_box(Vector3(s.x + 0.3, 0.08, s.z + 0.3)), red, c + Vector3(0, s.y + 0.04, 0))
				# Posts and a red canopy over the counter and Skrugs.
				for dz in [-s.z * 0.5, s.z * 0.5]:
					_mesh(_cyl(0.06, 2.6), wood, c + Vector3(-1.2, 1.3, dz))
					_mesh(_cyl(0.06, 2.6), wood, c + Vector3(0.45, 1.3, dz))
				_mesh(_box(Vector3(2.2, 0.06, s.z + 0.6)), red, c + Vector3(-0.4, 2.62, 0), Vector3(0, 0, -8))
				# A price board: one speeder, one price.
				_mesh(_box(Vector3(0.06, 0.7, 1.2)), mats.flat(Color("#e8dcc0"), 0.9), c + Vector3(0.5, 1.75, 0))
			"display_pad":
				_mesh(_box(s), metal, c + Vector3(0, s.y * 0.5, 0))


## A mesh at a point in the post's own frame (turned and placed into the world).
func _mesh(mesh: Mesh, mat: Material, local: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)
	mi.global_position = origin + local.rotated(Vector3.UP, yaw)
	mi.rotation_degrees = rot_deg + Vector3(0, rad_to_deg(yaw), 0)
	return mi


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _cyl(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 8
	return c


func _dome(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r
	s.is_hemisphere = true
	s.radial_segments = 20
	s.rings = 8
	return s
