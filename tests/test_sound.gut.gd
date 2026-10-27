extends GutTest
## Issue #16: the sound library and the music. Every sound and track the library
## names must exist and load; the music picks space over battle over ambient,
## battle starts 30 s in and loops back there, and credits make coin noises.

const DATA := "res://content/look/sound.json"
var cfg: Dictionary


func before_all() -> void:
	cfg = JSON.parse_string(FileAccess.get_file_as_string(DATA))


func _paths() -> Array:
	var out: Array = []
	for k in cfg.sfx:
		var s = cfg.sfx[k].stream
		out.append_array(s if s is Array else [s])
	out.append_array(cfg.music.ambient)
	out.append(cfg.music.battle.stream)
	out.append(cfg.music.space.stream)
	return out


func test_every_sound_and_track_loads() -> void:
	for p in _paths():
		assert_true(ResourceLoader.exists(str(p)), "exists: " + str(p))
		assert_true(load(str(p)) is AudioStream, "loads: " + str(p))


func test_the_issue_asks_for_these_sounds() -> void:
	for k in ["coin_gain", "coin_spend", "jet_loop", "ship_engine", "ship_laser", "droid_beep", "droid_hum"]:
		assert_true(cfg.sfx.has(k), "sfx key: " + k)
	assert_gt(cfg.music.ambient.size(), 1, "more than one ambient track to cycle")
	assert_eq(float(cfg.music.battle.start), 30.0, "battle starts 30 s in")


func test_buses_exist() -> void:
	assert_gt(AudioServer.get_bus_index(Sound.MUSIC_BUS), 0, "Music bus")
	assert_gt(AudioServer.get_bus_index(Sound.SFX_BUS), 0, "SFX bus")


func test_music_priority() -> void:
	var s: Sound = autofree(Sound.new())
	assert_eq(s.want_mode(), "ambient")
	s.battle_left = 5.0
	assert_eq(s.want_mode(), "battle", "NPCs shooting")
	s.in_space = true
	assert_eq(s.want_mode(), "space", "space wins")
	s.in_space = false
	s.battle_left = 0.0
	assert_eq(s.want_mode(), "ambient", "back to ambient")


func test_battle_holds_then_lets_go() -> void:
	var s: Sound = add_child_autofree(Sound.new())
	s.battle_left = float(cfg.music.battle_hold)
	s._process(float(cfg.music.battle_hold) - 1.0)
	assert_eq(s.want_mode(), "battle", "still holding")
	s._process(2.0)
	assert_eq(s.want_mode(), "ambient", "quiet long enough")


func test_battle_plays_from_30s_and_loops_there() -> void:
	var s: Sound = add_child_autofree(Sound.new())
	s._switch("battle")
	assert_eq(s.mode, "battle")
	var st = s._deck.stream
	assert_true(st is AudioStreamMP3, "battle track")
	assert_true(st.loop, "loops")
	assert_eq(st.loop_offset, 30.0, "loops back to 30 s")
	assert_true(s._deck.playing, "playing")


func test_ambient_cycles() -> void:
	var s: Sound = add_child_autofree(Sound.new())
	var seen := {}
	for i in cfg.music.ambient.size():
		s._switch("ambient")
		seen[s._deck.stream.resource_path] = true
	assert_eq(seen.size(), cfg.music.ambient.size(), "each ambient track in turn")


func test_credits_make_coin_noises() -> void:
	var s := Sound.lib()
	var before := s.one_shots
	var had := WorldState.credits
	s._credits = had
	WorldState.credits = had + 25
	s._watch_credits()
	assert_eq(s.one_shots, before + 1, "a coin sound for credits in")
	WorldState.credits = had
	s._watch_credits()
	assert_eq(s.one_shots, before + 2, "and one for credits out")


func test_blade_is_quieter() -> void:
	var look: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/look/hand_weapons.json"))
	assert_lt(float(look.blade_volume.db), -6.0, "blade one-shots under the old -6 dB")
	assert_lt(float(look.blade_volume.hum_db), -16.0, "hum under the old -16 dB")
