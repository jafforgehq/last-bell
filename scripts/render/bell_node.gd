## The school bell (round 24, "base life"; the game is Thirty Bells): a brass bell on a small wooden frame by the north wall, a little east
## of the gate. It hangs still with a faint sway in the wind, and SWINGS and rings when the rules ring a bell (`on_event` is given the
## rules' events by main.gd): the dusk bell with its full swing (and the sound main.gd already plays for it), the call to arms' higher bell
## (`lure`) smaller, a season turning (`season`) wide and slow, a building finished (`built`) a tiny tap. The swing decays over a few
## seconds, the clapper trails it, and while it rings pale rings go out from it, as the sound does. The bell is the title's
## (scripts/ui/bell_glyph.gd's outline and brass), scaled to about three quarters of a tile.
##
## ONE baked mesh in ONE draw call (two while it rings: the rings are a quad of their own, shown only then): the swing is the vertex shader
## below, which turns the bell about the ring it hangs from by `swing` (radians, set each frame), trails the clapper and slides the shadow;
## the rings are a fragment shader of `age`. Nothing is redrawn and nothing is allocated in a frame. Hidden off the screen by
## scripts/render/base_life.gd. Under "reduce motion" it hangs still and does not ring.
##
## The mesh's UV.x says what a vertex belongs to: 0 the frame (still), 1 the bell (turns with it), 2 the clapper (turns, and trails), 3 the shadow.
extends Node2D

const Glyph := preload("res://scripts/ui/bell_glyph.gd")
const Kit := preload("res://scripts/render/life_kit.gd")
const TILE := 64.0
const K := 0.6
const GALLOWS_H := 80.0
const POST_X := 40.0
const PIVOT := Vector2(0.0, -GALLOWS_H)
## How long a ring lasts (seconds), how fast the bell swings (radians a second), and the widest swing (radians) of a full ring.
const RING_S := 7.0
const OMEGA := 5.0
const FULL := 0.42
const WOOD := Color("#5a4028")
const WOOD_HI := Color("#8a6a44")
## What each of the rules' bells swings: the share of FULL.
const STRENGTH := {"bell": 1.0, "lure": 0.6, "season": 0.85, "built": 0.22}

const SHADER := "
shader_type canvas_item;
uniform float swing = 0.0;
uniform float clap = 0.0;
uniform vec2 pivot = vec2(0.0, -80.0);
void vertex() {
	float part = UV.x;
	if (part > 0.5 && part < 2.5) {
		float c = cos(swing);
		float s = sin(swing);
		vec2 d = VERTEX - pivot;
		VERTEX = pivot + vec2(d.x * c - d.y * s, d.x * s + d.y * c);
		if (part > 1.5) {
			VERTEX.x += clap;
		}
	} else if (part > 2.5) {
		VERTEX.x += sin(swing) * 40.0;
	}
}
"

## The rings that go out from the bell while it rings loudly: three, a third of a cycle apart, growing and fading.
const RING_SHADER := "
shader_type canvas_item;
uniform float age = 0.0;
uniform float loud = 0.0;
uniform float cx = 0.0;
void fragment() {
	vec2 p = (UV - 0.5) * 260.0 - vec2(cx, 0.0);
	float d = length(p);
	float a = 0.0;
	for (int i = 0; i < 3; i++) {
		float k = fract(age * 0.9 + float(i) / 3.0);
		float r = 30.0 + k * 90.0;
		a += (1.0 - k) * (1.0 - smoothstep(0.0, 2.4, abs(d - r)));
	}
	COLOR = vec4(1.0, 0.95, 0.75, clamp(a, 0.0, 1.0) * loud * 0.5);
}
"

var foot := Vector2.ZERO
var t := 0.0
var wind := 0.3
var moving := true
## The widest swing left now (radians) and the seconds since the last ring began (-1 when it never has).
var amp := 0.0
var age := -1.0
var rings := 0
## The angle and the clapper's lag it was last given (for the tests).
var angle := 0.0
var _mat: ShaderMaterial
var _ring_mat: ShaderMaterial
var _body: MeshInstance2D
var _ring_quad: MeshInstance2D


