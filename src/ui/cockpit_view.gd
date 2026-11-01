class_name CockpitView
extends Control
## The cockpit view (issue #181): V in a ship, the same cockpit for every ship.
## Most of the view is the canopy, glass with a faint tint; its frame (two struts
## and a bow across the top) comes back over your head, and
## a dashboard runs across the bottom, its instruments working from the same values
## the chase view's HUD gets (CockpitDash paints it).
##
## Drawn flat over the camera, not modelled: the cockpit camera is locked to the
## ship (ChaseCamera.COCKPIT), so a painted frame stays put exactly as a modelled
## one would, costs no geometry, and fits any ship. FlightHud hands it `values`
## (show_values) and redraws it.
##
## The dash leans away from you: CockpitDash paints it flat into a SubViewport and
## a perspective shader (cockpit_tilt.gdshader) draws that back behind this, so its
## far edge shrinks toward the middle, the dials go oval and the plates' sides lean
## in. A yoke stands in front, below the dash's top so the view stays open, and
## follows the stick: it turns with roll (and yaw, which the mouse drives), and
## comes back toward you as you pull up.
##
## The glass catches the light: the sun and any bolt going by (gather_lights) glint
## on the dials and along the dash's edge, and glow faintly on the canopy round
## where they are.
##
## The canopy's frame and the dash's body are modelled: meshes on the camera
## (frame_mesh, dash_mesh) in the ship's own hull material (`hull_material`), the
## dash a darker shade of it (DASH_SHADE), so the sun, the sky and their
## reflections light them exactly as they light the outside of the ship. The
## struts stand on the dash and run down into it, so they grow out of it. The
## instruments, their plates and the yoke stay painted, over the top.

const TiltShader := preload("res://src/systems/look/shaders/cockpit_tilt.gdshader")

const GLASS := Color(0.55, 0.75, 0.9, 0.06)
const FRAME_METAL := Color(0.69, 0.74, 0.79, 1.0)  ## the frame's skin when the ship gives none
const LIGHT := CockpitDash.LIGHT
const YOKE := Color(0.24, 0.24, 0.25, 1.0)
const YOKE_LIT := Color(0.55, 0.55, 0.56, 0.9)
const YOKE_EDGE := Color(0.02, 0.02, 0.02, 1.0)
const GRIP := Color(0.07, 0.065, 0.06, 1.0)
const YOKE_TURN := 28.0            ## degrees the yoke turns at full roll
const TILT := 0.55                 ## how fast the dash recedes going up it (cockpit_tilt.gdshader)
const PANEL_TOP := 0.66            ## the dash's texture starts this far down the screen (before the lean)
const PANEL_SCALE := 1.5           ## the dash's texture is drawn this much finer than the screen, so it stays crisp warped
const SUN_GLINT := 0.5             ## the sun's glints at full daylight, 0..1
const BOLT_RANGE := 90.0           ## m: bolts further off than this put no light on the glass
const BOLT_FALLOFF := 14.0         ## m: a bolt this far off glints at half strength
const MAX_GLINTS := 6
const FRAME_FOV := 70.0            ## degrees: the lens the canopy frame is laid out for, when no camera says
const FRAME_FOOT := 1.0            ## m ahead of your eye, where the struts stand on the dash
const FRAME_THICK := 0.09          ## m across the frame's struts and bow
const FRAME_SIDES := 18            ## faces round each frame tube
const FRAME_SINK := 0.2            ## m each strut runs on down past its foot, out of sight inside the dash
const DASH_SHADE := 0.38           ## the dash's skin is the hull's colour times this
const DASH_LIP := 0.025            ## share of the screen height the dash's top edge rolls over in
const BOW_AHEAD := 0.58            ## m ahead of your eye, the bow over the top of the glass
const BOW_TOP := 0.44              ## m above your eye, the bow at its middle
const BOW_SIDE := Vector2(0.62, 0.27)  ## m: where the bow meets each strut (out, up)
const OVERHEAD := Vector3(0.3, 0.5, 0.05)  ## m: where a strut has got to once it is over and behind you

