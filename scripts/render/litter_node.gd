## Wind-blown leaves and litter (round 24, "base life"): a score of autumn leaves (orange, yellow, brown, red) and a few scraps of paper that
## drift across the yard on the wind, tumbling as they go, faster and more of a rush in a gust, and fade out at the edge of the yard to come
## in again at the other. ONE MultiMesh of small quads in ONE draw call, moved entirely by the vertex shader below from a single number
## the base's life sets each frame (`drift`, the tiles the wind has carried them: the integral of the wind's speed), so there is no
## per-leaf work on the CPU and nothing is allocated. They lie under the people (z 5, with the ground's bits). In rain they are plastered
## to the ground and not drawn; under "reduce motion" they are not drawn. Hidden off the screen by scripts/render/base_life.gd (it asks
## whether the view is inside the yard's rectangle `AREA`).
extends MultiMeshInstance2D

const Kit := preload("res://scripts/render/life_kit.gd")
const TILE := 64.0
## The stretch of ground they blow across (tiles): the yard.
const AREA := Rect2(22.0, 21.5, 39.0, 22.0)
const COUNT := 24

const SHADER := "
shader_type canvas_item;
uniform float drift = 0.0;
uniform vec2 area_px = vec2(2496.0, 1408.0);
uniform vec2 origin_px = vec2(1408.0, 1376.0);
uniform float fade = 1.0;
varying vec3 tint;
varying float edge;
vec3 palette(float k) {
	vec3 orange = vec3(0.86, 0.46, 0.15);
	vec3 yellow = vec3(0.90, 0.72, 0.22);
	vec3 brown = vec3(0.50, 0.33, 0.19);
	vec3 red = vec3(0.70, 0.26, 0.16);
	vec3 paper = vec3(0.86, 0.85, 0.80);
	if (k < 0.2) return orange;
	if (k < 0.4) return yellow;
	if (k < 0.6) return brown;
	if (k < 0.8) return red;
	return paper;
}
void vertex() {
	float s = INSTANCE_CUSTOM.x;
	float v = 0.55 + INSTANCE_CUSTOM.y * 0.9;
	float size = INSTANCE_CUSTOM.z;
	float x = mod(s * area_px.x + drift * 64.0 * v, area_px.x);
	float y = mod(fract(s * 13.7) * area_px.y + sin(drift * 1.3 * v + s * 50.0) * 22.0 + drift * 8.0 * v, area_px.y);
	float rot = drift * 2.4 * v + s * 30.0;
	vec2 c = vec2(cos(rot), sin(rot));
	vec2 q = VERTEX * vec2(size, size * 0.6);
	q = vec2(q.x * c.x - q.y * c.y, q.x * c.y + q.y * c.x);
	VERTEX = origin_px + vec2(x, y) + q;
	edge = clamp(min(min(x, area_px.x - x), min(y, area_px.y - y)) / 160.0, 0.0, 1.0);
	tint = palette(INSTANCE_CUSTOM.w);
}
void fragment() {
	float m = 1.0 - smoothstep(0.36, 0.5, length(UV - 0.5));
	COLOR = vec4(tint * (0.88 + 0.24 * UV.x), m * edge * fade);
}
"

var _mat: ShaderMaterial
## The share of them that show now (0 to 1: 0 in rain), for the tests.
var fade := 1.0
## The stretch of ground they cross: the yard's (`AREA`), or the one `setup` was given (the title's street).
var area := AREA


## `area_override`: another stretch of ground in tiles (the title's town), with an area of its own; left out, the school's yard.
func setup(seed_value: int = 5, area_override: Rect2 = Rect2()) -> void:
	if area_override.has_area():
		area = area_override
	z_index = 5
	name = "Litter"
	var b := Kit.Builder.new()
	b.add_grid(Vector2(-0.5, -0.5), Vector2(1.0, 1.0), 1, 1, Color.WHITE, Color.WHITE, 0.0, 1.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_custom_data = true
	mm.mesh = b.bake()
	mm.instance_count = COUNT
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in COUNT:
		mm.set_instance_transform_2d(i, Transform2D.IDENTITY)
		# seed, own speed, size (px), colour: a few scraps of paper among the leaves
		var paper := i % 6 == 5
		mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), rng.randf_range(11.0, 16.0) if not paper else rng.randf_range(11.0, 15.0), 0.9 if paper else rng.randf() * 0.78))
	multimesh = mm
	_mat = Kit.material(SHADER)
	_mat.set_shader_parameter("area_px", area.size * TILE)
	_mat.set_shader_parameter("origin_px", area.position * TILE)
	material = _mat
	# the bits are placed by the shader, far from the instances' own (all at the origin): tell the renderer where they are, or it culls them
	RenderingServer.canvas_item_set_custom_rect(get_canvas_item(), true, Rect2(area.position * TILE, area.size * TILE))


## Called every frame while shown: `drift` is how far the wind has carried them (tiles), `rain` how wet it is (0 to 1).
func apply(drift: float, rain: float) -> void:
	fade = clampf(1.0 - rain * 1.6, 0.0, 1.0)
	_mat.set_shader_parameter("drift", drift)
	_mat.set_shader_parameter("fade", fade)


## The ground it covers (tiles), for the culling.
func bounds() -> Rect2:
	return area
