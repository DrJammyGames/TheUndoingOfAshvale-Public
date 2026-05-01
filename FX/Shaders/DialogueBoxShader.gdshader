shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float edge_softness : hint_range(0.0, 0.5) = 0.1;

void fragment() {
    vec4 tex = texture(TEXTURE, UV);

    // Center-out reveal mask
    float alpha_mask;
    if (progress <= 0.0) {
        alpha_mask = 0.0;
    } else if (progress >= 1.0) {
        alpha_mask = 1.0;
    } else {
        vec2 centered = abs(UV - vec2(0.5));
        float dist = max(centered.x, centered.y);

        float r = progress * 0.5; // half panel
        float half_soft = edge_softness * 0.5;

        float m = smoothstep(r - half_soft, r + half_soft, dist);
        alpha_mask = 1.0 - m;
    }

    // Only affect alpha; keep RGB untouched
    tex.a *= alpha_mask;

    COLOR = tex;
}
