class_name HarmfulSurface
extends Node
## Issue #298: a planet whose surface you cannot breathe on (the asteroid station's
## rock). Outside the shelter (the station's dome, its hallway and its landing
## pit; or any ship you are flying) and without armour on, you take damage at a
## steady rate, a straight line to death, with a message telling you why. Armour
## worn (anything in the "armour" slot) keeps you breathing.
##
## Which planets: a "harmful_surface" block on the planet type
## (content/core/planets/types.json; the asteroid has one) or on the planet's own
## file, which wins. PlanetGen passes it through as planet.harmful_surface.

var demo                              ## town_demo.gd
var player: CharacterBody3D
var cfg: Dictionary = {}
var exposed := false                  ## this frame: outside, no armour, alive (traces)
var exposed_s := 0.0                  ## seconds exposed in a row
var damage_done := 0.0
var _owed := 0.0                      ## damage not yet whole enough to apply
var _told_left := 0.0


## The planet's block ({} = the surface is fine).
static func config(planet: Dictionary) -> Dictionary:
	var b = planet.get("harmful_surface", {})
	return b if b is Dictionary else {}


func setup(town_demo, block: Dictionary) -> HarmfulSurface:
	demo = town_demo
	player = demo._player
	cfg = block
	name = "HarmfulSurface"
	return self


## Under cover: the station's dome, hallway or pit (AsteroidWorld.sheltered), or
## the town itself where there is no such enclosure.
func sheltered(p: Vector3) -> bool:
	var plat = demo.get("platform")
	if plat != null and is_instance_valid(plat) and plat.has_method("sheltered"):
		return plat.sheltered(p)
	return TownNav.in_town(demo.get("town"), p)


## Armour on (whatever is in the armour slot).
static func armoured() -> bool:
	return WorldState.inventory != null and WorldState.inventory.in_slot("armour") != ""


func _physics_process(dt: float) -> void:
	exposed = false
	if player == null or not is_instance_valid(player) or bool(player.get("is_downed")):
		exposed_s = 0.0
		return
	if bool(player.get("piloting")) or armoured() or sheltered(player.global_position):
		exposed_s = 0.0
		_told_left = 0.0
		return
	exposed = true
	exposed_s += dt
	_owed += float(cfg.get("damage_per_s", 5.0)) * dt
	if _owed >= 1.0:
		var whole := floorf(_owed)
		_owed -= whole
		damage_done += whole
		player.apply_damage(whole)
	_told_left -= dt
	if _told_left <= 0.0:
		_told_left = float(cfg.get("remind_s", 6.0))
		var gear = demo.get("gear")
		var text := str(cfg.get("text", "Put on armour to roam this planet's surface."))
		if gear != null and gear.hud != null:
			gear.hud.toast(text, 4.0)
