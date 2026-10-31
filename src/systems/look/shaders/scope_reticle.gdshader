shader_type spatial;
// The rifle scope's reticle (issue #229): lit, unshaded, drawn over everything
// (no depth test) so the glass never hides it. Aimed in, pinned to the eye
// (viewmodel_pin): a millimetre of drift here is pixels on screen.
render_mode unshaded, cull_disabled, depth_test_disabled, skip_vertex_transform;

#include "res://src/systems/look/shaders/viewmodel_pin.gdshaderinc"

uniform vec4 color : source_color = vec4(1.0, 0.165, 0.102, 1.0);
uniform float energy = 3.0;

void vertex() {
	VERTEX = (pin_modelview(MODELVIEW_MATRIX) * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ALBEDO = color.rgb;
	EMISSION = color.rgb * energy;
	ALPHA = 1.0;
}
