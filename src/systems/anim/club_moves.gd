class_name ClubMoves
extends RefCounted
## Issue #261: how the club's people move. Pure math like BodyAnimator's dance:
## a performer's playing loop and the crowd's sip from a bottle, as joint
## rotations (degrees) and, for hands that belong on an instrument, where the hand
## goes in the performer's own space (feet at the origin, +Z forward, +X their
## left). NpcBody puts those hands there with CharacterKit's arm IK, so a DJ's
## fingers stay on the decks while the body bobs. ClubProps builds every
## instrument from the same numbers below, so the hands and the props agree.
##
## Each loop is LOOP_S long: five moves of SEG_S crossfaded over BLEND_S, like the
## dancer's. They look round the room, move their arms, bob on the beat and (the
## ones standing) shift their weight. The beat is the profile's "bpm".
##
## Conventions are CharacterKit's: a negative X on a shoulder lifts the arm
## forward, a negative Z on the right shoulder (positive on the left) lifts it out
## to the side, a negative X on an elbow bends it, a positive X on a hip swings the
## leg back, a positive X on a knee bends the shin back, a positive X on the head
## looks down and a positive Y turns it to the performer's left.

const PELVIS_Y := 0.97
const SEG_S := 4.0
const BLEND_S := 0.8
const MOVES := 5
const LOOP_S := SEG_S * MOVES
const KINDS := ["dj", "drum", "bass"]

## The DJ's desk: its top `DJ_TOP` high, the two decks DJ_DECK_X either side of the
## middle and DJ_Z in front of the DJ's feet, the mixer between them.
const DJ_TOP := 1.0
const DJ_Z := 0.5
const DJ_DECK_X := 0.32
## The techno drum kit: the snare pad DRUM_Z in front at DRUM_PAD_Y, a tom pad
## either side DRUM_TOM_X out and higher, cymbal pads DRUM_CYM_X out up high.
## The sticks are STICK long.
const DRUM_Z := 0.5
const DRUM_PAD_Y := 0.86
const DRUM_TOM_X := 0.3
const DRUM_TOM_Y := 0.96
const DRUM_CYM_X := 0.48
const DRUM_CYM_Y := 1.3
const STICK := 0.4
## The upright bass: its spike on the floor at (BASS_X, 0, BASS_Z), leaning back
## toward the player by BASS_TILT degrees; strings face away from them.
const BASS_X := -0.1
const BASS_Z := 0.5
const BASS_TILT := 9.0
const BASS_HEIGHT := 1.8

## The crowd's bottle: held at the chest between sips; a sip takes SIP_S.
const SIP_S := 2.4
const HOLD := { "r_shoulder": Vector3(-14, 0, -8), "r_elbow": Vector3(-80, 0, 0) }


static func is_kind(kind: String) -> bool:
	return kind in KINDS


## Where the bass's axis is (performer space) `h` metres up from its spike.
static func bass_axis(h: float) -> Vector3:
	return Vector3(BASS_X, h * cos(deg_to_rad(BASS_TILT)), BASS_Z - h * sin(deg_to_rad(BASS_TILT)))


## The pose of performer `kind` at `seconds` into their set, `bpm` beats a minute.
## -> { joints: {name: Vector3 deg}, pelvis_y, pelvis_x,
##      hands: {"l"/"r": Vector3 or null}, reach: {"l"/"r": 0..1} }
static func pose(kind: String, seconds: float, bpm := 110.0) -> Dictionary:
	var t := fposmod(seconds, LOOP_S)
	var i := int(t / SEG_S) % MOVES
	var u := t - float(i) * SEG_S
	var cur := _move(kind, i, u + BLEND_S, seconds, bpm)
	var into := u - (SEG_S - BLEND_S)
	if into <= 0.0:
		return cur
	var nxt := _move(kind, (i + 1) % MOVES, into, seconds, bpm)
	var w := _smooth01(into / BLEND_S)
	var joints := {}
	for n in BodyAnimator.JOINTS:
		joints[n] = (cur.joints[n] as Vector3).lerp(nxt.joints[n], w)
	var hands := {}
	var reach := {}
	for s in ["l", "r"]:
		var a = cur.hands[s]
		var b = nxt.hands[s]
		hands[s] = a.lerp(b, w) if a != null and b != null else (a if w < 0.5 else b)
		reach[s] = lerpf(float(cur.reach[s]), float(nxt.reach[s]), w)
	return {
		"joints": joints, "hands": hands, "reach": reach,
		"pelvis_y": lerpf(cur.pelvis_y, nxt.pelvis_y, w),
		"pelvis_x": lerpf(cur.pelvis_x, nxt.pelvis_x, w),
	}


