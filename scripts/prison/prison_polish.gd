## ART PASS (round 11): static ground polish for the prison game only, drawn under the walls and props in 16 x 16 tile chunks (so the camera culls them).
## One light direction everywhere: upper left, so shadows fall to the right and down. Nothing here touches the rules; it reads the world's terrain grid, its objects and (in the base) the Base layout.
## Layers: z 0 ground variety (stains, patches, tyre marks, trampled grass, mud, bones), z 1 floors per room, wall ambient occlusion, prop contact shadows, cell door bars.
extends RefCounted

const TILE := 64.0
const CHUNK := 16
const CONCRETE := preload("res://assets/terrain/concrete.png")
const DrawNode := preload("res://scripts/render/draw_node.gd")

const T_CONCRETE := 12
const T_WALL := 20
## The look of a ground tile is its kit group (TownArt.GROUNDS index; the prison's own G_ codes are one off from the names, so the look is not the terrain id).
const G_LAWN := 0
const G_ASPHALT := 1
const G_SIDEWALK := 2
const G_PATH := 3

var world
var base    # prison_base.gd instance in the base, null in a raid
var W := 0
var H := 0
var T := PackedByteArray()
var GR := PackedByteArray()
var lanes: Array = []
var seed_i := 1


static func install(w, the_base, seed_v: int) -> void:
	var p := new()
	p.world = w
	p.base = the_base
	p.seed_i = seed_v
	p.W = w.W
	p.H = w.H
	p.T = w.terrain
	p.GR = w.grp
	for m in w.d.marks:
		if String(m.kind) == "lanes":
			p.lanes.append(m)
	w.set_meta("polish", p)    # (the painters are Callables on a RefCounted: keep it alive)
	var low := Node2D.new()
	low.name = "PolishGround"
	low.z_index = 0
	var high := Node2D.new()
	high.name = "PolishFloor"
	high.z_index = 1
	w.add_child(low)
	w.add_child(high)
	var top := Node2D.new()
	top.name = "PolishFence"
	top.z_index = 5
	w.add_child(top)
	for cy in range(0, p.H, CHUNK):
		for cx in range(0, p.W, CHUNK):
			var a := DrawNode.new()
			a.painter = Callable(p, "_ground").bind(cx, cy)
			low.add_child(a)
			var b := DrawNode.new()
			b.painter = Callable(p, "_floor").bind(cx, cy)
			high.add_child(b)
			if the_base != null:
				var f := DrawNode.new()
				f.painter = Callable(p, "_fence").bind(cx, cy)
				top.add_child(f)


# ------------------------------------------------------------------ helpers --

func _r(x: float, y: float, k: int) -> float:
	return fposmod(sin(x * 127.1 + y * 311.7 + float(k) * 74.7 + float(seed_i) * 0.37) * 43758.5453, 1.0)


