shader_type canvas_item;

uniform vec2 screen_center = vec2(0.0, 0.0);
uniform vec2 viewport_size = vec2(1920.0, 1080.0);
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float max_radius = 256.0;
uniform float softness = 12.0;
uniform float alpha_mul : hint_range(0.0, 1.0) = 1.0;


void fragment() {
    vec4 c = texture(TEXTURE, UV);

    float r = progress * max_radius;
    vec2 frag_screen = SCREEN_UV * viewport_size;
    float d = distance(frag_screen, screen_center);

     // Keep pixels outside the expanding radius, clear inside it.
    // This starts fully visible at progress=0 and then erases outward.
    float keep = smoothstep(r - softness, r, d);

    // APPLY MASK
    c.a *= keep * alpha_mul;
    COLOR = c;
}
