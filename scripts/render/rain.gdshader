// The town's rain (RAIN): ONE full-screen quad, three depth layers of streaks worked out from a hash of the pixel's place: no texture is read, nothing is allocated.
// scripts/render/rain_view.gd puts it on a CanvasLayer over the world and under the HUD, and feeds the few numbers below each frame.
//
// A layer is a field of columns; each column has its own pace and offset, and in it a streak is a cell of the column with a chance `dens` of holding one: a thin line with a dim tail and a
// bright blunt head, falling along the wind's slant. The far layer is fine, dim, slow and many; the middle one is bolder; the near one is long, bright, fast and few (and left out in "reduce
// motion"). The sizes are for a window 800 pixels high and grow with it, so that a larger window shows the same rain, not a finer one. At night the streaks are dim (the world's
// own light does not reach a layer of the screen) and they brighten in the pool of light round the avatar, with a faint warm mist there.
shader_type canvas_item;
render_mode unshaded;

uniform float intensity = 0.0;       // 0 to 1: how much rain there is (the density; 0.30 a drizzle, 0.62 steady rain, 1.0 a storm), already faded for being indoors
uniform float wind = 0.18;           // the slant: sideways travel for each unit of fall
uniform float t = 0.0;               // the rain's clock in seconds (it stops with the game)
uniform vec2 res = vec2(1280.0, 800.0);
uniform float dark = 0.0;            // 0 by day to 1 at night (lighting.dark)
uniform vec2 pool = vec2(0.5, 0.5);  // where the avatar is on the screen (0 to 1)
uniform float pool_r = 0.22;         // how far her light reaches, in screen heights
uniform float calm = 0.0;            // 1: "reduce motion": fewer streaks, no near layer
uniform float haze = 0.0;            // 0 to 1: a grey veil over it all (a steady rain and a storm)
uniform vec4 day_tint : source_color = vec4(0.80, 0.86, 0.94, 1.0);
uniform vec4 night_tint : source_color = vec4(0.54, 0.64, 0.86, 1.0);

float h12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// One layer. `p` is in pixels along the fall (x across it, y down it); `cell` the size of a cell; `speed` pixels a second.
float layer(vec2 p, vec2 cell, float speed, float len, float width, float dens, float seed) {
	vec2 q = p / cell;
	float col = floor(q.x);
	float hc = h12(vec2(col, seed));
	float yy = q.y - (t * speed * (0.8 + 0.4 * hc)) / cell.y + hc * 31.0;
	float row = floor(yy);
	float f = fract(yy);
	float r = h12(vec2(col * 1.13 + seed, row));
	if (r > dens) {
		return 0.0;
	}
	float cx = 0.2 + 0.6 * h12(vec2(r * 57.0 + seed, col));
	float dx = abs(fract(q.x) - cx) * cell.x;
	float body = 1.0 - smoothstep(0.0, width, dx);
	float along = smoothstep(0.0, len, f) * (1.0 - smoothstep(len * 0.88, len, f));
	return body * along;
}

void fragment() {
	float u = res.y / 800.0;
	vec2 px = UV * res;
	vec2 d = normalize(vec2(wind, 1.0));
	vec2 p = vec2(dot(px, vec2(d.y, -d.x)), dot(px, d)) / u;
	float thin = 1.0 - 0.45 * calm;
	float a = 0.0;
	a += 0.36 * layer(p, vec2(11.0, 46.0), 520.0, 0.55, 1.0, 0.62 * intensity * thin, 1.0);
	a += 0.52 * layer(p, vec2(23.0, 88.0), 800.0, 0.50, 1.3, 0.50 * intensity * thin, 2.0);
	if (calm < 0.5) {
		a += 0.70 * layer(p, vec2(58.0, 210.0), 1250.0, 0.42, 2.0, 0.36 * intensity, 3.0);
	}
	// her light: the streaks are brighter and warmer in the pool round her, and the air has a faint mist there
	float pd = length((UV - pool) * vec2(res.x / res.y, 1.0));
	float pk = (1.0 - smoothstep(0.0, pool_r, pd)) * dark;
	float lum = mix(1.0, 0.66, dark) + 1.5 * pk;
	vec3 tint = mix(day_tint.rgb, night_tint.rgb, dark);
	tint = mix(tint, vec3(0.86, 0.92, 1.0), clamp(pk * 0.7, 0.0, 0.6));
	float streak = clamp(a * lum * (0.35 + 0.65 * intensity), 0.0, 0.9);
	float veil = haze * mix(0.075, 0.05, dark) + 0.06 * pk * intensity;
	vec3 veil_col = mix(vec3(0.62, 0.68, 0.76), vec3(0.20, 0.26, 0.38), dark);
	veil_col = mix(veil_col, vec3(0.60, 0.68, 0.80), pk * 0.5);
	float al = streak + veil * (1.0 - streak);
	COLOR = vec4((tint * streak + veil_col * veil * (1.0 - streak)) / max(al, 0.001), al);
}