func _t(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= W or y >= H:
		return -1
	return T[y * W + x]


func _g(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= W or y >= H:
		return -1
	return GR[y * W + x]


func _wall(x: int, y: int) -> bool:
	return _t(x, y) >= T_WALL


## A soft blob: a few stacked ellipses of falling size, so the edge fades.
func _blob(c: CanvasItem, p: Vector2, rx: float, ry: float, rot: float, col: Color, layers: int = 3) -> void:
	for i in layers:
		var k := 1.0 - float(i) / float(layers) * 0.6
		var pts := PackedVector2Array()
		for j in 12:
			var a := TAU * float(j) / 12.0
			var v := Vector2(cos(a) * rx * k, sin(a) * ry * k).rotated(rot) + p
			pts.append(v)
		c.draw_colored_polygon(pts, Color(col.r, col.g, col.b, col.a / float(layers) * 1.6))


func _in_lane(x: float, y: float) -> bool:
	for m in lanes:
		var hw := float(m.w) / 2.0
		var hh := float(m.h) / 2.0
		if absf(x - float(m.cx)) <= hw and absf(y - float(m.cy)) <= hh:
			if String(m.dir) == "h" and absf(y - float(m.cy)) < 0.5:
				return true
			if String(m.dir) != "h" and absf(x - float(m.cx)) < 0.5:
				return true
	return false


# -------------------------------------------------------------- z 0: ground --

func _ground(c: CanvasItem, cx: int, cy: int) -> void:
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2(TILE, TILE))
	for y in range(cy, mini(cy + CHUNK, H)):
		for x in range(cx, mini(cx + CHUNK, W)):
			var t := _g(x, y)
			var fx := float(x)
			var fy := float(y)
			var o := Vector2(_r(fx, fy, 1), _r(fx, fy, 2))
			match t:
				G_ASPHALT:
					if _in_lane(fx + 0.5, fy + 0.5):
						continue
					if _r(fx, fy, 3) < 0.10:    # oil
						_blob(c, Vector2(fx, fy) + o, 0.22 + o.x * 0.2, 0.15 + o.y * 0.15, o.x * 3.0, Color(0.02, 0.02, 0.03, 0.30))
						_blob(c, Vector2(fx, fy) + o + Vector2(-0.03, -0.03), 0.1, 0.07, o.x * 3.0, Color(0.30, 0.34, 0.45, 0.10), 2)
					elif _r(fx, fy, 4) < 0.05:    # a repaired patch
						var pr := Rect2(fx + 0.1 + o.x * 0.2, fy + 0.15 + o.y * 0.2, 0.55 + o.y * 0.2, 0.4 + o.x * 0.2)
						c.draw_rect(pr, Color(0.07, 0.07, 0.09, 0.14))
						c.draw_rect(pr, Color(0.0, 0.0, 0.0, 0.2), false, 0.015)
					elif _r(fx, fy, 5) < 0.025:    # a pothole: dark centre, crumbled rim, a little rain in it
						_blob(c, Vector2(fx, fy) + o, 0.3, 0.22, o.x * 3.0, Color(0.05, 0.05, 0.06, 0.35))
						_blob(c, Vector2(fx, fy) + o + Vector2(0.03, 0.03), 0.17, 0.11, o.x * 3.0, Color(0.0, 0.0, 0.0, 0.55))
						_blob(c, Vector2(fx, fy) + o + Vector2(-0.05, -0.04), 0.07, 0.04, o.x * 3.0, Color(0.5, 0.58, 0.7, 0.22), 2)
				G_SIDEWALK:
					if _r(fx, fy, 6) < 0.22:    # damp or stained slab: breaks the repeat of the texture
						_blob(c, Vector2(fx, fy) + o, 0.35 + o.x * 0.4, 0.3 + o.y * 0.3, o.y * 3.0, Color(0.10, 0.09, 0.08, 0.10 + o.x * 0.08))
					if _r(fx, fy, 7) < 0.05:
						_blob(c, Vector2(fx, fy) + o, 0.12, 0.09, o.x * 3.0, Color(0.03, 0.02, 0.02, 0.32))    # oil
					if _r(fx, fy, 8) < 0.04:    # a lighter, swept slab
						c.draw_rect(Rect2(fx, fy, 1, 1), Color(1, 1, 1, 0.045))
				G_PATH:
					if _r(fx, fy, 9) < 0.28:
						_blob(c, Vector2(fx, fy) + o, 0.3 + o.x * 0.3, 0.2 + o.y * 0.2, o.y * 3.0, Color(0.12, 0.08, 0.04, 0.16))
					if _r(fx, fy, 10) < 0.18:
						_blob(c, Vector2(fx, fy) + o, 0.25, 0.16, o.y * 3.0, Color(0.78, 0.68, 0.5, 0.07))
					if _r(fx, fy, 11) < 0.10:    # pebbles
						for k in 3:
							var q := Vector2(_r(fx, fy, 20 + k), _r(fx, fy, 30 + k))
							c.draw_circle(Vector2(fx, fy) + q, 0.03 + q.x * 0.02, Color(0.18, 0.15, 0.12, 0.55))
				G_LAWN:
					if _r(fx, fy, 12) < 0.07:
						_blob(c, Vector2(fx, fy) + o, 0.5 + o.x * 0.4, 0.35 + o.y * 0.3, o.y * 3.0, Color(0.06, 0.12, 0.04, 0.16))
					for k in 2:    # tufts: three short strokes
						if _r(fx, fy, 40 + k) < 0.55:
							var q := Vector2(_r(fx, fy, 50 + k), _r(fx, fy, 60 + k))
							var col := Color(0.10, 0.22, 0.08, 0.55) if _r(fx, fy, 70 + k) < 0.5 else Color(0.5, 0.58, 0.25, 0.45)
							var b := Vector2(fx, fy) + q
							c.draw_line(b, b + Vector2(-0.05, -0.12), col, 0.025)
							c.draw_line(b, b + Vector2(0.0, -0.15), col, 0.025)
							c.draw_line(b, b + Vector2(0.06, -0.11), col, 0.025)
	for m in lanes:
		_tyres(c, m, cx, cy)
	if base != null:
		_outside(c, cx, cy)
		_yard_marks(c, cx, cy)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _tyres(c: CanvasItem, m: Dictionary, cx: int, cy: int) -> void:
	var horiz := String(m.dir) == "h"
	var len_t := float(m.w) if horiz else float(m.h)
	var wid_t := float(m.h) if horiz else float(m.w)
	var c0 := (float(m.cx) if horiz else float(m.cy)) - len_t / 2.0
	var cc := float(m.cy) if horiz else float(m.cx)
	var n := int(len_t / 3.0)
	for i in n:
		var a := c0 + _r(float(i), cc, 80) * len_t
		var seg := 2.0 + _r(float(i), cc, 81) * 5.0
		var off := (_r(float(i), cc, 82) - 0.5) * (wid_t - 1.6)
		if absf(off) < 0.5:
			off += 0.9 if off >= 0.0 else -0.9
		for k in 2:
			var d := off + (-0.28 if k == 0 else 0.28)
			var p0 := Vector2(a, cc + d) if horiz else Vector2(cc + d, a)
			var p1 := Vector2(a + seg, cc + d) if horiz else Vector2(cc + d, a + seg)
			var mid := (p0 + p1) / 2.0
			if int(mid.x) < cx or int(mid.x) >= cx + CHUNK or int(mid.y) < cy or int(mid.y) >= cy + CHUNK:
				continue
			c.draw_line(p0, p1, Color(0.0, 0.0, 0.0, 0.14), 0.06)


## The base only: the dead press on the fence south of the gate, and trample the grass to bare mud; bones and rags in it.
func _outside(c: CanvasItem, cx: int, cy: int) -> void:
	var gx: float = 48.0
	var fy: float = float(base.FENCE.end.y)
	for i in 70:
		var x := gx + (_r(float(i), 1.0, 90) + _r(float(i), 2.0, 91) - 1.0) * 26.0
		var y := fy + 0.2 + _r(float(i), 3.0, 92) * 3.2
		if int(x) < cx or int(x) >= cx + CHUNK or int(y) < cy or int(y) >= cy + CHUNK:
			continue
		if _g(int(x), int(y)) != G_LAWN:
			continue
		var f := 1.0 - minf(absf(x - gx) / 26.0, 1.0)
		_blob(c, Vector2(x, y), 0.8 + _r(float(i), 4.0, 93), 0.4 + _r(float(i), 5.0, 94) * 0.4, 0.0, Color(0.20, 0.14, 0.08, 0.20 * f + 0.04))
	for i in 18:    # mud with a wet shine
		var x := gx + (_r(float(i), 6.0, 95) - 0.5) * 30.0
		var y := fy + 0.4 + _r(float(i), 7.0, 96) * 2.6
		if int(x) < cx or int(x) >= cx + CHUNK or int(y) < cy or int(y) >= cy + CHUNK or _g(int(x), int(y)) != G_LAWN:
			continue
		_blob(c, Vector2(x, y), 0.5 + _r(float(i), 8.0, 97) * 0.4, 0.28, _r(float(i), 9.0, 98) * 0.6, Color(0.13, 0.09, 0.05, 0.38))
		_blob(c, Vector2(x - 0.1, y - 0.07), 0.2, 0.09, 0.0, Color(0.6, 0.62, 0.6, 0.14), 2)
	for i in 26:    # bones and rags
		var x := gx + (_r(float(i), 10.0, 99) - 0.5) * 36.0
		var y := fy + 0.3 + _r(float(i), 11.0, 100) * 3.4
		if int(x) < cx or int(x) >= cx + CHUNK or int(y) < cy or int(y) >= cy + CHUNK or _g(int(x), int(y)) != G_LAWN:
			continue
		var a := _r(float(i), 12.0, 101) * TAU
		var d := Vector2(cos(a), sin(a)) * (0.07 + _r(float(i), 13.0, 102) * 0.08)
		if i % 5 == 0:
			c.draw_circle(Vector2(x, y), 0.07, Color(0.82, 0.8, 0.7, 0.9))    # a skull
			c.draw_circle(Vector2(x - 0.025, y), 0.016, Color(0.1, 0.08, 0.06))
			c.draw_circle(Vector2(x + 0.025, y), 0.016, Color(0.1, 0.08, 0.06))
		elif i % 3 == 0:
			var cols := [Color(0.35, 0.18, 0.15, 0.8), Color(0.25, 0.3, 0.35, 0.8), Color(0.4, 0.38, 0.3, 0.8)]
			c.draw_colored_polygon(PackedVector2Array([Vector2(x, y), Vector2(x + 0.22, y + 0.05), Vector2(x + 0.15, y + 0.2), Vector2(x - 0.05, y + 0.14)]), cols[i % 3])
		else:
			c.draw_line(Vector2(x, y) - d, Vector2(x, y) + d, Color(0.0, 0.0, 0.0, 0.3), 0.07)
			c.draw_line(Vector2(x, y) - d + Vector2(-0.01, -0.01), Vector2(x, y) + d + Vector2(-0.01, -0.01), Color(0.86, 0.84, 0.74, 0.95), 0.05)
	# paths worn by the guards inside: bare strips along the fence
	for i in 26:
		var x: float = float(base.FENCE.position.x) + 2.0 + float(i) * 3.4
		var y: float = float(base.FENCE.end.y) - 2.2 + (_r(float(i), 14.0, 103) - 0.5) * 0.5
		if int(x) < cx or int(x) >= cx + CHUNK or int(y) < cy or int(y) >= cy + CHUNK:
			continue
		_blob(c, Vector2(x, y), 1.5, 0.35, 0.0, Color(0.1, 0.07, 0.04, 0.16))


## Tyre ruts and oil where the truck stands, a scorch ring at each fire.
func _yard_marks(c: CanvasItem, cx: int, cy: int) -> void:
	var tp: Vector2 = base.stations["truck"]
	for k in 2:
		var y := tp.y + (-0.7 if k == 0 else 0.7)
		var x0 := tp.x - 3.0
		if int(tp.x) < cx or int(tp.x) >= cx + CHUNK or int(y) < cy or int(y) >= cy + CHUNK:
			continue
		c.draw_line(Vector2(x0, y), Vector2(tp.x + 3.0, y), Color(0, 0, 0, 0.18), 0.1)
	for f in base.fires:
		var fv: Vector2 = f
		if int(fv.x) < cx or int(fv.x) >= cx + CHUNK or int(fv.y) < cy or int(fv.y) >= cy + CHUNK:
			continue
		_blob(c, fv, 1.1, 0.95, 0.0, Color(0.03, 0.02, 0.02, 0.42))
		for j in 8:
			var a := TAU * float(j) / 8.0 + 0.3
			c.draw_circle(fv + Vector2(cos(a), sin(a)) * 0.62, 0.07, Color(0.28, 0.27, 0.26, 0.9))    # fire ring stones


# -------------------------------------------------------------- z 1: floors --

func _floor(c: CanvasItem, cx: int, cy: int) -> void:
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2(TILE, TILE))
	if base != null:
		_rooms(c, cx, cy)
	_ao(c, cx, cy)
	_shadows(c, cx, cy)
	if base != null:
		_bars(c, cx, cy)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _floor_tile(c: CanvasItem, x: int, y: int, kind: String) -> void:
	var fx := float(x)
	var fy := float(y)
	var o := Vector2(_r(fx, fy, 110), _r(fx, fy, 111))
	match kind:
		"cell", "work", "store":
			var src := Rect2(o.x * 384.0, o.y * 384.0, 128.0, 128.0)
			var v := 0.82 + _r(fx, fy, 112) * 0.2
			var tint := Color(v, v, v * 1.02) if kind == "cell" else Color(v * 0.95, v * 0.95, v * 0.92)
			c.draw_texture_rect_region(CONCRETE, Rect2(fx, fy, 1, 1), src, tint)
			c.draw_rect(Rect2(fx, fy + 0.96, 1, 0.04), Color(0, 0, 0, 0.35))    # slab joints
			c.draw_rect(Rect2(fx + 0.96, fy, 0.04, 1), Color(0, 0, 0, 0.30))
			c.draw_rect(Rect2(fx, fy, 1, 0.025), Color(1, 1, 1, 0.07))
			if _r(fx, fy, 113) < 0.3:
				_blob(c, Vector2(fx, fy) + o, 0.3 + o.x * 0.3, 0.25, o.y * 3.0, Color(0.08, 0.08, 0.07, 0.14))
			if kind == "work" and _r(fx, fy, 114) < 0.12:
				_blob(c, Vector2(fx, fy) + o, 0.15 + o.y * 0.3, 0.1 + o.x * 0.16, o.x * 6.0, Color(0.02, 0.02, 0.02, 0.34))    # oil
				_blob(c, Vector2(fx, fy) + o + Vector2(-0.04, -0.03), 0.1, 0.06, o.x * 3.0, Color(0.4, 0.4, 0.55, 0.12), 2)
		"tile", "lino", "ktile":
			var a := Color(0.74, 0.72, 0.63) if kind == "tile" else (Color(0.78, 0.84, 0.82) if kind == "lino" else Color(0.50, 0.52, 0.5))
			var b := Color(0.50, 0.55, 0.51) if kind == "tile" else (Color(0.66, 0.74, 0.72) if kind == "lino" else Color(0.36, 0.39, 0.38))
			for j in 4:
				var q := Vector2(float(j % 2), float(j / 2)) * 0.5
				var col := a if (j + x + y) % 2 == 0 else b
				var v := 0.9 + _r(fx + q.x, fy + q.y, 115) * 0.14
				c.draw_rect(Rect2(fx + q.x, fy + q.y, 0.5, 0.5), Color(col.r * v, col.g * v, col.b * v))
			c.draw_rect(Rect2(fx, fy + 0.49, 1, 0.02), Color(0.2, 0.2, 0.18, 0.35))    # grout
			c.draw_rect(Rect2(fx + 0.49, fy, 0.02, 1), Color(0.2, 0.2, 0.18, 0.35))
			c.draw_rect(Rect2(fx, fy + 0.97, 1, 0.03), Color(0.1, 0.1, 0.08, 0.30))
			if _r(fx, fy, 116) < 0.22:
				_blob(c, Vector2(fx, fy) + o, 0.3, 0.22, o.y * 3.0, Color(0.15, 0.12, 0.08, 0.16))    # scuffs and grime


