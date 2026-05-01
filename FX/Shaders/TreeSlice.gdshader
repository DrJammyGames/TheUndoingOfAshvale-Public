shader_type canvas_item;

// Y position of the cut line in UV space (0 = top, 1 = bottom)
uniform float slice_y : hint_range(0.0, 1.0) = 0.75;

// Animation progress: 0 = intact, 1 = fully fallen
uniform float fall_progress : hint_range(0.0, 1.0) = 0.0;

// Direction the canopy falls: -1.0 = left, 1.0 = right
uniform float fall_direction : hint_range(-1.0, 1.0) = 1.0;

// Maximum rotation in radians (PI/2 = 90 degrees)
uniform float max_angle : hint_range(0.0, 3.14159) = 1.5708;

// Texture width in pixels for pixel-perfect UV snapping
uniform float pixel_size = 32.0;

// Vertex expansion so rotated canopy doesn't clip
uniform float expansion_factor = 1.0;

void vertex() {
	float scale = 1.0 + expansion_factor * 2.0;
	VERTEX *= scale;
	UV = (UV - 0.5) * scale + 0.5;
}

void fragment() {
	// Pixel-snap for clean pixel art
	vec2 uv = floor(UV * pixel_size) / pixel_size;

	// Is this pixel part of the canopy (above the cut)?
	bool is_canopy = uv.y < slice_y;

	if (!is_canopy) {
		// --- STUMP: stays in place, fades at the end ---
		if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
			COLOR = vec4(0.0);
		} else {
			COLOR = texture(TEXTURE, uv);
			// Fade out so the spawned stump node can take over
			float stump_fade = smoothstep(0.7, 1.0, fall_progress);
			COLOR.a *= (1.0 - stump_fade);
		}
	} else {
		// --- CANOPY: rotates around the cut line and falls ---
		float angle = fall_progress * max_angle * fall_direction;
		vec2 pivot = vec2(0.5, slice_y);

		// Inverse rotation to find which source pixel to sample
		vec2 offset = uv - pivot;
		float s = sin(-angle);
		float c = cos(-angle);
		vec2 source_uv = vec2(
			offset.x * c - offset.y * s,
			offset.x * s + offset.y * c
		) + pivot;

		// Only draw if source is in-bounds and in the canopy region
		if (source_uv.x < 0.0 || source_uv.x > 1.0 ||
			source_uv.y < 0.0 || source_uv.y >= slice_y) {
			COLOR = vec4(0.0);
		} else {
			COLOR = texture(TEXTURE, source_uv);
			// Fade as it falls
			COLOR.a *= (1.0 - fall_progress * 0.7);
		}
	}
}
