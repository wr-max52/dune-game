class_name HitFeedback
extends Node
## Hit markers and the thud (issue #65, package C). PlayerWeapons forwards every
## hit_something here. We decide whether the thing actually took damage (a bolt's
## on_hit also fires for walls and the ground), whether the hit killed it, then pop
## the marker and play the thud.
##
## "Took damage" is read from the target afterwards, because the hit has already
## landed by the time the signal fires: bodies stamp `damage_usec` (the clock time
## of their last accepted hit) and we check it is fresh. That way
## ignored friendly fire and hits on the dead show nothing. Ship hulls stamp it too
## (issue #181). Things with no stamp (droids) count if they have apply_damage at all.

const THUD := "res://assets/audio/hud/hit_thud.wav"
const KILL := "res://assets/audio/hud/hit_kill.wav"
## A hit stamp older than this is not the hit that just landed (the signal fires in
## the same call that dealt the damage, so the real gap is microseconds).
const FRESH_USEC := 20000
const MIN_GAP_MS := 50          ## a rifle burst must not stack into noise

enum Result { NONE, HIT, KILL }

var marker: HitMarker
var world_markers_shown := 0    ## markers pinned where a hit landed (seekers, mark_at)
var _hud: CanvasLayer
var hit_markers_shown := 0
var kill_markers_shown := 0
var thuds_played := 0           ## thuds that actually started (after the rate limit)
var _last_thud_ms := -1000000
var _thud: AudioStreamPlayer
var _kill: AudioStreamPlayer


## Put the marker on `hud` (its own child, so it ignores the crosshair's visibility).
func setup(hud: CanvasLayer) -> void:
	name = "HitFeedback"
	_hud = hud
	marker = HitMarker.new()
	hud.add_child(marker)
	_thud = _player(THUD, -4.0)
	_kill = _player(KILL, -1.0)


func _player(path: String, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	if ResourceLoader.exists(path):
		p.stream = load(path)
	p.volume_db = db
	p.max_polyphony = 2
	p.bus = Sound.SFX_BUS
	add_child(p)
	return p


## Whether `target` took damage from the hit that just landed, and died of it.
static func classify(target: Object) -> int:
	if target == null or not is_instance_valid(target):
		return Result.NONE
	var t: Object = target
	if not t.has_method("apply_damage") and not t.has_method("apply_damage_from"):
		var parent = (t as Node).get_parent() if t is Node else null
		if parent == null or not parent.has_method("apply_damage"):
			return Result.NONE
		t = parent
	var stamp = t.get("damage_usec")
	if stamp != null and Time.get_ticks_usec() - int(stamp) > FRESH_USEC:
		return Result.NONE
	if t.get("dead") == true or t.get("is_down") == true:
		return Result.KILL
	return Result.HIT


## Connected to PlayerWeapons.hit_something.
func on_hit(target: Object, _damage: float = 0.0) -> void:
	var r := classify(target)
	if r == Result.NONE:
		return
	confirm(r == Result.KILL)


## Issue #181: a hit the caller already knows landed (the space fight's director
## reports its own hits and kills), shown the same way.
func confirm(kill: bool) -> void:
	marker.show_hit(kill)
	if kill:
		kill_markers_shown += 1
	else:
		hit_markers_shown += 1
	_play_thud(kill)


## A seeker's hit lands far from the crosshair: pin a marker on `at` (world space)
## as well, held long enough to find. Silent; the hit's own confirm() makes the thud.
func mark_at(at: Vector3, kill: bool) -> void:
	if _hud == null:
		return
	var m := HitMarker.new()
	m.world_point = at
	m.life = 0.7
	_hud.add_child(m)
	m.show_hit(kill)
	world_markers_shown += 1
	get_tree().create_timer(m.life + 0.1, false).timeout.connect(m.queue_free)


func _play_thud(kill: bool) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_thud_ms < MIN_GAP_MS and not kill:   # a kill's heavier thud always lands
		return
	_last_thud_ms = now
	thuds_played += 1
	var p := _kill if kill else _thud
	if p.stream != null and p.is_inside_tree():
		p.pitch_scale = randf_range(0.93, 1.07)
		p.play()
