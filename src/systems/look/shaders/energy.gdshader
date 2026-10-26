shader_type spatial;
// Energy blade: an additive glow shell (soft at the edges) or a solid hot core.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.79, 0.23, 1.0);
uniform float energy = 3.0;
uniform float core = 0.0;     // 1 = solid core, 0 = soft shell
uniform float falloff = 2.0;

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float a = core > 0.5 ? 1.0 : pow(facing, falloff);
	ALBEDO = color.rgb * energy * a;
	ALPHA = a;
}
