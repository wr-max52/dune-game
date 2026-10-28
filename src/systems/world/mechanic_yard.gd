class_name MechanicYard
extends Node3D
## Issue #95: Dorrin Vask's speeder yard, out in the desert about a 30 second
## drive from the back gate (the "mechanic_yard" landmark in
## content/core/worlds/port_desert.json). This node dresses it (garage, bench,
## lift, scrap heap), stands Dorrin at his bench and runs his shop:
##
##   [E] beside him  -- the menu: paint, looks, performance, the Grav Lifter, and
##                      selling the speeder for scrap.
##
## He only works on a speeder of yours parked in his bay (within bay_radius of the
## lift). Parts are paid for here and fitted at once (SpeederPost.refit rebuilds the
## speeder where it stands). The fit is saved per speeder (WorldState.speeder_fits).
## Words, prices and parts: content/core/vehicles/speeder_upgrades.json.
##
## The headless test calls talk(), buy(), scrap() and the menu's choose() directly:
## the same code paths as the keys.

const CoreContent := preload("res://src/systems/dataload/core_content.gd")
const OUTFIT := { "head": "darker", "torso": "blue", "legs": "blue" }

var demo                              ## town_demo.gd
var ground: WorldGround
var player: CharacterBody3D
var gear: GearController              ## for its HUD (prompt, toast) and its focus (E is shared)
var cfg: Dictionary = {}              ## the "mechanic" block
var menu: DroidMenu
var mechanic: Node3D                  ## Dorrin's body
var xf := Transform3D()               ## the yard's frame (on the ball: along the ground's up)
var points: Dictionary = {}
var found := false                    ## the world has the landmark
var in_reach := false
var said := ""                        ## his last line, for tests
var fitted := 0                       ## parts sold this session (tests, traces)
var _was_locked := false


func setup(town_demo, world_ground: WorldGround, p_gear: GearController) -> void:
	demo = town_demo
	ground = world_ground
	gear = p_gear
	player = demo._player if demo != null else null
	name = "MechanicYard"


func _ready() -> void:
	cfg = SpeederUpgrades.mechanic()
	menu = DroidMenu.new()
	add_child(menu)
	var cc := CoreContent.new()
	cc.load_from()
	var world: Dictionary = demo.world if "world" in demo and not demo.world.is_empty() else cc.world_for_town("port_town")
	var id := str(cfg.get("location", "mechanic_yard"))
	for lm in world.get("landmarks", []):
		if str(lm.get("location", "")) != id:
			continue
		var at := WorldGround._v3(lm.get("at", [0, 0, 0]))
		var origin := Vector3(at.x, ground.terrain.height_at(at.x, at.z), at.z)
		var sp := ground.sphere()
		if sp != null:
			origin = sp.surface_at(at.x, at.z)
		xf = Transform3D(PlanetSphere.tilt_to(ground.up_at(origin)) * Basis(Vector3.UP, deg_to_rad(float(lm.get("yaw_deg", 0.0)))), origin)
		found = true
	if not found:
		return
	var loc: Dictionary = cc.get_location(id)
	for k in loc.get("points", {}):
		points[k] = WorldGround._v3(loc.points[k])
	if demo.use_look:
		_dress(loc)
	_build_mechanic()


func npc_name() -> String:
	return str(cfg.get("name", "the mechanic"))


func _l(key: String) -> String:
	return str(cfg.get("labels", {}).get(key, key))


func _line(key: String) -> String:
	return str(cfg.get("lines", {}).get(key, ""))


## A point from the location file, in the world, on the sand.
func world_point(id: String) -> Vector3:
	var lp: Vector3 = points.get(id, Vector3.ZERO)
	var p: Vector3 = xf * Vector3(lp.x, 0.0, lp.z)
	var sp := ground.sphere()
	if sp != null:
		var dir := (p - sp.center).normalized()
		return sp.center + dir * (sp.radius + sp.elevation(dir))
	p.y = ground.terrain.height_at(p.x, p.z)
	return p


# ------------------------------------------------------------------ the bay

## Your speeder parked in the bay (the nearest one to the lift), or null.
func speeder_in_bay() -> SpeederNode:
	var post: SpeederPost = demo.speeder_post if demo != null and "speeder_post" in demo else null
	if post == null or not found:
		return null
	var bay := world_point("bay")
	var best: SpeederNode = null
	var best_d := float(cfg.get("bay_radius", 16.0))
	for s in post.speeders:
		if not is_instance_valid(s) or s.riding:
			continue
		var d: float = s.model.position.distance_to(bay)
		if d <= best_d:
			best = s
			best_d = d
	return best


func _fit(s: SpeederNode) -> Dictionary:
	return demo.speeder_post.fit_for(int(s.get_meta("slot", 0)))


# ------------------------------------------------------------------ frame

