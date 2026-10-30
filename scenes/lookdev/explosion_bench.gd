extends Node3D
## Look-dev bench for ExplosionFx: a patch of sand, a droid-sized post, a speeder-
## sized and a ship-sized block. It blows them up in turn, on a loop: droid pop,
## speeder, ship. Space bar: all three again now.
##
## Run it in the editor (F6), or shoot frames of each to a folder:
##   godot --path . --resolution 1280x720 scenes/lookdev/explosion_bench.tscn -- shots=test_results/explosions

const LOOP_S := 9.0
const SHOT_TIMES := [0.05, 0.15, 0.35, 0.7, 1.2, 2.2]   ## seconds after each blast

var look: LookEnvironment
var camera: Camera3D
var _t := 0.0
var _fired := {}
var _shots_dir := ""
var _shots: Array = []          ## { at, name }: frames still to save, by bench time


func _ready() -> void:
	look = LookEnvironment.new()
	add_child(look)
	look.apply()
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("#c9a46a")
	gm.roughness = 0.95
	ground.material_override = gm
	add_child(ground)
	for spec in [[Vector3(-7, 0.75, 0), Vector3(0.6, 1.5, 0.6)], [Vector3(0, 0.6, 0), Vector3(3.0, 0.8, 1.6)], [Vector3(10, 1.5, -4), Vector3(8.0, 2.5, 6.0)]]:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = spec[1]
		b.mesh = bm
		b.position = spec[0]
		add_child(b)
	camera = Camera3D.new()
	camera.fov = 60.0
	add_child(camera)
	camera.look_at_from_position(Vector3(1.5, 5.0, 22.0), Vector3(1.5, 2.0, -1.0))
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("shots="):
			_shots_dir = str(a).substr(6)
	if _shots_dir != "":
		DirAccess.make_dir_recursive_absolute(_shots_dir)
		for blast in [["droid", 0.5], ["speeder", 3.5], ["ship", 6.5]]:
			for st in SHOT_TIMES:
				_shots.append({ "at": float(blast[1]) + st, "name": "%s_%03d" % [blast[0], int(st * 100)] })


func _process(dt: float) -> void:
	_t += dt
	var loop_t := fmod(_t, LOOP_S)
	var lap := int(_t / LOOP_S)
	_at(lap, loop_t, 0.5, "droid", func(): _frame(Vector3(-7, 1.2, 0), 7.0); ExplosionFx.small(self, Vector3(-7, 1.2, 0)))
	_at(lap, loop_t, 3.5, "speeder", func(): _frame(Vector3(0, 0.8, 0), 14.0); ExplosionFx.big(self, Vector3(0, 0.8, 0), 0.6))
	_at(lap, loop_t, 6.5, "ship", func(): _frame(Vector3(10, 2.0, -4), 26.0); ExplosionFx.big(self, Vector3(10, 2.0, -4), 1.0))
	if not _shots.is_empty() and _t >= float(_shots[0].at):
		var img := get_viewport().get_texture().get_image()
		img.save_png(_shots_dir.path_join(str(_shots[0].name) + ".png"))
		_shots.pop_front()
		if _shots.is_empty():
			get_tree().quit()


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and (e as InputEventKey).keycode == KEY_SPACE:
		ExplosionFx.small(self, Vector3(-7, 1.2, 0))
		ExplosionFx.big(self, Vector3(0, 0.8, 0), 0.6)
		ExplosionFx.big(self, Vector3(10, 2.0, -4), 1.0)


## Swing the camera round to look at a blast from `dist` metres.
func _frame(at: Vector3, dist: float) -> void:
	camera.look_at_from_position(at + Vector3(0.3, 0.35, 1.0).normalized() * dist, at + Vector3(0, dist * 0.08, 0))


func _at(lap: int, loop_t: float, when: float, key: String, fire: Callable) -> void:
	var k := "%d_%s" % [lap, key]
	if loop_t >= when and not _fired.has(k):
		_fired[k] = true
		fire.call()
