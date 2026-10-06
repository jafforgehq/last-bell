// The grade of the picture (scripts/render/dark_look.gd): ONE full-screen pass over the world and nothing above it (the glow layer, the marks, the HUD are drawn after).
// What the sky's CanvasModulate has made of the world is then
//  - drained of colour (`desat`) and pulled towards a cold grey-green-blue (`tint`): an overcast day with nothing cheerful in it,
//  - given deeper shadows (`shadow`, a gamma above 1: the dark stays dark, the light keeps its place),
//  - closed in at the edges (`vig` strength, `vig_from` where it begins: a vignette that is plain to see and does not eat the middle),
//  - given a very light, still film grain (`grain`: static, it does not crawl; the game turns it off with Reduce motion),
//  - and lifted or lowered by the player's Brightness setting (`bright`, 0.7 to 1.3: a gamma and a little exposure, so that a dim screen can have its shadows back).
// A cost of one texture read and about thirty operations a pixel.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_nearest;
uniform float desat : hint_range(0.0, 1.0) = 0.35;
uniform vec3 tint = vec3(0.94, 1.0, 1.03);
uniform float shadow : hint_range(0.8, 1.6) = 1.12;
uniform float vig : hint_range(0.0, 1.0) = 0.5;
uniform float vig_from : hint_range(0.0, 1.2) = 0.5;
uniform float grain : hint_range(0.0, 0.1) = 0.022;
uniform float bright : hint_range(0.5, 1.6) = 1.0;
// the cold the shadows are given (added where the picture is darkest, so that black is a dark blue and not a hole)
uniform vec3 floor_col = vec3(0.006, 0.009, 0.016);

float ign(vec2 p) {
	// interleaved gradient noise: even in low precision, and without a sin
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(l), desat) * tint;
	c = pow(max(c, vec3(0.0)), vec3(shadow));
	// the vignette: 0 in the middle, 1 in the corners (the distance runs 0 to 1.41)
	vec2 q = (SCREEN_UV - 0.5) * 2.0;
	float v = smoothstep(vig_from, 1.45, length(q));
	c *= 1.0 - vig * v * (0.55 + 0.45 * v);
	c += floor_col * (1.0 - clamp(l * 2.0, 0.0, 1.0));
	// the player's brightness: a gamma (the shadows come up) and a little exposure (the whole)
	c = pow(max(c, vec3(0.0)), vec3(1.0 / bright)) * mix(1.0, bright, 0.5);
	float n = ign(floor(FRAGCOORD.xy * 0.5)) - 0.5;
	c += n * grain * (1.1 - clamp(l * 2.0, 0.0, 0.8));
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
