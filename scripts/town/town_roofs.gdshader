// The roofs of the town in ONE MultiMesh: the roof texture (an atlas of 4 x 4 pieces of 128 px, one piece for each tile) is put on by the place in the world, so that
// a roof of any size repeats it as the ground does (the instance colour is the roof's fade). Placeholder until the town art kit lands.
shader_type canvas_item;

varying vec2 world_px;

void vertex() {
	world_px = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	// 64 px to the tile, the atlas covers 4 x 4 tiles = 256 px
	vec4 c = texture(TEXTURE, world_px / 256.0);
	COLOR = vec4(c.rgb, c.a) * COLOR;
}
