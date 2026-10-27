extends SceneTree
func _initialize():
	_run()
func _run():
	WorldState.reset()
	var demo = load("res://scenes/town_demo.tscn").instantiate()
	demo.npc_brains = false
	get_root().add_child(demo)
	for i in 30: await process_frame
	var post = demo.speeder_post
	print("SMOKE post=", post != null, " skrugs=", post.skrugs != null if post else false, " spot=", post.spot != null if post else false)
	print("SMOKE origin=", post.origin, " customer=", post.world_point("customer"), " spawn=", post.world_point("spawn"))
	print("SMOKE spots=", demo.bar.spots.map(func(s): return s.id()) if demo.bar else "nobar")
	print("SMOKE display y=", post.display.model.position, " ground=", post.display.model.ground_height())
	var p = demo._player
	p.global_position = post.world_point("customer") + Vector3(0, 0.05, 0)
	p.controller.body_pos = p.global_position
	for i in 20: await physics_frame
	print("SMOKE in range=", demo.bar.spot_in_range() == post.spot if demo.bar else "nobar", " player=", p.global_position)
	quit()
