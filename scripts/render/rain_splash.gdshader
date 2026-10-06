// A drop landing (RAIN): the ring that opens on the ground and fades, a bright speck where the drop struck. One MultiMesh of at most 30 quads draws all of them in one call
// (scripts/render/rain_view.gd): INSTANCE_CUSTOM is {age 0 to 1, a seed, how bright, 0}.
shader_type canvas_item;
render_mode unshaded;

varying vec4 cd;

void vertex() {
	cd = INSTANCE_CUSTOM;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float a = cd.x;
	float r = length(p);
	float ring_r = mix(0.12, 0.92, 1.0 - pow(1.0 - a, 2.0));
	float w = mix(0.11, 0.05, a);
	float ring = 1.0 - smoothstep(0.0, w, abs(r - ring_r));
	float inner = (1.0 - smoothstep(0.0, w * 0.8, abs(r - ring_r * 0.55))) * smoothstep(0.2, 0.4, a) * 0.55;
	float fade = pow(1.0 - a, 1.4);
	float speck = (1.0 - smoothstep(0.0, 0.24, r)) * (1.0 - smoothstep(0.0, 0.30, a));
	float al = ((ring + inner) * fade * 0.7 + speck * 0.8) * cd.z;
	COLOR = vec4(0.84, 0.91, 1.0, al);
}