static func _move(kind: String, i: int, s: float, secs: float, bpm: float) -> Dictionary:
	var p := {
		"joints": {}, "pelvis_y": PELVIS_Y, "pelvis_x": 0.0,
		"hands": { "l": null, "r": null }, "reach": { "l": 0.0, "r": 0.0 },
	}
	for n in BodyAnimator.JOINTS:
		p.joints[n] = Vector3.ZERO
	var beat := TAU * secs * bpm / 60.0
	match kind:
		"dj":
			_dj(p, i, s, beat)
		"drum":
			_drum(p, i, s, beat)
		"bass":
			_bass(p, i, s, beat)
	return p


## Knees giving on every beat and a little weight shift: anyone standing.
static func _bob(p: Dictionary, beat: float, depth := 1.0, shift := 0.0) -> void:
	var b := 0.5 + 0.5 * sin(beat)
	var j: Dictionary = p.joints
	j.l_hip = Vector3(-4.0 - 4.0 * b * depth, 0.0, 3.0 + 4.0 * shift)
	j.r_hip = Vector3(-4.0 - 4.0 * b * depth, 0.0, -3.0 + 4.0 * shift)
	j.l_knee = Vector3(6.0 + 9.0 * b * depth + maxf(0.0, -shift) * 10.0, 0.0, 0.0)
	j.r_knee = Vector3(6.0 + 9.0 * b * depth + maxf(0.0, shift) * 10.0, 0.0, 0.0)
	j.l_ankle = Vector3(-2.0 - 4.0 * b * depth, 0.0, 0.0)
	j.r_ankle = Vector3(-2.0 - 4.0 * b * depth, 0.0, 0.0)
	j.pelvis = Vector3(2.0, 0.0, -3.0 * shift)
	j.neck = Vector3(5.0 * sin(beat) * depth, 0.0, 0.0)
	p.pelvis_y = PELVIS_Y - 0.01 - 0.025 * b * depth
	p.pelvis_x = 0.04 * shift


## The DJ: decks, mixer, a cue in the headphones, a hand in the air, and long looks
## at the room.
static func _dj(p: Dictionary, i: int, s: float, beat: float) -> void:
	var j: Dictionary = p.joints
	var y := DJ_TOP + 0.03
	var deck_l := Vector3(DJ_DECK_X, y, DJ_Z)
	var deck_r := Vector3(-DJ_DECK_X, y, DJ_Z)
	var mixer := Vector3(0.0, y + 0.02, DJ_Z - 0.06)
	p.reach = { "l": 1.0, "r": 1.0 }
	j.spine = Vector3(6.0, 0.0, 0.0)
	j.chest = Vector3(8.0, 0.0, 0.0)
	match i:
		0:  # mixing: a hand riding the left deck, the other on the faders
			_bob(p, beat, 1.0, 0.3 * sin(TAU * s / 4.0))
			p.hands.l = deck_l + Vector3(0.04 * cos(TAU * s / 1.6), 0.0, 0.04 * sin(TAU * s / 1.6))
			p.hands.r = mixer + Vector3(0.03 * sin(TAU * s / 2.2), 0.0, 0.02 * sin(beat * 0.5))
			j.head = Vector3(18.0, 10.0 * sin(TAU * s / 5.0), 0.0)
		1:  # scratching on the right deck, the crossfader flicking under the left hand
			_bob(p, beat, 0.6)
			var flick := signf(sin(beat * 2.0))
			p.hands.r = deck_r + Vector3(0.0, 0.0, 0.06 * sin(beat * 2.0))
			p.hands.l = mixer + Vector3(0.05 + 0.04 * flick, 0.0, -0.04)
			j.chest = Vector3(12.0, -8.0, 0.0)
			j.head = Vector3(26.0, -18.0, 0.0)
		2:  # a cue in the headphones (left hand to the ear), eyes on the crowd
			_bob(p, beat, 0.8)
			p.hands.l = Vector3(0.16, 1.66, 0.05)
			p.hands.r = deck_r + Vector3(0.03 * sin(TAU * s / 1.4), 0.0, 0.0)
			j.head = Vector3(4.0, 30.0 * sin(TAU * s / 6.0), 12.0)
		3:  # a hand in the air on the drop
			_bob(p, beat, 1.4)
			p.reach.r = 0.0
			j.r_shoulder = Vector3(-30.0, 0.0, -150.0 + 12.0 * sin(beat))
			j.r_elbow = Vector3(-25.0 - 30.0 * maxf(0.0, sin(beat)), 0.0, 0.0)
			j.r_wrist = Vector3(0.0, 0.0, -12.0 * sin(beat))
			p.hands.l = deck_l
			j.chest = Vector3(2.0, 10.0, 0.0)
			j.head = Vector3(-10.0 + 8.0 * sin(beat), -20.0, 0.0)
		_:  # both hands on the knobs, a slow look round the whole room, weight shifting
			_bob(p, beat, 0.8, sin(TAU * s / 4.0))
			p.hands.l = mixer + Vector3(0.07, 0.03, 0.02 * sin(TAU * s / 1.3))
			p.hands.r = mixer + Vector3(-0.07, 0.03, -0.02 * sin(TAU * s / 1.7))
			j.head = Vector3(6.0, 50.0 * sin(TAU * s / 4.0), 0.0)
			j.chest = Vector3(8.0, 12.0 * sin(TAU * s / 4.0), 0.0)


