// Landing-pad metal: one recipe for every pad's plate (the port's pit and bays,
// the stations' pits, the cruiser's hangar). The plate is laid in rings of
// welded sectors round a central hatch, each sector its own tone, rivets along
// the ring seams, chequer tread on the r_out rings, soot where the engines sit
// and grime in the seams. Past the round plate (a square pad's corners) it is
// square tread plates on a 2 m grid.
//
// The includer declares `noise_tex` (a repeating noise texture) before this file.
// p: metres across the plate from its centre; edge: the round plate's radius.

float pm_hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 15731.743);
}

// Chequer plate: a raised bar in every 0.16 m cell, alternate cells at right
// angles, both at 45 degrees. 0 on the flat, 1 on top of a bar.
float pm_tread(vec2 q) {
	float cell = 0.16;
	vec2 c = floor(q / cell);
	vec2 f = fract(q / cell) - 0.5;
	vec2 d = vec2(f.x + f.y, f.x - f.y) * 0.7071;
	if (mod(c.x + c.y, 2.0) > 0.5) {
		d = d.yx;
	}
	float dist = length(vec2(max(abs(d.x) - 0.22, 0.0), d.y));
	return 1.0 - smoothstep(0.05, 0.1, dist);
}

// Fills the plate's colour, roughness and metallic, and `slope`: the tread's
// height change per metre in x and z (for the caller's normal).
void pad_metal(vec2 p, float edge, vec3 c_steel, vec3 c_grime, float soot_k,
		vec3 c_dust, float dust_k,
		out vec3 col, out float rough, out float metal, out vec2 slope) {
	float r = length(p);
	float ang = atan(p.y, p.x);
	float ring_r[4] = float[](0.0, 0.26, 0.58, 0.86);
	float sectors[4] = float[](1.0, 8.0, 16.0, 24.0);
	float band = 0.0;
	for (int i = 1; i < 4; i++) {
		band += step(ring_r[i] * edge, r);
	}
	int bi = int(band);
	float r_in = ring_r[bi] * edge;
	float r_out = bi < 3 ? ring_r[bi + 1] * edge : edge;
	float k = sectors[bi];
	float sec = floor((ang / 6.28318 + 0.5) * k);
	vec2 plate_id = vec2(band, sec);
	bool square = r > edge;
	vec2 sq = floor(p / 2.0);
	if (square) {
		plate_id = sq + vec2(17.0, 5.0);
	}

	// Seams: between rings, between sectors (in metres of arc), round the hatch.
	float seam_d;
	if (square) {
		vec2 g = abs(fract(p / 2.0) - 0.5) * 2.0;
		seam_d = (1.0 - max(g.x, g.y)) * 1.0;
	} else {
		float arc = abs(fract((ang / 6.28318 + 0.5) * k + 0.5) - 0.5) / k * 6.28318 * r;
		seam_d = min(r - r_in, r_out - r);
		if (bi > 0) {
			seam_d = min(seam_d, arc);
		}
	}
	float seam_k = 1.0 - smoothstep(0.015, 0.045, seam_d);

	// Rivets: a row just inside each ring seam, one every 0.4 m of arc.
	float rivet = 0.0;
	if (!square && bi > 0) {
		for (int s = 0; s < 2; s++) {
			float rr = s == 0 ? r_in + 0.12 : r_out - 0.12;
			float n_r = max(floor(6.28318 * rr / 0.4), 1.0);
			float a = (fract((ang / 6.28318 + 0.5) * n_r) - 0.5) / n_r * 6.28318 * rr;
			rivet = max(rivet, 1.0 - smoothstep(0.022, 0.034, length(vec2(r - rr, a))));
		}
	}

	// Per-plate tone; now and then a newer plate, brighter and less worn.
	float h = pm_hash(plate_id);
	float fresh = step(0.86, h);
	float n = texture(noise_tex, p * 0.09).r;
	float n_fine = texture(noise_tex, p * 0.7 + plate_id * 0.31).r;
	col = c_steel * (0.82 + h * 0.22 + fresh * 0.12) * (0.92 + n_fine * 0.12);
	// Brushing: fine streaks along each sector (round the ring), across the hatch.
	vec2 brush_dir = bi == 0 || square ? vec2(1.0, 0.0) : vec2(-sin(ang), cos(ang));
	float along = dot(p, brush_dir);
	float across = dot(p, vec2(-brush_dir.y, brush_dir.x));
	float brush = texture(noise_tex, vec2(along * 0.05, across * 4.0) + h).r;
	col *= 0.94 + brush * 0.1;
	rough = 0.38 + brush * 0.12 + (1.0 - fresh) * 0.06;
	metal = 0.78;

	// Tread on the r_out two rings and the square corners: the flats between the
	// bars hold grime, the bar tops are rubbed bright. Faded out where the bars
	// get smaller than a pixel, so it never shimmers.
	slope = vec2(0.0);
	float tread_on = (bi >= 2 || square) ? 1.0 : 0.0;
	float px = max(fwidth(p.x), fwidth(p.y));
	tread_on *= 1.0 - smoothstep(0.03, 0.08, px);
	if (tread_on > 0.0) {
		float t = pm_tread(p);
		float e = 0.012;
		slope = vec2(pm_tread(p + vec2(e, 0.0)) - pm_tread(p - vec2(e, 0.0)),
			pm_tread(p + vec2(0.0, e)) - pm_tread(p - vec2(0.0, e))) / (2.0 * e) * 0.012 * tread_on;
		col = mix(col, col * mix(0.72, 1.18, t), tread_on);
		rough = mix(rough, mix(0.62, 0.3, t), tread_on);
	}

	// Seams and rivets.
	col = mix(col, c_grime * 0.6, seam_k * 0.85);
	rough = mix(rough, 0.85, seam_k);
	col = mix(col, c_steel * 1.25, rivet * 0.8);
	rough = mix(rough, 0.3, rivet);

	// Grime: patchy, worse in the seams' lee; soot in a blotchy ring round the
	// centre where engines blast it; wear brightens the busiest walk lines.
	float blot = smoothstep(0.45, 0.85, texture(noise_tex, p * 0.035 + 3.7).r);
	col = mix(col, c_grime, blot * 0.35 * (1.0 - fresh));
	rough = mix(rough, 0.8, blot * 0.4);
	float sn = texture(noise_tex, p * 0.06 + 11.0).r;
	float soot = (1.0 - smoothstep(edge * 0.2, edge * 0.75 + sn * edge * 0.3, r)) * soot_k;
	col = mix(col, vec3(0.045, 0.04, 0.038), soot * (0.55 + sn * 0.35));
	rough = mix(rough, 0.75, soot * 0.6);
	metal = mix(metal, 0.4, soot * 0.6);

	// Dust blown on from outside, thickest at the rim and in the low spots.
	float dn = texture(noise_tex, p * 0.05 + 23.0).r;
	float drift = smoothstep(edge * 0.55, edge * 1.02, r + dn * edge * 0.35) * dust_k;
	drift = max(drift, smoothstep(0.62, 0.9, dn) * dust_k * 0.5);
	col = mix(col, c_dust, drift * (0.6 + seam_k * 0.4));
	rough = mix(rough, 0.95, drift);
	metal = mix(metal, 0.0, drift);
}

// The normal from `slope` on a plate's top face, for a fragment() that has
// MODEL_MATRIX and VIEW_MATRIX (local y is the plate's up).
vec3 pad_metal_normal(vec2 slope, mat4 model, mat4 view) {
	vec3 nl = normalize(vec3(-slope.x, 1.0, -slope.y));
	return normalize((view * model * vec4(nl, 0.0)).xyz);
}
