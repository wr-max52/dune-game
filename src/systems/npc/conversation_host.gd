class_name ConversationHost
extends Node
## Talking to the town's AI characters (M12; one host for all of them since #42).
## Owns what every conversation shares: the LLM service, the chat box, the debug
## (F3) and model settings (F10) panels, the "[E] Talk to ..." prompt and the save
## that holds what each character remembers. Each character is a TalkSpot (brain,
## body, where you stand): the Cantina Owner behind her counter, built here, and
## any others the town adds with add_spot() (Skrugs at his stall).
##
## Walk up to a spot: "[E] Talk to Oda Vell". Talking locks movement and weapons,
## frees the mouse, and moves the camera to a two-shot. Esc (or them ending it)
## walks you back out.
##
## town_demo.gd keeps this as `bar`; `brain`, `npc` and `bar_front` are still the
## Cantina Owner's, so code written for the one-character bar keeps working.

const TALK_RADIUS := 1.9
const TWO_SHOT_FOV := 34.0
const SAVE_PATH := "user://save.json"

var demo                              ## town_demo.gd
var llm: LLMService
var panel: DialoguePanel
var overlay: LLMDebugOverlay
var settings: LLMSettingsPanel
var save := SaveSystem.new()
var save_path := SAVE_PATH
var autosave := true
var spots: Array = []                 ## TalkSpot, the Cantina Owner first
var active: TalkSpot                  ## who the player is talking to (null when not)
var owner_spot: TalkSpot              ## the Cantina Owner's
var talking := false
var warmed := false
var reminders := 0                    ## issue #29: times the AI reminder was repeated (tests)

## The Cantina Owner's, for the code (and tests) written before #42.
var brain: NpcBrain:
	get: return owner_spot.brain if owner_spot != null else null
var npc: CantinaOwnerNPC:
	get: return owner_spot.body as CantinaOwnerNPC if owner_spot != null else null
var bar_front: Vector3:
	get: return owner_spot.stand if owner_spot != null else Vector3.ZERO

static var _loaded_once := false

var _prompt: Label
var _status_dot: Label
var _hud: CanvasLayer
var _scripted = null
var _loaded := false

const SaveSystem := preload("res://src/systems/save/save_system.gd")


## Build everything. `scripted` = CI provider (no network, no sidecar).
func setup(town_demo, scripted = null) -> void:
	demo = town_demo
	_scripted = scripted
	# The model service every character shares.
	llm = LLMService.new()
	add_child(llm)
	var cfg := LLMConfig.new().load_all()
	llm.configure(cfg, scripted)
	if scripted == null:
		llm.start_sidecar()
	llm.status_changed.connect(_on_llm_status)
	if is_inside_tree():
		get_tree().create_timer(3.0).timeout.connect(_on_llm_status)
	_load_save()
	# UI.
	panel = DialoguePanel.new()
	add_child(panel)
	panel.submitted.connect(_on_submit)
	panel.leave_requested.connect(end_talk)
	panel.job_answered.connect(_on_job_answer)
	overlay = LLMDebugOverlay.new()
	overlay.llm = llm
	add_child(overlay)
	settings = LLMSettingsPanel.new()
	settings.llm = llm
	add_child(settings)
	_hud = CanvasLayer.new()
	_hud.layer = 5
	add_child(_hud)
	_prompt = _label(Control.PRESET_CENTER_BOTTOM, Vector2(-260, -140), 22, HORIZONTAL_ALIGNMENT_CENTER)
	_prompt.visible = false
	RetroUI.prompt(_prompt)
	_status_dot = _label(Control.PRESET_TOP_RIGHT, Vector2(-760, 52), 14, HORIZONTAL_ALIGNMENT_RIGHT)
	_status_dot.offset_right = -16
	_status_dot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_dot.visible = false
	_build_cantina_owner()
	overlay.brain = owner_spot.brain


## The Cantina Owner: her body just behind the counter, facing the customers, and
## the bar front where you stand.
func _build_cantina_owner() -> void:
	var town = demo.town
	var front: Vector3 = town.marker_pos("bar_front")
	var counter: Dictionary = town.get_box("bar_counter")
	var marker: Vector3 = town.marker_pos("cantina_owner")
	var mats: LookMaterials = demo._flat_mats() if demo.has_method("_flat_mats") else LookMaterials.new()
	var body := CantinaOwnerNPC.new(mats)
	demo.add_child(body)
	var stand_x := float(counter.min[0]) - 0.55 if not counter.is_empty() else marker.x
	body.global_position = Vector3(stand_x, marker.y, marker.z)
	body.rotation.y = atan2(front.x - stand_x, 0.0)
	body.look_at_target = demo._player
	if demo.use_look:
		var dressing := CantinaDressing.new()
		demo.add_child(dressing)
		dressing.dress(town, mats)
		body.dressing = dressing
	var s := TalkSpot.new(NpcBrain.new(), body, front)
	s.radius = TALK_RADIUS
	add_spot(s)
	owner_spot = s


## Another character the player can talk to. Their brain shares this host's model
## service, and what they remember is loaded from (and saved to) the same save.
func add_spot(s: TalkSpot) -> void:
	spots.append(s)
	var b := s.brain
	if b.llm == null:
		b.attach(llm)
	b.thinking.connect(func(bark): _on_thinking(s, bark))
	b.line_delta.connect(func(text): _on_delta(s, text))
	b.line_done.connect(func(turn): _on_done(s, turn))
	b.job_offered.connect(func(j): _on_job(s, j))
	b.drink_poured.connect(func(d): _on_drink(s, d))
	b.ended.connect(func(reason): _end_soon(reason))
	var r := save.get_relationship(s.id())
	if not r.is_empty():
		b.rel.from_save(r)


