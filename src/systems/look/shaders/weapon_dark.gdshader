shader_type spatial;
// Dark variant of a textured gun (issue #65): the model's own albedo, normal and
// ORM maps stay, so the detail and wear survive. Neutral (grey) texels are
// multiplied down hard; saturated texels (the painted orange/red glow panels) keep
// most of their colour and get a little emission so they still read as glowing.
// Aimed in through a scope, the barrel left in view is pinned to the eye
// (viewmodel_pin, GunSights.pin).
render_mode skip_vertex_transform;

#include "res://src/systems/look/shaders/viewmodel_pin.gdshaderinc"

// Both sides drawn: where the model is cut open (its old optic and front sight, and
// aimed in the near_clip below) the inside shows as solid dark metal, not a hole
// that reads as a see-through gun.
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool use_normal = false;
uniform bool use_orm = false;
uniform float body_mul : hint_range(0.0, 1.0) = 0.3;     // multiplier on neutral texels
uniform float accent_mul : hint_range(0.0, 1.0) = 0.8;   // multiplier on saturated texels
uniform float glow : hint_range(0.0, 4.0) = 0.6;         // emission on saturated texels
uniform vec3 body_tint : source_color = vec3(0.85, 0.9, 1.0);
// Issue #229: a held gun is near-black, so against the sun or in shade it went to
// a flat silhouette. A rim keeps its outline; fill lifts the body a touch.
uniform float rim : hint_range(0.0, 1.0) = 0.0;
uniform float fill : hint_range(0.0, 1.0) = 0.0;
// Aimed in through a scope (GunSights.scope_view): nearer than this to the eye is
// cut, so the receiver round the open tube goes but the barrel ahead stays. 0 = off.
uniform float near_clip = 0.0;

void vertex() {
	mat4 mv = pin_modelview(MODELVIEW_MATRIX);
	VERTEX = (mv * vec4(VERTEX, 1.0)).xyz;
	NORMAL = normalize(mat3(mv) * NORMAL);
	TANGENT = normalize(mat3(mv) * TANGENT);
	BINORMAL = normalize(mat3(mv) * BINORMAL);
}

void fragment() {
	if (-VERTEX.z < near_clip) {
		discard;
	}
	vec3 c = texture(albedo_tex, UV).rgb;
	float sat = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
	float is_accent = smoothstep(0.2, 0.45, sat);
	vec3 dark = c * body_tint * body_mul;
	vec3 keep = c * accent_mul;
	ALBEDO = mix(dark, keep, is_accent);
	EMISSION = c * glow * is_accent + dark * fill;
	RIM = rim;
	RIM_TINT = 0.35;
	if (use_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
	if (use_orm) {
		vec3 orm = texture(orm_tex, UV).rgb;
		ROUGHNESS = orm.g;
		METALLIC = orm.b * (1.0 - is_accent);
	} else {
		ROUGHNESS = 0.55;
		METALLIC = 0.0;
	}
	if (!FRONT_FACING) {
		ALBEDO = vec3(0.012, 0.012, 0.014);
		EMISSION = vec3(0.0);
		ROUGHNESS = 0.9;
		METALLIC = 0.0;
		RIM = 0.0;
	}
}