## Standing at the techno kit with sticks: a groove (left on the snare pad on
## the beat, right on a tom off it), a fill across the toms, a crash on the cymbal
## pad, a stick in the air, and a long look round the room on the downbeats.
static func _drum(p: Dictionary, i: int, s: float, beat: float) -> void:
	var j: Dictionary = p.joints
	p.reach = { "l": 1.0, "r": 1.0 }
	j.spine = Vector3(5.0, 0.0, 0.0)
	j.chest = Vector3(8.0, 0.0, 0.0)
	var beats := beat / TAU
	var snare := drum_hand(Vector3(0.0, DRUM_PAD_Y, DRUM_Z), 0.0)
	var tom_l := drum_hand(Vector3(DRUM_TOM_X, DRUM_TOM_Y, DRUM_Z + 0.06), 0.0)
	var tom_r := drum_hand(Vector3(-DRUM_TOM_X, DRUM_TOM_Y, DRUM_Z + 0.06), 0.0)
	var up := Vector3(0, 1, 0)
	match i:
		0:  # the groove
			_bob(p, beat, 1.0, 0.3 * sin(TAU * s / 4.0))
			p.hands.l = snare + Vector3(0.05, 0, 0) + up * _strike(beats) * 0.14
			p.hands.r = tom_r + up * _strike(beats + 0.5) * 0.14
			j.head = Vector3(14.0, 10.0 * sin(TAU * s / 4.0), 0.0)
		1:  # a fill: sixteenths walking across the pads
			_bob(p, beat, 0.6)
			var step := int(fposmod(beats * 4.0, 4.0))
			var pads := [tom_l, snare, tom_r, snare]
			p.hands.l = (pads[step] as Vector3) + Vector3(0.06, 0, 0) + up * _strike(beats * 4.0) * 0.08
			p.hands.r = (pads[(step + 1) % 4] as Vector3) - Vector3(0.06, 0, 0) + up * _strike(beats * 4.0 + 0.5) * 0.08
			j.chest = Vector3(14.0, 6.0 * sin(beat * 2.0), 0.0)
			j.head = Vector3(22.0, 0.0, 0.0)
		2:  # a crash on the cymbal pad, the left hand keeping the snare
			_bob(p, beat, 1.3)
			var crash := drum_hand(Vector3(-DRUM_CYM_X, DRUM_CYM_Y, DRUM_Z + 0.1), 0.0)
			p.hands.r = crash + up * _strike(beats * 0.5) * 0.18
			p.hands.l = snare + Vector3(0.05, 0, 0) + up * _strike(beats) * 0.14
			j.chest = Vector3(4.0, -12.0, 0.0)
			j.head = Vector3(-4.0, -20.0, 0.0)
		3:  # a stick in the air, eyes on the crowd
			_bob(p, beat, 1.4)
			p.reach.r = 0.0
			j.r_shoulder = Vector3(-30.0, 0.0, -150.0 + 12.0 * sin(beat))
			j.r_elbow = Vector3(-25.0 - 25.0 * maxf(0.0, sin(beat)), 0.0, 0.0)
			p.hands.l = snare + Vector3(0.05, 0, 0) + up * _strike(beats) * 0.14
			j.head = Vector3(-8.0 + 8.0 * sin(beat), 18.0, 0.0)
		_:  # the downbeats only, a long look round the room, weight foot to foot
			_bob(p, beat, 0.8, sin(TAU * s / 4.0))
			p.hands.l = tom_l + up * _strike(beats * 0.5) * 0.2
			p.hands.r = tom_r + up * _strike(beats * 0.5 + 0.5) * 0.2
			j.head = Vector3(4.0, 55.0 * sin(TAU * s / 4.0), 0.0)
			j.chest = Vector3(8.0, 12.0 * sin(TAU * s / 4.0), 0.0)


