extends SceneTree
## Reviewer probes: each prints PROBE <name>: <result>.

var _f := 0
var demo
var body
var wall_body
var bolt_hit := false
var bolt
var target

class Dmg extends StaticBody3D:
	var hits := 0
	func apply_damage(_a):
		hits += 1


func _initialize() -> void:
	# 1. Camera basis handedness
	var Rig = load("res://src/systems/camera/camera_rig.gd")
	var rig = Rig.new()
	var t: Transform3D = rig.camera_transform(Vector3.ZERO)
	print("PROBE camera_basis_det: ", t.basis.determinant(), " look=", rig.look_direction(), " cam_forward(-Z)=", -t.basis.z, " cam_right(+X)=", t.basis.x)

	# 2. Squad coordinator with members NOT already on their nodes
	var Squad = load("res://src/systems/ai/squad_coordinator.gd")
	var sq = Squad.new()
	sq.cover_nodes = [{ "position": Vector3(0, 0, 0) }, { "position": Vector3(100, 0, 0) }]
	sq.members = [Vector3(99, 0, 0), Vector3(1, 0, 0)]  # member0 next to node1, member1 next to node0
	print("PROBE squad_assign (want [1,0]): ", sq.assign(2))

	# 3. Bartender fallback cycle
	var B = load("res://src/systems/llm/bartender_ai.gd")
	var b = B.new()
	b.fallback_lines = ["A", "B", "C"]
	var seq := []
	for i in 7:
		seq.append(b.respond("hi", {})["reply"])
	print("PROBE bartender_fallback_seq: ", seq)
	# 3b. Does the player's text reach the model at all?
	var S = load("res://src/systems/llm/scripted_client.gd")
	var c = S.new()
	c.new_with_responses([{ "text": "same answer" }, { "text": "same answer" }])
	b.client = c
	print("PROBE bartender_ignores_input: ", b.respond("where is the crate?", {})["reply"], " | ", b.respond("I hate you", {})["reply"])

	# 4. Weapon fire rate frame dependency (pistol rate 0.12s)
	var W = load("res://src/systems/combat/weapon.gd")
	for fps in [144, 60, 30]:
		var w = W.new({ "mag": 100000, "rate": 0.12 })
		var shots := 0
		for i in fps * 10:
			if w.start_firing(1.0 / fps, true) == W.Result.SHOT:
				shots += 1
		print("PROBE pistol_shots_in_10s @", fps, "fps: ", shots, " (spec ", int(10.0 / 0.12), ")")

	# 5. Duelist parry rate and stuck block
	var D = load("res://src/systems/ai/duelist_brain.gd")
	var d = D.new({ "max_stamina": 100.0 })
	d.player_pos = Vector3(1, 0, 0)
	var parries := 0
	for i in 20:
		for k in 30:
			d.player_is_attacking = false
			d.update(1.0 / 60.0)
		d.player_is_attacking = true
		if d.update(1.0 / 60.0) == D.Stance.PARRY:
			parries += 1
	print("PROBE duelist_parries_of_20 (2/sec swings): ", parries, " blade_state=", d.blade.state, " (3=BLOCK) stamina=", snappedf(d.blade.stamina, 0.1))

	# 6. Push-to-talk voice fallback leaks raw sample as typed text
	var P = load("res://src/systems/voice/push_to_talk.gd")
	var p = P.new()
	p.prefer_voice()
	var audio := PackedByteArray([1, 2, 3, 4])
	print("PROBE ptt_voice_fallback_text: '", p.capture(audio, 0, 0), "' source=", p.last_source)
	p.press(); p.now_ms = 0
	p.release("hello")
	print("PROBE ptt_real_latency: ", p.last_latency_ms, "ms (clock never advances)")

	# 7. Save before new_game
	var Sv = load("res://src/systems/save/save_system.gd")
	var sv = Sv.new()
	sv.set_player_position(Vector3(1, 2, 3))
	sv.save_to("user://probe.json")
	var sv2 = Sv.new()
	sv2.load_from("user://probe.json")
	print("PROBE save_int_roundtrip credits type: ", typeof(sv2.data.get("credits", "missing")), " pos=", sv2.get_player_position())

	# 8. Chunk streamer boundary thrash
	var CS = load("res://src/systems/world/chunk_streamer.gd")
	var world := []
	for i in 11:
		world.append({ "id": "c%d" % i, "center": i * 100.0, "load_ms": 18.0 })
	var cs = CS.new(world)
	cs.work_budget_per_frame = 50.0
	cs.active_radius = 120.0
	var reloads := 0
	var total_work := 0.0
	for i in 600:
		var x := 230.0 + (1.0 if i % 2 == 0 else -1.0) * 1.5  # jitter around 230 (edge of c1 window)
		total_work += cs.update(0.016, x)
	print("PROBE streamer_jitter_work_ms over 600 frames standing still: ", total_work)
	# Budget tautology: give it a 10s chunk
	var cs2 = CS.new([{ "id": "big", "center": 0.0, "load_ms": 10000.0 }])
	cs2.work_budget_per_frame = 50.0
	cs2.active_radius = 50.0
	var frames := 0
	while not cs2.is_covered(0.0) and frames < 100000:
		cs2.update(0.016, 0.0)
		frames += 1
	print("PROBE streamer_10s_chunk: within_budget=", cs2.within_budget(), " frames_until_ground=", frames)

	# 9. Health float damage
	var H = load("res://src/systems/combat/health.gd")
	var h = H.new(100)
	for i in 10:
		h.apply_damage(0.9)
	print("PROBE health_after_10x0.9_dmg: ", h.hp)

	# 10. Scene-level: demo player + walls + bolt
	demo = load("res://scenes/m1_demo.gd").new()
	demo._auto = false
	get_root().add_child(demo)
	# a wall 3m ahead of the player on +Z
	wall_body = StaticBody3D.new()
	var cs3 := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(10, 4, 0.5)
	cs3.shape = bs
	wall_body.add_child(cs3)
	wall_body.position = Vector3(0, 1, 3)
	demo.add_child(wall_body)
	# bolt fired at a damageable box
	target = Dmg.new()
	var tcs := CollisionShape3D.new()
	var tb := BoxShape3D.new()
	tb.size = Vector3(2, 2, 2)
	tcs.shape = tb
	target.add_child(tcs)
	target.position = Vector3(-10, 1, 0)
	demo.add_child(target)
	bolt = load("res://scenes/entities/bolt.tscn").instantiate()
	bolt.direction = Vector3(-1, 0, 0)
	demo.add_child(bolt)
	bolt.position = Vector3(-2, 1, 0)


func _physics_process(_d) -> bool:
	_f += 1
	if _f < 60:
		demo._player.set_command(Vector2(0, 1), false, false, false)  # walk "forward" into the wall
	if _f == 60:
		print("PROBE player_after_1s_walk_into_wall_at_z=3: pos=", demo._player.global_position, " ctrl=", demo._player.controller.body_pos)
		demo._player.set_command(Vector2.ZERO, false, false, false)
		demo._rig.rig.yaw = 0.05  # a tiny mouse nudge (~3 degrees), then hands off
	if _f == 120:
		print("PROBE player_rotation_y_after_2s after one 0.05 rad mouse nudge 1s ago: ", demo._player.rotation.y)
		print("PROBE bolt_hits_on_target: ", target.hits, " bolt_alive=", is_instance_valid(bolt))
		quit(0)
	return false
