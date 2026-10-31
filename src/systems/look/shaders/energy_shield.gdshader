shader_type spatial;
// Energy shield (the cruiser bay's mouth, the moon station's gate, hall and pit):
// faint scan lines rolling across it and a bright rim where it meets its frame.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.25, 0.65, 1.0, 1.0);
uniform vec3 half_size = vec3(1.0);              // the mesh's half extents (a disc: its radius in x and z)
uniform vec3 rim = vec3(0.0);                    // per axis, how far in the rim glows (0 = no rim there)
uniform vec3 line_axis = vec3(0.0, 1.0, 0.0);    // the scan lines roll along this
uniform bool disc = false;                       // round in x/z: the rim follows the radius

varying vec3 lp;

void vertex() { lp = VERTEX; }

void fragment() {
	float lines = 0.5 + 0.5 * sin(dot(lp, line_axis) * 3.0 - TIME * 2.0);
	vec3 d = abs(lp);
	if (disc) {
		d.xz = vec2(length(lp.xz));
	}
	vec3 e = smoothstep(half_size - max(rim, vec3(0.001)), half_size, d) * step(vec3(0.001), rim);
	ALBEDO = tint.rgb;
	ALPHA = 0.012 + 0.018 * lines + 0.3 * clamp(e.x + e.y + e.z, 0.0, 1.0);
}
