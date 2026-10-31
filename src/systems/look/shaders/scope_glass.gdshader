shader_type spatial;
// The rifle scope's lenses (issue #229): faint glass, so the front one reads from
// outside and neither tints the view; the objective's coating adds a rim sheen.
// Aimed in, pinned to the eye (viewmodel_pin).
render_mode blend_mix, skip_vertex_transform;

#include "res://src/systems/look/shaders/viewmodel_pin.gdshaderinc"

uniform vec4 tint : source_color = vec4(0.4, 0.7, 0.75, 0.1);
uniform float metallic = 0.0;
uniform float rim = 0.0;

void vertex() {
	mat4 mv = pin_modelview(MODELVIEW_MATRIX);
	VERTEX = (mv * vec4(VERTEX, 1.0)).xyz;
	NORMAL = normalize(mat3(mv) * NORMAL);
}

void fragment() {
	ALBEDO = tint.rgb;
	ALPHA = tint.a;
	METALLIC = metallic;
	ROUGHNESS = 0.03;
	SPECULAR = 1.0;
	RIM = rim;
	RIM_TINT = 1.0;
}
