extends SceneTree
## Issue #193 review stills: the Remnant cruiser from space and from inside. Boots
## the real town scene with the look on, Oda's cruiser chapter open, and stands
## the player (frozen) at each shot so the sky and the detail tier are the ones you
## would have there; a camera of its own takes the picture, with the HUD off. No
## bar, so the player's save is never loaded or written.
##
## Run (a window opens; real GPU):
##   godot --path . --fixed-fps 60 --resolution 1600x900 -s res://tools/review/cruiser_shot.gd -- out=/abs/dir [only=bay,bridge]

var demo
var out_dir := "res://test_results/cruiser"
var only: Array = []
var cam: Camera3D


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			out_dir = arg.trim_prefix("out=").trim_suffix("/")
		elif arg.begins_with("only="):
			only = Array(arg.trim_prefix("only=").split(","))
	WorldState.reset()
	GameFlow.reset()
	GameFlow.dogfight_override = false
	GameFlow.change_scene = func(_p: String) -> void: pass
	Story.skip_to("cruiser")
	WorldState.time_of_day = "noon"
	_run()


func frames(n: int) -> void:
	for i in n:
		await process_frame


## Shots: name -> [player stands at (cruiser frame), camera at, looks at (cruiser frame)].
func _shots() -> Array:
	return [
		["from_orbit", Vector3(-3200, 900, -900), Vector3(-3200, 900, -900), Vector3(0, 0, 40), true],
		["broadside", Vector3(24, -14, -62), Vector3(900, 120, -260), Vector3(0, 10, 0), false],
		["stern", Vector3(24, -14, -62), Vector3(420, 220, 760), Vector3(0, 20, 200), false],
		["bow", Vector3(24, -14, -62), Vector3(300, 60, -700), Vector3(0, 0, -100), false],
		["bay", Vector3(-30, -14, 10), Vector3(-34, -10.5, 14), Vector3(30, -8, -90), false],
		["bay_mouth", Vector3(-30, -14, -60), Vector3(-40, -6, -40), Vector3(60, -4, -70), false],
		["corridor", Vector3(0, -14, 60), Vector3(0, -12.2, 50), Vector3(0, -12.2, 200), false],
		["shaft", Vector3(-12, -14, 280), Vector3(-16, -12.3, 276), Vector3(6, 40, 312), false],
		["bridge", Vector3(0, 58, 262), Vector3(0, 60.2, 266), Vector3(0, 59.5, 214), false],
		["bridge_window", Vector3(0, 58, 222), Vector3(-14, 59.8, 226), Vector3(10, 59.0, 212), false],
	]


func _run() -> void:
	demo = load("res://scenes/town_demo.gd").new()
	demo.use_look = true
	demo.with_bar = false          # the bar owns the save: never load or write the player's
	get_root().add_child(demo)
	await frames(30)
	var c = demo.cruiser
	if c == null:
		print("CRUISER_SHOT no cruiser")
		quit(1)
		return
	cam = Camera3D.new()
	cam.far = 160000.0
	cam.near = 0.1
	cam.fov = 70.0
	demo.add_child(cam)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var player: Node3D = demo._player
	for s in _shots():
		var name := str(s[0])
		if not only.is_empty() and not only.has(name):
			continue
		paused = false
		player.process_mode = Node.PROCESS_MODE_INHERIT
		player.global_position = c.frame * (s[1] as Vector3) + Vector3(0, 0.1, 0)
		await frames(3)
		if bool(s[4]):
			player.process_mode = Node.PROCESS_MODE_DISABLED     # hanging in space: no falling
		var at: Vector3 = c.frame * (s[2] as Vector3)
		var look: Vector3 = c.frame * (s[3] as Vector3)
		cam.global_transform = Transform3D(Basis.looking_at(look - at, Vector3.UP), at)
		for i in 90:
			paused = false             # the first-run overlays pause the game
			cam.make_current()
			_hide_hud(get_root())
			await process_frame
		await RenderingServer.frame_post_draw
		var img: Image = get_root().get_texture().get_image()
		var path := ProjectSettings.globalize_path(out_dir + "/" + name + ".png")
		img.save_png(path)
		print("CRUISER_SHOT ", path)
	demo.queue_free()
	await frames(5)
	quit()


## Stills of the place, not the HUD: every canvas layer off.
func _hide_hud(n: Node) -> void:
	if n is CanvasLayer:
		(n as CanvasLayer).visible = false
		return
	for ch in n.get_children():
		_hide_hud(ch)
