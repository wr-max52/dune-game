shader_type spatial;
// Sand: two scales of wind ripples in the normal, warm (not grey) shadow sides,
// slope tint and a soft glitter close to the camera. Journey is the reference.

uniform vec4 sand_light : source_color = vec4(0.91, 0.77, 0.56, 1.0);
uniform vec4 sand_mid : source_color = vec4(0.79, 0.58, 0.35, 1.0);
uniform vec4 sand_shadow : source_color = vec4(0.48, 0.35, 0.29, 1.0);
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec2 wind_dir = vec2(0.8, 0.6);
uniform vec3 sun_dir = vec3(0.0, 0.15, -1.0);
uniform float ripple_strength = 0.16;
uniform float glitter = 1.0;

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float n_big = texture(noise_tex, wpos.xz * 0.0021).r;
	float n_mid = texture(noise_tex, wpos.xz * 0.019).r;
	float n_fine = texture(noise_tex, wpos.xz * 0.11).r;

	vec3 alb = mix(sand_mid.rgb, sand_light.rgb, smoothstep(0.25, 0.85, n_big * 0.6 + n_mid * 0.4));
	float slope = 1.0 - clamp(wnorm.y, 0.0, 1.0);
	alb = mix(alb, sand_shadow.rgb, smoothstep(0.15, 0.55, slope) * 0.45);

	// Ripples run across the wind. Warping the phase keeps them from looking ruled.
	vec2 wd = normalize(wind_dir);
	vec2 wd2 = normalize(vec2(wd.x + 0.35, wd.y - 0.2));
	float warp = n_mid * 7.0 + n_big * 18.0;
	float ph1 = dot(wpos.xz, wd) * 1.6 + warp;
	float ph2 = dot(wpos.xz, wd2) * 7.5 + warp * 2.0 + n_fine * 3.0;
	float fade1 = 1.0 - smoothstep(25.0, 140.0, dist);
	float fade2 = 1.0 - smoothstep(8.0, 45.0, dist);
	// Flat ground ripples more than steep dune faces (sand slides there).
	float flat_k = smoothstep(0.35, 0.05, slope);
	// sin + a harmonic gives a skewed, asymmetric ripple profile.
	vec2 grad = wd * (cos(ph1) + 0.45 * cos(2.0 * ph1 + 0.6)) * fade1 * ripple_strength
		+ wd2 * (cos(ph2) + 0.4 * cos(2.0 * ph2)) * fade2 * ripple_strength * 0.6;
	grad *= flat_k;
	vec3 nw = normalize(wnorm - vec3(grad.x, 0.0, grad.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);

	alb *= 1.0 - 0.035 * sin(ph1) * fade1 * flat_k;
	alb *= 0.94 + 0.12 * n_fine;
	ALBEDO = alb;
	ROUGHNESS = 0.93;
	SPECULAR = 0.3;

	// Glitter: a few cells per metre catch the sun, only near the camera.
	vec2 cell = floor(wpos.xz * 14.0);
	float hsh = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
	vec3 v = normalize(CAMERA_POSITION_WORLD - wpos);
	float flick = fract(hsh * 37.0 + dot(v, vec3(3.1, 1.7, 2.3)) * 3.0);
	float sunlit = clamp(dot(nw, normalize(sun_dir)) * 3.0, 0.0, 1.0);
	EMISSION = vec3(1.0, 0.88, 0.7) * step(0.997, flick) * fade2 * sunlit * glitter * 2.0;
}