func _physics_process(dt: float) -> void:
	if not found or player == null or mechanic == null:
		return
	var to := player.global_position - mechanic.global_position
	if to.length() < 12.0:
		var local := xf.basis.inverse() * to
		mechanic.rotation.y = lerp_angle(mechanic.rotation.y, atan2(local.x, local.z), minf(1.0, dt * 4.0))
	_tick_focus()


func _tick_focus() -> void:
	if menu.is_open():
		return
	if _was_locked:
		player.locked = false
		_was_locked = false
	var p := player.global_position
	var at := mechanic.global_position
	in_reach = not player.piloting and Vector2(p.x - at.x, p.z - at.z).length() <= float(cfg.get("reach", 3.4)) \
		and absf(p.y - at.y) <= 2.0 and (gear == null or gear.focus.is_empty())
	if not in_reach:
		return
	if gear != null and gear.hud != null:
		gear.hud.set_prompt(_l("talk") % npc_name())
	if not player.locked and InputMap.has_action("interact") and Input.is_action_just_pressed("interact"):
		talk()


# ------------------------------------------------------------------ the shop

## [E] beside him: the top menu, or "bring one round" with no speeder in the bay.
func talk() -> void:
	var s := speeder_in_bay()
	if s == null:
		_say(_line("no_speeder"))
		return
	var fit := _fit(s)
	var opts := [
		{ "id": "group:paint", "text": _l("menu_paint") },
		{ "id": "group:looks", "text": _l("menu_looks") },
		{ "id": "group:performance", "text": _l("menu_performance") },
	]
	for p in SpeederUpgrades.in_group("lifter"):
		opts.append(_row(fit, p))
	opts.append({ "id": "scrap", "text": _l("menu_scrap") % SpeederUpgrades.scrap_value(fit) })
	_open(_line("hello"), opts, _on_top)


func group_options(group: String) -> Array:
	var s := speeder_in_bay()
	if s == null:
		return []
	var fit := _fit(s)
	var out: Array = []
	for p in SpeederUpgrades.in_group(group):
		out.append(_row(fit, p))
	out.append({ "id": "back", "text": _l("back") })
	return out


func _row(fit: Dictionary, p: Dictionary) -> Dictionary:
	var id := str(p.get("id", ""))
	var why := SpeederUpgrades.why_not(fit, id)
	var text := _l("buy") % [str(p.get("label", id)), int(p.get("price", 0))]
	if why == "owned":
		text = _l("owned") % str(p.get("label", id))
	elif why.begins_with("needs:"):
		text = _l("locked") % [str(p.get("label", id)), int(p.get("price", 0)),
			str(SpeederUpgrades.part(why.substr(6)).get("label", why.substr(6)))]
	return { "id": "buy:" + id, "text": text }


func _on_top(id: String) -> void:
	if id.begins_with("group:"):
		var g := id.substr(6)
		_open(_line("hello"), group_options(g), _on_group.bind(g))
	elif id.begins_with("buy:"):
		buy(id.substr(4))
	elif id == "scrap":
		var s := speeder_in_bay()
		if s != null:
			_open(_l("confirm_scrap") % SpeederUpgrades.scrap_value(_fit(s)),
				[{ "id": "yes", "text": _l("yes_scrap") }, { "id": "no", "text": _l("no_scrap") }], _on_scrap)


func _on_group(id: String, group: String) -> void:
	if id == "back":
		talk()
	elif id.begins_with("buy:"):
		buy(id.substr(4))
		if speeder_in_bay() != null:
			_open(said, group_options(group), _on_group.bind(group))


func _on_scrap(id: String) -> void:
	if id == "yes":
		scrap()
	else:
		talk()


## Buy part `id` for the speeder in the bay and fit it now. Returns "bought",
## "cant_afford", "no_speeder", "owned", "needs:<part>" or "unknown".
func buy(id: String) -> String:
	var s := speeder_in_bay()
	if s == null:
		_say(_line("no_speeder"))
		return "no_speeder"
	var fit := _fit(s)
	var why := SpeederUpgrades.why_not(fit, id)
	if why != "":
		return why
	var p := SpeederUpgrades.part(id)
	var price := int(p.get("price", 0))
	if WorldState.credits < price:
		_say(_line("too_poor"))
		return "cant_afford"
	WorldState.credits -= price
	SpeederUpgrades.fit_part(fit, id)
	fitted += 1
	WorldState.log_event(_l("event_bought") % str(p.get("label", id)).to_lower())
	demo.speeder_post.refit(s)
	_say(_line("bought"))
	return "bought"


## Sell the speeder in the bay for scrap. Returns the credits paid (0 = none there).
func scrap() -> int:
	var s := speeder_in_bay()
	if s == null:
		_say(_line("no_speeder"))
		return 0
	var pay := SpeederUpgrades.scrap_value(_fit(s))
	WorldState.credits += pay
	demo.speeder_post.remove(s)
	WorldState.log_event(_l("event_scrapped"))
	_say(_line("scrapped"))
	return pay


