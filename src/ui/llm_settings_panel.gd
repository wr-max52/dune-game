class_name LLMSettingsPanel
extends CanvasLayer
## F10 at the bar (M12): configure character AI and NPC voice, no restart.
## The cloud and ElevenLabs keys are stored in user://llm/keys.cfg and shown masked.
## "Test" sends a one-line LLM request; "Save" writes the settings.
##
## Issue #328: "AI characters" at the top turns the whole thing on or off (off on a
## fresh install) and is saved at once. Pasting a cloud key sets the cloud URL, type
## and model to that key's provider. Test works with AI off too, and says in plain
## words why a provider failed.

var llm: LLMService
var _panel: PanelContainer
var _mode: OptionButton
var _ai_on: CheckButton
var _fields: Dictionary = {}
var _cloud_type: OptionButton
var _cloud_on: CheckBox
var _key: LineEdit
var _key_now: Label
var _elevenlabs_key: LineEdit
var _elevenlabs_key_now: Label
var _speech_speed: SpinBox
var _result: Label
var _prompt_box: VBoxContainer
var _prompt_intro: Label
var _prompt_text: TextEdit
var _test_id := -1
var _voice_settings_saved := true
var _content: VBoxContainer
var host                          ## issue #80: the F11 panel this lives in (its "LLM" tab), or null
const MODES := ["auto", "local", "ollama", "cloud"]


func _ready() -> void:
	layer = 8
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -330
	_panel.offset_right = 330
	_panel.offset_top = -340
	_panel.offset_bottom = 340
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.06, 0.06, 0.96)
	sb.border_color = Color("#b08e50")
	sb.set_border_width_all(1)
	for side in ["left", "right", "top", "bottom"]:
		sb.set("content_margin_" + side, 14)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_panel.add_child(v)
	_content = v
	var title := Label.new()
	title.text = "AI and NPC voice settings"
	title.add_theme_font_size_override("font_size", 18)
	v.add_child(title)
	_ai_on = CheckButton.new()
	_ai_on.text = "AI characters (off: written lines and a topic menu)"
	_ai_on.toggled.connect(set_ai_enabled)
	v.add_child(_ai_on)
	_mode = OptionButton.new()
	for m in MODES:
		_mode.add_item(m)
	_mode.item_selected.connect(func(i): llm.set_mode(MODES[i]))
	v.add_child(_row("Mode", _mode))
	for f in [["local/base_url", "Local URL"], ["local/model", "Local model"], ["ollama/base_url", "Ollama URL"],
			["ollama/model", "Ollama model"], ["cloud/base_url", "Cloud URL"], ["cloud/model", "Cloud model"]]:
		var e := LineEdit.new()
		e.custom_minimum_size = Vector2(380, 0)
		_fields[f[0]] = e
		var row := _row(f[1], e)
		if (f[0] as String).ends_with("/model"):
			_add_help_buttons(row, (f[0] as String).get_slice("/", 0))
		v.add_child(row)
	_prompt_box = VBoxContainer.new()
	_prompt_box.visible = false
	v.add_child(_prompt_box)
	_prompt_intro = Label.new()
	_prompt_intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt_intro.custom_minimum_size = Vector2(600, 0)
	_prompt_box.add_child(_prompt_intro)
	_prompt_text = TextEdit.new()
	_prompt_text.editable = false
	_prompt_text.add_theme_color_override("font_readonly_color", Color(0.88, 0.85, 0.8))
	_prompt_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_prompt_text.custom_minimum_size = Vector2(600, 120)
	_prompt_box.add_child(_prompt_text)
	var pb := HBoxContainer.new()
	_prompt_box.add_child(pb)
	var copy := Button.new()
	copy.text = "Copy prompt"
	copy.pressed.connect(func(): _copy_prompt(_prompt_text.text))
	pb.add_child(copy)
	var hide_btn := Button.new()
	hide_btn.text = "Hide"
	hide_btn.pressed.connect(func(): _prompt_box.visible = false)
	pb.add_child(hide_btn)
	_cloud_type = OptionButton.new()
	_cloud_type.add_item("openai_compat")
	_cloud_type.add_item("anthropic")
	v.add_child(_row("Cloud type", _cloud_type))
	_cloud_on = CheckBox.new()
	_cloud_on.text = "Cloud enabled"
	v.add_child(_cloud_on)
	_key = LineEdit.new()
	_key.secret = true
	_key.placeholder_text = "paste a key to replace the stored one"
	_key.custom_minimum_size = Vector2(380, 0)
	v.add_child(_row("Cloud key", _key))
	_key_now = Label.new()
	v.add_child(_key_now)
	_elevenlabs_key = LineEdit.new()
	_elevenlabs_key.secret = true
	_elevenlabs_key.placeholder_text = "enter your ElevenLabs API key"
	_elevenlabs_key.custom_minimum_size = Vector2(380, 0)
	v.add_child(_row("ElevenLabs key", _elevenlabs_key))
	_elevenlabs_key_now = Label.new()
	v.add_child(_elevenlabs_key_now)
	_speech_speed = SpinBox.new()
	_speech_speed.min_value = 0.7
	_speech_speed.max_value = 1.2
	_speech_speed.step = 0.05
	_speech_speed.value = 1.0
	v.add_child(_row("NPC speech speed", _speech_speed))
	var h := HBoxContainer.new()
	v.add_child(h)
	for b in [["Test", _test], ["Save", _save], ["Close", _close]]:
		var btn := Button.new()
		btn.text = b[0]
		btn.pressed.connect(b[1])
		h.add_child(btn)
	_result = Label.new()
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result.custom_minimum_size = Vector2(600, 60)
	v.add_child(_result)
	visible = false


