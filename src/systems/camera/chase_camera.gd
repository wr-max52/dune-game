extends RefCounted
## Flight camera math (M10). Pure, like the M1 camera rig: given the ship's
## transform each frame it returns where the camera should be. Two views, toggled
## with the same "toggle_view" action as on foot:
##   CHASE   -- behind and above the ship, lagging slightly so turns read on screen
##   COCKPIT -- at the pilot's eye, locked to the ship
## The node layer copies the result onto a Camera3D.

enum Mode { CHASE, COCKPIT }

var mode := Mode.CHASE
var chase_back := 18.0      ## metres behind the ship
var chase_up := 5.0         ## metres above
var look_ahead := 60.0      ## the camera aims this far ahead of the nose
var stiffness := 7.0        ## higher = tighter follow
var cockpit_offset := Vector3(0.0, 0.9, -1.2)
var xform := Transform3D.IDENTITY
var _primed := false


func toggle_mode() -> void:
	mode = Mode.COCKPIT if mode == Mode.CHASE else Mode.CHASE


func is_cockpit() -> bool:
	return mode == Mode.COCKPIT


## Size the chase offset to the ship (bigger ships sit further from the camera).
func fit_to(ship_length: float) -> void:
	chase_back = maxf(12.0, ship_length * 2.0)
	chase_up = maxf(3.5, ship_length * 0.55)


func desired(ship: Transform3D) -> Transform3D:
	var b := ship.basis.orthonormalized()
	if mode == Mode.COCKPIT:
		return Transform3D(b, ship * cockpit_offset)
	var pos := ship.origin + b.z * chase_back + b.y * chase_up
	var target := ship.origin - b.z * look_ahead
	return Transform3D(Basis.looking_at(target - pos, b.y), pos)


func update(dt: float, ship: Transform3D) -> Transform3D:
	var want := desired(ship)
	if not _primed or mode == Mode.COCKPIT:
		xform = want
		_primed = true
		return xform
	var k := 1.0 - exp(-stiffness * dt)
	var q := xform.basis.get_rotation_quaternion().slerp(want.basis.get_rotation_quaternion(), k)
	xform = Transform3D(Basis(q), xform.origin.lerp(want.origin, k))
	return xform
