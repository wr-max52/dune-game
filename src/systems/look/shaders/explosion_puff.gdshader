shader_type spatial;
// One puff of an explosion's fireball or smoke (ExplosionFx), drawn on a camera-facing
// quad by a CPUParticles3D. No texture: a lumpy disc of value noise that eats itself
// away from the rim as the puff ages, so it reads as a solid billowing shape with a
// crisp edge rather than a soft blob. The particle's colour ramp carries the
// white-hot -> orange -> red -> soot change; this shader adds the hot core, a dark
// rim and (for smoke) light from above.
//
// INSTANCE_CUSTOM (CPUParticles3D): x = the particle's angle, y = its age 0..1,
// z = its anim offset, used as a steady random seed (ExplosionFx sets it 0..1).
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float erode = 0.75;        // how much of the puff is eaten away by the end of its life
uniform float soft = 0.07;         // edge softness (small = crisp, toon-like)
uniform float energy = 3.0;        // HDR boost while young (the scene's glow picks it up)
uniform float heat = 1.5;          // extra white in the thick middle while young
uniform float shade = 0.0;         // 0 = fire, lit from within; 1 = smoke, lit from above
uniform float lumps = 2.4;         // noise frequency across the puff

varying vec3 v_custom;          // INSTANCE_CUSTOM, which fragment() cannot read

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return s;
}

void vertex() {
	// Face the camera (as StandardMaterial3D's particle billboard), turned by the
	// particle's angle and keeping its scale.
	mat4 w = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	float a = INSTANCE_CUSTOM.x;
	w = w * mat4(vec4(cos(a), -sin(a), 0.0, 0.0), vec4(sin(a), cos(a), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * w;
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	v_custom = INSTANCE_CUSTOM.xyz;
}

void fragment() {
	float age = v_custom.y;
	float seed = v_custom.z * 61.0;
	vec2 c = UV - 0.5;
	float r = length(c) * 2.0;
	// The noise drifts a little as it ages: the puff boils instead of sliding.
	float n = fbm(UV * lumps + vec2(seed, seed * 1.37) + vec2(age * 0.6, -age * 0.9));
	float body = 1.0 - r + (n - 0.5) * 1.1;
	float cut = 0.04 + erode * age * age;
	float a = smoothstep(cut, cut + soft, body);
	if (a <= 0.001) {
		discard;
	}
	float young = 1.0 - smoothstep(0.15, 0.55, age);
	float core = smoothstep(cut + 0.05, cut + 0.6, body);
	vec3 col = COLOR.rgb;
	col *= 1.0 + heat * young * core * core;
	col *= mix(0.55, 1.0, smoothstep(cut, cut + 0.14, body));      // a darker rim
	// Smoke: brighter on top. The quad turns with the particle's angle, so take "up"
	// in the quad's own frame back out of that turn.
	float ang = v_custom.x;
	vec2 up = vec2(sin(ang), -cos(ang));
	float lit = clamp(0.55 + dot(c, up) * 1.4 + (n - 0.5) * 0.7, 0.0, 1.0);
	col *= mix(1.0, mix(0.45, 1.3, lit), shade);
	col *= mix(1.0, energy, young);
	ALBEDO = col;
	ALPHA = a * COLOR.a;
}