func _room_kind(x: int, y: int) -> String:
	if _wall(x, y) or _t(x, y) != T_CONCRETE and _t(x, y) != 7:
		return ""
	for z in base.ZONES:
		var r: Rect2i = z.rect
		if not r.has_point(Vector2i(x, y)):
			continue
		match String(z.id):
			"cella", "cellb":
				return "cell"
			"canteen":
				return "ktile" if y < 13 else "tile"
			"infirmary":
				return "lino"
			"workshop":
				return "work"
			"stores":
				return "store"
	return ""


func _rooms(c: CanvasItem, cx: int, cy: int) -> void:
	for y in range(cy, mini(cy + CHUNK, H)):
		for x in range(cx, mini(cx + CHUNK, W)):
			var k := _room_kind(x, y)
			if k != "":
				_floor_tile(c, x, y, k)
	# drains in the cells and the corridor
	for z in base.ZONES:
		var id := String(z.id)
		if id != "cella" and id != "cellb":
			continue
		var r: Rect2i = z.rect
		for row in 2:
			for i in 6:
				var gx := float(r.position.x + 1 + i * 4) + 1.5
				var gy := float(r.position.y + (3 if row == 0 else 11)) + 0.55
				if int(gx) < cx or int(gx) >= cx + CHUNK or int(gy) < cy or int(gy) >= cy + CHUNK:
					continue
				_drain(c, Vector2(gx, gy))
		for i in 4:    # corridor gutter drains
			var gx := float(r.position.x + 3 + i * 6)
			var gy := float(r.position.y + 7) + 0.5
			if int(gx) >= cx and int(gx) < cx + CHUNK and int(gy) >= cy and int(gy) < cy + CHUNK:
				_drain(c, Vector2(gx, gy))


