shader_type canvas_item;

uniform float curvature = 6.0;        // how strong the arc is
uniform float wobble_amplitude = 1.0; // tiny up/down wobble
uniform float wobble_speed = 3.0;
uniform float text_width = 100.0;     // will be set from script

void vertex() {
	// Center X across the entire label: -1.0 (left) to +1.0 (right)
	float half_width = text_width * 0.5;
	float x = (VERTEX.x - half_width) / half_width;

	// Parabolic arc: highest in the middle, lower at the edges
	float base_arc = -(1.0 - x * x) * curvature;

	// Optional wobble so it feels alive
	float wobble = sin(TIME * wobble_speed) * wobble_amplitude;

	VERTEX.y += base_arc + wobble;
}
