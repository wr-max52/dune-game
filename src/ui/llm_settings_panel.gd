class_name LLMSettingsPanel
extends CanvasLayer
## F10 at the bar (M12): configure character AI and NPC voice, no restart.
## The cloud and ElevenLabs keys are stored in user://llm/keys.cfg and shown masked.
## "Test" sends a one-line LLM request; "Save" writes the settings.

var llm: LLMService
var _panel: PanelContainer
var _mode: OptionButton
var _fields: Dictionary = {}
var _cloud_type: OptionButton
var _cloud_on: CheckBox
var _key: LineEdit
var _key_now: Label
var _elevenlabs_key: LineEdit
var _elevenlabs_key_now: Label
var _speech_speed: SpinBox
var _result: Label
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
		v.add_child(_row(f[1], e))
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


func _load() -> void:
	var cfg := llm.config
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
		cfg.set_api_key("cloud", _key.text.strip_edges())
		_key.text = ""
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


func _test() -> void:
	_apply()
	_result.text = "Testing %s ..." % llm.mode
	if not llm.finished.is_connected(_on_test_done):
		llm.finished.connect(_on_test_done)
	_test_id = llm.chat([{ "role": "system", "content": "Reply with one short sentence." },
		{ "role": "user", "content": "Say that you are ready." }], { "max_tokens": 30 })


func _on_test_done(id: int, r: Dictionary) -> void:
	if id != _test_id:
		return
	if bool(r.ok):
		_result.text = "OK via %s (%s): first token %d ms, total %d ms.\n%s" % [r.provider, r.model, r.ms_first_token, r.ms_total, str(r.text).substr(0, 160)]
	else:
		_result.text = "Failed: %s  %s" % [str(r.error), str(r.fell_back_from)]
