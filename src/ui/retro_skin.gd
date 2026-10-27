class_name RetroSkin
extends Node
## Issue #52: puts every on-screen Control in the town in the 80s HUD style
## (RetroUI.skin) as it appears, and re-skins them all when the player picks a
## new HUD colour. Popups (their own windows: menus, the colour picker) keep the
## engine look. Interaction prompts pulse gently so they read as live.

signal color_changed(c: Color)

static var current: RetroSkin        ## the one in the town (null in the CI greybox)

var _skinned: Array[WeakRef] = []
var _prompts: Array[WeakRef] = []    ## the pulsing "[E] ..." labels
var _t := 0.0


func _enter_tree() -> void:
	current = self
	RetroUI.load_settings()
	get_tree().node_added.connect(_on_added)


func _exit_tree() -> void:
	if current == self:
		current = null
	if get_tree().node_added.is_connected(_on_added):
		get_tree().node_added.disconnect(_on_added)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_walk(get_tree().root)


func _walk(n: Node) -> void:
	if n is Control:
		_on_added(n)
	for c in n.get_children():
		_walk(c)


## Wait a frame: whoever made the node sets its own colours and sizes right after
## add_child, and skin() reads them.
func _on_added(n: Node) -> void:
	if n is Control:
		_skin.call_deferred(n)


func _skin(c: Control) -> void:
	if not is_instance_valid(c) or not c.is_inside_tree() or c.get_window() != get_tree().root:
		return
	RetroUI.skin(c)
	_skinned.append(weakref(c))
	if c.has_meta("retro_prompt"):
		_prompts.append(weakref(c))


func set_color(c: Color) -> void:
	RetroUI.accent = c
	RetroUI.save_settings()
	var keep: Array[WeakRef] = []
	for w in _skinned:
		var n = w.get_ref()
		if n != null and is_instance_valid(n):
			RetroUI.skin(n)
			keep.append(w)
	_skinned = keep
	color_changed.emit(c)


func _process(dt: float) -> void:
	_t += dt
	var pulse := 0.82 + 0.18 * sin(_t * 4.0)
	for w in _prompts:
		var n = w.get_ref()
		if n != null and n.visible:
			n.self_modulate.a = pulse
