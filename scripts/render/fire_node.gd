## Flames for a fire barrel, or for the burnt-out car in the street.
## Layered tongues: red-orange outside, yellow inside, a pale core.
extends Node2D

const S := preload("res://scripts/render/shapes.gd")
const TILE := 64.0

const LAYERS := [
	[1.0, Color(214 / 255.0, 72 / 255.0, 22 / 255.0, 0.92), Color(1.0, 110 / 255.0, 30 / 255.0, 0.0)],
	[0.72, Color(1.0, 152 / 255.0, 44 / 255.0, 0.95), Color(1.0, 196 / 255.0, 80 / 255.0, 0.0)],
	[0.42, Color(1.0, 238 / 255.0, 168 / 255.0, 0.95), Color(1.0, 250 / 255.0, 220 / 255.0, 0.0)],
]
# the burnt-out car sits at a slight angle; flames run along it
const CAR_FLAMES := [[-1.5, 0.3, 0.8], [-0.55, -0.1, 1.25], [0.4, 0.25, 1.05], [1.35, -0.05, 0.75]]

var big := false
var fire_t := 0.0


func setup(x: float, y: float, is_big: bool) -> void:
	big = is_big
	position = Vector2(x, y) * TILE


func tick(t: float) -> void:
	fire_t = t
	queue_redraw()


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(TILE, TILE))
	if big:
		var c := cos(0.22)
		var sn := sin(0.22)
		for f in CAR_FLAMES:
			_flames(f[0] * c - f[1] * sn, 0.2 + f[0] * sn + f[1] * c, f[2], f[0] * 7.0, 6)
	else:
		_flames(0.0, 0.2, 0.62, position.x / TILE, 5)


func _flames(x: float, y: float, s: float, seed: float, n: int) -> void:
	for li in LAYERS.size():
		var scale: float = LAYERS[li][0]
		var c0: Color = LAYERS[li][1]
		var c1: Color = LAYERS[li][2]
		for i in n:
			var u := 0.0 if n == 1 else float(i) / float(n - 1) - 0.5
			var ph := fire_t * (5.5 + i * 0.7) + seed * 1.3 + i * 1.9 + li * 0.8
			var fx := x + u * s * 0.62 * (1.0 - li * 0.3) + sin(ph * 0.8) * 0.04 * s
			var h := s * scale * (0.8 + 0.28 * sin(ph) * cos(ph * 0.43)) * (1.0 - absf(u) * 0.9)
			var w := s * 0.17 * scale + 0.015
			_tongue(fx, y, w, h, sin(ph * 1.4) * w * 0.9, c0, c1)


func _tongue(x: float, y: float, w: float, h: float, lean: float, c0: Color, c1: Color) -> void:
	var pts := PackedVector2Array()
	pts.append_array(S.cubic(Vector2(x - w, y), Vector2(x - w * 1.15, y - h * 0.35), Vector2(x + lean - w * 0.35, y - h * 0.72), Vector2(x + lean, y - h), 7))
	var right := S.cubic(Vector2(x + lean, y - h), Vector2(x + lean + w * 0.35, y - h * 0.72), Vector2(x + w * 1.15, y - h * 0.35), Vector2(x + w, y), 7)
	right.remove_at(0)
	pts.append_array(right)
	var base := S.quad(Vector2(x + w, y), Vector2(x, y + w * 0.6), Vector2(x - w, y), 4)
	base.remove_at(0)
	base.remove_at(base.size() - 1)
	pts.append_array(base)
	var cols := PackedColorArray()
	for p in pts:
		var k := clampf((y - p.y) / maxf(h, 0.001), 0.0, 1.0)
		cols.append(c0 if k <= 0.5 else c0.lerp(c1, (k - 0.5) / 0.5))
	draw_polygon(pts, cols)
