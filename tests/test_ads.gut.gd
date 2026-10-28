extends GutTest
## Aim down sights (issue #65): per-gun magnification from data, the ADS pose
## solver putting the sight on the camera centre line, the crosshair hiding behind
## the sights, the scope and iron sights on the guns, and the dark variants.

const Ads := preload("res://src/systems/look/ads.gd")
const BodyAnimator := preload("res://src/systems/anim/body_animator.gd")
const LOOK := "res://content/look/hand_weapons.json"
var look: Dictionary


func before_all() -> void:
	look = JSON.parse_string(FileAccess.get_file_as_string(LOOK))


func test_magnification_from_data() -> void:
	assert_almost_eq(Ads.magnification(look, "pistol_blaster"), 1.25, 0.0001)
	assert_almost_eq(Ads.magnification(look, "rifle_blaster"), 2.5, 0.0001)


func test_rifle_zooms_twice_the_pistol() -> void:
	var p := Ads.magnification(look, "pistol_blaster")
	var r := Ads.magnification(look, "rifle_blaster")
	assert_almost_eq(r / p, 2.0, 0.0001, "rifle magnification is 2x the pistol's")
	assert_almost_eq(Ads.zoom(look, "pistol_blaster") / Ads.zoom(look, "rifle_blaster"), 2.0, 0.0001)
	assert_almost_eq(75.0 * Ads.zoom(look, "rifle_blaster"), 30.0, 0.0001, "fov = base / mag")


func test_every_gun_has_an_ads_block() -> void:
	for id in ["pistol_blaster", "rifle_blaster"]:
		assert_true(Ads.has_ads(look, id), id)
		var a := Ads.spec(look, id)
		assert_almost_eq(float(a.blend_s), 0.15, 0.05, id + " blend time ~0.15 s")
		assert_gt(float(a.relief), 0.0)


func test_solver_puts_sight_on_camera_centre_line() -> void:
	for id in ["pistol_blaster", "rifle_blaster"]:
		var sight := Ads.sight_point(look, id)
		var relief := float(Ads.spec(look, id).relief)
		for yaw in [0.0, 0.7, -2.3, 3.0]:
			for pitch in [-1.2, -0.5, 0.0, 0.4, 1.3]:
				var cam := Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0.0)), Vector3(3.2, 1.6, -7.5))
				var w := Ads.weapon_global(cam, sight, relief)
				assert_lt(Ads.centre_error(cam, w, sight), 0.001, "%s yaw %.1f pitch %.1f" % [id, yaw, pitch])
				# At relief metres in front of the eye, barrel along the view.
				var local := cam.affine_inverse() * (w * sight)
				assert_almost_eq(local.z, -relief, 0.001)
				var fwd := (w.basis * Vector3.BACK).normalized()
				assert_gt(fwd.dot(-cam.basis.z), 0.9999, "barrel points along camera forward")


func test_crosshair_hides_when_aimed_in_first_person() -> void:
	var shown := PlayerWeapons.crosshair_shown
	assert_true(shown.call(true, true, false, true, 0.0), "hip fire keeps it")
	assert_true(shown.call(true, true, false, true, 0.5), "still shown while the blend is under way")
	assert_false(shown.call(true, true, false, true, 1.0), "hidden fully aimed in first person")
	assert_true(shown.call(true, true, false, false, 1.0), "third person aimed keeps it")
	assert_false(shown.call(false, true, false, false, 0.0), "no gun, no crosshair")


func _avatar() -> PlayerAvatar:
	var a := PlayerAvatar.new()
	add_child_autofree(a)
	a.build_weapons(["pistol_blaster", "energy_blade", "rifle_blaster"])
	return a


func test_avatar_sight_lands_on_screen_centre() -> void:
	var a := _avatar()
	a.set_first_person(true)
	var cam := Camera3D.new()
	add_child_autofree(cam)
	a.ads_camera = cam
	for id in ["pistol_blaster", "rifle_blaster"]:
		for pitch in [-0.6, 0.0, 0.5]:
			cam.global_transform = Transform3D(Basis.from_euler(Vector3(pitch, 1.1, 0.0)), Vector3(0.0, 1.6, 0.0))
			a.current = id
			a.drawn = 1.0
			a.ads_on = true
			a.ads_blend = 0.0
			a.animate(1.0 / 60.0, { "upper": BodyAnimator.UPPER_RIFLE if id == "rifle_blaster" else BodyAnimator.UPPER_AIM, "cam_yaw": 1.1, "aim_pitch": pitch })
			a._process(1.0)
			assert_eq(a.ads_blend, 1.0)
			var sight := Ads.sight_point(look, id)
			var err := Ads.centre_error(cam.global_transform, a.weapon_node(id).global_transform, sight)
			assert_lt(err, 0.001, "%s sight on the centre line at pitch %.1f (error %.4f m)" % [id, pitch, err])
	# Leaving aim blends back to the hip pose.
	a.ads_on = false
	a._process(1.0)
	assert_eq(a.ads_blend, 0.0)