func setup(at_tile: Vector2) -> void:
	foot = at_tile
	position = at_tile * TILE
	z_index = 7
	name = "Bell"
	_mat = Kit.material(SHADER)
	_mat.set_shader_parameter("pivot", PIVOT)
	_body = MeshInstance2D.new()
	_body.name = "Body"
	_body.mesh = _bake()
	_body.material = _mat
	add_child(_body)
	var q := Kit.Builder.new()
	q.add_grid(Vector2(-130.0, PIVOT.y + 42.0 - 130.0), Vector2(260.0, 260.0), 1, 1, Color.WHITE, Color.WHITE, 0.0, 1.0)
	_ring_quad = MeshInstance2D.new()
	_ring_quad.name = "Rings"
	_ring_quad.mesh = q.bake()
	_ring_mat = Kit.material(RING_SHADER)
	_ring_quad.material = _ring_mat
	_ring_quad.visible = false
	add_child(_ring_quad)


func _bake() -> ArrayMesh:
	var b := Kit.Builder.new()
	var ink := Kit.INK
	# the shadow on the ground (it slides with the swing)
	b.add_ellipse(Vector2(0.0, 2.0), 26.0, 8.0, Color(0, 0, 0, 0.22), Vector2(3, 0), 14)
	# the frame: two posts with a foot each, two braces, a beam across the top
	for s in [-1.0, 1.0]:
		b.add_stroke(Vector2(s * POST_X, 2.0), Vector2(s * POST_X, PIVOT.y - 6.0), 8.0, ink)
		b.add_stroke(Vector2(s * POST_X, 2.0), Vector2(s * POST_X, PIVOT.y - 6.0), 5.0, WOOD)
		b.add_stroke(Vector2(s * POST_X - 1.5, -6.0), Vector2(s * POST_X - 1.5, PIVOT.y - 4.0), 1.2, WOOD_HI)
		b.add_grid(Vector2(s * POST_X - 7.0, -2.0), Vector2(14.0, 6.0), 1, 1, ink, ink)
		b.add_grid(Vector2(s * POST_X - 6.0, -1.0), Vector2(12.0, 4.0), 1, 1, WOOD, WOOD)
		b.add_stroke(Vector2(s * POST_X, PIVOT.y + 22.0), Vector2(s * (POST_X - 16.0), PIVOT.y - 2.0), 3.0, WOOD)
	b.add_stroke(Vector2(-POST_X - 6.0, PIVOT.y - 6.0), Vector2(POST_X + 6.0, PIVOT.y - 6.0), 10.0, ink)
	b.add_stroke(Vector2(-POST_X - 5.0, PIVOT.y - 6.0), Vector2(POST_X + 5.0, PIVOT.y - 6.0), 7.0, WOOD)
	b.add_stroke(Vector2(-POST_X - 4.0, PIVOT.y - 8.0), Vector2(POST_X + 4.0, PIVOT.y - 8.0), 1.4, WOOD_HI)
	# the clapper, behind the lip (it trails the swing: UV.x 2)
	var clap_at := PIVOT + (Glyph.CLAPPER - Glyph.RING) * K
	b.add_ellipse(clap_at, (Glyph.CLAPPER_R + 1.2) * K, (Glyph.CLAPPER_R + 1.2) * K, Glyph.RIM, Vector2(2, 0), 8)
	b.add_ellipse(clap_at, Glyph.CLAPPER_R * K, Glyph.CLAPPER_R * K, Glyph.DEEP, Vector2(2, 0), 8)
	# the bell, brass lit from the left (the title's colours), with a rim under it
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.3, 0.68, 1.0])
	ramp.colors = PackedColorArray([Glyph.LIGHT, Glyph.MID, Glyph.DEEP, Glyph.SHADE])
	var outline := PackedVector2Array()
	var rim := PackedVector2Array()
	var cols := PackedColorArray()
	var centre := PIVOT + (Vector2(Glyph.CENTER_X, 50.0) - Glyph.RING) * K
	for p in Glyph.body_points():
		var q: Vector2 = PIVOT + (p - Glyph.RING) * K
		outline.append(q)
		rim.append(centre + (q - centre) * 1.07)
		cols.append(ramp.sample(clampf((p.x - Glyph.CENTER_X) / 96.0 + 0.4, 0.0, 1.0)))
	var rim_cols := PackedColorArray()
	rim_cols.resize(rim.size())
	rim_cols.fill(Glyph.RIM)
	b.add_fan(centre, Glyph.RIM, rim, rim_cols, Vector2(1, 0))
	b.add_fan(centre, Glyph.MID, outline, cols, Vector2(1, 0))
	# the lip: a band across the bottom with a glint, and the ring it hangs from
	var lip_at := PIVOT + (Vector2(Glyph.CENTER_X - Glyph.LIP_HALF, Glyph.LIP_Y) - Glyph.RING) * K
	var lip_size := Vector2(Glyph.LIP_HALF * 2.0, Glyph.LIP_H) * K
	b.add_grid(lip_at - Vector2(1.0, 1.0), lip_size + Vector2(2.0, 2.0), 1, 1, Glyph.RIM, Glyph.RIM, 1.0, 1.0)
	b.add_grid(lip_at, lip_size, 1, 1, Glyph.DEEP, Glyph.DEEP, 1.0, 1.0)
	b.add_grid(lip_at + Vector2(1.5, 1.2), Vector2(lip_size.x * 0.34, 1.8), 1, 1, Glyph.LIGHT, Glyph.LIGHT, 1.0, 1.0)
	b.add_ellipse(PIVOT, 5.0, 5.0, Glyph.RIM, Vector2(1, 0), 8)
	b.add_ellipse(PIVOT, 2.6, 2.6, Glyph.MID, Vector2(1, 0), 8)
	return b.bake()