func _drain(c: CanvasItem, p: Vector2) -> void:
	_blob(c, p, 0.36, 0.3, 0.0, Color(0.0, 0.0, 0.0, 0.25))
	c.draw_circle(p, 0.15, Color(0.11, 0.11, 0.12))
	c.draw_arc(p, 0.15, 0.0, TAU, 14, Color(0.4, 0.4, 0.42), 0.025)
	for k in 5:
		var xx := -0.1 + float(k) * 0.05
		c.draw_line(p + Vector2(xx, -0.1), p + Vector2(xx, 0.1), Color(0.34, 0.34, 0.36), 0.018)


## Ambient occlusion where a wall meets the ground. Light comes from the upper left: a long soft shadow to the right and down, a thin dark seam on the lit sides.
func _ao(c: CanvasItem, cx: int, cy: int) -> void:
	var dark := Color(0.02, 0.015, 0.01, 0.34)
	var none := Color(0.02, 0.015, 0.01, 0.0)
	for y in range(cy, mini(cy + CHUNK, H)):
		for x in range(cx, mini(cx + CHUNK, W)):
			if not _wall(x, y):
				continue
			var fx := float(x)
			var fy := float(y)
			if _t(x + 1, y) >= 0 and not _wall(x + 1, y) and _t(x + 1, y) != 0:
				_grad(c, Vector2(fx + 1.0, fy), Vector2(0.55, 1.0), true, dark, none)
			if _t(x, y + 1) >= 0 and not _wall(x, y + 1) and _t(x, y + 1) != 0:
				_grad(c, Vector2(fx, fy + 1.0), Vector2(1.0, 0.6), false, dark, none)
			if _t(x - 1, y) >= 0 and not _wall(x - 1, y):
				_grad(c, Vector2(fx - 0.2, fy), Vector2(0.2, 1.0), true, none, Color(dark.r, dark.g, dark.b, 0.2))
			if _t(x, y - 1) >= 0 and not _wall(x, y - 1):
				_grad(c, Vector2(fx, fy - 0.22), Vector2(1.0, 0.22), false, none, Color(dark.r, dark.g, dark.b, 0.2))


