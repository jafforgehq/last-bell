## The paint on the ground of one chunk of the town: the gutter and the curb where paving meets the road, the soil line at the edge of grass, and the dashes
## of the lanes (the same colours and shapes as scripts/render/ground_details.gd, but only inside the chunk's rectangle, so that a chunk that is off screen
## costs nothing and a first look draws a chunk, not the whole town). It is drawn once, when it is first visible.
extends Node2D

const TILE := 64.0
## The lane dash: every 0.5 tile, its wear a hash of its place along the road (so that a chunk draws the same dash the whole road would).
const DASH := 0.5

var world
var rect: Rect2
var road_id := 0
var grass_id := 0


func setup(w, r: Rect2) -> void:
	world = w
	rect = r
	road_id = int(w.d.terrainTypes.ASPHALT.id)
	grass_id = int(w.d.terrainTypes.GRASS.id)


func _draw() -> void:
	if world == null:
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(TILE, TILE))
	var W: int = world.W
	var H: int = world.H
	var t_arr: PackedByteArray = world.terrain
	var curb := Color8(206, 202, 190, 230)
	var gutter := Color8(20, 18, 16, 89)
	var soil := Color8(52, 40, 26, 115)
	var x0 := int(rect.position.x)
	var y0 := int(rect.position.y)
	var x1 := mini(W, int(rect.end.x))
	var y1 := mini(H, int(rect.end.y))
	for y in range(y0, y1):
		for x in range(x0, x1):
			var t := t_arr[y * W + x]
			var right := t_arr[y * W + x + 1] if x + 1 < W else t
			var down := t_arr[(y + 1) * W + x] if y + 1 < H else t
			for k in 2:
				var n := right if k == 0 else down
				if n == t:
					continue
				var vert := k == 0
				var ex := float(x + 1) if vert else float(x)
				var ey := float(y) if vert else float(y + 1)
				var t_road := t == road_id
				var n_road := n == road_id
				if t_road != n_road:
					var s := -1 if t_road else 1
					if vert:
						draw_rect(Rect2(ex - (0.1 if s > 0 else 0.0), ey, 0.1, 1.0), gutter)
						draw_rect(Rect2(ex - (0.0 if s > 0 else 0.14), ey, 0.14, 1.0), curb)
					else:
						draw_rect(Rect2(ex, ey - (0.1 if s > 0 else 0.0), 1.0, 0.1), gutter)
						draw_rect(Rect2(ex, ey - (0.0 if s > 0 else 0.14), 1.0, 0.14), curb)
				elif (t == grass_id) != (n == grass_id):
					if vert:
						draw_rect(Rect2(ex - 0.04, ey, 0.08, 1.0), soil)
					else:
						draw_rect(Rect2(ex, ey - 0.04, 1.0, 0.08), soil)
	for m in world.d.marks:
		if m.kind == "lanes":
			_lanes(m)


func _lanes(m: Dictionary) -> void:
	var horiz: bool = m.dir == "h"
	var L: float = m.w if horiz else m.h
	var wd: float = m.h if horiz else m.w
	var c0: float = (m.cx - m.w / 2.0) if horiz else (m.cy - m.h / 2.0)
	# the road must cross the chunk
	var across: float = m.cy if horiz else m.cx
	var chunk_across0 := rect.position.y if horiz else rect.position.x
	var chunk_across1 := rect.end.y if horiz else rect.end.x
	if across + wd / 2.0 < chunk_across0 or across - wd / 2.0 > chunk_across1:
		return
	var a0 := rect.position.x if horiz else rect.position.y
	var a1 := rect.end.x if horiz else rect.end.y
	draw_set_transform(Vector2(m.cx, m.cy) * TILE, 0.0 if horiz else PI / 2.0, Vector2(TILE, TILE))
	var first := int(floor((a0 - c0) / DASH))
	var last := int(ceil((a1 - c0) / DASH))
	for k in range(maxi(0, first), mini(int(L / DASH), last)):
		var ta := c0 + float(k) * DASH
		var gap := false
		for g in m.gaps:
			if ta >= g[0] and ta < g[1]:
				gap = true
				break
		if gap:
			continue
		var t := -L / 2.0 + float(k) * DASH
		var wear := 0.5 + float((k * 2654435761 + int(m.seed) * 40503) & 1023) / 1023.0 * 0.4
		var yellow := Color8(214, 170, 58)
		yellow.a = wear
		draw_rect(Rect2(t, -0.14, DASH, 0.08), yellow)
		draw_rect(Rect2(t, 0.06, DASH, 0.08), yellow)
		var white := Color8(226, 222, 208)
		white.a = wear * 0.6
		draw_rect(Rect2(t, -wd / 2.0 + 0.35, DASH, 0.06), white)
		draw_rect(Rect2(t, wd / 2.0 - 0.41, DASH, 0.06), white)
