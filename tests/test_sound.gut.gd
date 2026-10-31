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
	for id in cfg.club.playlists:
		for t in cfg.club.playlists[id]:
			out.append(t.stream)
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
	# Issue #104: the score and the club mix both go through the Music slider.
	for b in [Sound.SCORE_BUS, Sound.CLUB_BUS]:
		var i := AudioServer.get_bus_index(b)
		assert_gt(i, 0, b + " bus")
		assert_eq(str(AudioServer.get_bus_send(i)), Sound.MUSIC_BUS, b + " sends to Music")
	assert_true(AudioServer.get_bus_effect(AudioServer.get_bus_index(Sound.CLUB_BUS), 0) is AudioEffectLowPassFilter,
		"the club is muffled through the wall")


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


# ------------------------------------------------------------------ issue #104: the club

## A Sound with a test playlist made of the ambient tracks (the real playlists
## wait for the approved tracks), two tagged "hard".
func _club_sound() -> Sound:
	var s: Sound = add_child_autofree(Sound.new())
	var amb: Array = cfg.music.ambient
	s.cfg.club = cfg.club.duplicate(true)
	s.cfg.club.playlists = { "test": [
		{ "stream": amb[0], "moods": ["chill"] },
		{ "stream": amb[1], "moods": ["hard"] },
		{ "stream": amb[2], "moods": ["hard", "dark"] },
	] }
	s.music_on = true
	return s


func test_club_config() -> void:
	assert_eq(float(cfg.club.fade), 10.0, "songs blend over 10 s")
	assert_eq(float(cfg.club.hear), 40.0, "heard from 40 m out")
	for id in ["dust_lounge", "salvage_rave"]:
		assert_true(cfg.club.playlists.has(id), "playlist " + id)
		for t in cfg.club.playlists[id]:
			assert_false((t.get("moods", []) as Array).is_empty(), "mood tags on " + str(t.stream))
	for f in ["port_desert", "grit_station"]:
		var p: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/core/planets/%s.json" % f))
		assert_true(cfg.club.playlists.has(str(p.get("club", ""))), f + " names a playlist")


func test_club_distance() -> void:
	var r := Rect2(-90, -16, 40, 32)
	assert_eq(ClubMusic.distance(r, -70, 0), 0.0, "inside")
	assert_almost_eq(ClubMusic.distance(r, -30, 0), 20.0, 0.001, "20 m out the door side")
	assert_almost_eq(ClubMusic.near(20.0, 40.0), 0.5, 0.001)
	assert_eq(ClubMusic.near(50.0, 40.0), 0.0, "out of earshot")
	assert_eq(ClubMusic.near(0.0, 40.0), 1.0, "at the wall")


func test_club_level_by_where_you_are() -> void:
	var s := _club_sound()
	assert_eq(s.club_target(), 0.0, "no club")
	s.club = "test"
	s.club_near = 1.0
	assert_almost_eq(s.club_target(), float(cfg.club.outside), 0.001, "at the wall: part of it, muffled")
	s.club_inside = true
	assert_eq(s.club_target(), 1.0, "inside: all of it")
	s.in_space = true
	assert_eq(s.club_target(), 0.0, "not in space")


func test_club_plays_and_ducks_the_score() -> void:
	var s := _club_sound()
	s.club = "test"
	s.club_inside = true
	for i in 30:
		s._process(0.1)
	assert_true(s._club_deck.playing, "a song is on")
	assert_true(s.club_tracks("test").has(s.club_track), "from the playlist")
	assert_gt(s.club_level, 0.9, "faded in")
	var si := AudioServer.get_bus_index(Sound.SCORE_BUS)
	assert_lt(AudioServer.get_bus_volume_db(si), -20.0, "the score ducks under it")
	s.battle_left = 10.0
	s._process(0.1)
	assert_true(s._club_deck.playing, "gunfire does not cut the club")
	s.club = ""
	for i in 60:
		s._process(0.1)
	assert_eq(s.club_level, 0.0, "walked away")
	assert_false(s._club_deck.playing, "stopped, so the next visit starts a new song")
	assert_gt(AudioServer.get_bus_volume_db(si), -0.1, "the score is back")


func test_club_shuffles_without_repeats() -> void:
	var s := _club_sound()
	s.club = "test"
	var last := ""
	for i in 9:
		assert_true(s._club_next(), "next song")
		assert_ne(s.club_track, last, "not the same twice in a row")
		last = s.club_track


func test_oda_changes_the_vibe() -> void:
	var s := _club_sound()
	s.club = "test"
	for i in 5:
		assert_true(s.vibe("hard"))
		assert_true(str(s.club_track) in [cfg.music.ambient[1], cfg.music.ambient[2]], "a hard song")
	assert_true(s.vibe("polka"), "no such mood: any song")


func test_dead_band_stops_the_music() -> void:
	var s := _club_sound()
	s.club = "test"
	s.club_inside = true
	s._process(0.1)
	assert_true(s._club_deck.playing)
	s.club_live = false
	s._process(0.1)
	assert_eq(s._club_playing, "", "the music stops")
	assert_false(s._club_next(), "and nothing new starts")