## A quad with a colour ramp: `horiz` ramps along x (from `a` at the left edge to `b` at the right), else along y.
func _grad(c: CanvasItem, p: Vector2, s: Vector2, horiz: bool, a: Color, b: Color) -> void:
	var pts := PackedVector2Array([p, p + Vector2(s.x, 0), p + s, p + Vector2(0, s.y)])
	var cols := PackedColorArray([a, b, b, a]) if horiz else PackedColorArray([a, a, b, b])
	c.draw_polygon(pts, cols)


## Contact shadows under every solid prop (the sprites carry only a dark outline).
func _shadows(c: CanvasItem, cx: int, cy: int) -> void:
	for o in world.d.objects:
		if not bool(o.get("solid", false)):
			continue
		var kind := String(o.kind)
		if kind.contains("fence") or kind.contains("wall") or kind.contains("lamp") or kind.contains("walkway") or kind.contains("tower") or kind.contains("ladder") or kind == "campfire" or kind.begins_with("car") or kind.contains("truck") or kind.contains("van") or kind.contains("bus") or float(o.w) * float(o.h) > 12.0:
			continue
		var w := float(o.w)
		var h := float(o.h)
		var f := String(o.get("facing", "s"))
		if f == "e" or f == "w":
			var tmp := w
			w = h
			h = tmp
		var ox := float(o.cx)
		var oy := float(o.cy)
		if int(ox) < cx - 1 or int(ox) >= cx + CHUNK + 1 or int(oy) < cy - 1 or int(oy) >= cy + CHUNK + 1:
			continue
		for i in 3:
			var g := 0.05 + float(i) * 0.035
			var r := Rect2(ox - w / 2.0 + 0.1 + g * 0.5, oy - h / 2.0 + 0.14 + g * 0.5, w + g, h + g)
			c.draw_rect(r, Color(0.02, 0.015, 0.01, 0.11))


