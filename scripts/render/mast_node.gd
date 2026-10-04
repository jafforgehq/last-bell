## The radio mast (round 24, "base life"): a thin mast on the brick corner of the school, over the radio desk, with a small dish that
## turns (scanning) and two whip aerials that sway in the wind, and a red lamp on the top that blinks slowly (on for the first part of
## every cycle, dim between). At night the blink also puts a red halo in the glow layer (`glow_paint`, which main.gd's glow node calls
## with the radial texture and the darkness). ONE baked mesh in ONE draw call: the dish squashing as it turns, the aerials swaying and the
## lamp blinking are the vertex and fragment shader below, moved by three numbers (`t`, `wind`, `moving`) set each frame, so nothing is
## redrawn and nothing is allocated. Hidden off the screen by scripts/render/base_life.gd. Under "reduce motion" the dish stands
## still, the aerials hang and the lamp burns steady.
##
## The mesh's UV.x says what a vertex belongs to: 0 the mast, 1 an aerial (UV.y 0 at its foot to 1 at its tip), 2 the dish, 3 the dish's horn,
## 4 the lamp, 5 the lamp's glint.
extends MeshInstance2D

const Kit := preload("res://scripts/render/life_kit.gd")
const TILE := 64.0
## The blink: the length of a cycle in seconds and how much of it the lamp is lit.
const BLINK_S := 1.7
const BLINK_ON := 0.38
const MAST_H := 96.0
## The mesh is drawn this much bigger than its numbers, so that it reads at the game's zoom.
const SCALE := 1.3
const DISH_AT := Vector2(0.0, -58.0)
const STEEL := Color("#4b525a")
const STEEL_HI := Color("#8b949c")
const LAMP_ON := Color("#ff3b30")
const LAMP_OFF := Color("#5a1612")

const SHADER := "
shader_type canvas_item;
uniform float t = 0.0;
uniform float wind = 0.3;
uniform float moving = 1.0;
uniform float blink_s = 1.7;
uniform float blink_on = 0.38;
uniform vec2 dish_at = vec2(0.0, -58.0);
varying float lit;
varying float part;
void vertex() {
	part = UV.x;
	float a = moving > 0.5 ? sin(t * 0.7) * 1.3 : 0.4;
	float face = abs(cos(a));
	lit = moving > 0.5 ? step(fract(t / blink_s), blink_on) : 1.0;
	if (part > 0.5 && part < 1.5) {
		float sway = (sin(t * 2.1) * 2.5 + sin(t * 3.3 + 1.0) * 1.5) * wind * moving;
		VERTEX.x += sway * UV.y * (VERTEX.x < 0.0 ? 1.0 : 1.3);
	} else if (part > 1.5 && part < 3.5) {
		float d = VERTEX.x - dish_at.x;
		VERTEX.x = dish_at.x + d * (5.0 + 9.0 * face) / 14.0 + sin(a) * 6.0 + (part > 2.5 ? cos(a) * 2.0 : 0.0);
	}
	// which side of the dish faces us decides the shade
	COLOR = part > 1.5 && part < 2.5 && cos(a) <= 0.0 ? vec4(COLOR.rgb * 0.55, COLOR.a) : COLOR;
}
void fragment() {
	if (part > 3.5 && part < 4.5) {
		COLOR.rgb = mix(vec3(0.353, 0.086, 0.071), vec3(1.0, 0.231, 0.188), lit);
	} else if (part > 4.5) {
		COLOR.a *= lit;
	}
}
"

## The foot of the mast (tiles) and the animation time, wind and whether it moves, as the base's life last gave them.
var foot := Vector2.ZERO
var t := 0.0
var wind := 0.3
var moving := true
## Whether the lamp is lit now, for the glow.
var lit := 0.0
var _mat: ShaderMaterial


func setup(at_tile: Vector2) -> void:
	foot = at_tile
	position = at_tile * TILE
	scale = Vector2(SCALE, SCALE)
	z_index = 7
	name = "Mast"
	_mat = Kit.material(SHADER)
	_mat.set_shader_parameter("dish_at", DISH_AT)
	_mat.set_shader_parameter("blink_s", BLINK_S)
	_mat.set_shader_parameter("blink_on", BLINK_ON)
	material = _mat
	mesh = _bake()


