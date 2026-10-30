shader_type spatial;
// Issue #193: the Remnant star cruiser, clean. One shader for every surface it is
// made of, picked by `finish`; the meshes are in the cruiser's own frame (x to
// starboard, y up, z bow to stern), so panels and window rows line up with the ship.
//   0 hull     light grey armour plates, seams, a little tone per plate, and rows
//              of small lit windows along the flanks (they make its size legible)
//   1 trim     dark grey bands, frames, turrets
//   2 deck     dark deck plates on a 2 m grid with lit seams near the edges
//   3 wall     panelled bulkheads
//   4 grate    walkway grating
//   5 ramp     deck with cleats across it
//   6 cargo    crates, stencilled, in drab colours
//   7 console  dark panels with small lit keys
//   8 rail     dark rails with a little safety yellow in them
//   9 bridge   polished dark floor with inlaid light lines
//  10 pad      a landing pad: painted ring and cross, edge lights (plate_half)
//  11 beacon   a red light that blinks

uniform int finish = 0;
uniform vec4 hull_color : source_color = vec4(0.55, 0.58, 0.62, 1.0);
uniform vec4 trim_color : source_color = vec4(0.22, 0.23, 0.25, 1.0);
uniform vec4 deck_color : source_color = vec4(0.17, 0.18, 0.20, 1.0);
uniform vec4 wall_color : source_color = vec4(0.40, 0.42, 0.45, 1.0);
uniform vec4 accent : source_color = vec4(0.62, 0.10, 0.08, 1.0);
uniform vec4 window_light : source_color = vec4(1.0, 0.86, 0.62, 1.0);
uniform vec4 strip_light : source_color = vec4(0.55, 0.85, 1.0, 1.0);
uniform vec4 paint : source_color = vec4(0.95, 0.78, 0.22, 1.0);
uniform vec3 plate_half = vec3(10.0, 0.05, 10.0);
uniform float window_energy = 2.2;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;

varying vec3 lpos;
varying vec3 lnorm;

