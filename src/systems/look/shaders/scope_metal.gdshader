shader_type spatial;
// The rifle scope's metal (issue #229): hard-anodised black, not plastic.
// - Anodise: a fine mottle in colour and roughness, so the tube catches light
//   unevenly the way a real finish does.
// - Knurl: diamond knurling (turret caps, the eyepiece's focus ring), in UV:
//   u round the part, v along it. Bumped, with bright worn tips.
// - Grooves: rings cut round the part every `groove` of v (the power ring).
// - Edge wear: lighter metal where the noise is high on a knurled or grooved part.
// Back faces cull, so aimed in, the open tube is see-through round the reticle
// (GunSights hides the outside hardware then, or it would show through).
// Aimed in, the parts left in view are pinned to the eye (viewmodel_pin).

render_mode skip_vertex_transform;

#include "res://src/systems/look/shaders/viewmodel_pin.gdshaderinc"

uniform vec4 base : source_color = vec4(0.045, 0.045, 0.05, 1.0);
uniform float roughness = 0.42;
uniform float metallic = 0.55;
uniform float knurl = 0.0;          // diamonds round the part (0 = smooth)
uniform float groove = 0.0;         // grooves along the part (0 = none)
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;

varying vec3 lpos;

void vertex() {
	lpos = VERTEX;
	mat4 mv = pin_modelview(MODELVIEW_MATRIX);
	VERTEX = (mv * vec4(VERTEX, 1.0)).xyz;
	NORMAL = normalize(mat3(mv) * NORMAL);
	TANGENT = normalize(mat3(mv) * TANGENT);
	BINORMAL = normalize(mat3(mv) * BINORMAL);
}

void fragment() {
	float n = texture(noise_tex, lpos.xy * 30.0 + lpos.z * 7.0).r;
	float n2 = texture(noise_tex, lpos.zy * 90.0).r;
	vec3 col = base.rgb * (0.85 + 0.3 * n);
	float rough = roughness + (n2 - 0.5) * 0.12;
	vec2 slope = vec2(0.0);
	float tip = 0.0;
	if (knurl > 0.0) {
		float a = UV.x * knurl + UV.y * knurl * 0.5;
		float b = UV.x * knurl - UV.y * knurl * 0.5;
		float da = abs(fract(a) - 0.5);
		float db = abs(fract(b) - 0.5);
		float h = min(da, db);          // 0 in the cut lines, 0.5 at a diamond's centre
		tip = smoothstep(0.32, 0.5, h);
		slope += vec2(sign(fract(a) - 0.5) + sign(fract(b) - 0.5), sign(fract(a) - 0.5) - sign(fract(b) - 0.5))
				* (1.0 - smoothstep(0.0, 0.12, h)) * 0.6;
		col *= 0.75 + 0.35 * smoothstep(0.05, 0.25, h);
	}
	if (groove > 0.0) {
		float g = abs(fract(UV.y * groove) - 0.5);
		col *= 0.7 + 0.3 * smoothstep(0.1, 0.25, g);
		slope.y += sign(fract(UV.y * groove) - 0.5) * (1.0 - smoothstep(0.1, 0.2, g)) * 0.5;
		tip = max(tip, smoothstep(0.42, 0.5, g) * 0.6);
	}
	float worn = tip * smoothstep(0.45, 0.75, n);
	col = mix(col, vec3(0.32, 0.32, 0.34), worn * 0.6);
	rough = mix(rough, 0.25, worn);

	ALBEDO = col;
	METALLIC = metallic;
	ROUGHNESS = clamp(rough, 0.15, 1.0);
	NORMAL_MAP = normalize(vec3(-slope.x, -slope.y, 1.0)) * 0.5 + 0.5;
	RIM = 0.12;
	RIM_TINT = 0.6;
}
