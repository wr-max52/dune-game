class_name NativeMoves
extends RefCounted
## Issue #96: the desert packs' one-off moves, played over the walk by NpcBody.act():
## a club swing, a knife slash, a spear thrust, a rock throw, and the hand gestures
## they trade with (they do not speak the port's language). Pure math like
## BodyAnimator: a move and how far through it (0..1) give joint rotations in
## degrees, and a weight that blends the upper body in and back out.
##
## Conventions are CharacterKit's: the model faces +Z, its left is +X, limbs hang
## along -Y. A negative X on a shoulder lifts the arm forward (-90 level, -180
## straight up); a negative Z on the right shoulder (positive on the left) lifts it
## out to the side; a negative X on an elbow bends the forearm forward; a positive
## X on the chest bows it forward.

## Seconds each move takes when NpcBody.act() is given none.
const LENGTHS := {
	"swing": 0.6, "slash": 0.45, "thrust": 0.55, "throw": 0.7,
	"gesture_wave": 1.8, "gesture_offer": 3.0, "gesture_thanks": 2.0,
	"gesture_no": 2.4, "gesture_lower": 2.6,
}
## How far through a throw the rock leaves the hand (the director fires it then).
const RELEASE := 0.55
## How far through a melee move the blow lands.
const STRIKE := { "swing": 0.5, "slash": 0.45, "thrust": 0.45 }


static func length(move: String) -> float:
	return float(LENGTHS.get(move, 1.0))


static func is_attack(move: String) -> bool:
	return move in ["swing", "slash", "thrust", "throw"]


## How much of the move to show at `t` (0..1): quick in and out for a blow, softer
## for a gesture.
static func weight(move: String, t: float) -> float:
	var edge := 0.12 if is_attack(move) else 0.18
	t = clampf(t, 0.0, 1.0)
	return _smooth(minf(t / edge, (1.0 - t) / edge))


