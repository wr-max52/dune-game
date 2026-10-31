class_name ClubMusic
extends Node
## Issue #104: tells Sound where the player is from this town's cantina, every
## frame: the club's playlist, how near they are (0 at `hear` metres from the
## walls .. 1 against them) and whether they are inside. The scene changes and
## this node goes: no club.
##
## A new band plays every visit, so the music is back on when the town is built
## again after the last band was killed.

var playlist := ""
var rect := Rect2()     ## the cantina's floor (x, z), in the scene's space
var target: Node3D      ## the player
var hear := 40.0


func setup(id: String, zone: Dictionary, who: Node3D) -> ClubMusic:
	name = "ClubMusic"
	playlist = id
	target = who
	var a: Array = zone.get("min", [0, 0])
	var b: Array = zone.get("max", [0, 0])
	rect = Rect2(float(a[0]), float(a[1]), float(b[0]) - float(a[0]), float(b[1]) - float(a[1]))
	hear = float(Sound.lib().cfg.get("club", {}).get("hear", 40.0))
	Sound.set_club_live(true)
	return self


func _process(_dt: float) -> void:
	if playlist == "" or not is_instance_valid(target):
		Sound.set_club("", 0.0, false)
		return
	var p := target.global_position
	var d := distance(rect, p.x, p.z)
	Sound.set_club(playlist, near(d, hear), d <= 0.0)


func _exit_tree() -> void:
	Sound.set_club("", 0.0, false)


## Metres from (x, z) to the nearest point of `r` (0 inside it).
static func distance(r: Rect2, x: float, z: float) -> float:
	var dx := maxf(maxf(r.position.x - x, 0.0), x - r.end.x)
	var dz := maxf(maxf(r.position.y - z, 0.0), z - r.end.y)
	return sqrt(dx * dx + dz * dz)


## 1 at the walls, falling to 0 at `hear` metres out.
static func near(d: float, hear_m: float) -> float:
	return clampf(1.0 - d / maxf(hear_m, 0.001), 0.0, 1.0)
