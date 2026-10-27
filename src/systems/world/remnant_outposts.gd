class_name RemnantOutposts
extends Node3D
## The Remnant's three desert outposts out the front gate (issue #64): near, mid
## and far, each a little different. Their footprints are world data (landmarks
## in content/core/worlds/port_desert.json, buildings in
## content/core/locations/remnant_outpost_*.json), so ships and speeders already
## collide with them. This node adds, for each one:
##   - the ground: a heightmap collider of the sand round it, so the people there
##     stand on something even when the town's terrain collider (which follows the
##     player) is far away,
##   - the look: one dark grey, black and red building (the far ones add a comms
##     mast and a lookout), and a cargo ship parked beside it,
##   - two troopers (soldiers/outpost_trooper.json) for the town's Garrison, and
##     the patrol of one assassin droid (DroidController reads droid_specs()),
##   - the bounty target: whoever Oda's contract names (WorldState.bounty_target)
##     stands at the outpost it names, in red. Killing them is
##     WorldState.on_bounty_killed().
## Before the fleet is beaten they are like the town's garrison (standing decides);
## after, they shoot on sight (Story.remnant_hostile, read by the Garrison).
## Dead troopers come back after a few minutes (the town's respawn rule).

const CoreContent := preload("res://src/systems/dataload/core_content.gd")
const TownDecor := preload("res://src/systems/world/town_decor.gd")
const GROUND_HALF := 40.0          ## metres of sand collider either side of the anchor
const GROUND_STEP := 2.0
const WAKE_DIST := 320.0           ## bodies further than this from the player sleep

var demo                           ## town_demo.gd
var ground: WorldGround
var outposts: Array = []           ## { id, label, origin, yaw, cfg }
var guards: Array = []             ## NpcBody at the outposts (also in demo.npcs)
var target: NpcBody                ## the bounty target, while one is out there
var target_run := -1               ## which contract it is
var bounty_kills := 0              ## for tests and traces


func setup(town_demo, world_ground: WorldGround) -> void:
	demo = town_demo
	ground = world_ground
	name = "RemnantOutposts"


## Read the outposts and build them, troopers included. Called by the town before
## its Garrison is set up (the troopers join it).
func build() -> void:
	var cc := CoreContent.new()
	cc.load_from()
	var world: Dictionary = cc.world_for_town("port_town")
	for id in Story.OUTPOSTS:
		for lm in world.get("landmarks", []):
			if str(lm.get("location", "")) != id:
				continue
			var at := WorldGround._v3(lm.get("at", [0, 0, 0]))
			var loc: Dictionary = cc.get_location(id)
			var o := { "id": id, "label": str(loc.get("label", id)), "cfg": loc,
				"origin": Vector3(at.x, ground.terrain.height_at(at.x, at.z), at.z),
				"yaw": deg_to_rad(float(lm.get("yaw_deg", 0.0))) }
			outposts.append(o)
			_build_ground(o)
			if demo.use_look:
				_dress(o)
				_park_ship(o)
			for p in ["guard_a", "guard_b"]:
				_add_guard(o, p)


func outpost(id: String) -> Dictionary:
	for o in outposts:
		if str(o.id) == id:
			return o
	return {}


## A point from an outpost's location file, in the world, on the sand.
func world_point(o: Dictionary, local) -> Vector3:
	var lp: Vector3 = local if local is Vector3 else WorldGround._v3(local)
	var p: Vector3 = o.origin + lp.rotated(Vector3.UP, float(o.yaw))
	p.y = ground.terrain.height_at(p.x, p.z)
	return p


func point(o: Dictionary, key: String) -> Vector3:
	return world_point(o, o.cfg.get("points", {}).get(key, [0, 0, 0]))


## The assassin droid each outpost keeps: where it walks.
func droid_specs() -> Array:
	var out: Array = []
	for o in outposts:
		var pts: Array = []
		for p in o.cfg.get("points", {}).get("patrol", []):
			pts.append(world_point(o, p))
		out.append({ "outpost": o.id, "patrol": pts })
	return out


# ------------------------------------------------------------------ people

