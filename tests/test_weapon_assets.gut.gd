extends GutTest
## Every model and sound the hand weapons point at must exist and load. A missing
## file used to fail silently (no gun on screen): the M11 models were never
## committed because a `models/` ignore rule matched their folder.

const LOOK := "res://content/look/hand_weapons.json"
var look: Dictionary


func before_all() -> void:
	look = JSON.parse_string(FileAccess.get_file_as_string(LOOK))


func _meshes(n: Node) -> int:
	var c := 1 if n is MeshInstance3D else 0
	for k in n.get_children():
		c += _meshes(k)
	return c


func test_weapon_models_exist_and_have_meshes() -> void:
	for id in ["pistol_blaster", "rifle_blaster"]:
		var path := str(look[id].model)
		assert_true(ResourceLoader.exists(path), "model exists: " + path)
		var scene = load(path)
		assert_true(scene is PackedScene, "model loads: " + path)
		if scene is PackedScene:
			var n: Node = scene.instantiate()
			assert_gt(_meshes(n), 0, "model has meshes: " + path)
			n.free()


func test_weapon_sounds_exist() -> void:
	var paths: Array = look.sounds.values()
	paths.append(look.pistol_blaster.sound)
	paths.append(look.rifle_blaster.sound)
	for p in paths:
		assert_true(ResourceLoader.exists(str(p)), "sound exists: " + str(p))


func test_avatar_builds_visible_gun_meshes() -> void:
	var a := PlayerAvatar.new()
	a.build_weapons(["pistol_blaster", "energy_blade", "rifle_blaster"])
	for id in ["pistol_blaster", "rifle_blaster"]:
		assert_gt(_meshes(a.weapon_node(id)), 3, id + " has its model, not just the muzzle")
	a.free()