## The joints of `move` at `t` (0..1). `secs` = seconds into it (for the gestures'
## repeats: chewing, a shake of the head, a wave).
static func pose(move: String, t: float, secs: float = 0.0) -> Dictionary:
	t = clampf(t, 0.0, 1.0)
	match move:
		"swing":
			# Club up and back over the shoulder, down hard, then through.
			return _keys(t, [
				[0.0, { "r_shoulder": Vector3(-60, 0, -10), "r_elbow": Vector3(-60, 0, 0), "chest": Vector3(0, 0, 0) }],
				[0.38, { "r_shoulder": Vector3(-170, 0, -15), "r_elbow": Vector3(-85, 0, 0), "chest": Vector3(-8, 18, 0) }],
				[0.55, { "r_shoulder": Vector3(-45, 0, 8), "r_elbow": Vector3(-8, 0, 0), "chest": Vector3(14, -14, 0) }],
				[1.0, { "r_shoulder": Vector3(-20, 0, 12), "r_elbow": Vector3(-20, 0, 0), "chest": Vector3(4, -6, 0) }],
			], { "l_shoulder": Vector3(-35, 0, 18), "l_elbow": Vector3(-50, 0, 0) })
		"slash":
			return _keys(t, [
				[0.0, { "r_shoulder": Vector3(-70, 0, -55), "r_elbow": Vector3(-70, 0, 0), "chest": Vector3(0, 20, 0) }],
				[0.5, { "r_shoulder": Vector3(-75, 0, 30), "r_elbow": Vector3(-12, 0, 0), "chest": Vector3(6, -20, 0) }],
				[1.0, { "r_shoulder": Vector3(-40, 0, 20), "r_elbow": Vector3(-30, 0, 0), "chest": Vector3(0, -8, 0) }],
			], { "l_shoulder": Vector3(-40, 0, 20), "l_elbow": Vector3(-60, 0, 0) })
		"thrust":
			# Spear drawn back at the hip, driven straight out.
			return _keys(t, [
				[0.0, { "r_shoulder": Vector3(-40, 0, -10), "r_elbow": Vector3(-100, 0, 0), "chest": Vector3(0, 15, 0) }],
				[0.35, { "r_shoulder": Vector3(-30, 0, -15), "r_elbow": Vector3(-115, 0, 0), "chest": Vector3(-4, 22, 0) }],
				[0.5, { "r_shoulder": Vector3(-88, 0, 0), "r_elbow": Vector3(-2, 0, 0), "chest": Vector3(12, -10, 0) }],
				[1.0, { "r_shoulder": Vector3(-60, 0, -5), "r_elbow": Vector3(-40, 0, 0), "chest": Vector3(2, 0, 0) }],
			], { "l_shoulder": Vector3(-60, 0, 10), "l_elbow": Vector3(-40, 0, 0) })
		"throw":
			# Overarm: wind back high, whip through at RELEASE, follow down.
			return _keys(t, [
				[0.0, { "r_shoulder": Vector3(-40, 0, -10), "r_elbow": Vector3(-40, 0, 0), "chest": Vector3(0, 0, 0),
					"l_shoulder": Vector3(-30, 0, 15) }],
				[0.42, { "r_shoulder": Vector3(-155, 0, -40), "r_elbow": Vector3(-115, 0, 0), "chest": Vector3(-10, 25, 0),
					"l_shoulder": Vector3(-80, 0, 10) }],
				[RELEASE, { "r_shoulder": Vector3(-95, 0, -5), "r_elbow": Vector3(-15, 0, 0), "chest": Vector3(10, -10, 0),
					"l_shoulder": Vector3(-50, 0, 20) }],
				[1.0, { "r_shoulder": Vector3(-30, 0, 15), "r_elbow": Vector3(-25, 0, 0), "chest": Vector3(6, -12, 0),
					"l_shoulder": Vector3(-20, 0, 15) }],
			], { "l_elbow": Vector3(-30, 0, 0) })
		"gesture_wave":
			# Arm up and out to the side, the forearm waving: over here.
			return { "r_shoulder": Vector3(-20, 0, -150), "r_elbow": Vector3(-45 + 25 * sin(secs * 9.0), 0, 0),
				"l_shoulder": Vector3(-10, 0, 8), "l_elbow": Vector3(-20, 0, 0) }
		"gesture_offer":
			# First half: a hand to the mouth, chewing (food?). Second: both hands
			# out, palms up (quartz for it).
			if t < 0.5:
				return { "r_shoulder": Vector3(-48, 0, 32), "r_elbow": Vector3(-135 + 14 * sin(secs * 12.0), 0, 0),
					"l_shoulder": Vector3(-10, 0, 8), "l_elbow": Vector3(-25, 0, 0) }
			return { "r_shoulder": Vector3(-68, 0, -8), "r_elbow": Vector3(-22, 0, 0), "r_wrist": Vector3(0, 0, -80),
				"l_shoulder": Vector3(-68, 0, 8), "l_elbow": Vector3(-22, 0, 0), "l_wrist": Vector3(0, 0, 80),
				"chest": Vector3(8, 0, 0) }
		"gesture_thanks":
			# A hand to the forehead and a small bow.
			return { "r_shoulder": Vector3(-62, 0, 36), "r_elbow": Vector3(-150, 0, 0), "chest": Vector3(16, 0, 0),
				"neck": Vector3(14, 0, 0), "l_shoulder": Vector3(-8, 0, 6), "l_elbow": Vector3(-15, 0, 0) }
		"gesture_no":
			# A hand rubbing the belly, the head shaking: no food, no quartz.
			return { "r_shoulder": Vector3(-25, 0, 22 + 8 * sin(secs * 8.0)), "r_elbow": Vector3(-95, 0, 0),
				"neck": Vector3(0, 22 * sin(secs * 9.0), 0), "head": Vector3(0, 14 * sin(secs * 9.0), 0) }
		"gesture_lower":
			# Weapons down, both palms open and out: no fight.
			return { "r_shoulder": Vector3(-22, 0, -32), "r_elbow": Vector3(-18, 0, 0), "r_wrist": Vector3(0, 0, -60),
				"l_shoulder": Vector3(-22, 0, 32), "l_elbow": Vector3(-18, 0, 0), "l_wrist": Vector3(0, 0, 60),
				"chest": Vector3(6, 0, 0) }
	return {}


## Keyframes [[t, {joint: deg}], ...] eased between; `hold` joints stay put throughout.
static func _keys(t: float, keys: Array, hold: Dictionary = {}) -> Dictionary:
	var out := hold.duplicate()
	var a: Array = keys[0]
	var b: Array = keys[keys.size() - 1]
	for i in keys.size() - 1:
		if t >= float(keys[i][0]) and t <= float(keys[i + 1][0]):
			a = keys[i]
			b = keys[i + 1]
			break
	var span := float(b[0]) - float(a[0])
	var f := _smooth((t - float(a[0])) / span) if span > 0.0 else 1.0
	var ja: Dictionary = a[1]
	var jb: Dictionary = b[1]
	for jn in ja:
		out[jn] = (ja[jn] as Vector3).lerp(jb.get(jn, ja[jn]), f)
	return out


static func _smooth(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)
