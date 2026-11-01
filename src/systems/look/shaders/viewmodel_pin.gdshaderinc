// Pinning a first person part to the eye (the scope aimed in).
// Far from the world's origin (the cruiser hangs 11.5 km out) a float holds a
// position only to about a millimetre. The camera and the scope are each rounded
// to that grid, and the GPU's view * model product rounds again, so a scope 11 cm
// from the eye at 2.5x jumped by several pixels a frame as the view turned.
// A part using this takes its model-to-camera transform from the CPU instead
// (pin_x/y/z: the rows of a 3x4, built from small local transforms only), with
// pin_on set; off, it is drawn the usual way. The shader needs
// render_mode skip_vertex_transform and calls pin_vertex() in vertex().

instance uniform vec4 pin_x = vec4(1.0, 0.0, 0.0, 0.0);
instance uniform vec4 pin_y = vec4(0.0, 1.0, 0.0, 0.0);
instance uniform vec4 pin_z = vec4(0.0, 0.0, 1.0, 0.0);
instance uniform float pin_on = 0.0;

mat4 pin_modelview(mat4 modelview) {
	if (pin_on < 0.5) {
		return modelview;
	}
	return mat4(vec4(pin_x.x, pin_y.x, pin_z.x, 0.0), vec4(pin_x.y, pin_y.y, pin_z.y, 0.0),
		vec4(pin_x.z, pin_y.z, pin_z.z, 0.0), vec4(pin_x.w, pin_y.w, pin_z.w, 1.0));
}
