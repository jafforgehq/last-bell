## Curbs where pavement meets the road, soil lines at grass edges, and the
## painted lane lines and crosswalks.
extends Node2D

const TILE := 64.0

var world
var road_id := 0
var grass_id := 0


func setup(w) -> void:
	world = w
	road_id = int(w.d.terrainTypes.ASPHALT.id)
	grass_id = int(w.d.terrainTypes.GRASS.id)
	queue_redraw()


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
	for y in H:
		for x in W:
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
		else:
			_crosswalk(m)


func _lanes(m: Dictionary) -> void:
	var horiz: bool = m.dir == "h"
	var L: float = m.w if horiz else m.h
	var wd: float = m.h if horiz else m.w
	var c0: float = (m.cx - m.w / 2.0) if horiz else (m.cy - m.h / 2.0)
	draw_set_transform(Vector2(m.cx, m.cy) * TILE, 0.0 if horiz else PI / 2.0, Vector2(TILE, TILE))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(m.seed)
	var t := -L / 2.0
	while t < L / 2.0:
		var ta := t + L / 2.0 + c0
		var gap := false
		for g in m.gaps:
			if ta >= g[0] and ta < g[1]:
				gap = true
		if not gap:
			var wear := 0.5 + rng.randf() * 0.4
			var yellow := Color8(214, 170, 58)
			yellow.a = wear
			draw_rect(Rect2(t, -0.14, 0.5, 0.08), yellow)
			draw_rect(Rect2(t, 0.06, 0.5, 0.08), yellow)
			var white := Color8(226, 222, 208)
			white.a = wear * 0.6
			draw_rect(Rect2(t, -wd / 2.0 + 0.35, 0.5, 0.06), white)
			draw_rect(Rect2(t, wd / 2.0 - 0.41, 0.5, 0.06), white)
		t += 0.5


func _crosswalk(m: Dictionary) -> void:
	var along_y: bool = m.dir == "v"
	var length: float = m.h if along_y else m.w
	var n := int(floor(length / 0.8))
	draw_set_transform(Vector2(m.cx, m.cy) * TILE, 0.0, Vector2(TILE, TILE))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(m.seed)
	for i in n:
		var t := -length / 2.0 + 0.2 + i * 0.8
		var c := Color8(226, 222, 208)
		c.a = 0.45 + rng.randf() * 0.3
		if along_y:
			draw_rect(Rect2(-m.w / 2.0, t, m.w, 0.42), c)
		else:
			draw_rect(Rect2(t, -m.h / 2.0, 0.42, m.h), c)