## The cell doors: a barred sliding door pushed open to one side, with a lock box.
func _bars(c: CanvasItem, cx: int, cy: int) -> void:
	for z in base.ZONES:
		var id := String(z.id)
		if id != "cella" and id != "cellb":
			continue
		var r: Rect2i = z.rect
		for row in 2:
			var wy := float(r.position.y + (5 if row == 0 else 9))
			for i in 6:
				var dx := float(r.position.x + 1 + i * 4) + 1.0
				if int(dx) < cx or int(dx) >= cx + CHUNK or int(wy) < cy or int(wy) >= cy + CHUNK:
					continue
				var y := wy + 0.5
				var steel := Color(0.28, 0.3, 0.33)
				var lit := Color(0.62, 0.64, 0.68)
				c.draw_rect(Rect2(dx - 0.05, wy - 0.02, 0.08, 1.04), Color(0.12, 0.12, 0.13))    # jambs
				c.draw_rect(Rect2(dx + 0.97, wy - 0.02, 0.08, 1.04), Color(0.12, 0.12, 0.13))
				var x0 := dx + 0.08
				for k in 5:    # the sliding leaf, pushed half open
					var bx := x0 + float(k) * 0.11
					c.draw_line(Vector2(bx + 0.02, y - 0.5), Vector2(bx + 0.02, y + 0.5), Color(0, 0, 0, 0.35), 0.05)
					c.draw_line(Vector2(bx, y - 0.5), Vector2(bx, y + 0.5), steel, 0.04)
					c.draw_line(Vector2(bx - 0.01, y - 0.5), Vector2(bx - 0.01, y + 0.5), lit, 0.012)
				c.draw_rect(Rect2(x0 - 0.04, y - 0.12, 0.52, 0.05), steel)
				c.draw_rect(Rect2(x0 - 0.04, y + 0.07, 0.52, 0.05), steel)
				c.draw_rect(Rect2(dx + 0.55, y - 0.07, 0.1, 0.14), Color(0.66, 0.56, 0.2))    # padlock box


