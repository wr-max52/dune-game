class_name Sound
extends Node
## The sound library and the music (issue #16). Data: content/look/sound.json.
##
## Systems ask for a sound by key and say nothing else:
##   Sound.play("ship_hit", point)      one-shot; 3D at `point`, 2D without one
##   Sound.loop("jet_loop", self)       a looping player on `self`; the caller
##                                      plays, stops and pitches it
##   Sound.battle()                     an NPC just fired at the player
##   Sound.set_space(true)              a fight in orbit started
##
## The music is three ambient tracks that cycle with cross-fades, a battle track
## (from 30 s in) while NPCs are shooting at you and for `battle_hold` seconds
## after, and a space track during a fight in orbit (not for being up there:
## nothing marks where space starts). Space beats battle beats
## ambient. Credits going up or down make a coin sound wherever they changed.
##
## Static and lazy, like GameFlow and WorldState (no autoload): the first call
## puts one node under the tree root, where it outlives scene changes, so the
## music does not restart when you launch or land. Two buses, Music and SFX
## (default_bus_layout.tres), set in the settings panel and saved per machine.

const DATA := "res://content/look/sound.json"
const SETTINGS_PATH := "user://settings/sound.cfg"
const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"
const SILENT_DB := -60.0

static var _lib: Sound

var cfg: Dictionary
var mode := ""                 ## what the music plays: "", "ambient", "battle", "space"
var in_space := false
var battle_left := 0.0
var ambient_index := -1
var music_on := false
var one_shots := 0
var _streams: Dictionary = {}  ## path -> AudioStream
var _deck: AudioStreamPlayer   ## the track playing now
var _spare: AudioStreamPlayer  ## the last one, fading out
var _tw: Tween
var _credits := -1
var _carried: Dictionary = {}  ## key -> AudioStreamPlayer (carried_loop)


# ------------------------------------------------------------------ the calls

static func lib() -> Sound:
	if is_instance_valid(_lib):
		return _lib
	_lib = Sound.new()
	_lib.name = "Sound"
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		# Deferred: the first call often comes from a scene's _ready, while the
		# root is still busy adding that scene.
		tree.root.add_child.call_deferred(_lib)
	return _lib


## A one-shot. 3D at `at` (falls off with distance), 2D when `at` is INF.
## Returns the player, or null when the key is unknown or too many are playing.
static func play(key: String, at: Vector3 = Vector3.INF) -> Node:
	var s := lib()
	var c: Dictionary = s.cfg.get("sfx", {}).get(key, {})
	var stream := s._pick(c)
	if stream == null or s.one_shots >= int(s.cfg.get("max_one_shots", 24)):
		return null
	var p := s._player(c, at != Vector3.INF)
	p.stream = stream
	p.autoplay = true            # plays once it is in the tree, even if that is next frame
	if at != Vector3.INF:
		(p as AudioStreamPlayer3D).position = at
	s.one_shots += 1
	p.finished.connect(func():
		s.one_shots -= 1
		p.queue_free())
	s.add_child(p)
	return p


## A looping player on `parent`: 3D when the parent is a Node3D (unless `spatial`
## is false: the sound of your own ship), 2D otherwise. Not playing yet. Null when
## the key is unknown.
static func loop(key: String, parent: Node, spatial := true) -> Node:
	var s := lib()
	var c: Dictionary = s.cfg.get("sfx", {}).get(key, {})
	var stream := s._pick(c)
	if stream == null:
		return null
	var p := s._player(c, spatial and parent is Node3D)
	p.stream = _looping(stream, 0.0)
	parent.add_child(p)
	return p


## A looping 2D player that lives under Sound, not in a scene, so it plays on
## across a scene change (the ship's drone over a no-fade handoff). One per key;
## the scene starts and stops it. Null when the key is unknown.
static func carried_loop(key: String) -> AudioStreamPlayer:
	var s := lib()
	var p: AudioStreamPlayer = s._carried.get(key)
	if p != null and is_instance_valid(p):
		return p
	p = loop(key, s, false) as AudioStreamPlayer
	if p != null:
		s._carried[key] = p
	return p


## An NPC fired at the player: battle music, and it holds a while after.
static func battle() -> void:
	var s := lib()
	s.battle_left = float(s.cfg.get("music", {}).get("battle_hold", 15.0))


static func set_space(on: bool) -> void:
	lib().in_space = on


## Start the music if it is not already going (each playable scene calls this).
static func start_music() -> void:
	lib().music_on = true


## A bus's volume as 0..1 (the settings sliders).
static func volume(bus: String) -> float:
	var i := AudioServer.get_bus_index(bus)
	return db_to_linear(AudioServer.get_bus_volume_db(i)) if i >= 0 else 1.0


