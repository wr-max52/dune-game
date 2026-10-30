shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;
// A blaster's muzzle flash (issue #229): additive quads crossed along the barrel
// (a tapering tongue of light) and one facing forward (a ragged star). Was a lit
// sphere, which read as a pale blob in front of the gun.
// mode 0: side tongue, uv.y 0 at the muzzle -> 1 at the tip. mode 1: front star.

uniform vec4 color : source_color = vec4(1.0, 0.55, 0.25, 1.0);
uniform float energy = 6.0;
uniform float mode = 0.0;
uniform float seed = 0.0;

void fragment() {
	vec2 c = UV - vec2(0.5);
	float a = 0.0;
	if (mode < 0.5) {
		float along = UV.y;
		float width = mix(0.42, 0.04, pow(along, 0.7));
		a = exp(-pow(abs(c.x) / max(width, 0.001), 2.0) * 3.0) * (1.0 - smoothstep(0.55, 1.0, along));
		a *= 0.75 + 0.25 * sin(along * 23.0 + seed * 6.0);
	} else {
		float r = length(c) * 2.0;
		float ang = atan(c.y, c.x);
		float spikes = 0.55 + 0.45 * pow(abs(cos(ang * 3.0 + seed * 5.0)), 6.0);
		a = (1.0 - smoothstep(0.0, spikes, r)) + exp(-r * r * 30.0);
	}
	vec3 hot = mix(color.rgb, vec3(1.0, 0.95, 0.85), clamp(a - 0.4, 0.0, 1.0));
	ALBEDO = hot * a * energy;
	ALPHA = clamp(a, 0.0, 1.0);
}
