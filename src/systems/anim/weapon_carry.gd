class_name WeaponCarry
extends RefCounted
## Issue #87: carrying a gun between shots. Anyone holding a gun (guards, the
## player in third person) raises it to aim when there is something to shoot at,
## keeps it up for a moment after, then lowers it to rest: a rifle slung low across
## the body with the muzzle down and to the left, a pistol pointed at the ground by
## the right thigh. Pure math (no nodes), so the timing and the rest placements are
## unit-tested headless (tests/test_weapon_carry.gut.gd).
##
## Rest placements are in chest space (CharacterKit: the model faces +Z, its left
## is +X) and are given as where the right-hand grip goes plus the gun's rotation,
## so any gun model rests in the hand whatever its own origin.

const RAISE_S := 0.22          ## rest -> aimed
const LOWER_S := 0.5           ## aimed -> rest
const HOLD_S := 2.5            ## stay up this long after the last reason to aim

## kind -> [right grip target (chest space), rotation degrees (Godot YXZ euler)]
const REST := {
	"rifle": [Vector3(-0.15, -0.38, 0.17), Vector3(44, 48, -14)],
	"pistol": [Vector3(-0.27, -0.5, 0.08), Vector3(78, 8, 0)],
}
## Issue #229: sprinting, a rifle at REST hung across the thighs, so a running leg
## swung through the barrel every stride. Port arms instead: diagonal across the
## chest, muzzle up and to the left, held out clear of the torso and the legs.
## A pistol keeps its rest (it hangs by the thigh, short of the knee).
const SPRINT := {
	"rifle": [Vector3(-0.1, -0.16, 0.34), Vector3(-45, 62, -25)],
}

var ready := 0.0               ## 0 = at rest, 1 = aimed (linear; see eased())
var _hold := 0.0


func _init(start_ready := 0.0) -> void:
	ready = clampf(start_ready, 0.0, 1.0)


## want_aim: there is something to aim at this frame (a target, the trigger, ADS).
## lowered: issue #133, sprinting; the gun drops now, whatever wants it up.
## Returns the eased ready.
func step(dt: float, want_aim: bool, lowered: bool = false) -> float:
	if lowered:
		_hold = 0.0
	elif want_aim:
		_hold = HOLD_S
	else:
		_hold = maxf(0.0, _hold - dt)
	var up := _hold > 0.0
	ready = move_toward(ready, 1.0 if up else 0.0, dt / (RAISE_S if up else LOWER_S))
	return eased()


func eased() -> float:
	return ready * ready * (3.0 - 2.0 * ready)


## Up far enough to put a shot where it is pointed.
func on_target() -> bool:
	return ready >= 0.75


## The resting transform (chest space) for a gun of `kind` whose right-hand grip
## sits at `grip_r` in the gun's own space.
static func rest_xf(kind: String, grip_r: Vector3, sprint := false) -> Transform3D:
	var r: Array = SPRINT[kind] if sprint and SPRINT.has(kind) else REST.get(kind, REST["rifle"])
	var b := Basis.from_euler((r[1] as Vector3) * PI / 180.0)
	return Transform3D(b, (r[0] as Vector3) - b * grip_r)


## Between rest and aim; `t` is eased().
static func blend(rest: Transform3D, aim: Transform3D, t: float) -> Transform3D:
	return rest.interpolate_with(aim, clampf(t, 0.0, 1.0))