func _bake() -> ArrayMesh:
	var b := Kit.Builder.new()
	var ink := Kit.INK
	# the foot: a steel plate; the mast with a highlight and three struts; a cross arm for the aerials
	b.add_grid(Vector2(-7, -4), Vector2(14, 7), 1, 1, ink, ink)
	b.add_grid(Vector2(-6, -3), Vector2(12, 5), 1, 1, STEEL, STEEL)
	b.add_stroke(Vector2(0, -MAST_H), Vector2(0, 0), 5.0, ink)
	b.add_stroke(Vector2(0, -MAST_H), Vector2(0, 0), 3.0, STEEL)
	b.add_stroke(Vector2(-1.0, -MAST_H + 4.0), Vector2(-1.0, -4.0), 1.0, STEEL_HI)
	for k in 3:
		var y := -22.0 - float(k) * 24.0
		b.add_stroke(Vector2(-6, y + 6), Vector2(6, y - 6), 1.4, STEEL)
	b.add_stroke(Vector2(-9, -MAST_H + 14.0), Vector2(9, -MAST_H + 14.0), 2.0, STEEL)
	# the whips: UV.y is how far up (0 at the arm, 1 at the tip), so the tips sway most
	b.add_stroke(Vector2(-9, -MAST_H + 14.0), Vector2(-10.0, -MAST_H - 20.0), 1.4, STEEL, Vector2(1, 0), Vector2(1, 1))
	b.add_stroke(Vector2(9, -MAST_H + 14.0), Vector2(10.0, -MAST_H - 14.0), 1.4, STEEL, Vector2(1, 0), Vector2(1, 1))
	# the dish (an ink rim, then the face) and its horn
	b.add_ellipse(DISH_AT, 15.4, 12.4, ink, Vector2(2, 0), 14)
	b.add_ellipse(DISH_AT, 14.0, 11.0, STEEL_HI, Vector2(2, 0), 14)
	b.add_ellipse(DISH_AT, 2.2, 2.2, ink, Vector2(3, 0), 6)
	# the lamp on the top: an ink ring, the lamp (its colour is the shader's) and a glint
	var lamp := Vector2(0, -MAST_H - 4.0)
	b.add_ellipse(lamp, 4.4, 4.4, ink, Vector2(0, 0), 8)
	b.add_ellipse(lamp, 3.3, 3.3, LAMP_ON, Vector2(4, 0), 8)
	b.add_ellipse(lamp + Vector2(-1.0, -1.0), 1.2, 1.2, Color(1, 0.85, 0.8), Vector2(5, 0), 6)
	return b.bake()


## Whether the lamp is lit at the animation time `at` (the cycle is BLINK_S, the first BLINK_ON of it is on).
static func lamp_lit(at: float) -> bool:
	return fposmod(at, BLINK_S) < BLINK_S * BLINK_ON


## The dish's angle at that time (turns, scanning back and forth through about a half turn).
static func dish_angle(at: float) -> float:
	return sin(at * 0.7) * 1.3


## Called every frame while the node is shown: the clock, the wind, and whether things move (not "reduce motion").
func tick(_dt: float, clock: float, wind_now: float, animate: bool) -> void:
	moving = animate
	t = clock
	wind = wind_now
	lit = 1.0 if (not animate or lamp_lit(t)) else 0.0
	_mat.set_shader_parameter("t", t)
	_mat.set_shader_parameter("wind", wind)
	_mat.set_shader_parameter("moving", 1.0 if animate else 0.0)


## The red halo of the lamp, in the glow layer (main.gd's glow node calls this with the radial texture and the darkness); in tile units.
func glow_paint(ci: CanvasItem, radial: Texture2D, dark: float) -> void:
	if not visible or lit < 0.5 or dark < 0.05 or radial == null:
		return
	var c := foot + Vector2(0.0, -(MAST_H + 4.0) * SCALE / TILE)
	var r := 0.95
	ci.draw_texture_rect(radial, Rect2(c.x - r, c.y - r, r * 2.0, r * 2.0), false, Color(1.0, 0.2, 0.15, 0.42 * minf(1.0, dark * 1.6)))


## The ground it covers (tiles), for the culling.
func bounds() -> Rect2:
	return Rect2(foot + Vector2(-1.0, -(MAST_H + 30.0) * SCALE / TILE), Vector2(2.0, (MAST_H + 38.0) * SCALE / TILE))
