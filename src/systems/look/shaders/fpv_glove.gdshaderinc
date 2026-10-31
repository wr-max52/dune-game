// First person sleeves and gloves (issue #229). They fill the bottom of the frame,
// closer than anything else, so flat black reads as a hole in the screen.
// - Grain: pebbled leather bumps (gloves), in the mesh's UV metres.
// - Weave: fine knit ribs running round the sleeve, a twill across them.
// - Stitch: a dashed seam at uv.x = stitch_u (down the inside of the sleeve) and
//   a ring of it above a cuff's hem. UVs are metres (FpvArms builds them).
// - Wear: lighter, glossier scuffs (knuckles, the cuff's edge) from object-space
//   noise, so each piece wears differently.
// - Sheen: a soft rim so the shape reads against a dark background.
// - FADE (fpv_glove_fade.gdshader, the upper arm only): faded out near the eye
//   (near_fade) and along the piece's own -Y (len_fade: whole by the elbow, gone a
//   hand's width up), so only its elbow end shows and nothing looms at the lens.

uniform vec4 base : source_color = vec4(0.07, 0.065, 0.06, 1.0);
uniform vec4 thread : source_color = vec4(0.17, 0.155, 0.135, 1.0);
uniform float roughness = 0.6;
uniform float sheen = 0.3;
uniform float grain = 0.0;
uniform float weave = 0.0;
uniform float stitch = 0.0;
uniform float stitch_u = 0.0;
uniform float stitch_rings = 0.0;     // > 0: v of a ring of stitches near each end
uniform float length_v = 0.0;         // the piece's v length (for the far ring)
uniform float wear = 0.4;
uniform float spec = 0.45;            // cloth wants little: a low sun ahead made sleeves glow tan
uniform float fill = 0.0;             // self-light (off: with the rim it read as bare skin)
#ifdef FADE
uniform vec2 near_fade = vec2(0.0);   // gone at .x metres from the eye, whole from .y (0 = off)
uniform vec2 len_fade = vec2(0.0);    // whole below local y = .x, gone above .y (0 = off)
#endif
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;

varying vec3 lpos;

void vertex() {
	lpos = VERTEX;
}

float grain_h(vec2 uv) {
	return texture(noise_tex, uv * 9.0).r * 0.6 + texture(noise_tex, uv * 23.0 + vec2(0.37, 0.11)).r * 0.4;
}

void fragment() {
	vec2 uv = UV;
	vec3 col = base.rgb;
	float rough = roughness;
	vec2 slope = vec2(0.0);

	if (grain > 0.0) {
		float e = 0.0015;
		float h0 = grain_h(uv);
		slope += vec2(grain_h(uv + vec2(e, 0.0)) - h0, grain_h(uv + vec2(0.0, e)) - h0) / e * 0.0009 * grain;
		col *= 0.9 + 0.2 * h0;
		rough -= 0.12 * h0 * grain;
	}
	if (weave > 0.0) {
		// Fades out as a rib gets near a pixel wide, so it never shimmers.
		float px = max(fwidth(uv.y * 1300.0), fwidth((uv.x + uv.y) * 2100.0)) / 6.2832;
		float fade = 1.0 - smoothstep(0.06, 0.18, px);
		float rib = sin(uv.y * 1300.0);
		float twill = sin((uv.x + uv.y) * 2100.0);
		slope += vec2(0.25 * twill, cos(uv.y * 1300.0) + 0.25 * twill) * 0.2 * weave * fade;
		col *= 1.0 + 0.04 * rib * twill * fade;
	}

	// Scuffs: lighter, slightly shinier patches.
	float n = texture(noise_tex, lpos.xy * 14.0).r * 0.5 + texture(noise_tex, lpos.zy * 14.0 + vec2(0.5)).r * 0.5;
	float scuff = smoothstep(0.68, 0.9, n) * wear;
	col = mix(col, col * 1.45 + vec3(0.018, 0.015, 0.012), scuff);
	rough -= 0.15 * scuff;

	float st = 0.0;
	if (stitch > 0.0) {
		float d = abs(uv.x - stitch_u);
		float dash = step(0.45, fract(uv.y * 160.0));
		st = (1.0 - smoothstep(0.0009, 0.0018, d)) * dash;
		if (stitch_rings > 0.0) {
			float dr = abs(uv.y - (length_v - stitch_rings));
			float ring_dash = step(0.45, fract(uv.x * 160.0));
			st = max(st, (1.0 - smoothstep(0.0007, 0.0015, dr)) * ring_dash);
		}
		st *= stitch;
	}
	col = mix(col, thread.rgb, st);

	ALBEDO = col;
	EMISSION = col * fill;
	ROUGHNESS = clamp(rough, 0.2, 1.0);
	METALLIC = 0.0;
	SPECULAR = spec;
	NORMAL_MAP = normalize(vec3(-slope.x, -slope.y, 1.0)) * 0.5 + 0.5;
	RIM = sheen;
	RIM_TINT = 0.4;
#ifdef FADE
	float show = 1.0;
	if (near_fade.y > 0.0) {
		show *= smoothstep(near_fade.x, near_fade.y, -VERTEX.z);
	}
	if (len_fade.x != len_fade.y) {
		show *= 1.0 - smoothstep(len_fade.x, len_fade.y, lpos.y);
	}
	ALPHA = show;
#endif
}
