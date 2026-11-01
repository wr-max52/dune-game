class_name QuestBanner
extends Control
## The quest banner (QuestNews): a headline in big amber capitals across the
## upper middle of the screen ("CARGO FOUND"), what it was about under it, and
## for a new quest the key to see it. It plays the news's sound as it comes up,
## holds for HOLD seconds and fades; news that came in meanwhile follows, one at
## a time. Under the arrival titles' line, over the world, never takes the mouse.

const AMBER := Color("#e0a050")
const INK := Color(0.95, 0.92, 0.85, 0.95)
const BAND := Color(0.05, 0.04, 0.03, 0.55)
const Y := 0.24                        ## the band's centre, as a share of the screen's height
const IN := 0.18                       ## seconds to come up
const HOLD := 2.6                      ## seconds fully up
const OUT := 0.45                      ## seconds to fade
const GAP := 0.2                       ## seconds between two banners
const MIN_W := 520.0

var band: PanelContainer
var head: Label
var sub: Label
var hint: Label
var showing: Dictionary = {}           ## the news up now, {} when none
var _t := 0.0                          ## seconds since it came up
var _wait := 0.0


func _init() -> void:
	name = "QuestBanner"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	band = PanelContainer.new()
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = BAND
	sb.border_color = Color(AMBER, 0.8)
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.content_margin_left = 48
	sb.content_margin_right = 48
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	band.add_theme_stylebox_override("panel", sb)
	band.custom_minimum_size = Vector2(MIN_W, 0)
	add_child(band)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	band.add_child(box)
	head = _label(40, AMBER, 7)
	sub = _label(20, INK, 5)
	hint = _label(15, Color(INK, 0.75), 4)
	box.add_child(head)
	box.add_child(sub)
	box.add_child(hint)
	band.modulate.a = 0.0
	band.visible = false


func _label(size: int, color: Color, outline: int) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", outline)
	return l


func _process(dt: float) -> void:
	if showing.is_empty():
		_wait -= dt
		if _wait <= 0.0:
			show_news(QuestNews.take())
		return
	_t += dt
	var a := 1.0
	if _t < IN:
		a = _t / IN
	elif _t > IN + HOLD:
		a = 1.0 - (_t - IN - HOLD) / OUT
	band.modulate.a = clampf(a, 0.0, 1.0)
	var s := lerpf(1.12, 1.0, clampf(_t / IN, 0.0, 1.0))   # a small punch in
	band.scale = Vector2(s, s)
	if _t >= IN + HOLD + OUT:
		showing = {}
		band.visible = false
		_wait = GAP


## Put `news` (a QuestNews entry) up now, with its sound. {} does nothing.
func show_news(news: Dictionary) -> void:
	if news.is_empty():
		return
	showing = news
	_t = 0.0
	head.text = str(news.head).to_upper()
	sub.text = str(news.sub)
	sub.visible = sub.text != ""
	hint.text = str(news.get("hint", ""))
	hint.visible = hint.text != ""
	band.visible = true
	band.modulate.a = 0.0
	band.reset_size()
	_place()
	if str(news.get("sound", "")) != "":
		Sound.play(str(news.sound))


func _place() -> void:
	var view := get_viewport_rect().size
	var sz := band.get_combined_minimum_size()
	band.size = sz
	band.position = Vector2((view.x - sz.x) * 0.5, view.y * Y - sz.y * 0.5)
	band.pivot_offset = sz * 0.5
