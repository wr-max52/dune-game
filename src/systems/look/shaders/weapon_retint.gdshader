shader_type spatial;
// Retints a palette-atlas model (Kenney's colormap) into a worn, desert-used
// palette: luminance drives a gunmetal ramp, saturated toy colours become the
// accent (leather / paint), and a little edge wear lifts the highlights.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec3 dark : source_color = vec3(0.09, 0.09, 0.1);
uniform vec3 light : source_color = vec3(0.42, 0.41, 0.4);
uniform vec3 accent : source_color = vec3(0.48, 0.34, 0.21);
uniform float grime = 0.35;

varying vec3 obj_pos;

void vertex() {
	obj_pos = VERTEX;
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb;
	float l = dot(c, vec3(0.3, 0.59, 0.11));
	float sat = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
	float is_accent = smoothstep(0.25, 0.5, sat);
	vec3 metal = mix(dark, light, smoothstep(0.05, 0.95, l));
	vec3 col = mix(metal, accent * (0.55 + 0.6 * l), is_accent);
	float speck = hash(floor(obj_pos * 60.0));
	col *= 1.0 - grime * 0.35 * speck;
	ALBEDO = col;
	METALLIC = mix(0.65, 0.05, is_accent);
	ROUGHNESS = mix(0.42, 0.78, is_accent) + 0.15 * speck;
}
