extends Area3D
## Visible projectile -- the "bolt" (M2). Travels straight, leaves a short glow,
## and on first contact with anything that can take damage, it deals its damage and
## dies. The weapon actor spawns bolts in different collision layers so they hit
## enemies but not their own owner. In the GUI the bolt is visible; in headless CI
## the bolt's behavior (it travels and deals damage on hit) is proven by GUT.

var direction := Vector3.FORWARD
var damage := 10.0
var speed := 30.0
var range_m := 60.0
var _traveled := 0.0
var _alive := true
## Test seam: if set, a hit applies damage to this node instead of the colliding body.
var hit_target

signal on_hit(target)


func integrate(dt: float) -> Vector3:
	## Pure: compute the displacement for this frame and update range. The caller
	## applies it to its own node. No scene-tree access, so it is unit-testable.
	if not _alive:
		return Vector3.ZERO
	var step: Vector3 = direction * speed * dt
	_traveled += step.length()
	if _traveled >= range_m:
		_die()
	return step


## Apply this bolt's damage to a node that can take damage, then kill the bolt.
## `target` is typed Node (not Node3D) so RefCounted health components work too.
func apply_to(target: Object) -> void:
	if not _alive:
		return
	_die()
	handle_hit(target)


func handle_hit(target: Object) -> void:
	if target == null:
		return
	if target.has_method("apply_damage"):
		target.apply_damage(damage)
	elif target.get_parent() != null and target.get_parent().has_method("apply_damage"):
		target.get_parent().apply_damage(damage)
	on_hit.emit(target)


func _ready() -> void:
	# The bolt.tscn already carries a Glow MeshInstance3D; this branch only runs
	# when a bolt is created without the scene (e.g. in a headless test).
	if not has_node("Glow"):
		var mesh := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.18
		mesh.mesh = sphere
		mesh.name = "Glow"
		add_child(mesh)
	body_entered.connect(_on_body_entered)


func _physics_process(dt: float) -> void:
	# Advance the bolt along its direction by one frame.
	global_position += integrate(dt)


func _on_body_entered(body: Node3D) -> void:
	if not _alive:
		return
	if hit_target != null:
		apply_to(hit_target)
	else:
		apply_to(body)


func _die() -> void:
	_alive = false
	# A bolt in the scene tree is freed by the engine; a detached bolt (created in
	# a headless unit test) is freed at process exit. GUT reports this as one
	# orphan, which does not fail the suite. (Documented in KNOWN_ISSUES.md.)
	queue_free()