func test_rifle_has_a_scope_on_the_sight_line() -> void:
	var a := _avatar()
	var rifle := a.weapon_node("rifle_blaster")
	var scope := rifle.find_child("Scope", true, false) as Node3D
	assert_not_null(scope, "rifle has a procedural scope")
	assert_not_null(scope.find_child("Reticle", true, false), "with a reticle")
	var sight := Ads.sight_point(look, "rifle_blaster")
	assert_almost_eq(scope.position.x, sight.x, 0.0005)
	assert_almost_eq(scope.position.y, sight.y, 0.0005, "scope axis is the sight line")
	var reticle := scope.find_child("Reticle", true, false) as Node3D
	assert_almost_eq(reticle.position.x, 0.0, 0.0001)
	assert_almost_eq(reticle.position.y, 0.0, 0.0001, "reticle sits on the scope axis")
	var rear_z := scope.position.z - float(look.rifle_blaster.scope.length) * 0.5
	assert_almost_eq(rear_z, sight.z, 0.006, "sight point is the eyepiece")
	assert_gt(_count_meshes(scope), 8, "tube, bells, rings, lenses, reticle")


func test_scope_lenses_are_transparent_glass() -> void:
	var a := _avatar()
	var scope := a.weapon_node("rifle_blaster").find_child("Scope", true, false) as Node3D
	var lenses := scope.find_children("Lens*", "MeshInstance3D", true, false)
	assert_eq(lenses.size(), 2, "front and rear lens")
	for l in lenses:
		var m := (l as MeshInstance3D).material_override as StandardMaterial3D
		assert_eq(m.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA)
		assert_lt(m.albedo_color.a, 0.3, "see-through glass")
	var ret := scope.find_child("Reticle", true, false).get_child(0) as MeshInstance3D
	var rm := ret.material_override as StandardMaterial3D
	assert_true(rm.no_depth_test, "reticle floats over the glass")
	assert_eq(rm.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED)


func test_pistol_has_front_post_and_rear_notch() -> void:
	var a := _avatar()
	var s := a.weapon_node("pistol_blaster").find_child("IronSights", true, false) as Node3D
	assert_not_null(s)
	assert_eq(s.get_child_count(), 3, "front post + two rear blades")
	var sight := Ads.sight_point(look, "pistol_blaster")
	var sp: Dictionary = look.pistol_blaster.sights
	var post_top := float(sp.front.pos[1]) + float(sp.front.size[1]) * 0.5
	assert_almost_eq(post_top, sight.y, 0.001, "post tip is on the sight line")
	assert_almost_eq(float(sp.front.pos[0]), sight.x, 0.0001)
	assert_lt(float(sp.rear.pos[1]) - float(sp.rear.size[1]) * 0.5, sight.y, "notch bottom below the line")
	assert_gt(float(sp.rear.pos[1]) + float(sp.rear.size[1]) * 0.5, sight.y, "blades rise past the line")


func test_guns_use_the_dark_variant() -> void:
	var a := _avatar()
	for id in ["pistol_blaster", "rifle_blaster"]:
		var found := 0
		for m in PlayerAvatar._meshes_under(a.weapon_node(id).get_child(0)):
			if m.material_override is ShaderMaterial:
				found += 1
				var mat := m.material_override as ShaderMaterial
				assert_not_null(mat.get_shader_parameter("albedo_tex"), id + " keeps its own texture")
				assert_lt(float(mat.get_shader_parameter("body_mul")), 0.5, id + " body is darkened")
				assert_gt(float(mat.get_shader_parameter("glow")), 0.0, id + " glow kept")
		assert_gt(found, 0, id + " model carries the dark material")


func _count_meshes(n: Node) -> int:
	var c := 1 if n is MeshInstance3D else 0
	for k in n.get_children():
		c += _count_meshes(k)
	return c
