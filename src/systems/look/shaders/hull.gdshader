shader_type spatial;
// Salvaged hull metal: panel seams, scorch, and sand drifting up the base.
// Used on the wreck and on plates patched onto port buildings.

uniform vec4 metal : source_color = vec4(0.20, 0.21, 0.23, 1.0);
uniform vec4 metal_light : source_color = vec4(0.34, 0.34, 0.35, 1.0);
uniform vec4 scorch : source_color = vec4(0.08, 0.07, 0.07, 1.0);
uniform vec4 sand : source_color = vec4(0.79, 0.58, 0.35, 1.0);
uniform vec4 marking : source_color = vec4(0.42, 0.12, 0.12, 1.0);
uniform float panel_size = 4.0;
uniform float sand_y = 2.0;
uniform float marking_y = -1000.0;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;

varying vec3 wpos;
varying vec3 wnorm;
varying vec3 lpos;
varying vec3 lnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	lpos = VERTEX;
	lnorm = NORMAL;
}

float seams(vec2 p) {
	vec2 g = abs(fract(p / panel_size) - 0.5);
	vec2 g2 = abs(fract(p / (panel_size * 0.5) + 0.25) - 0.5);
	float main = smoothstep(0.47, 0.495, max(g.x, g.y));
	float minor = smoothstep(0.48, 0.497, g2.y) * 0.5;
	return max(main, minor);
}

void fragment() {
	// Pick the projection plane from the local normal (cheap triplanar).
	vec3 an = abs(lnorm);
	vec2 p = lpos.yz;
	if (an.y > an.x && an.y > an.z) { p = lpos.xz; }
	else if (an.z > an.x) { p = lpos.xy; }
	float seam = seams(p);
	float n = texture(noise_tex, p * 0.02).r;
	float n2 = texture(noise_tex, wpos.xz * 0.004 + wpos.y * 0.003).r;
	float panel_var = texture(noise_tex, floor(p / panel_size) * 0.137).r;

	vec3 alb = mix(metal.rgb, metal_light.rgb, panel_var * 0.8 + n * 0.2);
	alb *= 1.0 - seam * 0.55;
	float burn = smoothstep(0.5, 0.8, n2);
	alb = mix(alb, scorch.rgb, burn * 0.85);
	float mark = step(abs(wpos.y - marking_y), 3.0) * (1.0 - burn);
	alb = mix(alb, marking.rgb, mark * 0.9);
	float drift = 1.0 - smoothstep(sand_y - 1.0, sand_y + 4.0 + n * 6.0, wpos.y);
	drift = max(drift, smoothstep(0.75, 0.95, wnorm.y) * 0.6 * (1.0 - burn));
	alb = mix(alb, sand.rgb, drift);

	ALBEDO = alb;
	METALLIC = mix(0.55, 0.0, max(drift, burn));
	ROUGHNESS = mix(0.5, 0.95, max(drift, burn)) + seam * 0.1;
}