## Where the hand goes for its stick's tip to land on a pad at `pad`: up and back
## toward the drummer by the stick's reach, `lift` higher.
static func drum_hand(pad: Vector3, lift: float) -> Vector3:
	return pad + Vector3(0.0, 0.16 + lift, -STICK * 0.8)


## The upright bass, played up on the neck with both hands (the left fretting,
## the right tapping just below it): the groove, walking up the neck, leaning
## in, a long look round, and hammering it.
static func _bass(p: Dictionary, i: int, s: float, beat: float) -> void:
	var j: Dictionary = p.joints
	var neck_h := 1.36
	var gap := 0.2                  # the right hand this far below the left
	p.reach = { "l": 1.0, "r": 1.0 }
	j.chest = Vector3(4.0, -6.0, 0.0)
	var tap := 0.02 * _strike(beat / TAU * 2.0)
	match i:
		0:  # the groove, nodding along, eyes on the neck now and then
			_bob(p, beat, 0.8, 0.3 * sin(TAU * s / 4.0))
			neck_h += 0.03 * sin(beat * 0.5)
			j.head = Vector3(10.0, -14.0 + 10.0 * sin(TAU * s / 4.0), 0.0)
		1:  # walking both hands up the neck, watching them
			_bob(p, beat, 0.6)
			neck_h = lerpf(1.26, 1.46, _smooth01(s / SEG_S))
			tap *= 1.5
			j.head = Vector3(18.0, 18.0, 6.0)
		2:  # leaning in, eyes closed, swaying with it
			_bob(p, beat, 0.5)
			j.spine = Vector3(8.0, 0.0, 6.0 * sin(TAU * s / 4.0))
			j.chest = Vector3(10.0, -10.0, 4.0 * sin(TAU * s / 4.0))
			j.head = Vector3(22.0, -4.0, 10.0 * sin(TAU * s / 4.0))
		3:  # a long look round the room, weight from foot to foot
			_bob(p, beat, 0.7, sin(TAU * s / 4.0))
			j.head = Vector3(0.0, 55.0 * sin(TAU * s / 4.0) - 10.0, 0.0)
		_:  # hammering it: the hands spread, bigger taps, a big nod
			_bob(p, beat, 1.3)
			gap = 0.28
			tap = 0.05 * _strike(beat / TAU * 2.0)
			j.head = Vector3(6.0 + 10.0 * sin(beat), -10.0, 0.0)
	var hi := bass_axis(neck_h)
	var lo := bass_axis(neck_h - gap)
	p.hands.l = Vector3(hi.x + 0.05, hi.y, hi.z + 0.03)
	p.hands.r = Vector3(lo.x - 0.05, lo.y + tap, lo.z + 0.05 + tap)


## A hand strike over a beat: 0 on the skin at each whole beat, up in between.
static func _strike(beats: float) -> float:
	var u := fposmod(beats, 1.0)
	return pow(sin(PI * u), 2.0) * (1.0 if u > 0.15 else u / 0.15)


static func _smooth01(x: float) -> float:
	var u := clampf(x, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


# ------------------------------------------------------------------ the crowd

## The bottle at the chest between sips (weight 0..1 over the walk).
static func hold(joints: Dictionary, w: float) -> void:
	for n in HOLD:
		if joints.has(n):
			var j := joints[n] as Node3D
			j.rotation_degrees = j.rotation_degrees.lerp(HOLD[n], w)


## A sip: the bottle up to the mouth, the head back, and down again. `t` 0..1.
static func sip_pose(t: float) -> Dictionary:
	var up := _smooth01(t / 0.3) * (1.0 - _smooth01((t - 0.75) / 0.25))
	var tilt := _smooth01((t - 0.35) / 0.25) * (1.0 - _smooth01((t - 0.7) / 0.15))
	return {
		"r_shoulder": HOLD.r_shoulder.lerp(Vector3(-58.0, 0.0, -26.0), up),
		"r_elbow": HOLD.r_elbow.lerp(Vector3(-140.0, 0.0, 0.0), up),
		"r_wrist": Vector3(0.0, 0.0, 0.0).lerp(Vector3(-20.0, 0.0, 0.0), tilt),
		"neck": Vector3(-6.0 * up - 6.0 * tilt, 0.0, 0.0),
		"head": Vector3(-8.0 * up - 16.0 * tilt, 0.0, 0.0),
	}