func _row(label: String, c: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(130, 0)
	h.add_child(l)
	h.add_child(c)
	return h


## Beside a provider's model: Link (its download page) and Prompt (set-up text for a
## coding agent, copied and shown).
func _add_help_buttons(h: HBoxContainer, id: String) -> void:
	var link := Button.new()
	link.text = "Link"
	link.tooltip_text = "Open " + LLMSetupHelp.link(id)
	link.pressed.connect(func(): OS.shell_open(LLMSetupHelp.link(id)))
	h.add_child(link)
	var prompt := Button.new()
	prompt.text = "Prompt"
	prompt.tooltip_text = "Copy a set-up prompt for a coding agent"
	prompt.pressed.connect(func(): show_prompt(id))
	h.add_child(prompt)


## Show the set-up prompt for `id` and put it on the clipboard.
func show_prompt(id: String) -> void:
	_prompt_intro.text = "%s: %s" % [str(LLMSetupHelp.provider(id).get("title", id)), LLMSetupHelp.intro()]
	_prompt_text.text = LLMSetupHelp.prompt(id)
	_prompt_box.visible = true
	_copy_prompt(_prompt_text.text)


func _copy_prompt(text: String) -> void:
	DisplayServer.clipboard_set(text)
	_result.text = "Prompt copied. " + LLMSetupHelp.intro()


func toggle() -> void:
	if host != null:
		host.open_tab("LLM")             # issue #80: one settings panel (F10 is a shortcut)
		_load()
		return
	visible = not visible
	if visible:
		_load()


## Issue #80: move this panel's controls into `parent` (the F11 panel's LLM tab).
## From then on F10 opens that tab and Close closes the settings.
func embed_into(parent: Control, settings_panel) -> void:
	if _content == null:
		return
	_content.get_parent().remove_child(_content)
	parent.add_child(_content)
	host = settings_panel
	visible = false
	_load()


func _close() -> void:
	if host != null:
		host.close()
	else:
		visible = false


## Issue #328: AI characters on or off, saved now (the town's host refreshes an
## open conversation's menu when it hears).
func set_ai_enabled(on: bool) -> void:
	if llm == null or llm.config == null or llm.ai_on() == on:
		return
	var bar := get_parent() as ConversationHost
	if bar != null:
		bar.set_ai_enabled(on)
	else:
		llm.set_ai_enabled(on)
		llm.config.save_user()
	_result.text = "AI characters on. Local models load in the background." if on else "AI characters off."


func _load() -> void:
	var cfg := llm.config
	_ai_on.set_pressed_no_signal(llm.ai_on())
	_mode.select(maxi(0, MODES.find(llm.mode)))
	for path in _fields:
		var p := (path as String).split("/")
		(_fields[path] as LineEdit).text = str(cfg.profile(p[0]).get(p[1], ""))
	_cloud_type.select(1 if str(cfg.profile("cloud").get("type", "")) == "anthropic" else 0)
	_cloud_on.button_pressed = bool(cfg.profile("cloud").get("enabled", false))
	_key_now.text = "stored key: " + LLMConfig.masked(cfg.api_key("cloud"))
	_elevenlabs_key_now.text = "stored locally: " + LLMConfig.masked(NpcVoice.api_key())
	_speech_speed.value = NpcVoice.speed()


func _apply() -> void:
	var cfg := llm.config
	_voice_settings_saved = true
	for path in _fields:
		cfg.set_value("profiles/" + path, (_fields[path] as LineEdit).text.strip_edges())
	cfg.set_value("profiles/cloud/type", _cloud_type.get_item_text(_cloud_type.selected))
	cfg.set_value("profiles/cloud/enabled", _cloud_on.button_pressed)
	if _key.text.strip_edges() != "":
		var key := _key.text.strip_edges()
		cfg.set_api_key("cloud", key)
		_key.text = ""
		# Issue #328: the key says which provider it is for.
		if cfg.apply_key_preset("cloud", key):
			for path in ["cloud/base_url", "cloud/model"]:
				(_fields[path] as LineEdit).text = str(cfg.profile("cloud").get(path.get_file(), ""))
			_cloud_type.select(1 if str(cfg.profile("cloud").get("type", "")) == "anthropic" else 0)
	if _elevenlabs_key.text.strip_edges() != "":
		_voice_settings_saved = NpcVoice.set_api_key(_elevenlabs_key.text.strip_edges())
		if _voice_settings_saved:
			_elevenlabs_key.text = ""
	var speed_saved := NpcVoice.set_speed(_speech_speed.value)
	_voice_settings_saved = _voice_settings_saved and speed_saved
	llm.configure(cfg)
	llm.set_mode(MODES[_mode.selected])
	_key_now.text = "stored key: " + LLMConfig.masked(cfg.api_key("cloud"))
	_elevenlabs_key_now.text = "stored locally: " + LLMConfig.masked(NpcVoice.api_key())


func _save() -> void:
	_apply()
	var llm_saved := llm.config.save_user()
	_result.text = "Saved." if llm_saved and _voice_settings_saved else "Could not save settings."


## Test: one real request down the chain (even with AI characters off).
func _test() -> void:
	_apply()
	_result.text = "Testing %s ..." % llm.mode
	if not llm.finished.is_connected(_on_test_done):
		llm.finished.connect(_on_test_done)
	_test_id = llm.chat([{ "role": "system", "content": "Reply with one short sentence." },
		{ "role": "user", "content": "Say that you are ready." }], { "max_tokens": 30, "force": true })


func _on_test_done(id: int, r: Dictionary) -> void:
	if id != _test_id:
		return
	_result.text = test_text(r, llm)


## Issue #328: a Test result in plain words: the provider that answered and its
## first words, or why each one failed.
static func test_text(r: Dictionary, service: LLMService) -> String:
	if bool(r.get("ok", false)):
		var fell := ""
		if not (r.get("fell_back_from", []) as Array).is_empty():
			fell = "\nSkipped: " + service.explain({ "fell_back_from": r.fell_back_from })
		return "OK via %s (%s): first word %d ms, total %d ms.\n%s%s" % [r.provider, r.model, int(r.ms_first_token), int(r.ms_total),
			str(r.text).substr(0, 160), fell]
	return "Failed. " + service.explain(r)
