shader_type spatial;
// The additive parts of an explosion (ExplosionFx): the first flash, the shock ring,
// and the sparks. Drawn by a CPUParticles3D; colour from its ramp, times `energy`
// so the scene's glow blooms it.
//   shape 0: a soft round flash, facing the camera
//   shape 1: a thin ring that thins out as it grows, facing the camera
//   shape 2: as the mesh is (a spark's thin box, stretched along its flight)
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform int shape = 0;
uniform float energy = 4.0;

varying float v_age;             // INSTANCE_CUSTOM.y, which fragment() cannot read

void vertex() {
	v_age = INSTANCE_CUSTOM.y;
	if (shape != 2) {
		mat4 w = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = VIEW_MATRIX * w;
		MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	}
}

void fragment() {
	float age = v_age;
	float r = length(UV - 0.5) * 2.0;
	float a = 1.0;
	if (shape == 0) {
		a = pow(clamp(1.0 - r, 0.0, 1.0), 1.6);
	} else if (shape == 1) {
		float w = mix(0.22, 0.04, age);
		a = 1.0 - smoothstep(0.0, w, abs(r - (0.96 - w)));
		a *= (1.0 - age) * (1.0 - age);
	}
	ALBEDO = COLOR.rgb * energy;
	ALPHA = a * COLOR.a;
}
