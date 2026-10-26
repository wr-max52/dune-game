class_name BarScene
extends Node
## The cantina bar, live (M12). Owns the bartender's body, her brain, the LLM
## service, the conversation UI, the debug and settings panels, and saving what
## she remembers. town_demo.gd builds one of these when the look is on.
##
## Walk up to the bar (the bar_front marker): "[E] Talk to Oda". Talking locks
## movement and weapons, frees the mouse, and moves the camera to a two-shot.
## Esc (or her ending it) walks you back out.

const TALK_RADIUS := 1.9
const TWO_SHOT_FOV := 34.0
const SAVE_PATH := "user://save.json"

var demo                              ## town_demo.gd
var npc: BartenderNPC
var llm: LLMService
var brain: BartenderBrain
var panel: DialoguePanel
var overlay: LLMDebugOverlay
var settings: LLMSettingsPanel
var save := SaveSystem.new()
var save_path := SAVE_PATH
var autosave := true
var bar_front := Vector3.ZERO
var talking := false
var warmed := false

static var _loaded_once := false

var _prompt: Label
var _status_dot: Label
var _hud: CanvasLayer
var _toast_left := 0.0

const SaveSystem := preload("res://src/systems/save/save_system.gd")


## Build everything. `scripted` = CI provider (no network, no sidecar).
func setup(town_demo, scripted = null) -> void:
	demo = town_demo
	var town = demo.town
	bar_front = town.marker_pos("bar_front")
	# Her body stands just behind the counter, facing the customers.
	var counter: Dictionary = town.get_box("bar_counter")
	var marker: Vector3 = town.marker_pos("bartender")
	var mats: LookMaterials = demo._flat_mats() if demo.has_method("_flat_mats") else LookMaterials.new()
	npc = BartenderNPC.new(mats)
	demo.add_child(npc)
	var stand_x := float(counter.min[0]) - 0.55 if not counter.is_empty() else marker.x
	npc.global_position = Vector3(stand_x, marker.y, marker.z)
	npc.rotation.y = atan2(bar_front.x - stand_x, 0.0)
	npc.look_at_target = demo._player
	if demo.use_look:
		var dressing := CantinaDressing.new()
		demo.add_child(dressing)
		dressing.dress(town, mats)
	# Brain.
	llm = LLMService.new()
	add_child(llm)
	var cfg := LLMConfig.new().load_all()
	llm.configure(cfg, scripted)
	if scripted == null:
		llm.start_sidecar()
	llm.status_changed.connect(_on_llm_status)
	if is_inside_tree():
		get_tree().create_timer(3.0).timeout.connect(_on_llm_status)
	brain = BartenderBrain.new(llm)
	brain.thinking.connect(_on_thinking)
	brain.line_delta.connect(_on_delta)
	brain.line_done.connect(_on_done)
	brain.job_offered.connect(func(j): panel.show_job(j))
	brain.drink_poured.connect(_on_drink)
	brain.ended.connect(func(reason): _end_soon(reason))
	_load_memory()
	# UI.
	panel = DialoguePanel.new()
	add_child(panel)
	panel.submitted.connect(_on_submit)
	panel.leave_requested.connect(end_talk)
	panel.job_answered.connect(_on_job_answer)
	overlay = LLMDebugOverlay.new()
	overlay.brain = brain
	overlay.llm = llm
	add_child(overlay)
	settings = LLMSettingsPanel.new()
	settings.llm = llm
	add_child(settings)
	_hud = CanvasLayer.new()
	_hud.layer = 5
	add_child(_hud)
	_prompt = _label(Control.PRESET_CENTER_BOTTOM, Vector2(-260, -140), 22, HORIZONTAL_ALIGNMENT_CENTER)
	_prompt.text = "[E]  Talk to " + str(brain.card.get("name", "the bartender"))
	_prompt.visible = false
	_status_dot = _label(Control.PRESET_TOP_RIGHT, Vector2(-760, 12), 14, HORIZONTAL_ALIGNMENT_RIGHT)
	_status_dot.offset_right = -16
	_status_dot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_dot.visible = false


func _label(preset: int, off: Vector2, size: int, align: int) -> Label:
	var l := Label.new()
	l.set_anchors_preset(preset)
	l.offset_left = off.x
	l.offset_top = off.y
	l.offset_right = off.x + 520 if align == HORIZONTAL_ALIGNMENT_CENTER else off.x + 288
	l.offset_bottom = off.y + 32
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	_hud.add_child(l)
	return l


func is_talking() -> bool:
	return talking


func player_in_range() -> bool:
	var p: Node3D = demo._player
	if p == null or not is_instance_valid(p):
		return false
	var d := Vector2(p.global_position.x - bar_front.x, p.global_position.z - bar_front.z).length()
	return d <= TALK_RADIUS and absf(p.global_position.y - bar_front.y) < 1.5


func _process(_dt: float) -> void:
	if brain == null:
		return
	brain.tick()
	if overlay.visible:
		overlay.refresh()
	if not talking:
		var near := player_in_range()
		_prompt.visible = near
		if near and not brain.serving():
			_prompt.text = "She's not serving you. Come back later."
		elif near:
			_prompt.text = "[E]  Talk to " + str(brain.card.get("name", "the bartender"))
		if near and brain.serving() and InputMap.has_action("interact") and Input.is_action_just_pressed("interact"):
			start_talk()
	if not warmed and llm.mode == "auto" and bool(llm.health.get("local", {}).get("up", false)):
		warmed = true
		brain.warm_up()
	if talking:
		var rep := llm.brain_report()
		_status_dot.visible = true
		_status_dot.text = rep.summary
		_status_dot.add_theme_color_override("font_color", Color(1.0, 0.75, 0.35) if not rep.any_up else Color(0.7, 0.68, 0.62))
	else:
		_status_dot.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F3:
		overlay.toggle()
	elif event.keycode == KEY_F10 and event.shift_pressed:
		var m := llm.cycle_mode()
		_toast("Bartender brain: " + m)
	elif event.keycode == KEY_F10:
		settings.toggle()


