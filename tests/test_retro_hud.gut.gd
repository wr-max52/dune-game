extends GutTest
## Issue #52: the 80s HUD. RetroUI (the look), RetroSkin (puts it on everything,
## re-skins on a colour change) and RetroHud (banner, footer, F1 info screen).

var _was: Color


func before_all() -> void:
	RetroUI.load_settings()
	_was = RetroUI.accent


func after_all() -> void:
	RetroUI.accent = _was
	RetroUI.save_settings()


func test_text_bars() -> void:
	assert_eq(RetroUI.bar(0.5, 10), "[|||||.....]")
	assert_eq(RetroUI.bar(2.0, 4), "[||||]", "clamped")
	assert_eq(RetroUI.bar(-1.0, 4), "[....]")


func test_the_font_is_bundled() -> void:
	assert_true(ResourceLoader.exists("res://assets/fonts/AnonymousPro-Regular.ttf"))
	assert_true(FileAccess.file_exists("res://assets/fonts/OFL.txt"), "its licence ships with it")
	assert_ne(RetroUI.font(), ThemeDB.fallback_font)


func test_neutral_text_turns_phosphor_but_meaning_stays() -> void:
	RetroUI.accent = Color("#4dff88")
	var white := Label.new()
	white.add_theme_color_override("font_color", Color(0.97, 0.92, 0.82))
	var plain := Label.new()
	var red := Label.new()
	red.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
	for l in [white, plain, red]:
		RetroUI.skin(l)
	assert_eq(white.get_theme_color("font_color"), RetroUI.accent, "cream text -> phosphor")
	assert_eq(plain.get_theme_color("font_color"), RetroUI.accent)
	assert_eq(red.get_theme_color("font_color"), Color(1, 0.2, 0.2), "a warning keeps its red")
	RetroUI.accent = Color("#3fe0ff")
	RetroUI.skin(white)
	assert_eq(white.get_theme_color("font_color"), Color("#3fe0ff"), "re-skins to a new colour")
	for l in [white, plain, red]:
		l.free()


func test_panels_get_the_glowing_rim() -> void:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.set_content_margin_all(14)
	p.add_theme_stylebox_override("panel", sb)
	RetroUI.skin(p)
	var now := p.get_theme_stylebox("panel") as StyleBoxFlat
	assert_eq(now.border_color, RetroUI.accent)
	assert_eq(now.content_margin_left, 14.0, "keeps its padding")
	var clear := PanelContainer.new()
	clear.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	RetroUI.skin(clear)
	assert_true(clear.get_theme_stylebox("panel") is StyleBoxEmpty, "layout boxes stay invisible")
	p.free()
	clear.free()


func test_prompts_are_big() -> void:
	var l := Label.new()
	l.offset_left = -300
	l.offset_right = 300
	RetroUI.prompt(l)
	assert_eq(l.get_theme_font_size("font_size"), RetroUI.PROMPT_SIZE)
	assert_gte(RetroUI.PROMPT_SIZE, 32, "issue #52: interaction text is bigger")
	assert_eq(l.offset_left + l.offset_right, 0.0, "still centred")
	l.free()


func test_skin_follows_new_nodes_and_colour_changes() -> void:
	var skin := RetroSkin.new()
	add_child_autofree(skin)
	var layer := CanvasLayer.new()
	add_child_autofree(layer)
	var l := Label.new()
	layer.add_child(l)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(l.get_theme_font("font"), RetroUI.font(), "skinned as it appeared")
	skin.set_color(Color("#ff4fd8"))
	assert_eq(l.get_theme_color("font_color"), Color("#ff4fd8"))
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(RetroUI.SETTINGS_PATH), OK, "the favourite colour is saved")
	assert_eq(cfg.get_value("hud", "color"), Color("#ff4fd8"))


func test_banner_footer_and_info() -> void:
	WorldState.reset()
	WorldState.credits = 160
	var hud := RetroHud.new()
	add_child_autofree(hud)
	assert_true(hud._money.text.contains("CR 160"))
	assert_true(hud._clock.text.contains(":"), "a clock")
	assert_false(hud.info.visible)
	hud.toggle_info()
	assert_true(hud.info.visible)
	var t := hud._info_text.text
	for f in WorldState.FACTIONS:
		assert_true(t.contains(str(f).capitalize()), "standing with " + f)
	assert_true(t.contains("HOSTILE") or t.contains("UNFRIENDLY"), "the Remnant does not like you yet")
	assert_eq(RetroHud.standing_word(60), "ALLIED")
	assert_eq(RetroHud.standing_word(0), "NEUTRAL")
