## Puddle ripples (round 24, "base life"): when it rains the ground of the yard is pocked with small pale rings that open and fade, a few
## hundred milliseconds each, each in a new place of its own part of the yard. ONE MultiMesh of 30 quads (a 6 by 5 grid of the yard, a
## ripple in each cell) in ONE draw call, drawn only while it rains; the rings, their growth and where each next lands are worked out by the
## fragment and vertex shader below from the clock and the strength of the rain (an eased 0 to 1 the base's life sets each frame), so there is
## no work on the CPU and nothing is allocated. The rain is the rules' weather (`sim.weather == "rain"`; the rules draw no rain of their own).
## Under "reduce motion" nothing is drawn. Hidden off the screen by scripts/render/base_life.gd.
extends MultiMeshInstance2D

const Kit := preload("res://scripts/render/life_kit.gd")
const TILE := 64.0
## The ground the rain falls on (tiles): the yard, in a grid of CELLS cells with one ripple each.
const AREA := Rect2(22.0, 21.5, 39.0, 22.0)
const CELLS := Vector2i(6, 5)

const SHADER := "
shader_type canvas_item;
uniform float t = 0.0;
uniform float strength = 0.0;
uniform vec2 area_px = vec2(2496.0, 1408.0);
uniform vec2 origin_px = vec2(1408.0, 1376.0);
uniform vec2 cells = vec2(6.0, 5.0);
varying float alpha;
float hash(float n) {
	return fract(sin(n * 91.7 + 3.1) * 43758.5453);
}
void vertex() {
	float s = INSTANCE_CUSTOM.x;
	float period = INSTANCE_CUSTOM.y;
	float cell = INSTANCE_CUSTOM.z;
	float cyc = t / period + s * 7.0;
	float n = floor(cyc);
	float prog = fract(cyc);
	vec2 cs = area_px / cells;
	vec2 cxy = vec2(mod(cell, cells.x), floor(cell / cells.x));
	vec2 jit = vec2(hash(cell * 3.1 + n * 1.7), hash(cell * 7.7 + n * 2.3));
	vec2 c = origin_px + (cxy + 0.15 + 0.7 * jit) * cs;
	float r = 9.0 + 34.0 * prog;
	alpha = (1.0 - prog) * strength * step(hash(cell * 11.0 + n * 5.3), 0.25 + 0.75 * strength);
	VERTEX = c + VERTEX * vec2(2.0 * r + 4.0, (2.0 * r + 4.0) * 0.5);
}
void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float ring = smoothstep(0.78, 0.9, d) * (1.0 - smoothstep(0.92, 1.0, d));
	float inner = smoothstep(0.42, 0.5, d) * (1.0 - smoothstep(0.52, 0.62, d)) * 0.6;
	COLOR = vec4(0.88, 0.93, 0.98, clamp((ring + inner) * alpha, 0.0, 1.0) * 0.85);
}
"

var _mat: ShaderMaterial
## How wet it is now (0 to 1), for the tests.
var strength := 0.0


func setup() -> void:
	z_index = 5
	name = "Ripples"
	var b := Kit.Builder.new()
	b.add_grid(Vector2(-0.5, -0.5), Vector2(1.0, 1.0), 1, 1, Color.WHITE, Color.WHITE, 0.0, 1.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_custom_data = true
	mm.mesh = b.bake()
	var n := CELLS.x * CELLS.y
	mm.instance_count = n
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in n:
		mm.set_instance_transform_2d(i, Transform2D.IDENTITY)
		mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf_range(0.8, 1.5), float(i), 0.0))
	multimesh = mm
	_mat = Kit.material(SHADER)
	_mat.set_shader_parameter("area_px", AREA.size * TILE)
	_mat.set_shader_parameter("origin_px", AREA.position * TILE)
	_mat.set_shader_parameter("cells", Vector2(CELLS.x, CELLS.y))
	material = _mat
	# the bits are placed by the shader, far from the instances' own (all at the origin): tell the renderer where they are, or it culls them
	RenderingServer.canvas_item_set_custom_rect(get_canvas_item(), true, Rect2(AREA.position * TILE, AREA.size * TILE))


## Called every frame while shown: the clock (game seconds) and how wet it is (0 to 1).
func apply(clock: float, wet: float) -> void:
	strength = wet
	_mat.set_shader_parameter("t", clock)
	_mat.set_shader_parameter("strength", wet)


## The ground it covers (tiles), for the culling.
func bounds() -> Rect2:
	return AREA
