shader_type spatial;
// The bridge's holo table (the cruiser's map): light, not matter. Additive and
// unshaded, brightest at the rim, with lines of latitude and longitude on a ball
// (grid > 0), scan bands climbing it and a faint flicker. Its own object space is
// the ball's, so the grid turns with it.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(0.25, 0.8, 1.0, 1.0);
uniform float energy = 1.0;
uniform float fill = 0.12;          // the body's own glow, square on
uniform float rim = 1.2;            // and at its edge
uniform float grid = 0.0;           // lines of latitude/longitude (0 = none)
uniform float bands = 1.0;          // the climbing scan bands' strength
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float land = 0.0;           // dune tone from the noise (the planet)

varying vec3 opos;

void vertex() {
	opos = VERTEX;
}

void fragment() {
	float fres = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.0);
	float a = fill + rim * fres;
	if (grid > 0.0) {
		vec3 d = normalize(opos);
		float lat = asin(clamp(d.y, -1.0, 1.0)) / 3.14159 * grid;
		float lon = atan(d.z, d.x) / 6.28318 * grid * 2.0;
		float dl = abs(fract(lat + 0.5) - 0.5);
		float dn = abs(fract(lon + 0.5) - 0.5);
		float gl = 1.0 - smoothstep(0.0, 0.05, min(dl, dn));
		a += gl * 0.5;
	}
	if (land > 0.0) {
		vec3 d = normalize(opos);
		float n = texture(noise_tex, vec2(atan(d.z, d.x) / 6.28318, d.y * 0.5 + 0.5) * vec2(3.0, 1.5)).r;
		a += smoothstep(0.45, 0.7, n) * land;
	}
	float scan = smoothstep(0.85, 1.0, fract(opos.y * 2.5 - TIME * 0.35));
	a += scan * 0.35 * bands;
	a *= 0.9 + 0.1 * sin(TIME * 23.0 + opos.y * 40.0);
	ALBEDO = color.rgb * a * energy;
	ALPHA = clamp(a, 0.0, 1.0);
}
