shader_type spatial;
render_mode cull_back;
// The first person upper arm (issue #229): the glove shader, faded with alpha so
// only its elbow end shows. A separate shader so the rest stay opaque.
#define FADE
#include "res://src/systems/look/shaders/fpv_glove.gdshaderinc"
