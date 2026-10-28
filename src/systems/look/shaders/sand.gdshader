shader_type spatial;
// Sand: two scales of wind ripples in the normal, warm (not grey) shadow sides,
// slope tint and a soft glitter close to the camera. Journey is the reference.
//
// Issue #77: on a ball (planet_radius > 0) every pattern is laid out in map
// coordinates (distance and direction along the ground from the port) and the
// ripples tilt with the ground. A layer of sand sinks out of the way wherever the
// finer layer inside it covers (hole_*: that layer's square, per instance).

uniform vec4 sand_light : source_color = vec4(0.91, 0.77, 0.56, 1.0);
uniform vec4 sand_mid : source_color = vec4(0.79, 0.58, 0.35, 1.0);
uniform vec4 sand_shadow : source_color = vec4(0.48, 0.35, 0.29, 1.0);
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec2 wind_dir = vec2(0.8, 0.6);
uniform vec3 sun_dir = vec3(0.0, 0.15, -1.0);
uniform float ripple_strength = 0.16;
uniform float glitter = 1.0;
uniform vec3 planet_center = vec3(0.0);
uniform float planet_radius = 0.0;          // 0 = flat ground
uniform float hole_sink = 6.0;
// Wide twilight (issue #77): one real sun lights the ball, and where it has set the
// sand glows a dim dusk instead of going black.
uniform vec4 dusk_color : source_color = vec4(0.42, 0.30, 0.30, 1.0);
uniform float dusk_strength = 0.35;
instance uniform vec4 hole_origin = vec4(0.0, 0.0, 0.0, 0.0);   // xyz, w = half size (0 = none)
instance uniform vec3 hole_x = vec3(1.0, 0.0, 0.0);
instance uniform vec3 hole_z = vec3(0.0, 0.0, 1.0);

varying vec3 wpos;
varying vec3 wnorm;
varying vec2 mpos;
varying vec3 wup;

vec2 to_map(vec3 w) {
	if (planet_radius <= 0.0) {
		return w.xz;
	}
	vec3 d = normalize(w - planet_center);
	float hl = length(d.xz);
	if (hl < 1e-6) {
		return vec2(0.0);
	}
	return d.xz / hl * atan(hl, d.y) * planet_radius;
}

// The rotation taking (0, 1, 0) to `up`, applied to v.
vec3 tilt(vec3 v, vec3 up) {
	vec3 axis = cross(vec3(0.0, 1.0, 0.0), up);
	float s = length(axis);
	if (s < 1e-6) {
		return v;
	}
	axis /= s;
	float c = up.y;
	return v * c + cross(axis, v) * s + axis * dot(axis, v) * (1.0 - c);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wup = planet_radius > 0.0 ? normalize(wpos - planet_center) : vec3(0.0, 1.0, 0.0);
	if (hole_origin.w > 0.0) {
		vec3 rel = wpos - hole_origin.xyz;
		float edge = max(abs(dot(rel, hole_x)), abs(dot(rel, hole_z)));
		// Fully sunk well inside the inner square, back level just past its edge.
		float k = 1.0 - smoothstep(hole_origin.w * 0.92, hole_origin.w * 1.02, edge);
		if (k > 0.0) {
			wpos -= wup * hole_sink * k;
			VERTEX = (inverse(MODEL_MATRIX) * vec4(wpos, 1.0)).xyz;
		}
	}
	mpos = to_map(wpos);
}

void fragment() {
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float n_big = texture(noise_tex, mpos * 0.0021).r;
	float n_mid = texture(noise_tex, mpos * 0.019).r;
	float n_fine = texture(noise_tex, mpos * 0.11).r;

	vec3 up = normalize(wup);
	vec3 alb = mix(sand_mid.rgb, sand_light.rgb, smoothstep(0.25, 0.85, n_big * 0.6 + n_mid * 0.4));
	float slope = 1.0 - clamp(dot(wnorm, up), 0.0, 1.0);
	alb = mix(alb, sand_shadow.rgb, smoothstep(0.15, 0.55, slope) * 0.45);

	// Ripples run across the wind. Warping the phase keeps them from looking ruled.
	vec2 wd = normalize(wind_dir);
	vec2 wd2 = normalize(vec2(wd.x + 0.35, wd.y - 0.2));
	float warp = n_mid * 7.0 + n_big * 18.0;
	float ph1 = dot(mpos, wd) * 1.6 + warp;
	float ph2 = dot(mpos, wd2) * 7.5 + warp * 2.0 + n_fine * 3.0;
	float fade1 = 1.0 - smoothstep(25.0, 140.0, dist);
	float fade2 = 1.0 - smoothstep(8.0, 45.0, dist);
	// Flat ground ripples more than steep dune faces (sand slides there).
	float flat_k = smoothstep(0.35, 0.05, slope);
	// sin + a harmonic gives a skewed, asymmetric ripple profile.
	vec2 grad = wd * (cos(ph1) + 0.45 * cos(2.0 * ph1 + 0.6)) * fade1 * ripple_strength
		+ wd2 * (cos(ph2) + 0.4 * cos(2.0 * ph2)) * fade2 * ripple_strength * 0.6;
	grad *= flat_k;
	vec3 nw = normalize(wnorm - tilt(vec3(grad.x, 0.0, grad.y), up));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);

	alb *= 1.0 - 0.035 * sin(ph1) * fade1 * flat_k;
	alb *= 0.94 + 0.12 * n_fine;
	ALBEDO = alb;
	ROUGHNESS = 0.93;
	SPECULAR = 0.3;

	// Glitter: a few cells per metre catch the sun, only near the camera.
	vec2 cell = floor(mpos * 14.0);
	float hsh = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
	vec3 v = normalize(CAMERA_POSITION_WORLD - wpos);
	float flick = fract(hsh * 37.0 + dot(v, vec3(3.1, 1.7, 2.3)) * 3.0);
	float sunlit = clamp(dot(nw, normalize(sun_dir)) * 3.0, 0.0, 1.0);
	EMISSION = vec3(1.0, 0.88, 0.7) * step(0.997, flick) * fade2 * sunlit * glitter * 2.0;
	float sun_up = dot(up, normalize(sun_dir));
	if (planet_radius > 0.0) {
		EMISSION += alb * dusk_color.rgb * dusk_strength * smoothstep(0.25, -0.35, sun_up);
	}
}
