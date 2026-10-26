shader_type sky;
// Desert sky: gradient + sun glow + thin high cloud + a ringed giant planet.
// The planet is the "too big" thing in the sky (see docs/ART_DIRECTION.md).
// Every colour and size comes from content/look/time_of_day.json.

uniform vec3 sun_dir = vec3(0.0, 0.15, -1.0);
uniform vec4 zenith_color : source_color = vec4(0.31, 0.44, 0.62, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.95, 0.75, 0.54, 1.0);
uniform vec4 ground_color : source_color = vec4(0.72, 0.54, 0.37, 1.0);
uniform vec4 sun_glow_color : source_color = vec4(1.0, 0.69, 0.44, 1.0);
uniform vec4 sun_disk_color : source_color = vec4(1.0, 0.85, 0.65, 1.0);
uniform float sun_disk_energy = 30.0;
uniform float sun_disk_cos = 0.99985;
uniform float glow_strength = 0.8;
uniform float horizon_falloff = 0.45;
uniform float sky_energy = 1.0;

uniform sampler2D cloud_noise : repeat_enable, filter_linear_mipmap;
uniform float cloud_cover = 0.4;
uniform vec4 cloud_color : source_color = vec4(1.0, 0.86, 0.72, 1.0);
uniform vec4 cloud_shadow : source_color = vec4(0.62, 0.52, 0.55, 1.0);

uniform vec3 planet_dir = vec3(0.4, 0.28, -0.87);
uniform float planet_radius = 0.13;      // in units of planet distance (1.0)
uniform vec4 planet_color_a : source_color = vec4(0.82, 0.74, 0.66, 1.0);
uniform vec4 planet_color_b : source_color = vec4(0.55, 0.47, 0.45, 1.0);
uniform vec3 ring_normal = vec3(0.25, 0.95, 0.2);
uniform vec4 ring_color : source_color = vec4(0.9, 0.82, 0.72, 1.0);
uniform float planet_visibility = 0.75;  // 0 = lost in daylight, 1 = vivid

float hash(float n) { return fract(sin(n) * 43758.5453); }

vec3 base_sky(vec3 d) {
	float h = d.y;
	vec3 col;
	if (h >= 0.0) {
		col = mix(horizon_color.rgb, zenith_color.rgb, pow(clamp(h, 0.0, 1.0), horizon_falloff));
	} else {
		col = mix(horizon_color.rgb, ground_color.rgb, clamp(-h * 5.0, 0.0, 1.0));
	}
	float sd = max(dot(d, normalize(sun_dir)), 0.0);
	float near_horizon = 1.0 - clamp(abs(h) * 2.5, 0.0, 1.0);
	col = mix(col, sun_glow_color.rgb, pow(sd, 5.0) * 0.55 * near_horizon * glow_strength);
	col += sun_glow_color.rgb * pow(sd, 48.0) * 0.9 * glow_strength;
	col += sun_glow_color.rgb * pow(sd, 400.0) * 2.5 * glow_strength;
	return col;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 s = normalize(sun_dir);
	vec3 col = base_sky(d);

	// --- Ringed planet: a real ray/sphere + ray/plane test, lit by the sun. ---
	vec3 c = normalize(planet_dir);
	float r = planet_radius;
	float b = dot(d, c);
	float disc = b * b - (1.0 - r * r);
	float t_planet = 1e9;
	vec4 planet = vec4(0.0);
	if (disc > 0.0 && b > 0.0) {
		t_planet = b - sqrt(disc);
		vec3 n = normalize(d * t_planet - c);
		// Bands follow the ring plane, so the planet and its rings agree.
		vec3 rn = normalize(ring_normal);
		float lat = dot(n, rn);
		float band = sin(lat * 22.0 + sin(lat * 7.0) * 1.6) * 0.5 + 0.5;
		band = mix(band, hash(floor(lat * 30.0)), 0.25);
		vec3 albedo = mix(planet_color_b.rgb, planet_color_a.rgb, band);
		float lambert = smoothstep(-0.15, 0.6, dot(n, s));
		float rim = pow(1.0 - max(dot(n, -d), 0.0), 3.0);
		vec3 lit = albedo * (lambert * 1.15 + 0.06) + sun_glow_color.rgb * rim * lambert * 0.4;
		planet = vec4(lit, planet_visibility);
	}

	vec4 ring = vec4(0.0);
	float t_ring = 1e9;
	vec3 rn = normalize(ring_normal);
	float denom = dot(d, rn);
	if (abs(denom) > 1e-4) {
		float tr = dot(c, rn) / denom;
		if (tr > 0.0) {
			vec3 p = d * tr;
			float dist = length(p - c) / r;
			if (dist > 1.35 && dist < 2.5) {
				float k = (dist - 1.35) / 1.15;
				float bands = 0.55 + 0.45 * sin(k * 60.0) * sin(k * 17.0 + 1.3);
				float gap = smoothstep(0.02, 0.05, abs(k - 0.62));
				float edge = smoothstep(0.0, 0.06, k) * smoothstep(1.0, 0.85, k);
				// Planet shadow on the ring: does the line from p to the sun hit the sphere?
				float bs = dot(s, c - p);
				float shadow = 1.0;
				if (bs > 0.0) {
					float dd = length(c - p - s * bs);
					shadow = smoothstep(r * 0.9, r * 1.05, dd);
				}
				float a = bands * gap * edge * 0.8 * planet_visibility;
				ring = vec4(ring_color.rgb * (0.25 + 0.85 * shadow), a);
				t_ring = tr;
			}
		}
	}

	// Composite back to front, so the ring passes behind and in front of the planet.
	if (t_ring < t_planet) {
		col = mix(col, planet.rgb, planet.a);
		col = mix(col, ring.rgb, ring.a);
	} else {
		col = mix(col, ring.rgb, ring.a);
		col = mix(col, planet.rgb, planet.a);
	}

	// --- Thin high cloud streaks ---
	if (d.y > 0.0) {
		vec2 uv = d.xz / (d.y + 0.12);
		float n1 = texture(cloud_noise, uv * vec2(0.05, 0.16) + vec2(0.13, 0.4)).r;
		float n2 = texture(cloud_noise, uv * vec2(0.17, 0.5) + vec2(0.7, 0.2)).r;
		float n = n1 * 0.7 + n2 * 0.3;
		float cov = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.35, n);
		cov *= smoothstep(0.0, 0.12, d.y) * (1.0 - smoothstep(0.55, 0.95, d.y));
		float sd = max(dot(d, s), 0.0);
		vec3 cc = mix(cloud_shadow.rgb, cloud_color.rgb, 0.45 + 0.55 * n2);
		cc += sun_glow_color.rgb * pow(sd, 8.0) * 1.2;
		col = mix(col, cc, cov * 0.85);
	}

	// --- Sun disk (not in the radiance cubemap, or it would double the key light) ---
	if (!AT_CUBEMAP_PASS) {
		float sd = dot(d, s);
		col += sun_disk_color.rgb * smoothstep(sun_disk_cos - 0.00004, sun_disk_cos, sd) * sun_disk_energy;
	}

	COLOR = col * sky_energy;
}