# -------------------------------------------------------------- the fence --

## Razor wire along the top of the chain-link and the shadow it throws (down and to the right, like every other shadow).
func _fence(c: CanvasItem, cx: int, cy: int) -> void:
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2(TILE, TILE))
	for y in range(cy, mini(cy + CHUNK, H)):
		for x in range(cx, mini(cx + CHUNK, W)):
			if base.kl[y * W + x] != 3:
				continue
			var horiz: bool = (x > 0 and base.kl[y * W + x - 1] != 0) or (x + 1 < W and base.kl[y * W + x + 1] != 0)
			var vert: bool = (y > 0 and base.kl[(y - 1) * W + x] != 0) or (y + 1 < H and base.kl[(y + 1) * W + x] != 0)
			var fx := float(x)
			var fy := float(y)
			if horiz and not (vert and x % 2 == 0 and false):
				c.draw_rect(Rect2(fx, fy + 0.58, 1.0, 0.1), Color(0.02, 0.02, 0.01, 0.2))    # the shadow on the ground
				_coil(c, Vector2(fx, fy + 0.42), Vector2(1.0, 0.0), x)
			elif vert:
				c.draw_rect(Rect2(fx + 0.6, fy, 0.1, 1.0), Color(0.02, 0.02, 0.01, 0.2))
				_coil(c, Vector2(fx + 0.5, fy), Vector2(0.0, 1.0), y)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _coil(c: CanvasItem, p: Vector2, d: Vector2, k: int) -> void:
	var n := Vector2(-d.y, d.x)
	var pa := PackedVector2Array()
	var pb := PackedVector2Array()
	for i in 13:
		var t := float(i) / 12.0
		var ph := t * TAU * 3.0
		pa.append(p + d * t + n * sin(ph) * 0.045)
		pb.append(p + d * t + n * sin(ph + PI) * 0.045)
	c.draw_polyline(pa, Color(0.04, 0.04, 0.05, 0.55), 0.035)
	c.draw_polyline(pb, Color(0.04, 0.04, 0.05, 0.55), 0.035)
	c.draw_polyline(pa, Color(0.7, 0.72, 0.76, 0.9), 0.016)
	c.draw_polyline(pb, Color(0.5, 0.52, 0.56, 0.9), 0.016)


