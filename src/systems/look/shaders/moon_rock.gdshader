shader_type spatial;
// Moon rock (issue #99): the asteroid's ground, all the way round its ball. Grey
// regolith with a blocky look: the colour is laid in chunky cells (quantised
// noise, triplanar on the world position so it keeps its size anywhere on the
// ball), darker on steep crater walls and in pits, paler on rims and flats, with
// a fine grit close up. Same layering as the sand (planet_center/radius, the
// per-instance hole that sinks an outer layer under the inner one) and the same
// wide twilight, so one real sun lights both planets alike.

uniform vec4 rock_light : source_color = vec4(0.62, 0.62, 0.64, 1.0);
uniform vec4 rock_mid : source_color = vec4(0.46, 0.46, 0.48, 1.0);
uniform vec4 rock_dark : source_color = vec4(0.24, 0.24, 0.26, 1.0);
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 sun_dir = vec3(0.0, 0.15, -1.0);
uniform vec3 planet_center = vec3(0.0);
uniform float planet_radius = 0.0;
uniform float hole_sink = 6.0;
uniform float block_size = 3.5;            // metres: the chunky cells
uniform vec4 dusk_color : source_color = vec4(0.22, 0.22, 0.26, 1.0);
uniform float dusk_strength = 0.25;
instance uniform vec4 hole_origin = vec4(0.0, 0.0, 0.0, 0.0);
instance uniform vec3 hole_x = vec3(1.0, 0.0, 0.0);
instance uniform vec3 hole_z = vec3(0.0, 0.0, 1.0);

varying vec3 wpos;
varying vec3 wnorm;
varying vec3 wup;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wup = planet_radius > 0.0 ? normalize(wpos - planet_center) : vec3(0.0, 1.0, 0.0);
	if (hole_origin.w > 0.0) {
		vec3 rel = wpos - hole_origin.xyz;
		float edge = max(abs(dot(rel, hole_x)), abs(dot(rel, hole_z)));
		float k = 1.0 - smoothstep(hole_origin.w * 0.92, hole_origin.w * 1.02, edge);
		if (k > 0.0) {
			wpos -= wup * hole_sink * k;
			VERTEX = (inverse(MODEL_MATRIX) * vec4(wpos, 1.0)).xyz;
		}
	}
}

// Triplanar sample of the noise at a scale, picked by the ground's up.
float tri(vec3 p, vec3 w, float s) {
	return texture(noise_tex, p.zy * s).r * w.x + texture(noise_tex, p.xz * s).r * w.y + texture(noise_tex, p.xy * s).r * w.z;
}

// Blocky: the noise read at the corner of a chunky cell (one flat value per block),
// the cells' edges bent by noise so they read as broken rock, not tiles.
float blocks(vec3 p, vec3 w, float size) {
	vec3 bend = vec3(tri(p, w, 0.05), tri(p + vec3(37.0), w, 0.05), tri(p + vec3(71.0), w, 0.05)) - 0.5;
	vec3 q = floor((p + bend * size * 1.6) / size) * size;
	return tri(q, w, 0.013);
}

void fragment() {
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	vec3 up = normalize(wup);
	vec3 aw = pow(abs(up), vec3(8.0));
	aw /= (aw.x + aw.y + aw.z);
	float big = tri(wpos, aw, 0.0016);
	float blk = blocks(wpos, aw, block_size);
	float blk2 = blocks(wpos + vec3(1.7), aw, block_size * 4.0);
	float fine = tri(wpos, aw, 0.21);
	vec3 alb = mix(rock_mid.rgb, rock_light.rgb, smoothstep(0.3, 0.8, big * 0.5 + blk2 * 0.5));
	// Chunky plates: each block a shade of its own, fading out far away (no shimmer).
	float near_k = 1.0 - smoothstep(80.0, 600.0, dist);
	alb *= mix(1.0, 0.88 + 0.24 * blk, near_k);
	float slope = 1.0 - clamp(dot(wnorm, up), 0.0, 1.0);
	alb = mix(alb, rock_dark.rgb, smoothstep(0.12, 0.5, slope) * 0.75);
	alb *= 0.92 + 0.16 * fine;
	ALBEDO = alb;
	ROUGHNESS = 0.97;
	SPECULAR = 0.2;
	if (planet_radius > 0.0) {
		float sun_up = dot(up, normalize(sun_dir));
		EMISSION = alb * dusk_color.rgb * dusk_strength * smoothstep(0.25, -0.35, sun_up);
	}
}
