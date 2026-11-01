shader_type canvas_item;
// The cockpit's dash leaning away from you: CockpitDash paints the panel flat, into
// a texture, and this draws it back over the screen in perspective. The bottom
// edge stays where it is; higher up the panel is further off, so it shrinks toward
// the middle and its rows crowd together. CockpitView.project() is the same map
// forward; this is its inverse, worked per pixel.

uniform sampler2D panel : filter_linear, repeat_disable;
uniform float tilt = 1.0;          // how fast the panel recedes (CockpitView.TILT)
uniform vec2 screen = vec2(1920.0, 1080.0);
uniform float margin = 0.0;        // px of panel either side of the screen
uniform float top = 700.0;         // panel y of the texture's top row

void fragment() {
	vec2 s = UV * screen;
	float up = (screen.y - s.y) / screen.y;
	float den = 1.0 - tilt * up;
	COLOR = vec4(0.0);
	if (den > 0.0) {
		float v = up / den;
		float z = 1.0 + tilt * v;
		vec2 p = vec2(screen.x * 0.5 + (s.x - screen.x * 0.5) * z, screen.y * (1.0 - v));
		vec2 t = vec2((p.x + margin) / (screen.x + 2.0 * margin), (p.y - top) / (screen.y - top));
		if (t.x >= 0.0 && t.x <= 1.0 && t.y >= 0.0 && t.y <= 1.0) {
			COLOR = texture(panel, t);
		}
	}
}
