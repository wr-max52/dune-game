extends RefCounted
## Aim down sights maths (issue #65), kept pure so it is testable headless.
##
## The ADS pose is solved from the camera, not hand tuned: a fixed chest-space
## offset cannot keep a sight on the screen centre because in first person the
## chest follows the camera pitch at a different rate. So while aimed the weapon is
## put where the camera is: pointing along its forward axis, with the sight point
## on the centre line, `relief` metres in front of the eye. Anything on that line
## (rear notch, front post, scope reticle) lands on the crosshair.

const DEFAULTS := { "sight": [0.0, 0.1, 0.0], "relief": 0.25, "mag": 1.0, "blend_s": 0.15 }


## The `ads` block of a gun in hand_weapons.json, missing keys filled in.
static func spec(look: Dictionary, id: String) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate(true)
	var g = look.get(id, {})
	if g is Dictionary and g.get("ads") is Dictionary:
		out.merge(g.ads, true)
	return out


static func has_ads(look: Dictionary, id: String) -> bool:
	var g = look.get(id, {})
	return g is Dictionary and g.get("ads") is Dictionary


static func magnification(look: Dictionary, id: String) -> float:
	return maxf(1.0, float(spec(look, id).mag))


## What to hand CameraRigNode.set_zoom: fov = base_fov * zoom = base_fov / mag.
static func zoom(look: Dictionary, id: String) -> float:
	return 1.0 / magnification(look, id)


static func sight_point(look: Dictionary, id: String) -> Vector3:
	var a = spec(look, id).sight
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## World transform of the weapon (model space, +Z along the barrel) that puts
## `sight` (model space) on the camera's centre line, `relief` in front of the eye,
## with the barrel along the camera's forward axis (-Z of the camera).
static func weapon_global(cam: Transform3D, sight: Vector3, relief: float) -> Transform3D:
	var b := cam.basis.orthonormalized() * Basis(Vector3.UP, PI)
	return Transform3D(b, cam.origin - cam.basis.orthonormalized().z * relief - b * sight)


## How far (metres) the sight point is off the camera's centre line; 0 when aligned.
static func centre_error(cam: Transform3D, weapon: Transform3D, sight: Vector3) -> float:
	var local := cam.affine_inverse() * (weapon * sight)
	return Vector2(local.x, local.y).length()
