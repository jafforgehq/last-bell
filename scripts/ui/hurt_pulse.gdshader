// The red edge of the screen when the avatar is hurt (scripts/ui/hurt_pulse.gd): one full-screen quad, nothing in the middle, the screen's own corners darkest.
// `intensity` (0 to 1) is all the part moves; at 0 the quad is not drawn at all. At intensity 1 the corners are 0.88 red and the middle of each edge about 0.6.
shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.58, 0.02, 0.03, 1.0);

void fragment() {
	// 0 in the middle of the screen, 1 at the middle of each edge, 1.41 in the corners (the screen's own ellipse: the bands are as wide on a wide window as on a tall one)
	float d = length((UV - vec2(0.5)) * 2.0);
	float band = smoothstep(0.5, 1.3, d);
	COLOR = vec4(tint.rgb, clamp(band * intensity, 0.0, 0.88));
}
