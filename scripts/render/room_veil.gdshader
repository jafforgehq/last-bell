// The veil of a room that has not been opened yet (scripts/render/room_veil.gd): a dark room you cannot see well, not a hole.
//  - a deep desaturated blue black at 85 to 92 percent by day (a little more at night) over the room's floor, so the floor and the furniture show as faint shapes;
//    a bit lighter in the middle of the room and darker along the walls (the inner shadow);
//  - feathered edges (about half a tile) that run a little into the walls and the doorways: no outline;
//  - a very slow drift of dust (low contrast fog and a few motes);
//  - the light of an open door: a soft trapezoid from the doorway into the room, warm by day and cold at night;
//  - the reveal: `fade` takes the veil away and `flash` brightens the doorways for a moment.
// The quad is the room's floor grown by one tile on every side; `lp` is the place in tiles from the room's top left corner.
shader_type canvas_item;

uniform vec2 room_size = vec2(4.0, 3.0);
uniform float fade = 1.0;
uniform float flash = 0.0;
uniform float night = 0.0;
uniform float seed = 0.0;
// for each door of the room: xy the middle of the doorway (tiles from the room's corner), z how open and lit it is (0 to 1), w half its width (tiles)
uniform vec4 doors[4];
// the way the light goes from the door into the room (a unit vector)
uniform vec2 dirs[4];

varying vec2 lp;

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	lp = VERTEX / 64.0;
}

void fragment() {
	// how far outside the room's floor this place is (tiles; negative inside)
	vec2 q = abs(lp - room_size * 0.5) - room_size * 0.5;
	float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0);
	float cover = 1.0 - smoothstep(-0.2, 0.3, d);
	float reach = 1.0 - smoothstep(0.3, 1.0, d);
	float depth = clamp(-d / 1.6, 0.0, 1.0);

	vec3 veil_col = mix(vec3(0.050, 0.060, 0.092), vec3(0.020, 0.026, 0.050), night);
	float a = mix(mix(0.94, 0.88, depth), mix(0.97, 0.94, depth), night);

	// dust: a slow low contrast fog, and a few motes that drift and twinkle
	float n = vnoise(lp * 1.1 + vec2(TIME * 0.035, -TIME * 0.02) + seed * 7.1) * 0.65 + vnoise(lp * 2.7 + vec2(-TIME * 0.03, TIME * 0.025) + seed * 3.3) * 0.35;
	a += (0.5 - n) * 0.07;
	veil_col += (n - 0.5) * 0.06 * vec3(0.6, 0.7, 1.0);
	vec2 mq = lp * 7.0 + vec2(TIME * 0.12, TIME * 0.07);
	vec2 id = floor(mq);
	float hh = h21(id + seed);
	vec2 mp = vec2(h21(id + 3.1), h21(id + 7.7)) * 0.6 + 0.2;
	float mote = step(0.94, hh) * smoothstep(0.10, 0.0, length(fract(mq) - mp)) * (0.5 + 0.5 * sin(TIME * 0.9 + hh * 40.0));
	a -= mote * 0.10;
	veil_col += mote * 0.25;

	// the light of the doors that are open
	float light = 0.0;
	float glow = 0.0;
	for (int i = 0; i < 4; i++) {
		vec4 dd = doors[i];
		if (dd.w > 0.0) {
			vec2 p = lp - dd.xy;
			vec2 dir = dirs[i];
			float t = dot(p, dir);
			float s = dot(p, vec2(-dir.y, dir.x));
			float hw = dd.w * 0.8 + max(t, 0.0) * 0.45;
			float lat = 1.0 - smoothstep(hw * 0.25, hw, abs(s));
			float lon = smoothstep(-0.7, 0.1, t) * (1.0 - smoothstep(0.3, 3.6, t));
			light += dd.z * lat * lon;
			glow += (0.35 + 0.65 * dd.z) * exp(-dot(p, p) * 0.9);
		}
	}
	light = clamp(light, 0.0, 1.0);
	vec3 warm = mix(vec3(1.0, 0.80, 0.52), vec3(0.50, 0.64, 0.98), night);

	float av = a * cover * fade * (1.0 - light * 0.6);
	float al = light * reach * fade * 0.24 + clamp(glow, 0.0, 1.0) * flash * reach * 0.55;
	float ao = av + al * (1.0 - av);
	vec3 co = (veil_col * av + warm * al * (1.0 - av)) / max(ao, 0.0001);
	COLOR = vec4(co, ao);
}
