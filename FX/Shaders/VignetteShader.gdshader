shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform float vignette_intensity = 0.4;
uniform float vignette_opacity : hint_range(0.0, 1.0) = 0.5;
uniform vec4 vignette_rgb : source_color = vec4(0.0, 0.0, 0.0, 1.0);

float vignette(vec2 uv){
	uv *= 1.0 - uv.xy;
	float v = uv.x * uv.y * 15.0;
	return pow(v, vignette_intensity * vignette_opacity);
}

void fragment(){
	vec4 screen_color = texture(SCREEN_TEXTURE, SCREEN_UV);

	// Compute vignette factor (0 center -> 1 edges)
	float vig = 1.0 - vignette(UV);

	// Blend screen toward vignette color at edges
	vec3 final_rgb = mix(screen_color.rgb, vignette_rgb.rgb, vig * vignette_opacity);

	COLOR = vec4(final_rgb, 1.0);
}
