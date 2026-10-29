shader_type spatial;
render_mode cull_disabled;
// Wreck-only finish. No emission, flames or live engine lights.
// Weather is in the cruiser frame, not world Y or each individual plate:
// damage stays coherent across the leaning hull and never recolours the town.
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform mat4 wreck_from_world;
uniform int finish = 0; // 0 hull, 1 exposed metal, 2 soot, 3 faded marking, 4 nozzle
varying vec3 hull_pos;
varying vec3 hull_normal;
varying vec3 plate_pos;
varying vec3 plate_normal;

void vertex() {
	hull_pos = (wreck_from_world * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	hull_normal = normalize((wreck_from_world * MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	plate_pos = VERTEX;
	plate_normal = NORMAL;
}

float grain(vec3 p, float scale) {
	vec3 n = abs(normalize(hull_normal));
	n /= max(n.x + n.y + n.z, 0.001);
	return texture(noise_tex, p.yz * scale).r * n.x
		+ texture(noise_tex, p.xz * scale + 0.31).r * n.y
		+ texture(noise_tex, p.xy * scale + 0.67).r * n.z;
}

void fragment() {
	vec3 p = hull_pos;
	float broad = grain(p, 0.002);
	float medium = grain(p + 71.0, 0.012);
	float fine = grain(p, 0.14);
	vec3 an = abs(plate_normal);
	vec2 uv = plate_pos.yz;
	if (an.y > an.x && an.y > an.z) { uv = plate_pos.xz; }
	else if (an.z > an.x) { uv = plate_pos.xy; }
	vec2 panel = abs(fract(uv / vec2(7.5, 11.0)) - 0.5);
	float seam = smoothstep(0.478, 0.497, max(panel.x, panel.y));
	float panel_tone = texture(noise_tex, floor(uv / vec2(7.5, 11.0)) * 0.173).r;
	vec3 steel = mix(vec3(0.115, 0.13, 0.15), vec3(0.23, 0.25, 0.27), panel_tone);
	vec3 paint = vec3(0.29, 0.315, 0.33);
	float chips = smoothstep(0.53, 0.70, medium + fine * 0.06 + seam * 0.12);
	vec3 colour = mix(paint, steel, chips);
	// Heat-peeled paint, irregular black impact stains and rust in plate seams.
	float breach = (1.0 - smoothstep(78.0, 140.0, abs(p.z))) * smoothstep(15.0, 40.0, p.x);
	float scorch = smoothstep(0.49, 0.7, broad + medium * 0.08) * 0.65;
	scorch = max(scorch, breach * (0.35 + smoothstep(0.32, 0.64, medium) * 0.60));
	float oxide = smoothstep(0.54, 0.68, medium) * (0.09 + seam * 0.45) * (1.0 - scorch);
	colour = mix(colour, vec3(0.25, 0.12, 0.065), oxide * 0.65);
	colour *= 1.0 - seam * 0.6;
	colour = mix(colour, vec3(0.055, 0.052, 0.05), scorch);
	// Fine scored streaks, kept subtle so the broad forms still read at distance.
	float scores = smoothstep(0.77, 0.9, texture(noise_tex, uv * vec2(2.0, 0.045)).r);
	colour = mix(colour, steel * 1.35, scores * chips * 0.22);
	if (finish == 1) { colour = mix(steel * 1.35, vec3(0.08, 0.075, 0.07), scorch * 0.65); }
	if (finish == 2) { colour = mix(vec3(0.045, 0.042, 0.04), colour, 0.15); }
	if (finish == 3) { colour = mix(vec3(0.25, 0.065, 0.045), steel, chips * 0.65); }
	if (finish == 4) { colour = mix(vec3(0.025, 0.028, 0.033), vec3(0.09, 0.095, 0.10), fine); }
	// Sand only gathers on exposed upward faces, never coats every hull plate.
	float dust = smoothstep(0.5, 0.93, hull_normal.y) * (0.09 + medium * 0.12);
	colour = mix(colour, vec3(0.63, 0.46, 0.27), dust);
	ALBEDO = colour;
	METALLIC = (finish == 4 ? 0.24 : mix(0.2, 0.65, chips)) * (1.0 - scorch * 0.8);
	ROUGHNESS = clamp(0.72 + scorch * 0.24 + oxide * 0.12 - chips * 0.12, 0.0, 1.0);
}
