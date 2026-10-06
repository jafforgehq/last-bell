// The streets round the avatar, in a small round window (scripts/ui/minimap.gd). The town is read from three small textures made ONCE (one pixel for each tile of the town):
//   terrain_tex  L8: the terrain id of the tile (1 asphalt, 2 sidewalk, 3 yard, 4 grass, 5 soil, 12 concrete, 13 dirt, 20 and up walls)
//   house_tex    RGBA8, the town's own `tile_house` array read as bytes: alpha 0 on a tile of a house (red = the house's id), alpha 1 on the rest
//   flag_tex     256 x 1 L8, by house id: 0 plain, 1 looked in, 2 the base, 3 a house that may be claimed
// and the quad is drawn with `center` (the tile in the middle) and `span` (tiles across): that is all the CPU does each frame. Four taps for each pixel (the tiles are 1.7 pixels
// across at the usual size) keep the edges of the blocks smooth as the window scrolls.
shader_type canvas_item;

uniform sampler2D terrain_tex : filter_nearest, repeat_disable;
uniform sampler2D house_tex : filter_nearest, repeat_disable;
uniform sampler2D flag_tex : filter_nearest, repeat_disable;
uniform vec2 center = vec2(96.0, 96.0);
uniform float span = 80.0;
uniform vec2 world_size = vec2(192.0, 192.0);
// the size of the window in pixels (for the width of the edge and of a tap)
uniform float px = 136.0;
uniform float hot = 0.0;

vec3 tile_color(vec2 tile) {
	vec2 uv = tile / world_size;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x >= 1.0 || uv.y >= 1.0) {
		return vec3(0.0, 0.0, 0.0);      // beyond the town's edge
	}
	vec4 hs = texture(house_tex, uv);
	if (hs.a < 0.5) {
		float id = floor(hs.r * 255.0 + 0.5);
		float flag = floor(texture(flag_tex, vec2((id + 0.5) / 256.0, 0.5)).r * 255.0 + 0.5);
		if (flag > 2.5) {
			return vec3(0.36, 0.66, 0.38);
		}
		if (flag > 1.5) {
			return vec3(0.94, 0.76, 0.29);
		}
		if (flag > 0.5) {
			return vec3(0.62, 0.45, 0.25);
		}
		return vec3(0.52, 0.52, 0.46);
	}
	float t = floor(texture(terrain_tex, uv).r * 255.0 + 0.5);
	if (t < 1.5) {
		return vec3(0.115, 0.13, 0.135);    // asphalt: the darkest of the town
	}
	if (t < 2.5) {
		return vec3(0.29, 0.31, 0.29);      // sidewalk
	}
	if (t < 4.5) {
		return vec3(0.12, 0.21, 0.13);      // yard, grass
	}
	if (t < 5.5 || (t > 12.5 && t < 13.5)) {
		return vec3(0.19, 0.16, 0.11);      // soil, dirt
	}
	return vec3(0.24, 0.25, 0.24);          // concrete, fences
}

void fragment() {
	vec2 q = (UV - 0.5) * 2.0;
	float r = length(q);
	float tap = 0.25 * span / px;
	vec2 tile = center + (UV - 0.5) * span;
	vec3 col = tile_color(tile + vec2(-tap, -tap));
	col += tile_color(tile + vec2(tap, -tap));
	col += tile_color(tile + vec2(-tap, tap));
	col += tile_color(tile + vec2(tap, tap));
	col *= 0.25;
	// a little darker toward the edge, so that the middle (where you are) is the brightest
	col *= 1.0 - 0.28 * smoothstep(0.55, 1.0, r);
	float edge = 2.0 / px;
	float inside = 1.0 - smoothstep(1.0 - edge, 1.0, r);
	float rim = smoothstep(1.0 - 4.0 * edge, 1.0 - 3.0 * edge, r) * inside;
	vec3 brass = mix(vec3(0.62, 0.5, 0.28), vec3(0.95, 0.8, 0.42), hot);
	col = mix(col, brass, rim * 0.95);
	COLOR = vec4(col, inside);
}