void vertex() {
	lpos = VERTEX;
	lnorm = NORMAL;
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// The two coordinates across the face (cheap triplanar on the local normal).
vec2 face_uv(vec3 p, vec3 n) {
	vec3 a = abs(n);
	if (a.x > a.y && a.x > a.z) return p.zy;
	if (a.z > a.y) return p.xy;
	return p.xz;
}

float seam(vec2 uv, vec2 size, float w) {
	vec2 g = abs(fract(uv / size) - 0.5) * size;
	vec2 e = size * 0.5 - g;
	return 1.0 - smoothstep(0.0, w, min(e.x, e.y));
}

void fragment() {
	vec2 uv = face_uv(lpos, lnorm);
	float n = texture(noise_tex, uv * 0.013).r;
	vec3 col = hull_color.rgb;
	float rough = 0.55;
	float metal = 0.55;
	vec3 emit = vec3(0.0);
	if (finish == 0) {
		// Staggered armour plates, each its own tone, seams between them.
		vec2 size = vec2(6.0, 3.2);
		vec2 st = uv;
		st.x += step(0.5, fract(st.y / (size.y * 2.0))) * size.x * 0.5;
		vec2 cell = floor(st / size);
		float tone = hash2(cell);
		col = hull_color.rgb * (0.86 + tone * 0.2) * (0.92 + n * 0.14);
		col *= 1.0 - 0.55 * seam(st, size, 0.07);
		// Trenches every 24 m along the keel.
		float trench = 1.0 - smoothstep(0.0, 0.35, (0.5 - abs(fract(lpos.z / 24.0) - 0.5)) * 24.0);
		col *= 1.0 - 0.35 * trench;
		rough = 0.5 + tone * 0.15;
		// A few rows of small windows along the flanks and shoulders, some lit: in
		// bands of three decks with plain armour between, so from afar they read as
		// lines of light, not grit.
		if (abs(lnorm.x) > 0.55 && abs(lnorm.y) < 0.8) {
			vec2 w = vec2(lpos.z, lpos.y);
			vec2 wsize = vec2(3.5, 3.6);
			vec2 wc = floor(w / wsize);
			vec2 wf = fract(w / wsize);
			float pane = step(0.25, wf.x) * step(wf.x, 0.6) * step(0.4, wf.y) * step(wf.y, 0.62);
			float lit = step(0.6, hash2(wc + vec2(lnorm.x > 0.0 ? 3.0 : 7.0, 1.0)));
			float band = step(fract(wc.y / 7.0), 0.4) * step(0.12, fract(wc.x / 9.0));
			emit = window_light.rgb * pane * lit * band * window_energy;
			col = mix(col, vec3(0.05, 0.06, 0.07), pane * band * (1.0 - lit));
		}
	} else if (finish == 1) {
		col = trim_color.rgb * (0.85 + n * 0.25);
		col *= 1.0 - 0.4 * seam(uv, vec2(4.0, 2.0), 0.05);
		rough = 0.45;
		metal = 0.7;
	} else if (finish == 2 || finish == 5) {
		vec2 g = lpos.xz;
		col = deck_color.rgb * (0.9 + n * 0.2) * (0.92 + hash2(floor(g / 2.0)) * 0.12);
		col *= 1.0 - 0.45 * seam(g, vec2(2.0), 0.04);
		rough = 0.7;
		metal = 0.4;
		if (lnorm.y < 0.5) {
			col = trim_color.rgb * 0.8;
		}
		if (finish == 5) {
			float cleat = step(0.82, fract((lpos.y + lpos.z * 0.3 + lpos.x * 0.3) * 1.6));
			col = mix(col, paint.rgb * 0.55, cleat * 0.6);
		}
	} else if (finish == 3) {
		col = wall_color.rgb * (0.9 + n * 0.15);
		col *= 1.0 - 0.45 * seam(uv, vec2(3.0, 2.4), 0.04);
		rough = 0.6;
		metal = 0.45;
	} else if (finish == 4) {
		vec2 g = lpos.xz;
		float slat = step(0.55, fract(g.x * 3.0)) + step(0.55, fract(g.y * 3.0));
		col = mix(vec3(0.12, 0.13, 0.14), vec3(0.30, 0.31, 0.33), clamp(slat, 0.0, 1.0));
		rough = 0.6;
		metal = 0.7;
	} else if (finish == 6) {
		vec3 c = floor(lpos / 3.0);
		float h = hash2(c.xz + c.y);
		col = mix(vec3(0.30, 0.32, 0.26), vec3(0.42, 0.40, 0.36), h) * (0.85 + n * 0.25);
		col *= 1.0 - 0.5 * seam(uv, vec2(1.2, 1.2), 0.04);
		float stencil = step(0.8, fract(uv.x * 0.7 + h)) * step(0.5, fract(uv.y * 0.9));
		col = mix(col, paint.rgb * 0.7, stencil * 0.35);
		rough = 0.8;
		metal = 0.2;
	} else if (finish == 7) {
		col = vec3(0.07, 0.075, 0.085);
		vec2 k = floor(uv * 3.0);
		float key = step(0.86, hash2(k)) * step(0.3, fract(uv.x * 3.0)) * step(0.3, fract(uv.y * 3.0));
		emit = mix(strip_light.rgb, accent.rgb * 2.0, step(0.5, hash2(k + 9.0))) * key * 1.6;
		rough = 0.6;
		metal = 0.25;
	} else if (finish == 8) {
		col = mix(trim_color.rgb * 0.8, paint.rgb * 0.6, 0.35);
		rough = 0.4;
		metal = 0.8;
	} else if (finish == 9) {
		vec2 g = lpos.xz;
		col = vec3(0.10, 0.105, 0.115) * (0.9 + n * 0.15);
		col *= 1.0 - 0.3 * seam(g, vec2(3.0), 0.03);
		float line = 1.0 - smoothstep(0.04, 0.12, (0.5 - abs(fract(g.x / 7.0) - 0.5)) * 7.0);
		emit = strip_light.rgb * line * 1.2;
		rough = 0.42;
		metal = 0.3;
	} else if (finish == 10) {
		vec2 p = lpos.xz;
		float r = length(p);
		float edge = min(plate_half.x, plate_half.z);
		col = deck_color.rgb * 0.8 * (0.9 + n * 0.2);
		float ring = step(abs(r - edge * 0.78), 0.45);
		float cross_ = (step(abs(p.x), 0.4) + step(abs(p.y), 0.4)) * step(r, edge * 0.55);
		col = mix(col, paint.rgb, clamp(ring + cross_, 0.0, 1.0) * 0.85);
		// Lights round the rim, every 30 degrees.
		float ang = atan(p.y, p.x);
		float dots = step(0.9, fract(ang / 6.2831 * 12.0)) * step(abs(r - edge * 0.93), 0.35);
		emit = strip_light.rgb * dots * 3.0;
		rough = 0.6;
		metal = 0.4;
	} else if (finish == 11) {
		col = accent.rgb;
		emit = vec3(1.0, 0.12, 0.08) * step(0.82, fract(TIME * 0.6)) * 8.0 + vec3(0.4, 0.04, 0.03);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emit;
}
