class_name SilentKill
extends RefCounted
## Issue #307: a sword kill on someone who had not noticed you is silent. Nobody is
## told, no "man down", no alarm, unless another of them sees it happen (they had
## noticed or can see the player, or the victim is in their sight cone close by).
## The body is left where it fell; whoever later walks within sight of it finds it
## and raises the alarm as a "man down". Shots stay loud (NoiseEvents), so this is
## the sword only. Used by Garrison (troopers) and Townsfolk (locals).

const SEE_BODY_M := 16.0      ## a body is spotted at most this far (no wall check)


## The victim's last hit was the player's sword, landed before it had noticed them.
static func unaware_cut(g: NpcBody) -> bool:
	return g != null and bool(g.cut_unaware)


## Does anyone in `others` see this happen?
static func witnessed(victim: NpcBody, others: Array) -> bool:
	for o in others:
		if o == victim or not is_instance_valid(o) or o.dead:
			continue
		if o.perception.noticed or o.perception.visible:
			return true
		if sees(o, victim.global_position):
			return true
	return false


## Whether `o` has `at` in its sight cone, close enough to make out a body.
static func sees(o: NpcBody, at: Vector3) -> bool:
	if o.global_position.distance_to(at) > minf(SEE_BODY_M, o.perception.sight_range):
		return false
	return o.perception.cone_check(o.global_position, o.forward(), at, false)


## The first of `alive` that has one of `bodies` in sight: [finder, body], or [].
static func finder(alive: Array, bodies: Array) -> Array:
	for b in bodies:
		if not is_instance_valid(b):
			continue
		for o in alive:
			if sees(o, (b as Node3D).global_position):
				return [o, b]
	return []