func _add_guard(o: Dictionary, key: String) -> NpcBody:
	var here := point(o, key)
	var face: Vector3 = here + (here - (o.origin as Vector3)).normalized()      # looking out, away from the building
	var g: NpcBody = demo.make_soldier("outpost_trooper", here, atan2(face.x - here.x, face.z - here.z),
		"%s/%s" % [o.id, key], "npc:%s/%s" % [o.id, key])
	if g == null:
		return null
	adopt(g, str(o.id))
	guards.append(g)
	return g


## An outpost body: no navmesh out here (it holds its ground), and it sleeps
## while the player is far away.
func adopt(g: NpcBody, outpost_id: String) -> void:
	g.nav = null
	g.set_meta("outpost", outpost_id)


func _physics_process(_dt: float) -> void:
	_sync_target()
	var p: Node3D = demo._player if demo != null else null
	if p == null:
		return
	for g in guards + ([target] if target != null else []):
		if is_instance_valid(g) and not g.dead:
			var far: bool = g.global_position.distance_to(p.global_position) > WAKE_DIST
			g.process_mode = Node.PROCESS_MODE_DISABLED if far else Node.PROCESS_MODE_INHERIT
	guards = guards.filter(func(g): return is_instance_valid(g))


## Put the contract's officer at its outpost, or take them away when the contract
## is gone (a story reset).
func _sync_target() -> void:
	var b := WorldState.bounty_target()
	var alive := target != null and is_instance_valid(target) and not target.dead
	if b.is_empty():
		if alive:
			_drop_target()
		return
	if alive and target_run == int(b.run):
		return
	if alive:
		_drop_target()
	var o := outpost(str(b.outpost))
	if not o.is_empty():
		spawn_target(o, b)


func spawn_target(o: Dictionary, b: Dictionary) -> NpcBody:
	var here := point(o, "target")
	var t: NpcBody = demo.make_soldier("bounty_target", here, float(o.yaw) - PI * 0.5, "%s/target" % o.id, str(b.key))
	if t == null:
		return null
	adopt(t, str(o.id))
	t.set_meta("bounty", int(b.run))
	t.died.connect(_on_target_died.bind(t))
	if demo.garrison != null:
		demo.garrison.add_member(t)
	target = t
	target_run = int(b.run)
	return t


func _drop_target() -> void:
	if demo.garrison != null:
		demo.garrison.remove_member(target)
	demo.npcs.erase(target)
	target.queue_free()
	target = null


func _on_target_died(t: NpcBody) -> void:
	if int(t.get_meta("bounty", -1)) != int(WorldState.bounty.get("run", -2)):
		return
	bounty_kills += 1
	WorldState.on_bounty_killed()
	if demo.gear != null and demo.gear.hud != null:
		demo.gear.hud.toast(str(Story.bounty_cfg().get("killed_toast", "%s is dead.")) % t.display_name, 5.0)


# ------------------------------------------------------------------ ground

## The sand round the outpost as a heightmap, at the terrain's own heights.
func _build_ground(o: Dictionary) -> void:
	var n := int(GROUND_HALF * 2.0 / GROUND_STEP) + 1
	var hm := HeightMapShape3D.new()
	hm.map_width = n
	hm.map_depth = n
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	var c: Vector3 = o.origin
	for j in n:
		for i in n:
			var x := c.x - GROUND_HALF + i * GROUND_STEP
			var z := c.z - GROUND_HALF + j * GROUND_STEP
			heights[j * n + i] = ground.terrain.height_at(x, z)
	hm.map_data = heights
	var body := StaticBody3D.new()
	body.name = "Ground_" + str(o.id)
	var cs := CollisionShape3D.new()
	cs.shape = hm
	cs.scale = Vector3(GROUND_STEP, 1.0, GROUND_STEP)
	body.add_child(cs)
	add_child(body)
	body.global_position = Vector3(c.x, 0.0, c.z)


# ------------------------------------------------------------------ the look