func _open(text: String, opts: Array, pick: Callable) -> void:
	said = text
	menu.open(_l("menu_title") % [npc_name(), WorldState.credits], opts, pick, text)
	if player != null and not player.locked:
		player.locked = true
		_was_locked = true


func _say(text: String) -> void:
	said = text
	if gear != null and gear.hud != null and text != "":
		gear.hud.toast("%s: %s" % [npc_name(), text], 4.5)


# ------------------------------------------------------------------ Dorrin

func _build_mechanic() -> void:
	if demo.use_look:
		mechanic = MerchantNPC.new(CharacterKit.new(demo._flat_mats(), 0.0), "local", OUTFIT)
	else:
		mechanic = MerchantNPC.new(null)
	mechanic.name = "Mechanic"
	add_child(mechanic)
	mechanic.global_transform = Transform3D(xf.basis, world_point("mechanic"))
	mechanic.look_at_target = player


# ------------------------------------------------------------------ the look

## The garage (open toward the bay), the bench, the lift and the scrap heap, in
## the desert's colours: sun-bleached plaster, rust, oily steel.
func _dress(loc: Dictionary) -> void:
	var mats: LookMaterials = demo._flat_mats()
	var plaster := mats.plaster(xf.origin.y, xf.origin.y + 5.0, Color("#7a4a2a"), Color("#cdb48c"))
	var rust := mats.flat(Color("#8e4a26"), 0.85)
	var steel := mats.flat(Color("#4a4c52"), 0.45, 0.6)
	var dark := mats.flat(Color("#2a2622"), 0.9)
	var hazard := mats.flat(Color("#d8a020"), 0.7)
	for b in loc.get("buildings", []):
		var s := WorldGround._v3(b.get("size", [1, 1, 1]))
		var c := WorldGround._v3(b.get("position", [0, 0, 0]))
		match str(b.id):
			"garage":
				# Three walls and a roof; the side toward the bay (+x) stands open.
				_mesh(_box(Vector3(0.4, s.y, s.z)), plaster, c + Vector3(-s.x * 0.5, s.y * 0.5, 0))
				_mesh(_box(Vector3(s.x, s.y, 0.4)), plaster, c + Vector3(0, s.y * 0.5, s.z * 0.5))
				_mesh(_box(Vector3(s.x, s.y, 0.4)), plaster, c + Vector3(0, s.y * 0.5, -s.z * 0.5))
				_mesh(_box(Vector3(s.x + 1.2, 0.3, s.z + 0.6)), rust, c + Vector3(0.6, s.y + 0.15, 0))
				_mesh(_box(Vector3(s.x - 1.0, 0.05, s.z - 1.0)), dark, c + Vector3(0, 0.03, 0))
				# A sign over the door: a hover glow tube in the shape of a bar.
				_mesh(_box(Vector3(0.2, 0.9, 4.0)), rust, c + Vector3(s.x * 0.5 + 0.3, s.y - 0.4, 0))
				_mesh(_box(Vector3(0.1, 0.12, 3.4)), mats.glow(Color("#7fe0d0")), c + Vector3(s.x * 0.5 + 0.42, s.y - 0.4, 0))
			"bench":
				_mesh(_box(s), steel, c + Vector3(0, s.y * 0.5, 0))
				_mesh(_box(Vector3(s.x + 0.1, 0.06, s.z + 0.1)), rust, c + Vector3(0, s.y + 0.03, 0))
				for i in 3:
					_mesh(_box(Vector3(0.3, 0.25, 0.4)), dark if i % 2 == 0 else hazard, c + Vector3(0, s.y + 0.15, -1.0 + i * 1.0))
			"scrap_heap":
				var rng := RandomNumberGenerator.new()
				rng.seed = 95
				for i in 9:
					var sz := Vector3(rng.randf_range(0.8, 2.2), rng.randf_range(0.4, 1.4), rng.randf_range(0.8, 2.4))
					var m := _mesh(_box(sz), rust if i % 3 else steel,
						c + Vector3(rng.randf_range(-1.6, 1.6), sz.y * 0.4 + (i / 3) * 0.5, rng.randf_range(-1.6, 1.6)))
					m.rotation += Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(0, TAU), rng.randf_range(-0.3, 0.3))
	# The lift in the bay: a steel pad with yellow and black edges.
	var bay: Vector3 = points.get("bay", Vector3.ZERO)
	_mesh(_box(Vector3(7.0, 0.12, 4.0)), steel, bay + Vector3(0, 0.06, 0))
	for dz in [-2.05, 2.05]:
		_mesh(_box(Vector3(7.0, 0.14, 0.12)), hazard, bay + Vector3(0, 0.07, dz))


## A mesh at a point in the yard's own frame.
func _mesh(mesh: Mesh, mat: Material, local: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)
	mi.global_transform = xf * Transform3D(Basis.IDENTITY, local)
	return mi


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b
