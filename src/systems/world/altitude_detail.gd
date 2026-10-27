class_name AltitudeDetail
extends Node
## Less detail the higher you fly (issue #46). The town is lit for standing in it:
## real-time GI (SDFGI), SSAO, SSIL, volumetric fog, four shadow splits, lamps,
## people and hundreds of boulders. From a ship climbing at 300 m/s none of that
## reads, and SDFGI rebuilds its cascades every time the camera moves that fast,
## which is what made flying laggy. Each tier switches render features off and
## hides groups of nodes once you are above it, and gives them back on the way
## down (`hysteresis` metres lower, so hovering at a boundary never flickers).
##
## Tiers are data: the "detail" block of content/core/worlds/<id>.json.
##   off:  LookEnvironment features ("sdfgi", "ssil", "ssao", "volumetric", "shadows")
##   hide: node groups this scene registers with add_group() ("people", "props")
## A hidden group's nodes also stop processing (NPC brains, the bar), so the
## CPU gets the same break as the GPU. Pure tier maths in tier_for(), for tests.

var tiers: Array = []                ## [{ above, off: [], hide: [] }], ascending
var hysteresis := 60.0
var look: LookEnvironment
var groups := {}                     ## name -> [Node]
var tier := -1                       ## index of the highest tier in force, -1 = full detail
var changes := 0                     ## tier changes so far (tests, traces)


func _init() -> void:
	name = "AltitudeDetail"


func setup(cfg: Dictionary, look_env: LookEnvironment = null) -> void:
	look = look_env
	hysteresis = float(cfg.get("hysteresis", hysteresis))
	tiers = []
	for t in cfg.get("tiers", []):
		tiers.append({ "above": float(t.get("above", 0.0)), "off": t.get("off", []), "hide": t.get("hide", []) })
	tiers.sort_custom(func(a, b): return a.above < b.above)


## Nodes that `hide` can switch off as one (nulls are skipped).
func add_group(group: String, nodes: Array) -> void:
	var list: Array = groups.get(group, [])
	for n in nodes:
		if n != null:
			list.append(n)
	groups[group] = list


## The tier for `altitude`, coming from tier `current`: climbing past a tier's
## `above` enters it, and you only leave it `hysteresis` metres below that.
func tier_for(altitude: float, current: int) -> int:
	var t := -1
	for i in tiers.size():
		var edge: float = tiers[i].above - (hysteresis if i <= current else 0.0)
		if altitude >= edge:
			t = i
	return t


## Call every frame with the viewer's altitude above sea level.
func update_for(altitude: float) -> void:
	var t := tier_for(altitude, tier)
	if t == tier:
		return
	tier = t
	changes += 1
	_apply()


## Everything off at or below the current tier, everything else back on.
func _apply() -> void:
	var off: Array = []
	var hidden := {}
	for i in tier + 1:
		off.append_array(tiers[i].off)
		for g in tiers[i].hide:
			hidden[str(g)] = true
	if look != null:
		look.set_suppressed(off)
	for g in groups:
		var show := not hidden.has(g)
		for n in groups[g]:
			if not is_instance_valid(n):
				continue
			if n is Node3D or n is CanvasItem:
				n.visible = show
			n.process_mode = Node.PROCESS_MODE_INHERIT if show else Node.PROCESS_MODE_DISABLED


## What is held off right now (for the HUD, tests and traces).
func suppressed() -> Array:
	return look.suppressed.keys() if look != null else []


func hidden_groups() -> Array:
	var out: Array = []
	for i in tier + 1:
		for g in tiers[i].hide:
			if not out.has(g):
				out.append(g)
	return out
