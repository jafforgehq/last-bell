// The shimmer of a container that has not been searched (scripts/render/loot_shimmer.gd). One MultiMesh quad for each container, one draw call for all of them: the quad is the furniture's
// footprint grown by a few pixels (world pixels: 64 to a tile), and everything else is made here from the quad's UV.
//   INSTANCE_CUSTOM: x phase (0 to 1, so that two containers do not pulse together), y 1.0 for a container that cannot be searched yet (the dead are in the room), z, w the quad's size in px.
//   What is drawn: a soft rim of light a few pixels inside the quad, breathing; and, for a container that can be searched, a thin diagonal glint that crosses the footprint every 2.4 s or so, with a
//   faint wash of light just inside the rim. A container that cannot be searched yet has the rim in a grey red, breathing slower, and no glint.
//   `calm` (Reduce flashes, Reduce motion): nothing moves: a still rim, a little dimmer. `cb` (Colour-blind markers): the available one has corner brackets (a shape), the other a dashed rim.
//   `gain` raises the strength by the night's darkness (the world is under the sky's CanvasModulate, which would dim an additive glint to a smudge); it is on the strength and not on the colour,
//   which a gain of two or three would clip to white.
shader_type canvas_item;
render_mode blend_add, unshaded;

uniform float t = 0.0;
uniform float calm = 0.0;
uniform float cb = 0.0;
uniform float gain = 1.0;
uniform vec3 gold : source_color = vec3(1.0, 0.80, 0.34);
uniform vec3 grey_red : source_color = vec3(0.86, 0.44, 0.42);

varying flat vec4 inst;

void vertex() {
	inst = INSTANCE_CUSTOM;
}

float sd_box(vec2 p, vec2 b) {
	vec2 d = abs(p) - b;
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0);
}

void fragment() {
	vec2 size = inst.zw;
	float ph = inst.x;
	bool blocked = inst.y > 0.5;
	vec2 p = (UV - vec2(0.5)) * size;
	vec2 hb = size * 0.5 - vec2(5.0);
	float d = sd_box(p, hb);
	// the rim: about 3 px of light with a soft edge, either side of the line
	float rim = smoothstep(4.0, 0.8, abs(d));
	float breath;
	if (calm > 0.5) {
		breath = 0.7;
	} else if (blocked) {
		breath = 0.6 + 0.25 * sin(t * 1.6 + ph * 6.2832);
	} else {
		breath = 0.62 + 0.38 * sin(t * 2.6 + ph * 6.2832);    // (never quite out: at its lowest a fifth of its strength, so that no container is unmarked for a moment)
	}
	float a = rim * (blocked ? 0.62 : 0.62) * breath;
	if (!blocked && calm < 0.5) {
		// the glint: a band across the footprint on a slant, going once in 2.4 s, in the part of the cycle that is on the quad (the rest of it, it waits off to one side)
		float dg = (UV.x * size.x + UV.y * size.y * 0.7) / (size.x + size.y * 0.7);
		float pos = mix(-0.35, 1.35, fract(t * 0.42 + ph));
		float band = exp(-pow((dg - pos) / 0.07, 2.0));
		float inside = smoothstep(2.0, -4.0, d);
		a += band * inside * 0.55;
		a += smoothstep(0.0, -12.0, d) * 0.05 * breath;
	}
	if (cb > 0.5) {
		if (blocked) {
			// a dashed rim (a pattern): the line is cut in dashes along the way round
			float dash = step(0.5, fract((p.x + p.y) / 16.0));
			a = rim * 0.6 * dash;
		} else {
			// corner brackets (a shape): the rim kept only at the four corners, full, and thicker
			float arm = min(min(size.x, size.y) * 0.34, 24.0);
			vec2 q = abs(p);
			float corner = step(hb.x - arm, q.x) * step(hb.y - arm, q.y);
			float thick = smoothstep(6.0, 2.2, abs(d));
			a = max(a * 0.45, thick * corner * 0.9);
		}
	}
	// (the night's gain is put on the strength, not on the colour: a gold put through a gain of two or three clips to white)
	COLOR = vec4(blocked ? grey_red : gold, clamp(a * pow(gain, 0.75), 0.0, 1.0));
}