## The rules rang a bell: the event's type says which (`bell`, `lure`, `season`, `built`). Returns whether the node swings for it.
func on_event(e: Dictionary) -> bool:
	var strength: float = float(STRENGTH.get(String(e.get("type", "")), 0.0))
	if strength <= 0.0 or not moving:
		return false
	# a ring that comes while another is still going adds to it (never past a full swing)
	amp = minf(FULL, maxf(amp, FULL * strength) if amp > 0.01 else FULL * strength)
	age = 0.0
	rings += 1
	return true


## The widest swing now: a full ring dies away as exp(-age / 2.2) over RING_S seconds.
func swing_now() -> float:
	return amp * exp(-maxf(age, 0.0) / 2.2) if age >= 0.0 and age < RING_S else 0.0


func is_ringing() -> bool:
	return swing_now() > 0.01


## Called every frame while the node is shown: the clock, the wind, whether it moves; turns the bell and shows or hides the rings.
func tick(dt: float, clock: float, wind_now: float, animate: bool) -> void:
	moving = animate
	t = clock
	wind = wind_now
	if age >= 0.0:
		age += dt
		if age >= RING_S:
			age = -1.0
			amp = 0.0
	var sw := swing_now()
	angle = (sin(age * OMEGA) * sw if age >= 0.0 else 0.0) + (sin(t * 1.15) * 0.04 * wind if moving else 0.0)
	_mat.set_shader_parameter("swing", angle)
	_mat.set_shader_parameter("clap", -sin(angle * 8.0) * 6.0 * minf(1.0, sw * 6.0))
	var loud := sw > 0.05
	_ring_quad.visible = loud
	if loud:
		_ring_mat.set_shader_parameter("age", age)
		_ring_mat.set_shader_parameter("loud", minf(1.0, sw * 3.0))
		_ring_mat.set_shader_parameter("cx", sin(angle) * 34.0)


## The ground it covers (tiles), for the culling (the rings reach about two tiles).
func bounds() -> Rect2:
	return Rect2(foot + Vector2(-2.2, -3.2), Vector2(4.4, 3.9))
