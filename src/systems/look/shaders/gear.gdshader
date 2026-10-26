shader_type spatial;
render_mode cull_disabled;
// Character gear: one shader for armour, leather and cloth.
// - Wear: scuffed, lighter patches and scratches (metal) or faded patches (cloth).
// - Dust: the desert climbs up boots and hems (RDR2: clothing remembers the world).
// - Sheen: a soft rim on cloth so fabric reads differently from metal at a glance.

uniform vec4 base : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform float metallic = 0.0;
uniform float roughness = 0.8;
uniform float wear = 0.4;
uniform float sheen = 0.0;
uniform vec4 dust : source_color = vec4(0.72, 0.56, 0.4, 1.0);
uniform float floor_y = 8.0;
uniform float dust_height = 0.11;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;

varying vec3 wpos;
varying vec3 lpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	lpos = VERTEX;
}

void fragment() {
	vec2 uv = vec2(wpos.x + wpos.z, wpos.y);
	float n_big = texture(noise_tex, uv * 1.3).r;
	float n_fine = texture(noise_tex, uv * 7.0 + vec2(0.3, 0.7)).r;
	float scratch = texture(noise_tex, vec2(uv.x * 22.0, uv.y * 2.0)).r;

	vec3 col = base.rgb * (0.88 + 0.22 * n_big);
	float rough = roughness;
	float metal = metallic;
	if (metallic > 0.3) {
		// Bright worn metal on scratches and high-noise patches; dull elsewhere.
		float w = smoothstep(0.62, 0.8, n_big * 0.5 + scratch * 0.5) * wear;
		col = mix(col, col * 1.9 + vec3(0.05), w);
		rough = mix(roughness, roughness * 0.55, w);
		// Grime in the low spots.
		col *= 1.0 - 0.25 * smoothstep(0.55, 0.3, n_fine) * wear;
	} else {
		// Sun-faded cloth and leather.
		float fade = smoothstep(0.5, 0.85, n_big) * wear;
		col = mix(col, col * 1.25 + vec3(0.04, 0.035, 0.02), fade * 0.6);
		col *= 0.92 + 0.12 * n_fine;
	}
	float h = wpos.y - floor_y;
	float d = (1.0 - smoothstep(0.0, dust_height * (0.6 + 0.8 * n_big), h));
	col = mix(col, dust.rgb, d * 0.45);
	metal = mix(metal, 0.0, d);
	rough = mix(rough, 1.0, d);

	ALBEDO = col;
	METALLIC = metal;
	ROUGHNESS = rough;
	RIM = sheen;
	RIM_TINT = 0.6;
}