# ------------------------------------------------------------------ talking

func start_talk() -> void:
	if talking:
		return
	talking = true
	_prompt.visible = false
	var p: CharacterBody3D = demo._player
	p.locked = true
	if demo.player_kit != null:
		demo.player_kit.weapons.holder.request("")
		demo.player_kit.weapons.set_enabled(false)
	var rig = demo._rig
	if rig != null:
		rig.input_enabled = false
		rig.set_override(two_shot(), TWO_SHOT_FOV)
		# Face her.
		rig.rig.yaw = atan2(npc.global_position.x - p.global_position.x, npc.global_position.z - p.global_position.z)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var greeting := brain.begin_visit()
	panel.open(str(brain.card.get("name", "Bartender")), greeting)
	panel.set_mood(brain.rel.mood)
	panel.set_money(WorldState.credits, brain.rel.tab)
	npc.speak_pulse()


func end_talk() -> void:
	if not talking:
		return
	if settings.visible:
		settings.visible = false
		return
	talking = false
	brain.end_visit()
	panel.close()
	var p: CharacterBody3D = demo._player
	p.locked = false
	if demo.player_kit != null:
		demo.player_kit.weapons.set_enabled(true)
	var rig = demo._rig
	if rig != null:
		rig.input_enabled = true
		rig.clear_override()
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	npc.set_act(BartenderNPC.Act.IDLE)
	_save_memory()


## Over the player's shoulder, framing her in the top half of the screen (the
## conversation panel owns the bottom).
func two_shot() -> Transform3D:
	var her := npc.global_position + Vector3(0, 1.5, 0)
	var me: Vector3 = demo._player.global_position + Vector3(0, 1.62, 0)
	var to_her := Vector3(her.x - me.x, 0, her.z - me.z).normalized()
	var side := to_her.cross(Vector3.UP).normalized()
	var eye := me - to_her * 0.9 - side * 0.62 + Vector3(0, 0.05, 0)
	return Transform3D(Basis(), eye).looking_at(her + Vector3(0, -0.28, 0) - side * 0.1, Vector3.UP)


## Bots and tests talk through here (same path as the text field).
func player_says(text: String) -> bool:
	if not talking:
		return false
	return _on_submit(text)


func _on_submit(text: String) -> bool:
	if brain.busy:
		return false
	panel.commit_line()
	panel.add_player_line(text)
	panel.set_line("")
	panel.set_input_enabled(false)
	npc.set_act(BartenderNPC.Act.THINKING)
	return brain.say(text)


func _on_thinking(bark: String) -> void:
	panel.set_line(bark, true)
	npc.set_act(BartenderNPC.Act.THINKING)


func _on_delta(text: String) -> void:
	panel.set_line(text)
	npc.speak_pulse()


func _on_done(turn: Dictionary) -> void:
	panel.set_line(str(turn.say))
	panel.set_mood(brain.rel.mood + ("   (canned: no brain answered)" if str(turn.source) == "canned" else ""))
	panel.set_money(WorldState.credits, brain.rel.tab)
	panel.set_input_enabled(true)
	npc.speak_pulse()


func _on_drink(d: Dictionary) -> void:
	npc.set_act(BartenderNPC.Act.POURING, 1.4)
	panel.set_money(int(d.credits), int(d.tab))


func _on_job_answer(id: String, accepted: bool) -> void:
	if accepted and brain.accept_job(id):
		_toast("Job taken: " + str(WorldState.job(id).get("title", id)))


func _end_soon(_reason: String) -> void:
	var t := get_tree().create_timer(2.0) if is_inside_tree() else null
	if t != null:
		t.timeout.connect(end_talk)
	else:
		end_talk()


func _on_llm_status() -> void:
	if overlay != null:
		overlay.refresh()
	# Say why in the Godot output too, so a dumb bartender is never a mystery.
	var rep := llm.brain_report()
	var text := "Bartender brain: %s\n  %s" % [rep.summary, "\n  ".join(PackedStringArray(rep.lines))]
	if text != _last_report:
		_last_report = text
		print(text)


var _last_report := ""


func _toast(text: String) -> void:
	if demo.pads.size() > 0:
		demo.pads[0].toast(text, 2.5)


# ------------------------------------------------------------------ memory

func _load_memory() -> void:
	if not autosave:
		return
	if save.load_from(save_path):
		var r := save.get_relationship("bartender")
		if not r.is_empty():
			brain.rel.from_save(r)
		if not _loaded_once and not save.get_world().is_empty():
			var arrival := WorldState.to_save()     # keep what this session already did
			WorldState.from_save(save.get_world())
			for k in arrival.flags:
				WorldState.flags[k] = true
	else:
		save.new_game()
	_loaded_once = true


func _save_memory() -> void:
	if not autosave:
		return
	if save.data.is_empty():
		save.new_game()
	save.set_relationship("bartender", brain.rel.to_save())
	save.set_world(WorldState.to_save())
	save.data["credits"] = WorldState.credits
	save.save_to(save_path)


func _exit_tree() -> void:
	if brain != null:
		_save_memory()
