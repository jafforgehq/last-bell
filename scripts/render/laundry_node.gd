## Washing on a line (round 24, "base life"): two poles at the quiet south-east corner of the yard, a line that sags between them and five
## pieces hung from it (a shirt, trousers, a sheet, a rusty shirt, a towel) that swing in the wind, harder in rain. One baked mesh in
## ONE draw call; the swing is the vertex shader CLOTH_SHADER of scripts/render/life_kit.gd, moved by the two numbers `t` and `wind`
## that the base's life sets each frame. Nothing is solid: it stands where nobody goes (not the benches, the posts or the gate), over
## the people (z 7) like a thing hung up high. Hidden off the screen by scripts/render/base_life.gd.
extends MeshInstance2D

const Kit := preload("res://scripts/render/life_kit.gd")
const TILE := 64.0
const LINE := Color("#3a2e22")
const WOOD := Color("#4a3624")
const INK := Color(0.10, 0.08, 0.06, 0.8)
## The pieces: x along the line (px), width, hang, colour.
const PIECES := [
	[26.0, 30.0, 38.0, Color("#6f8fb8")],
	[78.0, 24.0, 44.0, Color("#85735a")],
	[128.0, 52.0, 34.0, Color("#eadfc4")],
	[196.0, 28.0, 36.0, Color("#b9573a")],
	[246.0, 26.0, 46.0, Color("#6e9660")],
]
const SPAN := 300.0

var foot := Vector2.ZERO


## `from_tile` is the foot of the west pole; the line runs east from it.
func setup(from_tile: Vector2, cloth_material: ShaderMaterial) -> void:
	foot = from_tile
	position = from_tile * TILE
	z_index = 7
	material = cloth_material
	mesh = _bake()
	name = "Laundry"


func _bake() -> ArrayMesh:
	var b := Kit.Builder.new()
	# the poles (their feet are at the origin's height, they stand a little over the line), then the line, sagging in the middle
	var top := -44.0
	b.add_stroke(Vector2(0, 0), Vector2(0, top - 4.0), 5.0, WOOD)
	b.add_stroke(Vector2(SPAN, 0), Vector2(SPAN, top - 4.0), 5.0, WOOD)
	var prev := Vector2(0, top)
	for i in range(1, 13):
		var u := float(i) / 12.0
		var p := Vector2(SPAN * u, top + sin(u * PI) * 9.0)
		b.add_stroke(prev, p, 1.6, LINE)
		prev = p
	for k in PIECES.size():
		var pc: Array = PIECES[k]
		var x: float = pc[0]
		var sag := sin(x / SPAN * PI) * 9.0
		var w: float = pc[1]
		var h: float = pc[2]
		var y := top + sag
		var col: Color = pc[3]
		# an ink edge under each piece, then the piece: lit at the top, a shade darker at the hem
		var phase := float(k) / float(PIECES.size())
		b.add_grid(Vector2(x - 1.5, y - 1.0), Vector2(w + 3.0, h + 3.0), 1, 4, INK, INK, phase, phase)
		b.add_grid(Vector2(x, y), Vector2(w, h), 1, 4, col.lightened(0.08), col.darkened(0.12), phase, phase)
	return b.bake()


## The ground it covers (tiles), for the culling.
func bounds() -> Rect2:
	return Rect2(foot + Vector2(-0.2, -1.0), Vector2(SPAN / TILE + 0.5, 1.9))
