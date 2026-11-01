shader_type spatial;
// A town's landing pad plate (the pit's empty pads, the plates under the ships):
// welded steel, see pad_metal.gdshaderinc. The mesh is centred on the pad.

uniform vec4 steel : source_color = vec4(0.46, 0.47, 0.49, 1.0);
uniform vec4 grime : source_color = vec4(0.16, 0.14, 0.12, 1.0);
uniform vec4 dust : source_color = vec4(0.79, 0.58, 0.35, 1.0);
uniform float dust_amount = 0.5;
uniform float soot_amount = 0.7;
uniform float metal_scale = 1.0;        // issue #45: town styles
uniform float rough_add = 0.0;
uniform float radius = 6.0;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;

#include "res://src/systems/look/shaders/pad_metal.gdshaderinc"

varying vec3 lpos;
varying vec3 lnorm;

void vertex() {
	lpos = VERTEX;
	lnorm = NORMAL;
}

void fragment() {
	vec3 col;
	float rough;
	float metal;
	vec2 slope;
	pad_metal(lpos.xz, radius, steel.rgb, grime.rgb, soot_amount, dust.rgb, dust_amount, col, rough, metal, slope);
	if (lnorm.y > 0.5) {
		NORMAL = pad_metal_normal(slope, MODEL_MATRIX, VIEW_MATRIX);
	} else {
		col *= 0.7;                      // the plate's rim
	}
	ALBEDO = col;
	ROUGHNESS = clamp(rough + rough_add, 0.0, 1.0);
	METALLIC = clamp(metal * metal_scale, 0.0, 1.0);
}
