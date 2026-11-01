shader_type spatial;
// The beast's shell: weathered desert rock, not shiny chitin. Like rock.gdshader
// (wind-cut strata, pits, crevices, sand on what faces up), but measured in the
// mesh's own space so the stone sticks to a body that walks. Each segment is a
// scaled sphere: strata run across it, cracks and pits cover it, sand settles
// on its back and in the cracks, and the belly is darker.

uniform vec4 rock_a : source_color = vec4(0.47, 0.36, 0.26, 1.0);
uniform vec4 rock_b : source_color = vec4(0.66, 0.52, 0.36, 1.0);
uniform vec4 rock_dark : source_color = vec4(0.20, 0.15, 0.11, 1.0);
uniform vec4 dust : source_color = vec4(0.86, 0.70, 0.50, 1.0);
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float scale = 1.0;           // noise repeats per metre of the mesh
uniform float strata = 3.0;          // bands per metre, across the body
uniform float cracks = 1.0;          // how cut up it is (0 = smooth stone)
uniform float bump = 1.0;            // how lumpy the surface is
uniform float dust_amount = 1.0;
// On the home planet's ball, "up" (for the sand on its back) is away from the
// centre; 0 radius = flat ground, straight up.
uniform vec3 planet_center = vec3(0.0);
uniform float planet_radius = 0.0;

varying vec3 lpos;
varying vec3 lnorm;
varying vec3 wnorm;
varying vec3 wup;

void vertex() {
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	lpos = VERTEX * sc;               // metres, so a big segment and a small leg share a grain
	lnorm = NORMAL;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wup = planet_radius > 0.0 ? normalize(wpos - planet_center) : vec3(0.0, 1.0, 0.0);
}

// Noise on the three planes, blended by the face's direction (no stretch).
float tri(vec3 p, vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	return texture(noise_tex, p.yz).r * w.x + texture(noise_tex, p.xz).r * w.y + texture(noise_tex, p.xy).r * w.z;
}

void fragment() {
	vec3 n = normalize(lnorm);
	vec3 p = lpos * scale;
	float big = tri(p * 0.06, n);
	float mid = tri(p * 0.21 + 3.7, n);
	float fine = tri(p * 0.9 + 11.0, n);

	// Strata across the body (local y, warped), like the mesas' sandstone.
	float band_ph = lpos.y * strata + big * 6.0 + mid * 1.5;
	float band = sin(band_ph) * 0.5 + 0.5;
	float thin = sin(band_ph * 4.1) * 0.5 + 0.5;
	vec3 alb = mix(rock_a.rgb, rock_b.rgb, band * 0.7 + thin * 0.3);
	alb *= 0.78 + 0.44 * mid;

	// Cracks: thin dark lines where the mid noise crosses its middle; pits where
	// the fine noise dips.
	float crack = (1.0 - smoothstep(0.0, 0.035, abs(mid - 0.5))) * cracks;
	crack = max(crack, (1.0 - smoothstep(0.0, 0.02, abs(big - 0.48))) * cracks * 0.8);
	float pit = smoothstep(0.38, 0.22, fine) * cracks;
	alb = mix(alb, rock_dark.rgb, clamp(crack * 0.85 + pit * 0.45, 0.0, 1.0));

	// Darker underneath (shade and wear), sand on its back and caught in cracks.
	alb = mix(rock_dark.rgb * 1.3, alb, smoothstep(-0.75, 0.15, n.y));
	vec3 nw = normalize(wnorm);
	float on_top = smoothstep(0.35, 0.85, dot(nw, normalize(wup)));
	float sand = on_top * smoothstep(0.35, 0.65, big + fine * 0.35) * 0.8 + crack * on_top * 0.4;
	alb = mix(alb, dust.rgb, clamp(sand * dust_amount, 0.0, 0.85));

	// Lumps and the strata's grooves in the normal (from the noise's slope, in
	// the mesh's space, then turned to view space).
	float e = 0.02;
	vec3 g = vec3(
		tri(p * 0.21 + 3.7 + vec3(e, 0.0, 0.0), n) - mid,
		tri(p * 0.21 + 3.7 + vec3(0.0, e, 0.0), n) - mid,
		tri(p * 0.21 + 3.7 + vec3(0.0, 0.0, e), n) - mid) / e;
	vec3 gf = vec3(
		tri(p * 0.9 + 11.0 + vec3(e, 0.0, 0.0), n) - fine,
		tri(p * 0.9 + 11.0 + vec3(0.0, e, 0.0), n) - fine,
		tri(p * 0.9 + 11.0 + vec3(0.0, 0.0, e), n) - fine) / e;
	vec3 tilt = (g * 0.10 + gf * 0.03) * bump + vec3(0.0, cos(band_ph * 4.1) * 0.10 * bump, 0.0);
	tilt -= n * dot(tilt, n);
	vec3 ln = normalize(n - tilt);
	vec3 wn = normalize((MODEL_MATRIX * vec4(ln, 0.0)).xyz);
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	ALBEDO = alb;
	ROUGHNESS = mix(0.82, 0.97, clamp(sand, 0.0, 1.0));
	SPECULAR = 0.3;
	AO = 1.0 - clamp(crack * 0.6 + pit * 0.3, 0.0, 0.8);
	AO_LIGHT_AFFECT = 0.5;
}
