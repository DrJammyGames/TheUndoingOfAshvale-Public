// Wind + Hit Flash Shader for Harvestables
// ----------------------------------------
// - Wind is always running if enable_wind == true.
// - Hit flash is driven by hit_amount (0.0 -> 1.0), which you tween in GDScript.
// - Designed for Sprite2D / TextureRect-style nodes.

shader_type canvas_item;
render_mode blend_mix;

//Wind settings (from the wind shader)
//Global wind speed multiplier.
uniform float speed = 1.0;

//Minimal / maximal wind strength.
uniform float minStrength : hint_range(0.0, 1.0) = 0.05;
uniform float maxStrength : hint_range(0.0, 1.0) = 0.1;

//Factor that scales wind strength up to pixel offset.
uniform float strengthScale = 100.0;

//Time between minimal and maximal strength changes.
uniform float interval = 3.5;

//Number of waves/detail in wind movement.
uniform float detail = 1.0;

//Not currently used in this version, but kept for tweaking if desired.
uniform float distortion : hint_range(0.0, 1.0) = 0.0;

//Height where the wind begins (0.0 = entire sprite; higher = only top moves).
uniform float heightOffset : hint_range(0.0, 1.0) = 0.0;

//Per-instance offset, so multiple trees don't sway identically.
//You can set this randomly in GDScript per instance.
uniform float offset = 0.0;

//Allow enabling/disabling wind per instance from GDScript.
uniform bool enable_wind = true;

// Hit flash settings
//Color to tint towards when hit (shock color).
uniform vec3 shock_color : source_color = vec3(1.0, 0.0, 0.0);

//How strong the hit wiggle should be in pixels.
uniform float hit_amplitude = 2.0;

//How fast the hit wiggle should be.
uniform float hit_frequency = 40.0;

//How "hit" we are: 0.0 = no effect, 1.0 = full effect.
//This is controlled from GDScript via a tween.
uniform float hit_amount : hint_range(0.0, 1.0) = 0.0;

//Helper for wind calculation
float getWind(vec2 vertex, vec2 uv, float time) {
    //Difference between max and min strength.
    float diff = pow(maxStrength - minStrength, 2.0);
    
    //Compute strength over time, clamped between min and max.
    float strength = clamp(
        minStrength + diff + sin(time / interval) * diff,
        minStrength,
        maxStrength
    ) * strengthScale;

    //Wind is stronger towards the top of the sprite (uv.y near 0).
    //heightOffset pushes the effect upwards (e.g. only top of tree moves).
    float vertical_factor = max(0.0, (1.0 - uv.y) - heightOffset);

    float wind = (sin(time) + cos(time * detail)) * strength * vertical_factor;
    return wind;
}

//Wind sway
void vertex() {
    float x_offset = 0.0;

    if (enable_wind) {
        float time = TIME * speed + offset;

        //Base wind offset from the wind function
        float base_wind = getWind(VERTEX.xy, UV, time);

        // When the tree is "hit", we want the wind
        // to calm down or pause briefly.
        //
        // hit_amount:
        //   0.0 -> no hit, full wind
        //   1.0 -> fully hit, no wind
        //
        //So we scale wind by (1.0 - hit_amount).
        float wind_factor = 1.0 - clamp(hit_amount, 0.0, 1.0);
        x_offset += base_wind * wind_factor;
    }

    //Hit wiggle
    //Additional fast wiggle effect only when hit_amount > 0.
    //This stacks on top of the (possibly reduced) wind.
    float hit_wiggle = sin(TIME * hit_frequency) * hit_amount * hit_amplitude;
    x_offset += hit_wiggle;

    //Apply final horizontal offset
    VERTEX.x += x_offset;
}

//Fragment: apply hit color tint
void fragment() {
    vec4 tex = texture(TEXTURE, UV);

    //Mix only the RGB channels towards shock_color based on hit_amount,
    //keep original alpha so transparency remains correct.
    vec3 mixed_rgb = mix(tex.rgb, shock_color, hit_amount);

    COLOR = vec4(mixed_rgb, tex.a);
}