## The gate: two steel rolling leaves with ribs, hazard stripes where they meet, a chain and a padlock, razor wire on top. `g` is the top left (pixels) of the gate, `leaf` the size of one leaf.
static func draw_gate(c: CanvasItem, g: Vector2, leaf: Vector2, gap: float) -> void:
	for side in 2:
		var o := g + Vector2((leaf.x + gap) * float(side), 0.0)
		c.draw_rect(Rect2(o + Vector2(4, 6), leaf), Color(0, 0, 0, 0.30))    # shadow
		c.draw_rect(Rect2(o, leaf), Color(0.36, 0.39, 0.42))
		var ribs := 7
		for i in ribs:
			var yy := o.y + 4.0 + float(i) * (leaf.y - 8.0) / float(ribs)
			c.draw_line(Vector2(o.x + 3, yy + 5), Vector2(o.x + leaf.x - 3, yy + 5), Color(0.17, 0.19, 0.21), 2.0)
			c.draw_line(Vector2(o.x + 3, yy + 3), Vector2(o.x + leaf.x - 3, yy + 3), Color(0.55, 0.58, 0.62, 0.8), 1.0)
		c.draw_rect(Rect2(o, leaf), Color(0.08, 0.09, 0.1), false, 3.0)
		c.draw_line(o + Vector2(2, 2), o + Vector2(leaf.x - 2, 2), Color(0.7, 0.73, 0.78, 0.8), 1.0)
		# hazard stripes on the edge where the leaves meet
		var ex := o.x + (leaf.x - 12.0 if side == 0 else 0.0)
		for i in 8:
			var col := Color(0.92, 0.74, 0.12) if i % 2 == 0 else Color(0.08, 0.08, 0.08)
			c.draw_rect(Rect2(ex, o.y + float(i) * leaf.y / 8.0, 12.0, leaf.y / 8.0), col)
		c.draw_rect(Rect2(ex, o.y, 12.0, leaf.y), Color(0, 0, 0, 0.12))
		# the track the leaf rolls on
		c.draw_rect(Rect2(o.x - (6.0 if side == 0 else 0.0), o.y + leaf.y - 5.0, leaf.x + 6.0, 4.0), Color(0.1, 0.1, 0.11, 0.8))
		for wx in [0.18, 0.82]:
			c.draw_circle(Vector2(o.x + leaf.x * wx, o.y + leaf.y - 3.0), 3.2, Color(0.2, 0.2, 0.22))
		# razor wire along the top
		var pa := PackedVector2Array()
		var pb := PackedVector2Array()
		for i in 25:
			var t := float(i) / 24.0
			var ph := t * TAU * 6.0
			pa.append(Vector2(o.x + t * leaf.x, o.y - 3.0 + sin(ph) * 3.0))
			pb.append(Vector2(o.x + t * leaf.x, o.y - 3.0 + sin(ph + PI) * 3.0))
		c.draw_polyline(pa, Color(0.75, 0.77, 0.82), 1.2)
		c.draw_polyline(pb, Color(0.5, 0.52, 0.56), 1.2)
	# chain across the middle and a padlock
	var m := g + Vector2(leaf.x + gap * 0.5, leaf.y * 0.5)
	for i in 6:
		var a := m + Vector2(-13.0 + float(i) * 5.0, sin(float(i) * 1.7) * 2.0)
		c.draw_circle(a, 2.4, Color(0.1, 0.1, 0.1))
		c.draw_circle(a, 1.5, Color(0.55, 0.57, 0.6))
	c.draw_rect(Rect2(m + Vector2(-5, -1), Vector2(10, 11)), Color(0.1, 0.08, 0.04))
	c.draw_rect(Rect2(m + Vector2(-4, 0), Vector2(8, 9)), Color(0.78, 0.62, 0.2))
	c.draw_arc(m + Vector2(0, -1), 4.0, PI, TAU, 8, Color(0.7, 0.72, 0.76), 1.6)
