extends RefCounted
## Camera rig math (M1).
##
## The rig's state is the player's yaw/pitch. First-person and third-person are
## two different *camera positions* computed from the SAME yaw/pitch, so toggling
## between them is a zero-second change that preserves the look direction (aim).
##
## This class holds no Node3D references: it is pure math so it is fully testable
## headless. The node (camera_rig_node.gd) owns a real Camera3D and drives these
## transforms. This is what makes "toggle view mid-combat without breaking aim"
## provable by a unit test rather than by eye.

## First-person camera offset relative to the player body origin (head height).
var fpv_offset := Vector3(0.0, 1.6, 0.0)
## Third-person distance / height behind and above the player.
var tpv_distance := 4.0
var tpv_height := 1.8
## M11: over-the-shoulder offset (meters to the camera's right). 0 = centered,
## which is the M1 behavior the tests pin; the scene sets a shoulder.
var tpv_shoulder := 0.0

enum Mode { FPV, TPV }

var yaw := 0.0            # radians, world-space horizontal angle
var pitch := 0.0          # radians, clamped
var mode := Mode.FPV
var min_pitch := -PI / 2.0 + 0.05
var max_pitch := PI / 2.0 - 0.05


func look_direction() -> Vector3:
	## Where the camera points, as a normalized direction. Same for both modes.
	var cp: float = cos(pitch)
	return Vector3(sin(yaw) * cp, sin(pitch), cos(yaw) * cp)


func camera_transform(player_pos: Vector3) -> Transform3D:
	## The Transform3D to apply to the live Camera3D this frame.
	var look := look_direction()
	var position: Vector3
	if mode == Mode.FPV:
		position = player_pos + fpv_offset
	else:
		# Sit behind and above the player, along the backward of the look dir.
		position = player_pos - look * tpv_distance + Vector3(0.0, tpv_height, 0.0)
		if tpv_shoulder != 0.0:
			position += look.cross(Vector3.UP).normalized() * tpv_shoulder
	# Build a right-handed basis whose -Z axis points along the look direction.
	# right = look x up. (Using -look x up flips right and gives a mirrored,
	# determinant -1 basis, which rendered the world left-right reversed.)
	var right: Vector3 = look.cross(Vector3.UP).normalized()
	var up: Vector3 = right.cross(look)
	var basis := Basis(right, up, -look)
	return Transform3D(basis, position)


## Returns true if toggling changed the mode.
func toggle_mode() -> bool:
	var before := mode
	mode = Mode.TPV if mode == Mode.FPV else Mode.FPV
	return mode != before


func set_mode(m: int) -> void:
	mode = m


## Where the third-person camera orbits from (the head), for wall collision.
func tpv_pivot(player_pos: Vector3) -> Vector3:
	return player_pos + Vector3(0.0, tpv_height, 0.0)


func is_first_person() -> bool:
	return mode == Mode.FPV


func add_yaw(delta: float) -> void:
	yaw += delta


func add_pitch(delta: float) -> void:
	pitch = clampf(pitch + delta, min_pitch, max_pitch)
