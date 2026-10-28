shader_type spatial;
// Wind-cut sandstone: horizontal strata, sand-dusted tops, darker base.
// Pairs with the faceted meshes from LookMeshKit.rock().

uniform vec4 rock_a : source_color = vec4(0.70, 0.45, 0.30, 1.0);
uniform vec4 rock_b : source_color = vec4(0.82, 0.62, 0.44, 1.0);
uniform vec4 rock_dark : source_color = vec4(0.42, 0.28, 0.22, 1.0);
uniform vec4 dust : source_color = vec4(0.88, 0.72, 0.52, 1.0);
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float strata_scale = 0.35;
uniform float ground_y = 0.0;
// Issue #77: on the home planet's ball, strata and "up" follow the ground (height
// = metres above the bare ball) and the dusk side glows as the sand does.
uniform vec3 planet_center = vec3(0.0);
uniform float planet_radius = 0.0;          // 0 = flat ground
uniform vec3 sun_dir = vec3(0.0, 0.15, -1.0);
uniform vec4 dusk_color : source_color = vec4(0.42, 0.30, 0.30, 1.0);
uniform float dusk_strength = 0.0;

varying vec3 wpos;
varying vec3 wnorm;
varying vec3 wup;
varying float wh;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wup = planet_radius > 0.0 ? normalize(wpos - planet_center) : vec3(0.0, 1.0, 0.0);
	wh = planet_radius > 0.0 ? length(wpos - planet_center) - planet_radius : wpos.y;
}

void fragment() {
	vec3 up = normalize(wup);
	float n = texture(noise_tex, wpos.xz * 0.013 + wh * 0.004).r;
	float n2 = texture(noise_tex, vec2(wpos.x + wpos.z, wh) * 0.07).r;
	float band_ph = wh * strata_scale + n * 2.5;
	float band = sin(band_ph) * 0.5 + 0.5;
	float fine = sin(band_ph * 5.3) * 0.5 + 0.5;
	vec3 alb = mix(rock_a.rgb, rock_b.rgb, band * 0.75 + fine * 0.25);
	alb *= 0.85 + 0.3 * n2;
	// Darker toward the ground (shade + wind polish), dust on upward faces.
	alb = mix(rock_dark.rgb, alb, smoothstep(ground_y - 2.0, ground_y + 25.0, wh));
	alb = mix(alb, dust.rgb, smoothstep(0.55, 0.85, dot(wnorm, up)) * 0.75);

	// Grooves along the strata tilt the normal up and down a little.
	vec3 nw = normalize(wnorm + up * cos(band_ph * 5.3) * 0.12);
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	ALBEDO = alb;
	ROUGHNESS = 0.88;
	SPECULAR = 0.35;
	EMISSION = alb * dusk_color.rgb * dusk_strength * smoothstep(0.25, -0.35, dot(up, normalize(sun_dir)));
}
