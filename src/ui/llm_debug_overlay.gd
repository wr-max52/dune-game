class_name LLMDebugOverlay
extends CanvasLayer
## F3 at the bar (M12): what the last turn actually did. Provider, model, time to
## first token, total time, tokens, fallbacks, dropped actions and why, filter
## flags, trust, the raw reply, and a button that copies the full prompt.

var brain: NpcBrain
var llm: LLMService
var _panel: PanelContainer
var _text: RichTextLabel


func _ready() -> void:
	layer = 7
	_panel = PanelContainer.new()
	_panel.offset_left = 16
	_panel.offset_top = 16
	_panel.offset_right = 560
	_panel.offset_bottom = 520
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.78)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	var v := VBoxContainer.new()
	_panel.add_child(v)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.custom_minimum_size = Vector2(520, 440)
	_text.add_theme_font_size_override("normal_font_size", 12)
	v.add_child(_text)
	var b := Button.new()
	b.text = "Copy prompt"
	b.pressed.connect(func():
		if brain != null:
			DisplayServer.clipboard_set(JSON.stringify(brain.last_turn.get("prompt", []), "  ")))
	v.add_child(b)
	visible = false


func toggle() -> void:
	visible = not visible
	refresh()


func refresh() -> void:
	if not visible or brain == null:
		return
	var t: Dictionary = brain.last_turn
	var L: PackedStringArray = []
	L.append("[b]mode[/b] %s   [b]trust[/b] %d (%s)   [b]mood[/b] %s" % [llm.mode if llm else "-", brain.rel.trust, brain.rel.tier(), brain.rel.mood])
	if llm != null:
		var rep := llm.brain_report()
		L.append("[b]brain[/b] " + str(rep.summary))
		for line in rep.lines:
			L.append("   " + str(line))
		if llm.sidecar != null and not llm.sidecar.log_tail.is_empty():
			L.append("[b]llama-server log[/b] " + str(llm.sidecar.log_tail[llm.sidecar.log_tail.size() - 1]).replace("[", "("))
		var st := llm.status()
		var ps: PackedStringArray = []
		for id in st:
			var s: Dictionary = st[id]
			ps.append("%s:%s%s%s" % [id, "up" if s.up else "DOWN", "" if s.usable else "(off)", " OPEN" if s.circuit_open else ""])
		L.append("[b]providers[/b] " + "  ".join(ps))
	if t.is_empty():
		L.append("(no turn yet)")
	else:
		L.append("[b]source[/b] %s   [b]provider[/b] %s   [b]model[/b] %s" % [t.source, t.provider, t.model])
		L.append("[b]first token[/b] %d ms   [b]total[/b] %d ms   [b]tokens[/b] %s" % [t.ms_first_token, t.ms_total, str(t.usage)])
		if not (t.fell_back_from as Array).is_empty():
			L.append("[b]fallbacks[/b] " + str(t.fell_back_from))
		L.append("[b]kept[/b] " + str(t.kept))
		if not (t.dropped as Array).is_empty():
			L.append("[color=#ff9070][b]dropped[/b] " + str(t.dropped) + "[/color]")
		if not (t.filter as Array).is_empty():
			L.append("[color=#ffd070][b]filter[/b] " + str(t.filter) + "[/color]")
		L.append("[b]raw[/b] " + str(t.raw).substr(0, 900).replace("[", "("))
	_text.text = "\n".join(L)
