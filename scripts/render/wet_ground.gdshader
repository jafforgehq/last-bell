// The wet look of the town's outdoor ground (RAIN): put by scripts/render/rain_view.gd on the ground meshes of the lawn, the road, the sidewalk, the dirt path and the gravel (about a dozen
// meshes, each of the greedy rectangles of the ground; NOT a shader for each tile) while the ground is wet, and taken off again when it is dry, so a dry day draws what it always did.
// The ground darkens and cools as it soaks; low, broad patches of it become puddles (darker, bluer, and they shine); and over wet paving a soft glint slides slowly about. The light of the
// night still multiplies all of it: a glint is only seen near a lamp, as it should be.
shader_type canvas_item;

uniform float wet : hint_range(0.0, 1.0) = 0.0;
uniform float paved : hint_range(0.0, 1.0) = 1.0;    // 1 road and sidewalk, a little for the lawn (its puddles are small, and it is darkened more than it shines)
uniform float t = 0.0;
varying vec2 wp;

float h21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	wp = VERTEX / 64.0;
}

void fragment() {
	vec4 c = COLOR;
	float n = 0.62 * vn(wp * 0.45) + 0.38 * vn(wp * 1.35 + 7.0);
	float thr = mix(0.88, 0.62, wet * wet);
	float pud = smoothstep(thr, thr + 0.06, n) * wet * (0.12 + 0.88 * paved);
	vec3 col = c.rgb * mix(vec3(1.0), vec3(0.80, 0.85, 0.93), wet);
	col = mix(col, col * vec3(0.74, 0.80, 0.90) + vec3(0.015, 0.025, 0.04), pud);
	if (paved > 0.05) {
		float g = smoothstep(0.62, 0.95, vn(wp * 0.9 + vec2(t * 0.09, -t * 0.05)));
		col += vec3(0.62, 0.72, 0.90) * g * (0.05 * wet * paved + 0.10 * pud);
	}
	COLOR = vec4(col, c.a);
}
