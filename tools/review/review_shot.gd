extends SceneTree
var demo
var f := 0
func _initialize():
	demo = load("res://scenes/m1_demo.gd").new()
	get_root().add_child(demo)
func _process(_d):
	f += 1
	if f == 90 or f == 250:
		var img = get_root().get_texture().get_image()
		img.save_png("user://review_shot_%d.png" % f)
		print("SHOT ", f, " view=", "FPV" if demo._rig.rig.is_first_person() else "TPV")
	if f > 250:
		quit()
	return false