func spot(id: String) -> TalkSpot:
	for s in spots:
		if s.id() == id:
			return s
	return null


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


## The spot the player is standing at (the nearest, if two overlap), or null.
func spot_in_range() -> TalkSpot:
	var p: Node3D = demo._player
	var best: TalkSpot = null
	for s in spots:
		if s.in_range(p) and (best == null or s.distance_to(p) < best.distance_to(p)):
			best = s
	return best


## At the bar front (the Cantina Owner's spot).
func player_in_range() -> bool:
	return owner_spot != null and owner_spot.in_range(demo._player)


func _process(_dt: float) -> void:
	if owner_spot == null:
		return
	for s in spots:
		s.brain.tick()
	if overlay.visible:
		overlay.refresh()
	if not talking:
		var s := spot_in_range()
		_prompt.visible = s != null
		if s != null and not s.brain.serving():
			_prompt.text = "%s won't talk to you. Come back later." % s.display_name()
		elif s != null:
			_prompt.text = "[E]  Talk to " + s.display_name()
		if s != null and s.brain.serving() and InputMap.has_action("interact") and Input.is_action_just_pressed("interact"):
			start_talk(s)
	if not warmed and llm.mode == "auto" and bool(llm.health.get("local", {}).get("up", false)):
		warmed = true
		owner_spot.brain.warm_up()
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
		_toast("AI brain: " + m)
	elif event.keycode == KEY_F10:
		settings.toggle()


# ------------------------------------------------------------------ talking

## Start talking to `s` (the Cantina Owner when null).
func start_talk(s: TalkSpot = null) -> void:
	if talking:
		return
	if s == null:
		s = owner_spot
	active = s
	talking = true
	overlay.brain = s.brain
	_prompt.visible = false
	var p: CharacterBody3D = demo._player
	p.locked = true
	if demo.player_kit != null:
		demo.player_kit.weapons.holder.request("")
		demo.player_kit.weapons.set_enabled(false)
	var rig = demo._rig
	if rig != null:
		rig.input_enabled = false
		rig.set_override(s.two_shot(p), TWO_SHOT_FOV)
		# Face them.
		rig.rig.yaw = atan2(s.body.global_position.x - p.global_position.x, s.body.global_position.z - p.global_position.z)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var greeting := s.brain.begin_visit()
	panel.open(s.display_name(), greeting)
	panel.set_notice(Disclaimers.talk_text(s.display_name()))   # issue #29
	panel.set_mood(s.brain.rel.mood)
	panel.set_money(WorldState.credits, s.brain.rel.tab)
	s.speak_pulse()


func end_talk() -> void:
	if not talking:
		return
	if settings.visible:
		settings.visible = false
		return
	var s := active
	talking = false
	active = null
	s.brain.end_visit()
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
	s.act("idle")
	_save_memory()


## The Cantina Owner's two-shot (kept for the review tools).
func two_shot() -> Transform3D:
	return owner_spot.two_shot(demo._player)


## Bots and tests talk through here (same path as the text field).
func player_says(text: String) -> bool:
	if not talking:
		return false
	return _on_submit(text)


func _on_submit(text: String) -> bool:
	var s := active
	if s == null or s.brain.busy:
		return false
	panel.commit_line()
	panel.add_player_line(text)
	if Disclaimers.triggered(text):
		# Issue #29: the reminder again, before their reply. The message still goes.
		panel.post_notice(Disclaimers.repeat_text(s.display_name()))
		reminders += 1
	panel.set_line("")
	panel.set_input_enabled(false)
	s.act("thinking")
	return s.brain.say(text)


func _on_thinking(s: TalkSpot, bark: String) -> void:
	if s != active:
		return
	panel.set_line(bark, true)
	s.act("thinking")


func _on_delta(s: TalkSpot, text: String) -> void:
	if s != active:
		return
	panel.set_line(text)
	s.speak_pulse()


func _on_done(s: TalkSpot, turn: Dictionary) -> void:
	if s != active:
		return
	panel.set_line(str(turn.say))
	panel.set_mood(s.brain.rel.mood + ("   (canned: no brain answered)" if str(turn.source) == "canned" else ""))
	panel.set_money(WorldState.credits, s.brain.rel.tab)
	panel.set_input_enabled(true)
	s.speak_pulse()


func _on_drink(s: TalkSpot, d: Dictionary) -> void:
	s.act("pouring", 1.4)
	if s.body != null and s.body.has_method("serve"):
		s.body.serve(d)
	if s == active:
		panel.set_money(int(d.credits), int(d.tab))


func _on_job(s: TalkSpot, j: Dictionary) -> void:
	if s == active:
		panel.show_job(j)


func _on_job_answer(id: String, accepted: bool) -> void:
	if accepted and active != null and active.brain.accept_job(id):
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
	# Say why in the Godot output too, so a canned character is never a mystery.
	var rep := llm.brain_report()
	var text := "AI brain: %s\n  %s" % [rep.summary, "\n  ".join(PackedStringArray(rep.lines))]
	if text != _last_report:
		_last_report = text
		print(text)


var _last_report := ""


func _toast(text: String) -> void:
	if demo.pads.size() > 0:
		demo.pads[0].toast(text, 2.5)


# ------------------------------------------------------------------ memory

## Read the save once: the world, and each character's relationship (applied as
## they are added).
func _load_save() -> void:
	if not autosave or _loaded:
		return
	_loaded = true
	if save.load_from(save_path):
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
	for s in spots:
		save.set_relationship(s.id(), s.brain.rel.to_save())
	save.set_world(WorldState.to_save())
	save.data["credits"] = WorldState.credits
	save.save_to(save_path)


func _exit_tree() -> void:
	if not spots.is_empty():
		_save_memory()
