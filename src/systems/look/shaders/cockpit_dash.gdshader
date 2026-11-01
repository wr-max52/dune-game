shader_type spatial;
// The cockpit's dash (CockpitView.dash_mesh): a darker shade of the ship's skin,
// lit by the real lights, with CockpitDash's painted instruments laid on it.
// Where the paint is, the surface is glass over the dials: not metal, smoother,
// and lit from behind as well (EMISSION), so the dials read in any light.

uniform vec3 skin : source_color = vec3(0.26, 0.28, 0.3);
uniform float skin_metallic = 0.85;
uniform float skin_roughness = 0.32;
uniform sampler2D panel : source_color, filter_linear, repeat_disable;
uniform float backlight = 1.0;

void fragment() {
	vec4 p = texture(panel, UV);
	ALBEDO = mix(skin, p.rgb * 0.3, p.a);
	METALLIC = mix(skin_metallic, 0.0, p.a);
	ROUGHNESS = mix(skin_roughness, 0.18, p.a);
	SPECULAR = 0.5;
	EMISSION = p.rgb * p.a * backlight;
}
