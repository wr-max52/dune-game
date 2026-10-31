extends GutTest
## The moon rave's laser droid: it carries the lasers, and a shot at its hull
## puts them out and drops it to the floor.


func test_a_shot_puts_the_lasers_out_and_drops_it() -> void:
	var d := RaveDroid.new()
	d.home = Vector3(0, 6.6, 0)
	d.floor_at = func(_p: Vector3) -> float: return 0.9
	d.lasers.add_child(Node3D.new())
	add_child_autofree(d)
	assert_true(d.lasers.visible, "lasers on while it flies")
	var b := preload("res://scenes/entities/bolt.gd").new()
	b.handle_hit(d.hull)     # what a bolt does when it lands on the hull
	b.free()
	assert_false(d.alive, "shot down")
	assert_false(d.lasers.visible, "lasers out")
	for i in 120:
		d._process(1.0 / 30.0)
	assert_almost_eq(d.position.y, 0.9 + 0.35 * RaveDroid.SCALE, 0.01, "lying on the deck")
	d.apply_damage(10.0)     # a second shot does nothing
	assert_false(d.alive)