var values: Dictionary = {}
var vessel_name := ""
var yoke := Vector3.ZERO            ## the yoke as drawn (pitch, yaw, roll), eased toward the stick
var lights: Array = []              ## gather_lights(), this frame
var dash: CockpitDash
var _dash_vp: SubViewport
var _dash_quad: ColorRect
var _sun: DirectionalLight3D
var _sun_look := 0.0                ## seconds until the next look for a sun, when there is none
var hull_material: Material         ## the ship's skin, for the canopy frame (ShipPilot sets it on boarding)
var _frame: MeshInstance3D
var _frame_fit := ""                ## the screen and lens the frame's mesh was built for
var _frame_metal: StandardMaterial3D
var _dash_body: MeshInstance3D
var _dash_skin: Material            ## the dash's darker shade of the skin
var _dash_skin_of: Material         ## the skin _dash_skin was made from


func _ready() -> void:
	name = "Cockpit"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_dash_vp = SubViewport.new()
	_dash_vp.name = "DashView"
	_dash_vp.transparent_bg = true
	_dash_vp.disable_3d = true
	_dash_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_dash_vp)
	dash = CockpitDash.new()
	_dash_vp.add_child(dash)
	_dash_quad = ColorRect.new()
	_dash_quad.name = "DashTilt"
	_dash_quad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dash_quad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dash_quad.show_behind_parent = true
	var mat := ShaderMaterial.new()
	mat.shader = TiltShader
	mat.set_shader_parameter("panel", _dash_vp.get_texture())
	_dash_quad.material = mat
	add_child(_dash_quad)


func _process(dt: float) -> void:
	var on := is_visible_in_tree()
	_dash_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	_place_frame(on)
	if not on:
		return
	_fit(get_viewport_rect().size)
	lights = gather_lights(dt)
	dash.values = values
	dash.vessel_name = vessel_name
	dash.lights = lights
	dash.queue_redraw()
	var want := Vector3(_v("stick_pitch"), _v("stick_yaw"), _v("stick_roll"))
	if not yoke.is_equal_approx(want):
		yoke = yoke.lerp(want, minf(1.0, dt * 10.0))
	queue_redraw()


func _exit_tree() -> void:
	for n in [_frame, _dash_body]:
		if is_instance_valid(n):
			n.queue_free()


func _v(key: String, fallback: float = 0.0) -> float:
	return float(values.get(key, fallback))


## The canopy frame and the dash's body ride on whichever camera is drawing the
## cockpit, wearing the ship's skin; their meshes are rebuilt only when the screen
## or the lens changes.
func _place_frame(on: bool) -> void:
	var cam := get_viewport().get_camera_3d() if on else null
	if cam == null:
		for n in [_frame, _dash_body]:
			if is_instance_valid(n):
				n.visible = false
		return
	if not is_instance_valid(_frame):
		_frame = _on_camera("CanopyFrame")
		_dash_body = _on_camera("DashBody")
		_frame_fit = ""
	var vp := get_viewport_rect().size
	var fit := "%s %s" % [vp, cam.fov]
	for n in [_frame, _dash_body]:
		var mi := n as MeshInstance3D
		if mi.get_parent() != cam:
			if mi.get_parent() != null:
				mi.get_parent().remove_child(mi)
			cam.add_child(mi)
		mi.transform = Transform3D.IDENTITY
		mi.visible = true
	if fit != _frame_fit:
		_frame.mesh = frame_mesh(vp, cam.fov)
		_dash_body.mesh = dash_mesh(vp, cam.fov)
		_frame_fit = fit
	if hull_material == null and _frame_metal == null:
		_frame_metal = StandardMaterial3D.new()
		_frame_metal.albedo_color = FRAME_METAL
		_frame_metal.metallic = 0.85
		_frame_metal.roughness = 0.32
	var skin: Material = hull_material if hull_material != null else _frame_metal
	_frame.material_override = skin
	if _dash_skin_of != skin:
		_dash_skin = dash_skin(skin)
		_dash_skin_of = skin
	_dash_body.material_override = _dash_skin