## Dark grey walls, a black roof and plinth, a red band and door frame, a red
## banner. look.mast: a comms mast on the roof; look.tower: a lookout at one corner.
func _dress(o: Dictionary) -> void:
	var mats: LookMaterials = demo._flat_mats()
	var wall := mats.plaster(o.origin.y, o.origin.y + 3.0, Color("#8a1a16"), Color("#3a3c40"))
	var black := mats.flat(Color("#141416"), 0.6, 0.3)
	var red := mats.flat(Color("#a81e1a"), 0.7)
	var steel := mats.flat(Color("#55585e"), 0.45, 0.6)
	var look: Dictionary = o.cfg.get("look", {})
	for b in o.cfg.get("buildings", []):
		var s := WorldGround._v3(b.get("size", [1, 1, 1]))
		var c := WorldGround._v3(b.get("position", [0, 0, 0]))
		_mesh(o, _box(s + Vector3(0, 1.0, 0)), wall, c + Vector3(0, s.y * 0.5 - 0.5, 0))
		_mesh(o, _box(Vector3(s.x + 0.6, 0.35, s.z + 0.6)), black, c + Vector3(0, s.y + 0.17, 0))
		_mesh(o, _box(Vector3(s.x + 0.3, 0.5, s.z + 0.3)), black, c + Vector3(0, 0.1, 0))
		_mesh(o, _box(Vector3(s.x + 0.04, 0.3, s.z + 0.04)), red, c + Vector3(0, s.y - 0.6, 0))
		# The door, toward the town, framed in red, and a banner beside it.
		_mesh(o, _box(Vector3(0.14, 2.5, 1.8)), red, c + Vector3(s.x * 0.5 + 0.02, 1.25, 0))
		_mesh(o, _box(Vector3(0.16, 2.2, 1.4)), black, c + Vector3(s.x * 0.5 + 0.06, 1.1, 0))
		_mesh(o, _box(Vector3(0.05, 2.6, 0.9)), red, c + Vector3(s.x * 0.5 + 0.05, s.y - 1.7, s.z * 0.5 - 0.9))
		if bool(look.get("mast", false)):
			_mesh(o, _cyl(0.12, 6.0), steel, c + Vector3(-s.x * 0.25, s.y + 3.0, -s.z * 0.25))
			_mesh(o, _box(Vector3(1.6, 0.1, 0.1)), steel, c + Vector3(-s.x * 0.25, s.y + 5.4, -s.z * 0.25))
			_mesh(o, _box(Vector3(0.25, 0.25, 0.25)), mats.glow(Color("#ff3020")), c + Vector3(-s.x * 0.25, s.y + 6.1, -s.z * 0.25))
		if bool(look.get("tower", false)):
			var t := c + Vector3(-s.x * 0.5 - 1.2, 0, s.z * 0.5 + 1.2)
			for dx in [-1.0, 1.0]:
				for dz in [-1.0, 1.0]:
					_mesh(o, _box(Vector3(0.25, 7.0, 0.25)), black, t + Vector3(dx, 3.5, dz))
			_mesh(o, _box(Vector3(2.8, 0.25, 2.8)), steel, t + Vector3(0, 7.0, 0))
			_mesh(o, _box(Vector3(2.8, 0.9, 0.12)), red, t + Vector3(0, 7.5, 1.35))
	# Crates by the wall, so it reads as a supply post.
	for i in 3:
		_mesh(o, _box(Vector3(1.0, 0.9, 1.0)), steel if i % 2 == 0 else black, Vector3(2.0 + i * 1.2, 0.45, -4.6 - (i % 2) * 0.6))


## The cargo ship (the location's "ship"): its model on the sand at the ship
## point, with a box collider round it so nobody walks through it.
func _park_ship(o: Dictionary) -> void:
	var cc := CoreContent.new()
	cc.load_from()
	var look_id := str(cc.get_ship(str(o.cfg.get("ship", ""))).get("look", ""))
	if look_id == "":
		return
	var ship := ShipKit.new().build(look_id)
	ship.name = "Ship_" + str(o.id)
	add_child(ship)
	var at := point(o, "ship")
	ship.global_position = at
	ship.rotation.y = float(o.yaw) + PI * 0.5
	var a := TownDecor.visual_aabb(ship)
	ship.global_position += Vector3(at.x - a.get_center().x, at.y - a.position.y, at.z - a.get_center().z)
	a = TownDecor.visual_aabb(ship)
	var body := StaticBody3D.new()
	body.name = "ShipCollider_" + str(o.id)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = a.size * Vector3(0.8, 0.9, 0.8)
	cs.shape = box
	body.add_child(cs)
	add_child(body)
	body.global_position = a.get_center()


func _mesh(o: Dictionary, mesh: Mesh, mat: Material, local: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)
	mi.global_position = o.origin + local.rotated(Vector3.UP, float(o.yaw))
	mi.rotation.y = float(o.yaw)
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
