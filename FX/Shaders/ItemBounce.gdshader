shader_type canvas_item;

// How high the item bounces in pixels
uniform float bounce_height : hint_range(0.0, 20.0) = 4.0;

// How fast the bounce loops (higher = faster)
uniform float bounce_speed : hint_range(0.0, 20.0) = 5.0;

// Per-instance offset so items don't all sync
uniform float time_offset = 0.0;

void vertex() {
    // Phase of the bounce
    float phase = (TIME + time_offset) * bounce_speed;

    // abs(sin) makes a "floor bounce" style curve:
    // sin        = -1..1
    // abs(sin)   =  0..1 (never below baseline)
    float bounce = abs(sin(phase)); // 0 = at ground, 1 = highest point

    // Move upwards as bounce increases.
    // Negative because in screen space, smaller y is higher.
    float y_offset = -bounce * bounce_height;

    //VERTEX.y += y_offset;
}