static func set_volume(bus: String, linear: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return
	linear = clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(i, linear <= 0.001)
	DirAccess.make_dir_recursive_absolute(SETTINGS_PATH.get_base_dir())
	var f := ConfigFile.new()
	f.load(SETTINGS_PATH)
	f.set_value("volume", bus, linear)
	f.save(SETTINGS_PATH)


# ------------------------------------------------------------------ the node

func _init() -> void:
	var t := FileAccess.get_file_as_string(DATA)
	var d = JSON.parse_string(t) if t != "" else null
	cfg = d if d is Dictionary else {}
	var f := ConfigFile.new()
	if f.load(SETTINGS_PATH) == OK:
		for bus in [MUSIC_BUS, SFX_BUS]:
			var i := AudioServer.get_bus_index(bus)
			if i >= 0 and f.has_section_key("volume", bus):
				var v := float(f.get_value("volume", bus))
				AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
				AudioServer.set_bus_mute(i, v <= 0.001)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_deck = _music_player()
	_spare = _music_player()


func _process(dt: float) -> void:
	battle_left = maxf(0.0, battle_left - dt)
	_watch_credits()
	if not music_on:
		return
	var want := want_mode()
	if want != mode:
		_switch(want)
	elif mode == "ambient" and _deck.playing and _deck.stream != null:
		# Near the end of an ambient track: cross-fade into the next one.
		if _deck.get_playback_position() >= _deck.stream.get_length() - _fade():
			_switch("ambient")
	elif not _deck.playing:
		_switch(mode)


## What the music should be playing right now.
func want_mode() -> String:
	if in_space:
		return "space"
	if battle_left > 0.0:
		return "battle"
	return "ambient"


func _switch(to: String) -> void:
	var m: Dictionary = cfg.get("music", {})
	var path := ""
	var start := 0.0
	var fade_in := _fade()
	var fade_out := _fade()
	# Issue #80: into and out of a fight the music cuts over at once (a slow
	# cross-fade lagged behind the gunfire); ambient tracks still blend.
	if to == "battle" or mode == "battle":
		fade_in = float(m.get("battle_cut", 0.25))
		fade_out = float(m.get("battle_cut", 0.25))
	match to:
		"ambient":
			var list: Array = m.get("ambient", [])
			if list.is_empty():
				mode = to
				return
			ambient_index = (ambient_index + 1) % list.size()
			path = str(list[ambient_index])
		"battle", "space":
			var c: Dictionary = m.get(to, {})
			path = str(c.get("stream", ""))
			start = float(c.get("start", 0.0))
			if to == "battle":
				fade_in = float(m.get("battle_fade_in", 0.05))
	mode = to
	var stream := _load(path)
	if stream == null:
		return
	if to != "ambient":
		stream = _looping(stream, start)
	# Swap decks: the old track fades out while the new one fades in.
	var old := _deck
	_deck = _spare
	_spare = old
	if _tw != null:
		_tw.kill()
	_deck.stream = stream
	_deck.volume_db = SILENT_DB
	_deck.play(start)
	_tw = create_tween().set_parallel(true)
	_tw.tween_property(_deck, "volume_db", float(m.get("volume_db", -12.0)), fade_in)
	if old.playing:
		_tw.tween_property(old, "volume_db", SILENT_DB, fade_out)
		_tw.chain().tween_callback(old.stop)


func _watch_credits() -> void:
	var now: int = WorldState.credits
	if _credits >= 0 and now != _credits:
		Sound.play("coin_gain" if now > _credits else "coin_spend")
	_credits = now


func _fade() -> float:
	return float(cfg.get("music", {}).get("fade", 4.0))


func _music_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = MUSIC_BUS
	p.volume_db = SILENT_DB
	add_child(p)
	return p


func _player(c: Dictionary, spatial: bool) -> Node:
	var p: Node
	if spatial:
		var p3 := AudioStreamPlayer3D.new()
		p3.unit_size = float(c.get("unit_size", 10.0))
		p3.max_distance = float(c.get("max_distance", 0.0))
		p = p3
	else:
		p = AudioStreamPlayer.new()
	p.bus = SFX_BUS
	p.volume_db = float(c.get("volume_db", 0.0))
	var pr: Array = c.get("pitch", [])
	if pr.size() == 2:
		p.pitch_scale = randf_range(float(pr[0]), float(pr[1]))
	return p


## One of the entry's streams (a list picks at random).
func _pick(c: Dictionary) -> AudioStream:
	var s = c.get("stream", "")
	if s is Array:
		s = s[randi() % s.size()] if not s.is_empty() else ""
	return _load(str(s))


func _load(path: String) -> AudioStream:
	if path == "":
		return null
	if not _streams.has(path):
		_streams[path] = load(path) if ResourceLoader.exists(path) else null
	return _streams[path]


## A looping copy of `stream` that comes back round to `from` seconds.
static func _looping(stream: AudioStream, from: float) -> AudioStream:
	var s: AudioStream = stream.duplicate()
	if s is AudioStreamWAV:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = int(from * s.mix_rate)
		s.loop_end = int(s.get_length() * s.mix_rate)
	elif s is AudioStreamMP3 or s is AudioStreamOggVorbis:
		s.loop = true
		s.loop_offset = from
	return s