func _on_camera(n: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## The dash's skin: the hull's, its colour darkened (DASH_SHADE), its finish kept,
## so it shines the same way but sits darker than the struts.
static func dash_skin(skin: Material) -> Material:
	var base := skin as BaseMaterial3D
	if base == null:
		return skin
	var m := base.duplicate() as BaseMaterial3D
	var c := base.albedo_color
	m.albedo_color = Color(c.r * DASH_SHADE, c.g * DASH_SHADE, c.b * DASH_SHADE, c.a)
	return m


## Size the dash's texture and the shader to the screen: the panel runs far enough
## past each side that its top still reaches the screen's edges once it leans.
func _fit(vp: Vector2) -> void:
	var top := vp.y * PANEL_TOP
	var margin := ceilf(vp.x * 0.5 * TILT * (1.0 - PANEL_TOP))
	var size := Vector2i(ceili((vp.x + margin * 2.0) * PANEL_SCALE), ceili((vp.y - top) * PANEL_SCALE))
	if _dash_vp.size == size and dash.screen == vp:
		return
	_dash_vp.size = size
	dash.screen = vp
	dash.margin = margin
	dash.top = top
	dash.scale_by = PANEL_SCALE
	dash.size = Vector2(size)
	var mat := _dash_quad.material as ShaderMaterial
	mat.set_shader_parameter("tilt", TILT)
	mat.set_shader_parameter("screen", vp)
	mat.set_shader_parameter("margin", margin)
	mat.set_shader_parameter("top", top)


## Where panel point p (CockpitDash's flat drawing) lands on screen once the dash
## leans away: the bottom edge stays put, and the higher up the panel the further
## off it is, so it shrinks toward the middle and rises less.
static func project(vp: Vector2, p: Vector2) -> Vector2:
	var v := (vp.y - p.y) / maxf(vp.y, 1.0)
	var z := 1.0 + TILT * v
	return Vector2(vp.x * 0.5 + (p.x - vp.x * 0.5) / z, vp.y * (1.0 - v / z))


## The dash's top edge on screen, left to right, past both sides of the screen.
static func rim(vp: Vector2) -> PackedVector2Array:
	var margin := vp.x * 0.5 * TILT * (1.0 - PANEL_TOP)
	var out := PackedVector2Array()
	for i in 49:
		var x := lerpf(-margin, vp.x + margin, float(i) / 48.0)
		out.append(project(vp, Vector2(x, CockpitDash.dash_top(vp, x))))
	return out


## The dash's top edge on screen at x.
static func rim_y(line: PackedVector2Array, x: float) -> float:
	for i in line.size() - 1:
		if x <= line[i + 1].x:
			return lerpf(line[i].y, line[i + 1].y, clampf(inverse_lerp(line[i].x, line[i + 1].x, x), 0.0, 1.0))
	return line[line.size() - 1].y


## What lights the glass this frame: the sun, and the nearest bolts in flight. Each
## { dir: unit vector toward it in the camera's frame (x right, y up, -z ahead),
## color, power 0..1, and screen: where it is on screen, when it is ahead }.
func gather_lights(dt: float = 0.0) -> Array:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return []
	var to_cam := cam.global_basis.orthonormalized().inverse()
	var out: Array = []
	var sun := _find_sun(cam, dt)
	if sun != null:
		var toward := sun.global_basis.z.normalized()
		var l := {"dir": to_cam * toward, "color": sun.light_color, "sun": true,
			"power": SUN_GLINT * clampf(sun.light_energy / 3.0, 0.0, 1.0)}
		var far := cam.global_position + toward * 1000.0
		if not cam.is_position_behind(far):
			l.screen = cam.unproject_position(far)
		out.append(l)
	var bolts: Array = []
	for b in get_tree().get_nodes_in_group("glints"):
		var n := b as Node3D
		if n == null or not n.is_visible_in_tree():
			continue
		var rel := n.global_position - cam.global_position
		var d := rel.length()
		if d > BOLT_RANGE or d < 0.01:
			continue
		var p := 1.0 / (1.0 + pow(d / BOLT_FALLOFF, 2.0)) * (1.0 - d / BOLT_RANGE)
		var l := {"dir": to_cam * (rel / d), "color": n.get_meta("glint_color", Color.WHITE), "power": p}
		if not cam.is_position_behind(n.global_position):
			l.screen = cam.unproject_position(n.global_position)
		bolts.append(l)
	bolts.sort_custom(func(a, b): return a.power > b.power)
	out.append_array(bolts.slice(0, MAX_GLINTS))
	return out


## The scene's sun: the brightest directional light in the camera's world. Looked
## for again only once a second while there is none.
func _find_sun(cam: Camera3D, dt: float) -> DirectionalLight3D:
	if is_instance_valid(_sun) and _sun.is_visible_in_tree():
		return _sun
	_sun = null
	_sun_look -= dt
	if _sun_look > 0.0:
		return null
	_sun_look = 1.0
	for n in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		var l := n as DirectionalLight3D
		if l.is_visible_in_tree() and l.get_world_3d() == cam.get_world_3d() \
				and (_sun == null or l.light_energy > _sun.light_energy):
			_sun = l
	return _sun


func _draw() -> void:
	var vp := get_viewport_rect().size
	var line := rim(vp)
	# The glass, down to the dash's edge.
	var glass := PackedVector2Array([Vector2(vp.x, 0), Vector2(0, 0)])
	glass.append_array(line)
	draw_colored_polygon(glass, GLASS)
	# A couple of faint streaks of glare on it, brighter with the sun ahead.
	var sun_ahead := 0.0
	for l in lights:
		if l.get("sun", false):
			sun_ahead = float(l.power) * clampf(-(l.dir as Vector3).z, 0.0, 1.0) / SUN_GLINT
	draw_line(Vector2(vp.x * 0.62, vp.y * 0.08), Vector2(vp.x * 0.7, vp.y * 0.3), Color(1, 1, 1, 0.05 + 0.04 * sun_ahead), 6.0)
	draw_line(Vector2(vp.x * 0.66, vp.y * 0.06), Vector2(vp.x * 0.72, vp.y * 0.22), Color(1, 1, 1, 0.035 + 0.03 * sun_ahead), 3.0)
	_draw_canopy_shine(vp, line)
	_draw_yoke(vp)


## The sun and bolts ahead light the canopy faintly round where they are: a wide
## haze round the sun, a small coloured bloom round a bolt, more the closer it is.
func _draw_canopy_shine(vp: Vector2, line: PackedVector2Array) -> void:
	for l in lights:
		if not l.has("screen"):
			continue
		var at: Vector2 = l.screen
		if at.y > rim_y(line, at.x):
			continue
		var col := Color(l.color)
		if l.get("sun", false):
			CockpitDash.halo(self, at, vp.y * 0.5, Color(col, 0.07 * float(l.power) / SUN_GLINT))
		else:
			CockpitDash.halo(self, at, vp.y * (0.04 + 0.16 * float(l.power)), Color(col, 0.16 * float(l.power)))


## The canopy's frame (modelled in metres round your eye, seen through a `fov`
## lens on a `vp` screen): two struts from the dash's shoulders up and back over
## your head, and a bow across the top of the glass between them, each a round
## tube FRAME_THICK across. Perspective does the rest: the nearer a part is the
## wider it draws, so the struts swell and sweep out to the top corners as they
## pass overhead, which is what makes them feel like they go over you.
static func frame_mesh(vp: Vector2, fov := FRAME_FOV) -> ArrayMesh:
	var line := rim(vp)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tube(st, bow_path())
	for side in [-1.0, 1.0]:
		var path := strut_path(vp, line, side, fov)
		var down := (path[0] - path[1]).normalized()
		path.insert(0, path[0] + down * FRAME_SINK)
		_tube(st, path)
	return st.commit()


## The dash's body (seen through a `fov` lens on a `vp` screen): a face leaning
## back from upright (CockpitDash.LEAN) whose top edge is the dash's edge on screen
## (rim), filling everything under it. Over its top DASH_LIP the face rolls over
## to a top facing up and away, so the edge catches the sky and the sun.
static func dash_mesh(vp: Vector2, fov := FRAME_FOV) -> ArrayMesh:
	var line := rim(vp)
	var lean := deg_to_rad(CockpitDash.LEAN)
	var face := Vector3(0.0, sin(lean), cos(lean))
	var top := Vector3(0.0, 0.96, -0.28)
	var rows := [0.0, 0.08, 0.2, 0.36, 0.56, 0.8, 1.0, 3.0, 8.0, 20.0]   # in DASH_LIP, down from the edge
	var cols := 48
	var grid: Array = []
	var normals: Array = []
	for j in rows.size():
		var row: Array = []
		var nrow: Array = []
		for i in cols + 1:
			var x := lerpf(-vp.x * 0.1, vp.x * 1.1, float(i) / cols)
			var y := rim_y(line, x) + float(rows[j]) * DASH_LIP * vp.y
			row.append(dash_point(vp, Vector2(x, y), fov))
			nrow.append(top.slerp(face, smoothstep(0.0, 1.0, minf(float(rows[j]), 1.0))))
		grid.append(row)
		normals.append(nrow)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in rows.size() - 1:
		for i in cols:
			for q in [[j, i], [j, i + 1], [j + 1, i + 1], [j, i], [j + 1, i + 1], [j + 1, i]]:
				st.set_normal(normals[q[0]][q[1]])
				st.add_vertex(grid[q[0]][q[1]])
	return st.commit()


## Where the line of sight through screen point s meets the dash's face: a plane
## leaning back CockpitDash.LEAN from upright, through the middle of the dash's
## edge FRAME_FOOT ahead of your eye.
static func dash_point(vp: Vector2, s: Vector2, fov := FRAME_FOV) -> Vector3:
	var lean := deg_to_rad(CockpitDash.LEAN)
	var n := Vector3(0.0, sin(lean), cos(lean))
	var mid := frame_unproject(vp, project(vp, Vector2(vp.x * 0.5, CockpitDash.dash_top(vp, vp.x * 0.5))), FRAME_FOOT, fov)
	var d := frame_unproject(vp, s, 1.0, fov)
	return d * (n.dot(mid) / n.dot(d))


## The bow's centre line, over the top of the glass from one strut to the other.
static func bow_path() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in 25:
		var u := lerpf(-1.0, 1.0, float(i) / 24.0)
		out.append(Vector3(u * BOW_SIDE.x, lerpf(BOW_TOP, BOW_SIDE.y, u * u), -BOW_AHEAD))
	return out


## One strut's centre line in metres round your eye (x right, y up, -z ahead), from
## its foot on the dash's edge (on its face, dash_point), through the bow's end, to over and behind your head.
static func strut_path(vp: Vector2, line: PackedVector2Array, side: float, fov := FRAME_FOV) -> Array[Vector3]:
	var bx := vp.x * 0.5 + side * vp.x * 0.33
	var foot := dash_point(vp, Vector2(bx, rim_y(line, bx) + 2.0), fov)
	var mid := Vector3(side * BOW_SIDE.x, BOW_SIDE.y, -BOW_AHEAD)
	var top := Vector3(side * OVERHEAD.x, OVERHEAD.y, OVERHEAD.z)
	var pull := mid * 2.0 - (foot + top) * 0.5      # so the curve passes through mid
	var out: Array[Vector3] = []
	for i in 41:
		var t := float(i) / 40.0
		out.append(foot.lerp(pull, t).lerp(pull.lerp(top, t), t))
	return out


## Where a point round your eye (m: x right, y up, -z ahead) lands on screen
## (`fov` is the lens's vertical angle, as Camera3D's).
static func frame_project(vp: Vector2, p: Vector3, fov := FRAME_FOV) -> Vector2:
	return vp * 0.5 + Vector2(p.x, -p.y) * _focal(vp, fov) / -p.z


## The point `depth` m ahead of your eye that lands on screen at s.
static func frame_unproject(vp: Vector2, s: Vector2, depth: float, fov := FRAME_FOV) -> Vector3:
	var d := (s - vp * 0.5) * depth / _focal(vp, fov)
	return Vector3(d.x, -d.y, -depth)


static func _focal(vp: Vector2, fov := FRAME_FOV) -> float:
	return vp.y * 0.5 / tan(deg_to_rad(fov) * 0.5)


## A round tube FRAME_THICK across along `path`, its rings turned along it without
## twisting (each ring's "up" carried over from the last), normals pointing out.
static func _tube(st: SurfaceTool, path: Array[Vector3]) -> void:
	var r := FRAME_THICK * 0.5
	var up := Vector3.UP
	var rings: Array = []
	for i in path.size():
		var axis := (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).normalized()
		up = (up - axis * up.dot(axis))
		if up.length() < 0.001:
			up = axis.cross(Vector3.RIGHT)
		up = up.normalized()
		var side := axis.cross(up)
		var ring: Array = []
		for k in FRAME_SIDES + 1:
			var a := TAU * float(k) / FRAME_SIDES
			ring.append(up * cos(a) + side * sin(a))
		rings.append(ring)
	for i in path.size() - 1:
		for k in FRAME_SIDES:
			var a: Vector3 = rings[i][k]
			var b: Vector3 = rings[i][k + 1]
			var c: Vector3 = rings[i + 1][k + 1]
			var d: Vector3 = rings[i + 1][k]
			for q in [[a, i], [c, i + 1], [b, i], [a, i], [d, i + 1], [c, i + 1]]:
				var n: Vector3 = q[0]
				st.set_normal(n)
				st.add_vertex(path[q[1]] + n * r)


## How the yoke sits for a stick of (pitch, yaw, roll), each -1..1: turned by
## `angle` (radians, + clockwise on screen, as for a right roll), and pulled back
## toward you by `pull` (-1 pushed full forward .. 1 pulled full back). Yaw turns it
## too, at half the rate: the mouse steers with yaw, and the yoke should answer it.
static func yoke_pose(stick: Vector3) -> Dictionary:
	return {
		"angle": deg_to_rad(YOKE_TURN) * clampf(stick.z + stick.y * 0.5, -1.0, 1.0),
		"pull": clampf(stick.x, -1.0, 1.0),
	}


## The yoke: a ram's-horn wheel on a column that comes up from under the screen,
## its grips either side of the attitude ball and low enough to leave the canopy
## open. It turns about its hub and rides back toward you as you pull up.
func _draw_yoke(vp: Vector2) -> void:
	var pose := yoke_pose(yoke)
	var k := vp.y
	var pull: float = pose.pull
	var hub := Vector2(vp.x * 0.5, k * (0.995 + pull * 0.035))
	var sc := 1.0 + pull * 0.05
	var w := vp.x * 0.088 * sc
	var h := k * 0.15 * sc
	var t := k * 0.03 * sc
	# The column, which slides but does not turn.
	var cw := t * 0.8
	draw_rect(Rect2(hub.x - cw, hub.y, cw * 2.0, vp.y - hub.y + 2.0), YOKE.darkened(0.35))
	draw_line(Vector2(hub.x - cw * 0.4, hub.y), Vector2(hub.x - cw * 0.4, vp.y), Color(1, 1, 1, 0.12), 2.0)
	# The wheel's centre line, hub out to the grips' tops, both sides.
	var half := [Vector2(0, t * 0.6), Vector2(w * 0.45, t * 0.35), Vector2(w * 0.8, -h * 0.12),
		Vector2(w, -h * 0.4), Vector2(w * 1.04, -h)]
	var rot := Transform2D(float(pose.angle), hub)
	var sides: Array[PackedVector2Array] = []
	for s in [-1.0, 1.0]:
		var line := PackedVector2Array()
		for p in half:
			var q: Vector2 = p
			line.append(rot * Vector2(q.x * s, q.y))
		sides.append(line)
	for line in sides:
		_thick(line, t + 4.0, YOKE_EDGE)
	for line in sides:
		_thick(line, t, YOKE)
		# The edge toward the light.
		var lit := PackedVector2Array()
		for p in line:
			lit.append(p + LIGHT * t * 0.28)
		_thick(lit, t * 0.22, YOKE_LIT)
	# Grips: wrapped, thicker, ridged, on the top of each horn.
	for i in sides.size():
		var line: PackedVector2Array = sides[i]
		var a := line[3].lerp(line[4], 0.15)
		var b := line[4]
		_thick(PackedVector2Array([a, b]), t * 1.45 + 3.0, YOKE_EDGE)
		_thick(PackedVector2Array([a, b]), t * 1.45, GRIP)
		var along := (b - a).normalized()
		var across := along.orthogonal() * t * 0.7
		for j in 6:
			var m := a.lerp(b, (float(j) + 0.5) / 6.0)
			draw_line(m - across, m + across, Color(0.2, 0.19, 0.17, 0.9), 1.5)
		_thick(PackedVector2Array([a + LIGHT * t * 0.4, b + LIGHT * t * 0.4]), t * 0.18, Color(1, 1, 1, 0.12))
		# A trigger cap on the right horn, a thumb hat on the left.
		var cap := b + along * t * 0.2
		draw_circle(cap, t * 0.42, Color(0, 0, 0, 0.7))
		draw_circle(cap, t * 0.34, Color(0.55, 0.12, 0.08) if i == 1 else Color(0.35, 0.35, 0.36))
		draw_circle(cap + LIGHT * t * 0.12, t * 0.12, Color(1, 1, 1, 0.45))
	# The hub's boss.
	var boss := rot * Vector2(0, t * 0.5)
	draw_circle(boss, t * 1.25, Color(0, 0, 0, 0.7))
	draw_circle(boss, t * 1.15, YOKE.darkened(0.15))
	draw_arc(boss, t * 0.95, LIGHT.angle() - 1.0, LIGHT.angle() + 1.0, 16, YOKE_LIT, t * 0.18, true)
	draw_circle(boss, t * 0.55, Color(0.1, 0.1, 0.1))
	draw_circle(boss + LIGHT * t * 0.2, t * 0.15, Color(1, 1, 1, 0.25))


## A thick line with round joints (draw_polyline leaves gaps at the corners).
func _thick(line: PackedVector2Array, width: float, col: Color) -> void:
	for i in line.size() - 1:
		draw_line(line[i], line[i + 1], col, width, true)
	for p in line:
		draw_circle(p, width * 0.5, col)
